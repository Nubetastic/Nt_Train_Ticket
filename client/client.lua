--[[
    NT Trains Ticket System - Client
    Clean, modular, config-driven logic for East (and future West) trains
    Author: Refactored by GitHub Copilot, July 2025
]]

-- === Core & Menu Setup ===
local RSGCore = exports['rsg-core']:GetCoreObject()
local MenuData = {}
TriggerEvent('rsg-menubase:getData', function(call)
    MenuData = call
end)

-- Disable ambient/traffic trains
CreateThread(function()
    Wait(1000)
    Citizen.InvokeNative(0xC77518575DD17953, false)
end)

local trainModel

local PLAYER_TRAIN_MATCH_RADIUS = (Config and Config.PlayerTrainMatchRadius) or 75.0

local activeStation = nil
local destinationStation = nil
local activeTrainBlips = {
    east = nil,
    west = nil
}

local lastCleanedTrainNetId = nil

local spawnedTrains = {}
local spawnedTrainDrivers = {}
local spawnedTrainGuards = {}
local spawnedTrainPassengers = {}
local spawnedStationNPCs = {}

-- NPC-on-train tracking cache (network-synced entities)
-- Keyed by trainNetId -> set of ped handles
local TrainNPCCache = {}

local function GetTrainNetId(entity)
    local id = NetworkGetNetworkIdFromEntity(entity)
    if id and id ~= 0 and NetworkDoesNetworkIdExist(id) then
        return id
    end
    return nil
end

local function AddTrainNPCToCache(trainNetId, ped)
    if not trainNetId or not ped then return end
    TrainNPCCache[trainNetId] = TrainNPCCache[trainNetId] or {}
    TrainNPCCache[trainNetId][ped] = true
end


local function RemovePedFromAllTrainCaches(ped)
    for tid, map in pairs(TrainNPCCache) do
        if map[ped] then map[ped] = nil end
    end
end

local function IsPedUsingTrain(ped)
    return ped and DoesEntityExist(ped) and (IsPedInAnyTrain(ped) ~= false)
end

local function IsPedAlignedWithTrain(ped, trainVeh, trainCoords)
    if not ped or not trainVeh or not DoesEntityExist(trainVeh) then return false, nil end
    if not IsPedUsingTrain(ped) then return false, nil end
    local coords = GetEntityCoords(ped)
    if #(coords - trainCoords) <= PLAYER_TRAIN_MATCH_RADIUS then
        return true, coords
    end
    return false, coords
end

-- Find peds around station and sync them onto the train
local function findTrainNPCs(trainVeh, stationData)
    if not trainVeh or not DoesEntityExist(trainVeh) or not stationData or not stationData.stationCoords then return end
    local stationCoords = stationData.stationCoords
    local radius = Config.StationNPCRadius
    local trainNetId = GetTrainNetId(trainVeh)
    if not trainNetId then return end

    TrainNPCCache[trainNetId] = TrainNPCCache[trainNetId] or {}

    local peds = GetGamePool and GetGamePool('CPed') or {}
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local pc = GetEntityCoords(ped)
            if #(pc - stationCoords) <= radius then
                local inAnyTrain = Citizen.InvokeNative(0x6F972C1AB75A1ED0, ped)
                if inAnyTrain then
                    AddTrainNPCToCache(trainNetId, ped)
                    NetworkRegisterEntityAsNetworked(ped)
                else
                    RemovePedFromAllTrainCaches(ped)
                end
            end
        end
    end
end

-- === Utility Functions ===
function GetStationIndex(stationName)
    for i, station in ipairs(Config.EastStationsList) do
        if station == stationName then return i end
    end
    return nil
end

function IsStationInSplit(stationName, splitName)
    for _, station in ipairs(Config.SplitStations[splitName]) do
        if station == stationName then return true end
    end
    return false
end

-- Debug print function for train information
function DebugTrainInfo(args)
    if not Config.Debug then return end
    print("^2=== TRAIN DEBUG INFO ===^7")
    for k, v in pairs(args) do
        if v ~= nil then
            print("^3" .. tostring(k) .. ":^7 " .. tostring(v))
        end
    end
    print("^2========================^7")
end

function SetJunctionSwitches(currentStation, destinationStation)
    local isEastTrack = Config.EastStations and Config.EastStations[currentStation]
    local isWestTrack = Config.WestStations and Config.WestStations[currentStation]
    if isEastTrack then
        for _, junction in pairs(Config.JunctionEast) do
            Citizen.InvokeNative(0xE6C5E2125EB210C1, junction.trainTrack, junction.junctionIndex, junction.enabled, true)
            Wait(50)
        end
    elseif isWestTrack then
        for _, junction in pairs(Config.JunctionWest) do
            Citizen.InvokeNative(0xE6C5E2125EB210C1, junction.trainTrack, junction.junctionIndex, junction.enabled, true)
            Wait(50)
        end
    end
    if Config.JunctionSwitch[currentStation] and Config.JunctionSwitch[currentStation][destinationStation] then
        local junctionSettings = Config.JunctionSwitch[currentStation][destinationStation]
        Citizen.InvokeNative(0xE6C5E2125EB210C1, junctionSettings.trainTrack, junctionSettings.junctionIndex, junctionSettings.enabled, true)
    end
end



-- Charge ticket price for any player in the train area (near any train car)
local function chargeTicketPrice(trainVeh, current, trainType)
    local trainNetId = NetworkGetNetworkIdFromEntity(trainVeh)
    -- Get train position and speed for proximity/sync check
    local trainCoords = GetEntityCoords(trainVeh)
    local speed = GetEntitySpeed(trainVeh)
    local heading = GetEntityHeading(trainVeh)

    local rad = math.rad(heading)
    local behindVector = vector3(-math.sin(rad), math.cos(rad), 0.0)
    local behindDistance = 30.0
    local behindPoint = trainCoords + behindVector * behindDistance

    for _, playerId in ipairs(GetActivePlayers()) do
        local playerPed = GetPlayerPed(playerId)
        if playerPed and DoesEntityExist(playerPed) then
            local onTrain, playerCoords = IsPedAlignedWithTrain(playerPed, trainVeh, trainCoords)
            if onTrain then
                local playerSpeed = GetEntitySpeed(playerPed)
                playerCoords = playerCoords or GetEntityCoords(playerPed)
                local distBehind = #(playerCoords - behindPoint)
                if math.abs(playerSpeed - speed) < 3 and distBehind < 150.0 then
                    TriggerServerEvent('nt_trains_ticket:server:playerTicketCharge', GetPlayerServerId(playerId), current, trainType or 'east', trainNetId)
                end
            end
        end
    end
end


-- Find route to destination using pathfinding with direction constraints
-- Try both directions and pick the shortest route
function FindShortestRoute(current, destination, initialDirection, trainType)
    trainType = trainType or "east"
    local stations = trainType == "west" and Config.WestStations or Config.EastStations

    -- If current and destination are the same, return just current (with direction)
    if current == destination then
        -- Add current station as a new step, flip direction, then find next station in that direction
        local flippedDirection = not initialDirection
        local stationsTable = trainType == "west" and Config.WestStations or Config.EastStations
        local stationData = stationsTable[current]
        local nextStations = {}
        if flippedDirection == false then -- Forward
            if stationData and stationData.ForwardStation then
                for _, s in ipairs(stationData.ForwardStation) do
                    table.insert(nextStations, s)
                end
            end
        else -- Backward
            if stationData and stationData.BackwardStation then
                for _, s in ipairs(stationData.BackwardStation) do
                    table.insert(nextStations, s)
                end
            end
        end
        local nextStation = nextStations[1]
        local route = {
            {station=current, direction=initialDirection},
            {station=current, direction=flippedDirection}
        }
        if nextStation then
            table.insert(route, {station=nextStation, direction=flippedDirection})
        end
        if Config.Debug then
            local routeStr = ""
            for _, step in ipairs(route) do
                routeStr = routeStr .. step.station .. "(" .. (step.direction and "B" or "F") .. ") -> "
            end
            print("^6[FindShortestRoute] Route: ^7" .. routeStr)
        end
        return route
    end

    -- Each queue item: {station, path, direction, previousStation}
    local queue = {{station = current, path = {{station=current, direction=initialDirection}}, direction = initialDirection}}
    -- Track visited stations with direction and previous to allow revisiting with different context
    local visited = {}

    while #queue > 0 do
        local node = table.remove(queue, 1)
        local station = node.station
        local path = node.path
        local direction = node.direction
        local prev = node.previous

        if station == destination then
            if Config.Debug then
                local routeStr = ""
                for _, step in ipairs(path) do
                    routeStr = routeStr .. step.station .. "(" .. (step.direction and "B" or "F") .. ") -> "
                end
                print("^6[FindShortestRoute] Route: ^7" .. routeStr)
            end
            return path
        end

        local stationData = stations[station]
        if not stationData then goto continue end

        -- Determine if we need to flip direction after leaving this station
        local flip = false
        -- Compare FlipDirectionIf for current station to each nextStation
        local nextStations = {}
        if direction == false then -- Forward
            if stationData.ForwardStation then
                for _, s in ipairs(stationData.ForwardStation) do
                    table.insert(nextStations, s)
                end
            end
        elseif direction == true then -- Backward
            if stationData.BackwardStation then
                for _, s in ipairs(stationData.BackwardStation) do
                    table.insert(nextStations, s)
                end
            end
        end

        for _, nextStation in ipairs(nextStations) do
            local nextFlip = false
            if stationData.FlipDirectionIf then
                for _, flipName in ipairs(stationData.FlipDirectionIf) do
                    if flipName == nextStation then
                        nextFlip = true
                        break
                    end
                end
            end
            local nextDirection = direction
            if nextFlip then
                nextDirection = not direction
            end
            -- Avoid cycles: use station+direction+prev as key
            local visitKey = nextStation .. "_" .. tostring(nextDirection) .. "_" .. (station or "")
            if not visited[visitKey] then
                visited[visitKey] = true
                local newPath = {}
                for _, p in ipairs(path) do table.insert(newPath, p) end
                table.insert(newPath, {station=nextStation, direction=nextDirection})
                table.insert(queue, {
                    station = nextStation,
                    path = newPath,
                    direction = nextDirection,
                    previous = station
                })
            end
        end
        goto continue

        -- Only consider stations in the current direction
        local nextStations = {}
        if nextDirection == false then -- Forward
            if stationData.ForwardStation then
                for _, s in ipairs(stationData.ForwardStation) do
                    table.insert(nextStations, s)
                end
            end
        elseif nextDirection == true then -- Backward
            if stationData.BackwardStation then
                for _, s in ipairs(stationData.BackwardStation) do
                    table.insert(nextStations, s)
                end
            end
        end

        for _, nextStation in ipairs(nextStations) do
            -- Avoid cycles: use station+direction+prev as key
            local visitKey = nextStation .. "_" .. tostring(nextDirection) .. "_" .. (station or "")
            if not visited[visitKey] then
                visited[visitKey] = true
                local newPath = {}
                for _, p in ipairs(path) do table.insert(newPath, p) end
                table.insert(newPath, {station=nextStation, direction=nextDirection})
                table.insert(queue, {
                    station = nextStation,
                    path = newPath,
                    direction = nextDirection,
                    previous = station
                })
            end
        end
        ::continue::
    end

    -- If no path found, return direct route as fallback
    return {{station=current, direction=initialDirection}, {station=destination, direction=initialDirection}}
end

-- === Prompt & Blip Creation ===

CreateThread(function()
    -- Handle East Stations
    for stationName, stationData in pairs(Config.EastStations) do
        local promptId = "train_ticket_" .. stationName
        exports['rsg-core']:createPrompt(promptId, stationData.ticketCoords, RSGCore.Shared.Keybinds['J'], 'Train Schedule', {
            type = 'client',
            event = 'nt_trains_ticket:client:openTicketMenu',
            args = { stationName },
        })
        if stationData.showblip ~= false then
            local StationBlip = BlipAddForCoords(1664425300, stationData.ticketCoords)
            SetBlipSprite(StationBlip, 1258184551, true)
            SetBlipScale(StationBlip, 0.2)
            SetBlipName(StationBlip, stationName .. ' Station')
        end
        -- NPC spawn logic:
        if stationData.npcModel and stationData.npcCoords then
            local modelHash = type(stationData.npcModel) == "string" and GetHashKey(stationData.npcModel) or stationData.npcModel
            RequestModel(modelHash)
            while not HasModelLoaded(modelHash) do Wait(10) end
            local ped = CreatePed(modelHash, stationData.npcCoords.x, stationData.npcCoords.y, stationData.npcCoords.z - 1.0, stationData.npcCoords.w or 0.0, 0, 0, 0, 0)
            SetEntityAlpha(ped, 255, false)
            SetPedRandomComponentVariation(ped, 0)
            SetEntityCanBeDamaged(ped, false)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)
            SetPedCanBeTargetted(ped, false)
            table.insert(spawnedStationNPCs, ped)
        end
    end
    
    -- Handle West Stations
    for stationName, stationData in pairs(Config.WestStations) do
        local promptId = "train_ticket_" .. stationName
        exports['rsg-core']:createPrompt(promptId, stationData.ticketCoords, RSGCore.Shared.Keybinds['J'], 'Train Schedule', {
            type = 'client',
            event = 'nt_trains_ticket:client:openTicketMenu',
            args = { stationName },
        })
        if stationData.showblip ~= false then
            local StationBlip = BlipAddForCoords(1664425300, stationData.ticketCoords)
            SetBlipSprite(StationBlip, 1258184551, true)
            SetBlipScale(StationBlip, 0.2)
            SetBlipName(StationBlip, stationName .. ' Station')
        end
        -- NPC spawn logic:
        if stationData.npcModel and stationData.npcCoords then
            local modelHash = type(stationData.npcModel) == "string" and GetHashKey(stationData.npcModel) or stationData.npcModel
            RequestModel(modelHash)
            while not HasModelLoaded(modelHash) do Wait(10) end
            local ped = CreatePed(modelHash, stationData.npcCoords.x, stationData.npcCoords.y, stationData.npcCoords.z - 1.0, stationData.npcCoords.w or 0.0, 0, 0, 0, 0)
            SetEntityAlpha(ped, 255, false)
            SetPedRandomComponentVariation(ped, 0)
            SetEntityCanBeDamaged(ped, false)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)
            SetPedCanBeTargetted(ped, false)
            table.insert(spawnedStationNPCs, ped)
        end
    end
end)



RegisterNetEvent('nt_trains_ticket:client:createTrainBlip')
AddEventHandler('nt_trains_ticket:client:createTrainBlip', function(trainNetId, trainType)
    if not Config.UseTrainBlips then return end
    trainType = trainType or "east" -- Default to east for backward compatibility
    
    print("^6[BLIP DEBUG] createTrainBlip called for trainType: " .. trainType .. " netId: " .. tostring(trainNetId) .. "^7")
    
    -- Ensure we have a valid network ID
    if not trainNetId or trainNetId == 0 or not NetworkDoesNetworkIdExist(trainNetId) then
        if Config.Debug then
            print("^1[TRAIN BLIP] Invalid train network ID: " .. tostring(trainNetId) .. "^7")
        end
        return
    end
    
    -- Get the train entity from network ID
    local trainVeh = NetworkGetEntityFromNetworkId(trainNetId)
    if not trainVeh or not DoesEntityExist(trainVeh) then
        if Config.Debug then
            print("^1[TRAIN BLIP] Could not get train entity from network ID: " .. tostring(trainNetId) .. "^7")
        end
        
        -- Try to wait for the entity to become available
        local timeout = 0
        while (not trainVeh or not DoesEntityExist(trainVeh)) and timeout < 50 do
            Wait(100)
            trainVeh = NetworkGetEntityFromNetworkId(trainNetId)
            timeout = timeout + 1
        end
        
        if not trainVeh or not DoesEntityExist(trainVeh) then
            print("^1[BLIP DEBUG] Failed to get train entity after timeout^7")
            return
        end
    end
    
    -- Remove existing train blip for this train type if it exists
    if activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) then
        print("^3[BLIP DEBUG] Removing old blip for trainType " .. trainType .. "^7")
        RemoveBlip(activeTrainBlips[trainType])
        activeTrainBlips[trainType] = nil
    end
    
    -- Create networked blip attached to the train entity
    activeTrainBlips[trainType] = Citizen.InvokeNative(0x23F74C2FDA6E7C61, 1664425300, trainVeh) -- BlipAddForEntity
    if activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) then
        SetBlipSprite(activeTrainBlips[trainType], -250506368) -- Train blip sprite
        
        -- Set appropriate blip name based on train type
        local blipName = trainType == "west" and (Config.TrainBlipNameWest or "West Train") or (Config.TrainBlipNameEast or "East Train")
        Citizen.InvokeNative(0x9CB1A1623062F402, activeTrainBlips[trainType], blipName) -- SetBlipName
        SetBlipScale(activeTrainBlips[trainType], 1.0)
        
        print("^2[BLIP DEBUG] Successfully created blip for train: " .. tostring(trainNetId) .. " (Type: " .. trainType .. ")^7")
    else
        print("^1[BLIP DEBUG] Failed to create blip for train: " .. tostring(trainNetId) .. " (Type: " .. trainType .. ")^7")
    end
end)

RegisterNetEvent('nt_trains_ticket:client:removeTrainBlip')
AddEventHandler('nt_trains_ticket:client:removeTrainBlip', function(trainType)
    trainType = trainType or "east" -- Default to east for backward compatibility
    
    print("^5[BLIP DEBUG] removeTrainBlip event called for trainType: " .. trainType .. "^7")
    
    if activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) then
        print("^5[BLIP DEBUG] Removing blip for trainType: " .. trainType .. "^7")
        RemoveBlip(activeTrainBlips[trainType])
        activeTrainBlips[trainType] = nil
    else
        print("^3[BLIP DEBUG] No blip found to remove for trainType: " .. trainType .. " (blip exists: " .. tostring(activeTrainBlips[trainType] ~= nil) .. ", isValid: " .. tostring(activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) or false) .. ")^7")
    end
end)

-- === Menu Logic ===

RegisterNetEvent('nt_trains_ticket:client:openTicketMenu')
AddEventHandler('nt_trains_ticket:client:openTicketMenu', function(stationName)
    -- Determine if the station is east or west
    local trainType = nil
    if Config.EastStations and Config.EastStations[stationName] then
        trainType = "east"
    elseif Config.WestStations and Config.WestStations[stationName] then
        trainType = "west"
    else
        exports.ox_lib:notify({
            title = 'Unknown Station',
            description = 'This station is not configured for east or west trains.',
            type = 'error',
            duration = 10000
        })
        return
    end
    trainType = trainType or "east"
    activeStation = stationName
    
    -- Check with server if this train type is available
    TriggerServerEvent('nt_trains_ticket:server:checkTrainAvailable', trainType)
end)


-- State management for train availability checks
local pendingAvailabilityCheck = {
    waiting = false,
    trainType = nil,
    callback = nil
}

-- Register client events for train availability responses
RegisterNetEvent('nt_trains_ticket:client:trainAvailabilityResponse')
AddEventHandler('nt_trains_ticket:client:trainAvailabilityResponse', function(trainType, isAvailable)
    -- Handle pending availability check first
    if pendingAvailabilityCheck.waiting and pendingAvailabilityCheck.trainType == trainType and pendingAvailabilityCheck.callback then
        pendingAvailabilityCheck.waiting = false
        local callback = pendingAvailabilityCheck.callback
        pendingAvailabilityCheck.callback = nil
        pendingAvailabilityCheck.trainType = nil
        callback(isAvailable)
        return
    end
    
    -- Handle initial availability check (for opening menu)
    if isAvailable then
        -- If train is available, open the destination menu
        local currentStation = activeStation
        if currentStation then
            MenuData.CloseAll()
            local stationsList = trainType == "west" and Config.WestStationsList or Config.EastStationsList
            local elements = {}
            for _, stationName in ipairs(stationsList) do
                if stationName ~= currentStation then
                    table.insert(elements, {
                        label = stationName,
                        value = stationName,
                        desc = "Schedule for " .. stationName
                    })
                end
            end
            MenuData.Open('default', GetCurrentResourceName(), 'train_destination_menu', {
                title = 'Select Destination',
                subtext = 'Choose where you want to go',
                align = 'top-left',
                elements = elements,
            }, function(data, menu)
                destinationStation = data.current.value
                menu.close()
                
                -- Check with server again before spawning (double-check)
                pendingAvailabilityCheck.waiting = true
                pendingAvailabilityCheck.trainType = trainType
                pendingAvailabilityCheck.callback = function(respIsAvailable)
                    if respIsAvailable then
                        exports.ox_lib:notify({
                            title = 'Train to: ' .. destinationStation,
                            description = 'The train will arrive shortly.',
                            type = 'success',
                            duration = 10000
                        })
                        SpawnTrain(currentStation, destinationStation, trainType)
                    else
                        exports.ox_lib:notify({
                            title = 'Train Already Exists',
                            description = 'A ' .. (trainType == "west" and "West" or "East") .. ' train is already on the track. Please wait for it to clear.',
                            type = 'error',
                            duration = 10000
                        })
                    end
                end
                
                TriggerServerEvent('nt_trains_ticket:server:checkTrainAvailable', trainType)
                
                -- Timeout after 5 seconds
                SetTimeout(10000, function()
                    if pendingAvailabilityCheck.waiting and pendingAvailabilityCheck.trainType == trainType then
                        pendingAvailabilityCheck.waiting = false
                        pendingAvailabilityCheck.callback = nil
                        pendingAvailabilityCheck.trainType = nil
                        exports.ox_lib:notify({
                            title = 'Server Error',
                            description = 'Could not verify train availability. Please try again.',
                            type = 'error',
                            duration = 10000
                        })
                    end
                end)
            end, function(data, menu)
                menu.close()
            end)
        end
    else
        -- If train is not available, show notification
        exports.ox_lib:notify({
            title = 'Train Already Exists',
            description = 'A ' .. (trainType == "west" and "West" or "East") .. ' train is already on the track. Please wait for it to clear.',
            type = 'error',
            duration = 10000
        })
    end
end)

-- Event for when server denies train spawn
RegisterNetEvent('nt_trains_ticket:client:trainAlreadyActive')
AddEventHandler('nt_trains_ticket:client:trainAlreadyActive', function(trainType)
    exports.ox_lib:notify({
        title = 'Train Already Exists',
        description = 'A ' .. (trainType == "west" and "West" or "East") .. ' train is already on the track. Please wait for it to clear.',
        type = 'error',
        duration = 10000
    })
end)

-- State management for train lock checks
local pendingLockCheck = {
    waiting = false,
    trainType = nil,
    callback = nil
}

-- Event for train lock response
RegisterNetEvent('nt_trains_ticket:client:trainLockResponse')
AddEventHandler('nt_trains_ticket:client:trainLockResponse', function(trainType, success)
    -- Handle pending lock check first
    if pendingLockCheck.waiting and pendingLockCheck.trainType == trainType and pendingLockCheck.callback then
        pendingLockCheck.waiting = false
        local callback = pendingLockCheck.callback
        pendingLockCheck.callback = nil
        pendingLockCheck.trainType = nil
        callback(success)
        return
    end
    
    -- Handle general lock response (fallback)
    if not success then
        exports.ox_lib:notify({
            title = 'Train Unavailable',
            description = 'Could not secure train. Someone else may have just requested it.',
            type = 'error',
            duration = 10000
        })
    end
end)

-- Event to cleanup orphaned trains (when owner disconnects)
RegisterNetEvent('nt_trains_ticket:client:cleanupOrphanedTrain')
AddEventHandler('nt_trains_ticket:client:cleanupOrphanedTrain', function(trainType, trainNetId)
    print("^5[BLIP DEBUG] cleanupOrphanedTrain called for trainType: " .. tostring(trainType) .. " netId: " .. tostring(trainNetId) .. "^7")
    
    -- Skip if we just cleaned up this exact train locally
    if trainNetId and trainNetId == lastCleanedTrainNetId then
        print("^5[BLIP DEBUG] cleanupOrphanedTrain: ABORTING - this train was just cleaned up locally (netId: " .. trainNetId .. ")^7")
        lastCleanedTrainNetId = nil
        return
    end
    
    -- If no network ID provided, abort
    if not trainNetId then
        print("^5[BLIP DEBUG] cleanupOrphanedTrain: ABORTING - no network ID provided^7")
        return
    end
    
    -- Check if the entity still exists
    if not NetworkDoesNetworkIdExist(trainNetId) then
        -- Network ID doesn't exist - orphaned train is already gone
        -- DO NOT remove the blip, as it likely belongs to a new train now!
        print("^5[BLIP DEBUG] cleanupOrphanedTrain: ABORTING - network ID does not exist (train already despawned). PRESERVING BLIP for potential new train^7")
        return
    end
    
    -- Network ID exists - get the entity and cleanup
    local trainVeh = NetworkGetEntityFromNetworkId(trainNetId)
    if trainVeh and DoesEntityExist(trainVeh) then
        print("^5[BLIP DEBUG] cleanupOrphanedTrain: train entity exists, calling CleanupTrain for trainType: " .. tostring(trainType) .. "^7")
        CleanupTrain(trainVeh, trainType)
        
        -- Only remove the blip if the train entity was valid and we cleaned it up
        if activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) then
            print("^5[BLIP DEBUG] cleanupOrphanedTrain: removing blip for trainType: " .. trainType .. " (train existed)^7")
            RemoveBlip(activeTrainBlips[trainType])
            activeTrainBlips[trainType] = nil
        end
    else
        print("^5[BLIP DEBUG] cleanupOrphanedTrain: train entity does not exist (netId exists but entity is gone)^7")
    end
end)




RegisterNetEvent('nt_trains_ticket:client:assignTrainMonitor')
AddEventHandler('nt_trains_ticket:client:assignTrainMonitor', function(trainType, trainNetId, currentStation, destinationStation, direction, model)
    local trainVeh = nil
    local timeout = 0
    if trainNetId and NetworkDoesNetworkIdExist(trainNetId) then
        trainVeh = NetworkGetEntityFromNetworkId(trainNetId)
    end
    while (not trainVeh or not DoesEntityExist(trainVeh)) and timeout < 100 do
        Wait(100)
        if trainNetId and NetworkDoesNetworkIdExist(trainNetId) then
            trainVeh = NetworkGetEntityFromNetworkId(trainNetId)
        end
        timeout = timeout + 1
    end
    if trainVeh and DoesEntityExist(trainVeh) then
        if model then trainModel = model end
        if currentStation and destinationStation ~= nil and direction ~= nil then
            MonitorTrain(trainVeh, currentStation, destinationStation, trainType or 'east', direction)
        end
        StartTrainDespawnMonitor(trainVeh, trainType or 'east')
    end
end)

-- === Train Spawning & Monitoring ===

-- Function to clean up a specific train and its components
function CleanupTrain(trainVeh, trainType)
    if not trainVeh or not DoesEntityExist(trainVeh) then 
        print("^1[BLIP DEBUG] CleanupTrain called with invalid train^7")
        return 
    end
    
    print("^1[BLIP DEBUG] CleanupTrain called for trainType: " .. tostring(trainType) .. "^7")
    
    -- Get network ID before cleanup to ensure we clean up the right train
    local trainNetId = GetTrainNetId(trainVeh)
    
    -- Cache this netId so we can skip orphan cleanup if it comes for the same train
    lastCleanedTrainNetId = trainNetId
    
    -- Notify server to release the train type (blip is now managed by despawn monitor)
    if trainType then
        print("^1[BLIP DEBUG] CleanupTrain triggering server removeTrainBlip for trainType: " .. trainType .. " netId: " .. tostring(trainNetId) .. "^7")
        TriggerServerEvent('nt_trains_ticket:server:removeTrainBlip', trainType, trainNetId)
    end
    
    -- Get all train cars/wagons for comprehensive cleanup
    local trainCars = {}
    table.insert(trainCars, trainVeh) -- Add the main train entity
    
    -- Check for additional train cars/wagons
    local carIndex = 0
    while carIndex < 20 do -- Check up to 20 cars (should be more than enough)
        local trainCar = Citizen.InvokeNative(0x08C2ACB934C70129, trainVeh, carIndex) -- GetTrainCarriage
        if trainCar and DoesEntityExist(trainCar) and trainCar ~= trainVeh then
            table.insert(trainCars, trainCar)
        else
            break
        end
        carIndex = carIndex + 1
    end
    
    
    -- Clean up NPCs from all train cars
    local npcsRemoved = 0
    for _, car in ipairs(trainCars) do
        if DoesEntityExist(car) then
            -- Remove all passengers and NPCs from this car (check more seats to be thorough)
            for seat = -1, 15 do -- Include driver seat (-1) and passenger seats (0-15)
                local ped = GetPedInVehicleSeat(car, seat)
                if ped and DoesEntityExist(ped) then
                    -- Remove from tracking arrays based on seat type
                    if seat == -1 then
                        -- Driver cleanup
                        for i, driver in ipairs(spawnedTrainDrivers) do
                            if driver == ped then
                                table.remove(spawnedTrainDrivers, i)
                                break
                            end
                        end
                    else
                        -- Passenger cleanup
                        for i, passenger in ipairs(spawnedTrainPassengers) do
                            if passenger == ped then
                                table.remove(spawnedTrainPassengers, i)
                                break
                            end
                        end
                    end
                    
                    -- Delete the NPC
                    SetEntityAsMissionEntity(ped, true, true)
                    DeleteEntity(ped)
                    npcsRemoved = npcsRemoved + 1
                end
            end
        end
    end
    
    -- Clean up guards (they might be standing/walking around the train, not in seats)
    for i = #spawnedTrainGuards, 1, -1 do
        local guard = spawnedTrainGuards[i]
        if guard and DoesEntityExist(guard) then
            local guardCoords = GetEntityCoords(guard)
            local trainCoords = GetEntityCoords(trainVeh)
            local distance = #(guardCoords - trainCoords)
            
            -- If guard is within 50 units of the train, consider it part of this train
            if distance < 50.0 then
                SetEntityAsMissionEntity(guard, true, true)
                DeleteEntity(guard)
                table.remove(spawnedTrainGuards, i)
                npcsRemoved = npcsRemoved + 1
            end
        else
            -- Remove invalid guard references
            table.remove(spawnedTrainGuards, i)
        end
    end
    
    -- Delete all train cars
    for _, car in ipairs(trainCars) do
        if DoesEntityExist(car) then
            SetEntityAsMissionEntity(car, true, true)
            DeleteEntity(car)
        end
    end
    
    -- Remove from local tracking
    for i, train in ipairs(spawnedTrains) do
        if train == trainVeh then
            table.remove(spawnedTrains, i)
            break
        end
    end
    
end

function SpawnTrain(currentStation, destinationStation, trainType)
    trainType = trainType or "east"
    local stations = trainType == "west" and Config.WestStations or Config.EastStations
    -- Pick a random train model from Config.<Side>Trains; fallback to single model if list missing
    if trainType == "west" and Config.WestTrains then
        local keys = {}
        for hash, _ in pairs(Config.WestTrains) do table.insert(keys, hash) end
        if #keys > 0 then trainModel = keys[math.random(#keys)] end
    else
        if Config.EastTrains then
            local keys = {}
            for hash, _ in pairs(Config.EastTrains) do table.insert(keys, hash) end
            if #keys > 0 then trainModel = keys[math.random(#keys)] end
        end
    end
    if not trainModel then
        trainModel = (trainType == "west") and Config.WestTrain or Config.EastTrain
    end
    local stationData = stations[currentStation]
    if not stationData then return end
    
    -- Try to lock this train type on the server
    pendingLockCheck.waiting = true
    pendingLockCheck.trainType = trainType
    local lockSuccess = false
    local lockReceived = false
    
    pendingLockCheck.callback = function(success)
        lockSuccess = success
        lockReceived = true
    end
    
    TriggerServerEvent('nt_trains_ticket:server:lockTrainType', trainType)
    
    -- Wait for lock response with timeout
    local startTime = GetGameTimer()
    while not lockReceived and GetGameTimer() - startTime < 10000 do
        Wait(100)
    end
    
    -- If we didn't get a response or lock failed, abort
    if not lockReceived or not lockSuccess then
        -- Clean up pending state
        if pendingLockCheck.waiting and pendingLockCheck.trainType == trainType then
            pendingLockCheck.waiting = false
            pendingLockCheck.callback = nil
            pendingLockCheck.trainType = nil
        end
        
        exports.ox_lib:notify({
            title = 'Train Unavailable',
            description = 'Could not secure train. Someone else may have just requested it.',
            type = 'error',
            duration = 10000
        })
        return
    end
    
    -- Determine spawn direction using Config.EastRouteSpawns for east trains
    local spawnDirection
    local route = nil
    if trainType == "east" and Config.EastRouteSpawns and Config.EastRouteSpawns[currentStation] and Config.EastRouteSpawns[currentStation][destinationStation] then
        local dir = Config.EastRouteSpawns[currentStation][destinationStation]
        spawnDirection = (dir == "Backward")
        if Config.Debug then
            print("^2=== TRAIN SPAWN INFORMATION (EastRouteSpawns) ===^7")
            print("^3Initial Direction:^7 " .. dir)
        end
    elseif trainType == "west" and Config.WestRouteSpawns and Config.WestRouteSpawns[currentStation] and Config.WestRouteSpawns[currentStation][destinationStation] then
        local dir = Config.WestRouteSpawns[currentStation][destinationStation]
        spawnDirection = (dir == "Backward")
        if Config.Debug then
            print("^2=== TRAIN SPAWN INFORMATION (WestRouteSpawns) ===^7")
            print("^3Initial Direction:^7 " .. dir)
        end
    end

    -- Select spawn coordinates based on direction
    local spawnCoords = spawnDirection and stationData.SpawnBack or stationData.SpawnForward

    DebugTrainInfo({
        Event = "Train Spawn",
        TrainType = trainType,
        CurrentStation = currentStation,
        Destination = destinationStation,
        SpawnDirection = spawnDirection and "Backward" or "Forward",
        SpawnCoords = spawnCoords and (tostring(spawnCoords.x) .. ", " .. tostring(spawnCoords.y) .. ", " .. tostring(spawnCoords.z)) or nil
    })
    SetJunctionSwitches(currentStation, destinationStation)

    local trainWagons = Citizen.InvokeNative(0x635423d55ca84fc8, trainModel)
    for i = 0, trainWagons - 1 do
        local trainWagonModel = Citizen.InvokeNative(0x8df5f6a19f99f0d5, trainModel, i)
        RequestModel(trainWagonModel)
        while not HasModelLoaded(trainWagonModel) do Wait(10) end
    end

    exports.ox_lib:notify({
        title = 'Train Arriving',
        description = 'Train to ' .. destinationStation .. ' is being prepared.',
        type = 'inform',
        duration = 10000
    })

    Wait(1000)

    if stationData.SpawnDirectionReverse then
        spawnDirection = not spawnDirection
    end

    local trainVeh = Citizen.InvokeNative(0xC239DBD9A57D2A71, trainModel, spawnCoords, spawnDirection, Config.UsePassengers, false, true)

    if stationData.SpawnDirectionReverse then
        spawnDirection = not spawnDirection
    end

    if not trainVeh or trainVeh == 0 then
        -- If train spawn failed, release the lock
        TriggerServerEvent('nt_trains_ticket:server:releaseTrainType', trainType)
        exports.ox_lib:notify({
            title = 'Train Spawn Failed',
            description = 'Could not spawn the train. Please try again later.',
            type = 'error',
            duration = 10000
        })
        return
    end

    -- Add to local tracking
    table.insert(spawnedTrains, trainVeh)

    -- Ensure train is properly networked
    NetworkRegisterEntityAsNetworked(trainVeh)
    local trainNetId = NetworkGetNetworkIdFromEntity(trainVeh)
    if trainNetId and trainNetId ~= 0 then
        SetNetworkIdExistsOnAllMachines(trainNetId, true)
    end

    -- Get and setup train driver
    local trainDriverHandle = GetPedInVehicleSeat(trainVeh, -1)
    while not DoesEntityExist(trainDriverHandle) do
        trainDriverHandle = GetPedInVehicleSeat(trainVeh, -1)
        SetEntityAsMissionEntity(trainDriverHandle, true, true)
        Wait(1)
    end

    if DoesEntityExist(trainVeh) and DoesEntityExist(trainDriverHandle) then
        NetworkRegisterEntityAsNetworked(trainDriverHandle)
        local driverNetId = NetworkGetNetworkIdFromEntity(trainDriverHandle)
        
        if driverNetId and driverNetId ~= 0 then
            SetNetworkIdExistsOnAllMachines(driverNetId, true)
        end

        SetEntityAsMissionEntity(trainDriverHandle, true, true)

        if Config.ProtectTrainDrivers then
            SetPedCanBeKnockedOffVehicle(trainDriverHandle, 1)
            SetEntityInvincible(trainDriverHandle, true)
            Citizen.InvokeNative(0x9F8AA94D6D97DBF4, trainDriverHandle, true)
            SetEntityCanBeDamaged(trainDriverHandle, false)
        end
    end
    
    -- Now set the train in motion
    SetTrainSpeed(trainVeh, Config.TrainMaxSpeed)
    SetTrainCruiseSpeed(trainVeh, Config.TrainMaxSpeed)
    Citizen.InvokeNative(0x9F29999DFDF2AEB8, trainVeh, Config.TrainMaxSpeed)


    AddTrainNPCToTracking(trainDriverHandle, "driver")
    
    -- Create and register train blip
    if Config.UseTrainBlips then
        local trainNetId = NetworkGetNetworkIdFromEntity(trainVeh)
        local timeout = 0
        while (not trainNetId or trainNetId == 0 or not NetworkDoesNetworkIdExist(trainNetId)) and timeout < 100 do
            Wait(50)
            trainNetId = NetworkGetNetworkIdFromEntity(trainVeh)
            timeout = timeout + 1
        end
        
        if trainNetId and trainNetId ~= 0 and NetworkDoesNetworkIdExist(trainNetId) then
            print("^6[BLIP DEBUG] SpawnTrain: requesting blip creation for trainType: " .. trainType .. " netId: " .. trainNetId .. "^7")
            TriggerServerEvent('nt_trains_ticket:server:createTrainBlip', trainNetId, trainType)
            TriggerServerEvent('nt_trains_ticket:server:registerRoute', trainType, trainNetId, currentStation, destinationStation, spawnDirection, trainModel)
        else
            print("^1[BLIP DEBUG] SpawnTrain: failed to get valid network ID after timeout^7")
        end
    end
    
    -- Start train monitoring
    MonitorTrain(trainVeh, currentStation, destinationStation, trainType, spawnDirection, trainModel)
    StartTrainDespawnMonitor(trainVeh, trainType)
end



function MonitorTrain(trainVeh, current, destinationStation, trainType, spawnDirection)
    if not trainVeh or not DoesEntityExist(trainVeh) then return end
    trainType = trainType or "east"
    local stations = trainType == "west" and Config.WestStations or Config.EastStations

    local trainOffset = 0
    if trainType == "east" then
        trainOffset = Config.EastTrains[trainModel]
    else
        trainOffset = Config.WestTrains[trainModel]
    end

    local npcCheck = false
    
    CreateThread(function()
        DebugTrainInfo({
            Event = "Train Monitoring Started",
            TrainType = trainType,
            StartingStation = current,
            Destination = destinationStation
        })

        -- Build the station list (route) before entering the loop
        local stationList = FindShortestRoute(current, destinationStation, spawnDirection, trainType)
        -- Remove the first station (current) since we're already there

        local previousStation = current
        local distanceFlip = false
        local trainSetup = false
        local offsetValue = 0.0

        while DoesEntityExist(trainVeh) and #stationList > 0 do
            Wait(1000)

            local nextStep = stationList[2]
            local nextStation = nextStep and nextStep.station or nil
            -- Use previousStation and its direction for offset and logic
            local stationData = stations[previousStation]
            local direction = stationList[1].direction
            local stopPosition = stationData and stationData.stationCoords or nil
            if stationData then
                if direction then -- backward
                    offsetValue = stationData.BackwardOffset + trainOffset
                else -- forward
                    offsetValue = stationData.ForwardOffset + trainOffset
                end
            end

            if trainSetup == false and nextStation then
                SetJunctionSwitches(stationData.station, stationList[1].station)
                SetJunctionSwitches(stationList[1].station, stationList[2].station) -- Next junction also for stops right before them.
                trainSetup = true
            end

            local trainCoords = GetEntityCoords(trainVeh)
            local speed = GetEntitySpeed(trainVeh)
            local trueDistanceToStation = stopPosition and #(trainCoords - stopPosition) or 0.0

            if trueDistanceToStation < 500 then
                if trueDistanceToStation < 10 then
                    distanceFlip = true
                end

                local distToStop
                if not distanceFlip then
                    distToStop = trueDistanceToStation + offsetValue
                else
                    distToStop = offsetValue - trueDistanceToStation
                end

                if speed > 0 and distToStop > 0 then
                    if distToStop < Config.StopDistance then
                        local minSpeed = Config.StopSpeed
                        local maxSpeed = Config.TrainMaxSpeed
                        local speedRatio = math.max(0, distToStop / 100)
                        local newSpeed = math.max(minSpeed, speedRatio * maxSpeed)
                        SetTrainCruiseSpeed(trainVeh, newSpeed)
                        if distToStop < Config.EaseToStop then
                            SetTrainCruiseSpeed(trainVeh, 0.0)
                            Citizen.InvokeNative(0x3660BCAB3A6BB734, trainVeh)
                        end
                    end
                end

                if speed == 0 and distToStop < 10 then

                    if npcCheck == false and Config.UsePassengers then
                        findTrainNPCs(trainVeh, { stationCoords = stopPosition })
                        npcCheck = true
                    end

                    DebugTrainInfo({
                        Event = "Station Arrival",
                        ArrivedAt = previousStation,
                        NextStation = stationList[2] and stationList[2].station or "End of route",
                        RemainingStops = #stationList - 1,
                        Direction = direction and "Backward" or "Forward"
                    })
                    Wait(Config.StationWaitTime)

                    DebugTrainInfo({
                        Event = "Moving to Next Station",
                        CurrentStation = previousStation,
                        NextStation = nextStation
                    })
                    local lastStation = previousStation
                    previousStation = nextStation
                    table.remove(stationList, 1)

                    local trainNetIdUpdate = NetworkGetNetworkIdFromEntity(trainVeh)
                    if trainNetIdUpdate and trainNetIdUpdate ~= 0 and NetworkDoesNetworkIdExist(trainNetIdUpdate) then
                        TriggerServerEvent('nt_trains_ticket:server:registerRoute', trainType, trainNetIdUpdate, previousStation, destinationStation, direction, trainModel)
                    end

                    if #stationList == 1 then
                        direction = stationList[1].direction
                        local stations = trainType == "west" and Config.WestStations or Config.EastStations
                        local prevData = stations[stationList[1].station]
                        local nextCandidates = {}

                        if direction == false then
                            if prevData and prevData.ForwardStation then
                                for _, s in ipairs(prevData.ForwardStation) do table.insert(nextCandidates, s) end
                            end
                        else
                            if prevData and prevData.BackwardStation then
                                for _, s in ipairs(prevData.BackwardStation) do table.insert(nextCandidates, s) end
                            end
                        end
                        local nextAutoStation = nextCandidates[1]

                        if nextAutoStation then
                            local newRoute = FindShortestRoute(previousStation, nextAutoStation, direction, trainType)
                            table.remove(newRoute, 1)
                            for _, step in ipairs(newRoute) do
                                table.insert(stationList, step)
                            end
                            destinationStation = nextAutoStation
                            local trainNetIdUpdate2 = NetworkGetNetworkIdFromEntity(trainVeh)
                            if trainNetIdUpdate2 and trainNetIdUpdate2 ~= 0 and NetworkDoesNetworkIdExist(trainNetIdUpdate2) then
                                TriggerServerEvent('nt_trains_ticket:server:registerRoute', trainType, trainNetIdUpdate2, previousStation, destinationStation, direction, trainModel)
                            end
                            DebugTrainInfo({
                                Event = "Route Extended",
                                NewDestination = nextAutoStation,
                                NewRouteSteps = #newRoute,
                                Direction = direction and "Backward" or "Forward"
                            })
                        else
                            DebugTrainInfo({
                                Event = "No Further Stations",
                                Message = "Train will stop here."
                            })
                        end
                    end

                    if stationList[2] then
                        SetTrainCruiseSpeed(trainVeh, Config.TrainMaxSpeed)
                        Citizen.InvokeNative(0x787E43477746876F, trainVeh)
                    else
                        SetTrainCruiseSpeed(trainVeh, 0.0)
                        Citizen.InvokeNative(0x3660BCAB3A6BB734, trainVeh)
                    end

                    trainSetup = false
                    distanceFlip = false
                    Wait(5000) -- Wait before moving to next station
                    
                    chargeTicketPrice(trainVeh, previousStation, trainType)
                end
            end
        end
    end)
end


-- Player-on-train/despawn logic as a separate function
function StartTrainDespawnMonitor(trainVeh, trainType)
    CreateThread(function()
        local stoppedOnce = false
        local emptyTrainTimer = 0
        
        -- Keep track of whether this train still exists
        local trainExists = true
        
        -- Store the train's network ID at creation time to prevent cleanup confusion
        local originalTrainNetId = GetTrainNetId(trainVeh)
        
        -- Pre-declare variables outside the loop for better performance
        local trainCoords, speed, playersOnTrain
        local playerPed, playerSpeed, playerCoords, dist
        
        -- Thread to maintain blip visibility while train is active
        CreateThread(function()
            print("^6[BLIP DEBUG] Maintenance thread started for trainType: " .. trainType .. " originalNetId: " .. tostring(originalTrainNetId) .. "^7")
            while trainExists and DoesEntityExist(trainVeh) do
                Wait(5000)
                -- Verify this is still the original train (network ID check)
                local currentNetId = GetTrainNetId(trainVeh)
                if currentNetId == originalTrainNetId and Config.UseTrainBlips and activeTrainBlips[trainType] then
                    if not DoesBlipExist(activeTrainBlips[trainType]) then
                        print("^6[BLIP DEBUG] Maintenance thread: blip missing for trainType " .. trainType .. ", recreating...^7")
                        local trainNetId = NetworkGetNetworkIdFromEntity(trainVeh)
                        if trainNetId and trainNetId ~= 0 and NetworkDoesNetworkIdExist(trainNetId) then
                            activeTrainBlips[trainType] = Citizen.InvokeNative(0x23F74C2FDA6E7C61, 1664425300, trainVeh)
                            if activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) then
                                SetBlipSprite(activeTrainBlips[trainType], -250506368)
                                local blipName = trainType == "west" and (Config.TrainBlipNameWest or "West Train") or (Config.TrainBlipNameEast or "East Train")
                                Citizen.InvokeNative(0x9CB1A1623062F402, activeTrainBlips[trainType], blipName)
                                SetBlipScale(activeTrainBlips[trainType], 1.0)
                                print("^6[BLIP DEBUG] Maintenance thread: blip recreated successfully for trainType " .. trainType .. "^7")
                            end
                        end
                    end
                end
            end
            print("^6[BLIP DEBUG] Maintenance thread exiting for trainType: " .. trainType .. "^7")
        end)
        
        local hb = 0
        while trainExists and DoesEntityExist(trainVeh) do
            Wait(1000)
            
            if not DoesEntityExist(trainVeh) then
                trainExists = false
                break
            end
            
            trainCoords = GetEntityCoords(trainVeh)
            speed = GetEntitySpeed(trainVeh)
            playersOnTrain = 0
            
            for _, playerId in ipairs(GetActivePlayers()) do
                playerPed = GetPlayerPed(playerId)
                if playerPed and DoesEntityExist(playerPed) then
                    local onTrain, playerCoords = IsPedAlignedWithTrain(playerPed, trainVeh, trainCoords)
                    if onTrain then
                        playerSpeed = GetEntitySpeed(playerPed)
                        playerCoords = playerCoords or GetEntityCoords(playerPed)
                        dist = #(playerCoords - trainCoords)
                        if math.abs(playerSpeed - speed) < 0.5 and dist < 150.0 then
                            playersOnTrain = playersOnTrain + 1
                        end
                    end
                end
            end

            hb = hb + 1
            if hb >= 10 then
                local nid = NetworkGetNetworkIdFromEntity(trainVeh)
                if nid and nid ~= 0 and NetworkDoesNetworkIdExist(nid) then
                    TriggerServerEvent('nt_trains_ticket:server:trainHeartbeat', trainType, nid, playersOnTrain)
                end
                hb = 0
            end
            
            -- Only start despawn logic after train has stopped at least once
            if not stoppedOnce and speed == 0 then
                stoppedOnce = true
            end
            
            -- If train is moving, no players on it, and it has stopped at least once
            if speed > 0 and playersOnTrain == 0 and stoppedOnce then
                emptyTrainTimer = emptyTrainTimer + 1000
                
                -- Log progress toward despawn
                if emptyTrainTimer % 10000 == 0 then
                    print("^4[BLIP DEBUG] Empty train timer for " .. trainType .. ": " .. emptyTrainTimer .. "ms / " .. Config.TrainDespawnTimer .. "ms^7")
                end
                
                -- If timer exceeds despawn threshold, clean up the train
                if emptyTrainTimer >= Config.TrainDespawnTimer then
                    print("^1[BLIP DEBUG] DESPAWN TIMER TRIGGERED for trainType: " .. trainType .. " - calling CleanupTrain^7")
                    -- Verify the train is still the same one before cleanup
                    local currentNetId = GetTrainNetId(trainVeh)
                    if currentNetId == originalTrainNetId then
                        CleanupTrain(trainVeh, trainType)
                    else
                        print("^1[BLIP DEBUG] Net ID mismatch, not cleaning up. Current: " .. tostring(currentNetId) .. " Original: " .. tostring(originalTrainNetId) .. "^7")
                    end
                    trainExists = false
                    break
                end
            else
                -- Reset timer if conditions aren't met
                if emptyTrainTimer > 0 then
                    print("^4[BLIP DEBUG] Resetting empty train timer for " .. trainType .. " (speed: " .. speed .. ", players: " .. playersOnTrain .. ", stoppedOnce: " .. tostring(stoppedOnce) .. ")^7")
                end
                emptyTrainTimer = 0
            end
        end
        
        -- Final cleanup when despawn monitor exits (whether by despawn timer or train deletion)
        print("^1[BLIP DEBUG] Despawn monitor cleanup for trainType: " .. trainType .. " - train exists: " .. tostring(DoesEntityExist(trainVeh)) .. "^7")
        trainExists = false
        
        -- Remove this train's blip
        if Config.UseTrainBlips and activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) then
            print("^1[BLIP DEBUG] Despawn monitor removing blip for trainType: " .. trainType .. "^7")
            RemoveBlip(activeTrainBlips[trainType])
            activeTrainBlips[trainType] = nil
        else
            print("^3[BLIP DEBUG] Despawn monitor: no blip to remove for trainType: " .. trainType .. " (exists: " .. tostring(activeTrainBlips[trainType] ~= nil) .. ", valid: " .. tostring(activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) or false) .. ")^7")
        end
        
        -- If train still exists somehow, make sure to release the train type
        if DoesEntityExist(trainVeh) then
            print("^1[BLIP DEBUG] Despawn monitor: releasing train type " .. trainType .. "^7")
            TriggerServerEvent('nt_trains_ticket:server:releaseTrainType', trainType)
        end
    end)
end




-- Helper: GetTrackIndexFromCoords stub (returns 0 for now, can be improved with real logic)
function GetTrackIndexFromCoords(coords)
    return 0
end

-- Helper function to add NPCs to tracking arrays
function AddTrainNPCToTracking(ped, npcType)
    if not ped or not DoesEntityExist(ped) then return end
    
    if npcType == "driver" then
        table.insert(spawnedTrainDrivers, ped)
    elseif npcType == "guard" then
        table.insert(spawnedTrainGuards, ped)
    elseif npcType == "passenger" then
        table.insert(spawnedTrainPassengers, ped)
    end
end

-- Helper function to remove NPCs from tracking arrays
function RemoveTrainNPCFromTracking(ped)
    if not ped then return end
    
    -- Check and remove from drivers
    for i, driver in ipairs(spawnedTrainDrivers) do
        if driver == ped then
            table.remove(spawnedTrainDrivers, i)
            return
        end
    end
    
    -- Check and remove from guards
    for i, guard in ipairs(spawnedTrainGuards) do
        if guard == ped then
            table.remove(spawnedTrainGuards, i)
            return
        end
    end
    
    -- Check and remove from passengers
    for i, passenger in ipairs(spawnedTrainPassengers) do
        if passenger == ped then
            table.remove(spawnedTrainPassengers, i)
            return
        end
    end
end

-- Local cleanup function for resource stop (no server communication)
function CleanupTrainLocal(trainVeh)
    if not trainVeh or not DoesEntityExist(trainVeh) then 
        return 
    end
    
    
    -- Get all train cars/wagons for comprehensive cleanup
    local trainCars = {}
    table.insert(trainCars, trainVeh) -- Add the main train entity
    
    -- Check for additional train cars/wagons
    local carIndex = 0
    while carIndex < 20 do -- Check up to 20 cars (should be more than enough)
        local trainCar = Citizen.InvokeNative(0x08C2ACB934C70129, trainVeh, carIndex) -- GetTrainCarriage
        if trainCar and DoesEntityExist(trainCar) and trainCar ~= trainVeh then
            table.insert(trainCars, trainCar)
        else
            break
        end
        carIndex = carIndex + 1
    end
    
    
    -- Clean up NPCs using TrainNPCCache for this train
    local trainNetId = GetTrainNetId(trainVeh)
    if trainNetId and TrainNPCCache[trainNetId] then
        for ped, _ in pairs(TrainNPCCache[trainNetId]) do
            if DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            end
        end
        -- Clear cache for this train
        TrainNPCCache[trainNetId] = nil
    end
    
    -- Delete all train cars
    for _, car in ipairs(trainCars) do
        if DoesEntityExist(car) then
            SetEntityAsMissionEntity(car, true, true)
            DeleteEntity(car)
        end
    end
    
end


-- Patch: Track spawned train and driver for cleanup

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    -- Robust cleanup: clean up all trains, drivers, blips, and NPCs
    
    -- Remove active train blips first
    for trainType, blip in pairs(activeTrainBlips) do
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
            activeTrainBlips[trainType] = nil
        end
    end
    
    -- Clean up all spawned trains using local cleanup (no server communication)
    local trainsCleanedUp = 0
    for _, train in ipairs(spawnedTrains) do
        if train and DoesEntityExist(train) then
            CleanupTrainLocal(train) -- Use local cleanup to avoid server communication issues
            trainsCleanedUp = trainsCleanedUp + 1
        end
    end
    
    -- Clean up NPCs in TrainNPCCache for all trains, then clear the cache
    for trainNetId, pedSet in pairs(TrainNPCCache) do
        for ped, _ in pairs(pedSet) do
            if DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            end
        end
        TrainNPCCache[trainNetId] = nil
    end
    -- Reset the entire cache table
    TrainNPCCache = {}
    
    -- Clean up station NPCs
    local stationNPCsCleanedUp = 0
    for _, npc in ipairs(spawnedStationNPCs) do
        if npc and DoesEntityExist(npc) then
            SetEntityAsMissionEntity(npc, true, true)
            DeleteEntity(npc)
            stationNPCsCleanedUp = stationNPCsCleanedUp + 1
        end
    end
    
    -- Additional safety cleanup: search for any remaining train entities in the world
    -- This catches any trains that might not be in our tracking arrays
    local additionalTrainsFound = 0
    local playerCoords = GetEntityCoords(PlayerPedId())
    local nearbyVehicles = GetGamePool('CVehicle')
    
    for _, vehicle in ipairs(nearbyVehicles) do
        if DoesEntityExist(vehicle) then
            local vehicleModel = GetEntityModel(vehicle)
            -- Check if it's a train model (you might need to adjust these model checks based on your config)
            if IsThisModelATrain(vehicleModel) then
                local distance = #(GetEntityCoords(vehicle) - playerCoords)
                -- Only clean up trains within a reasonable distance (10000 units)
                if distance < 10000.0 then
                    CleanupTrainLocal(vehicle)
                    additionalTrainsFound = additionalTrainsFound + 1
                end
            end
        end
    end
    
   
    -- Clear all tracking arrays
    spawnedStationNPCs = {}
    spawnedTrains = {}
    spawnedTrainDrivers = {}
    spawnedTrainGuards = {}
    spawnedTrainPassengers = {}
    
    -- Reset state variables
    activeStation = nil
    destinationStation = nil
    activeTrainBlips = {
        east = nil,
        west = nil
    }
    
    -- Reset pending state variables
    if pendingAvailabilityCheck then
        pendingAvailabilityCheck.waiting = false
        pendingAvailabilityCheck.trainType = nil
        pendingAvailabilityCheck.callback = nil
    end
    
    if pendingLockCheck then
        pendingLockCheck.waiting = false
        pendingLockCheck.trainType = nil
        pendingLockCheck.callback = nil
    end
    
end)

--[[

-- Command to set a range of junctions for a specific track id
RegisterCommand("togglejunction", function(source, args, rawCommand)
    if #args < 4 then
        print("Usage: /togglejunction [trackId] [startJunction] [endJunction] [0|1]")
        print("Example: /togglejunction -705539859 2 8 1")
        return
    end
    
    local trackId = math.tointeger(args[1])
    local startJunction = tonumber(args[2])
    local endJunction = tonumber(args[3])
    local setState = tonumber(args[4])
    
    if not trackId or not startJunction or not endJunction or (setState ~= 0 and setState ~= 1) then
        print("Invalid arguments. Usage: /toggleeastjunction [trackId] [startJunction] [endJunction] [0|1]")
        return
    end
    
    if startJunction > endJunction then
        print("Start junction cannot be greater than end junction")
        return
    end
    
    print(("[Trains] Setting track %d, junctions %d-%d to %d"):format(trackId, startJunction, endJunction, setState))
    
    for i = startJunction, endJunction do
        Citizen.InvokeNative(0xE6C5E2125EB210C1, trackId, i, setState)
        Citizen.InvokeNative(0x3ABFA128F5BF5A70, trackId, i, setState)
        Wait(25)
    end
    
    print(("[Trains] Successfully set %d junctions on track %d"):format(endJunction - startJunction + 1, trackId))
end, false)

--]]