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

local activeStation = nil
local destinationStation = nil
local activeTrainBlips = {
    east = nil,
    west = nil
}

local spawnedTrains = {}
local spawnedTrainDrivers = {}
local spawnedTrainGuards = {}
local spawnedTrainPassengers = {}
local spawnedStationNPCs = {}

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
local function chargeTicketPrice(trainVeh, current)
    -- Get train position and speed for proximity/sync check
    local trainCoords = GetEntityCoords(trainVeh)
    local speed = GetEntitySpeed(trainVeh)
    local heading = GetEntityHeading(trainVeh)

    -- Calculate the vector opposite the train's heading
    local rad = math.rad(heading)
    local behindVector = vector3(-math.sin(rad), math.cos(rad), 0.0) -- RedM heading is clockwise from North
    local behindDistance = 30.0 -- Distance behind the train to check (adjust as needed)
    local behindPoint = trainCoords + behindVector * behindDistance

    for _, playerId in ipairs(GetActivePlayers()) do
        local playerPed = GetPlayerPed(playerId)
        if playerPed and DoesEntityExist(playerPed) then
            if (IsPlayerRidingTrain(playerPed) or IsPedInAnyTrain(playerPed)) and (Citizen.InvokeNative(0x6DE03BCC15E81710, playerPed) == Citizen.InvokeNative(0x6DE03BCC15E81710, trainVeh)) then
                local playerSpeed = GetEntitySpeed(playerPed)
                local playerCoords = GetEntityCoords(playerPed)
                local distBehind = #(playerCoords - behindPoint)
                if math.abs(playerSpeed - speed) < 3 and distBehind < 150.0 then -- 150.0 is the radius behind, adjust as needed
                    -- Charge this player by sending their server id
                    TriggerServerEvent('nt_trains_ticket:server:playerTicketCharge', GetPlayerServerId(playerId), current)
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
            SetBlipSprite(StationBlip, 103490298, true)
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
            return
        end
    end
    
    -- Remove existing train blip for this train type if it exists
    if activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) then
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
        
        if Config.Debug then
            print("^2[TRAIN BLIP] Successfully created blip for train: " .. tostring(trainNetId) .. " (Type: " .. trainType .. ")^7")
        end
    else
        if Config.Debug then
            print("^1[TRAIN BLIP] Failed to create blip for train: " .. tostring(trainNetId) .. " (Type: " .. trainType .. ")^7")
        end
    end
end)

RegisterNetEvent('nt_trains_ticket:client:removeTrainBlip')
AddEventHandler('nt_trains_ticket:client:removeTrainBlip', function(trainType)
    trainType = trainType or "east" -- Default to east for backward compatibility
    
    if activeTrainBlips[trainType] and DoesBlipExist(activeTrainBlips[trainType]) then
        RemoveBlip(activeTrainBlips[trainType])
        activeTrainBlips[trainType] = nil
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
    -- Robust orphaned train cleanup (BGS style)
    if trainNetId and NetworkDoesNetworkIdExist(trainNetId) then
        local trainVeh = NetworkGetEntityFromNetworkId(trainNetId)
        if DoesEntityExist(trainVeh) then
            CleanupTrain(trainVeh, trainType)
        end
    end
    -- Also remove any blips if present
    for trainType, blip in pairs(activeTrainBlips) do
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
            activeTrainBlips[trainType] = nil
        end
    end
end)




-- === Train Spawning & Monitoring ===

-- Function to clean up a specific train and its components
function CleanupTrain(trainVeh, trainType)
    if not trainVeh or not DoesEntityExist(trainVeh) then 
        return 
    end
    
    
    -- Remove blip first and notify server to release the train type
    if trainType then
        TriggerServerEvent('nt_trains_ticket:server:removeTrainBlip', trainType)
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
    
    -- Remove any active blips if they exist
    for trainType, blip in pairs(activeTrainBlips) do
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
            activeTrainBlips[trainType] = nil
        end
    end
    
end

function SpawnTrain(currentStation, destinationStation, trainType)
    trainType = trainType or "east"
    local stations = trainType == "west" and Config.WestStations or Config.EastStations
    local trainModel = trainType == "west" and Config.WestTrain or Config.EastTrain
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

    local trainVeh = Citizen.InvokeNative(0xC239DBD9A57D2A71, trainModel, spawnCoords, spawnDirection, Config.UsePassengers, true, true)

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

    -- Initially set train speed to 0 to allow NPCs to get into place
    SetTrainSpeed(trainVeh, 0.0)
    SetTrainCruiseSpeed(trainVeh, 0.0)
    Citizen.InvokeNative(0x9F29999DFDF2AEB8, trainVeh, 0.0)
    Citizen.InvokeNative(0x4182C037AA1F0091, trainVeh, false)
    
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

    -- Ensure all NPCs on board are networked (driver, guards, passengers)
    -- Scan all seats in all train cars
    local trainCars = {}
    table.insert(trainCars, trainVeh)
    local carIndex = 0
    while carIndex < 20 do
        local trainCar = Citizen.InvokeNative(0x08C2ACB934C70129, trainVeh, carIndex)
        if trainCar and DoesEntityExist(trainCar) and trainCar ~= trainVeh then
            table.insert(trainCars, trainCar)
        else
            break
        end
        carIndex = carIndex + 1
    end

    for _, car in ipairs(trainCars) do
        for seat = -1, 15 do
            local ped = GetPedInVehicleSeat(car, seat)
            if ped and DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                NetworkRegisterEntityAsNetworked(ped)
                if NetworkDoesNetworkIdExist(NetworkGetNetworkIdFromEntity(ped)) then
                    SetNetworkIdExistsOnAllMachines(NetworkGetNetworkIdFromEntity(ped), true)
                end
            end
        end
    end

    
    Wait(5000)
    
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
            -- Update the server with the train's network ID
            TriggerServerEvent('nt_trains_ticket:server:createTrainBlip', trainNetId, trainType)
        end
    end
    
    -- Start train monitoring
    MonitorTrain(trainVeh, currentStation, destinationStation, trainType, spawnDirection)
    StartTrainDespawnMonitor(trainVeh, trainType)
end



function MonitorTrain(trainVeh, current, destinationStation, trainType, spawnDirection)
    if not trainVeh or not DoesEntityExist(trainVeh) then return end
    trainType = trainType or "east"
    local stations = trainType == "west" and Config.WestStations or Config.EastStations
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
                    offsetValue = stationData.BackwardOffset or 0.0
                else -- forward
                    offsetValue = stationData.ForwardOffset or 0.0
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
                    DebugTrainInfo({
                        Event = "Station Arrival",
                        ArrivedAt = previousStation,
                        NextStation = stationList[2] and stationList[2].station or "End of route",
                        RemainingStops = #stationList - 1,
                        Direction = direction and "Backward" or "Forward"
                    })
                    Wait(Config.StationWaitTime)
                    SetTrainCruiseSpeed(trainVeh, Config.TrainMaxSpeed)
                    Citizen.InvokeNative(0x787E43477746876F, trainVeh)

                    -- Move to next station in the route
                    DebugTrainInfo({
                        Event = "Moving to Next Station",
                        CurrentStation = previousStation,
                        NextStation = nextStation
                    })
                    local lastStation = previousStation
                    previousStation = nextStation
                    table.remove(stationList, 1)

                    -- If we've reached the end of the route, try to extend the route automatically
                    if #stationList == 1 then
                        direction = stationList[1].direction
                        -- Check if we need to flip direction at this junction before finding next station
                        local stations = trainType == "west" and Config.WestStations or Config.EastStations
                        local prevData = stations[stationList[1].station]
                        local nextCandidates = {}

                        if direction == false then -- Forward
                            if prevData and prevData.ForwardStation then
                                for _, s in ipairs(prevData.ForwardStation) do table.insert(nextCandidates, s) end
                            end
                        else -- Backward
                            if prevData and prevData.BackwardStation then
                                for _, s in ipairs(prevData.BackwardStation) do table.insert(nextCandidates, s) end
                            end
                        end
                        -- Pick the first valid next station (if any)
                        local nextAutoStation = nextCandidates[1]

                        if nextAutoStation then
                            -- Recalculate the route from previousStation to nextAutoStation, using current direction
                            local newRoute = FindShortestRoute(previousStation, nextAutoStation, direction, trainType)
                            -- Remove the first station (current) since we're already there
                            table.remove(newRoute, 1)
                            -- Append to stationList
                            for _, step in ipairs(newRoute) do
                                table.insert(stationList, step)
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

                    trainSetup = false
                    distanceFlip = false
                    Wait(5000) -- Wait before moving to next station
                    
                    chargeTicketPrice(trainVeh, previousStation)
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
        
        -- Pre-declare variables outside the loop for better performance
        local trainCoords, speed, playersOnTrain
        local playerPed, playerSpeed, playerCoords, dist
        
        while trainExists and DoesEntityExist(trainVeh) do
            Wait(1000)
            
            -- If train no longer exists, break out of the loop
            if not DoesEntityExist(trainVeh) then
                trainExists = false
                break
            end
            
            trainCoords = GetEntityCoords(trainVeh)
            speed = GetEntitySpeed(trainVeh)
            playersOnTrain = 0
            
            -- Check for players on or near the train
            for _, playerId in ipairs(GetActivePlayers()) do
                playerPed = GetPlayerPed(playerId)
                if playerPed and DoesEntityExist(playerPed) then
                    if IsPlayerRidingTrain(playerPed) or IsPedInAnyTrain(playerPed) then
                        playerSpeed = GetEntitySpeed(playerPed)
                        playerCoords = GetEntityCoords(playerPed)
                        dist = #(playerCoords - trainCoords)
                        if math.abs(playerSpeed - speed) < 0.5 and dist < 150.0 then
                            playersOnTrain = playersOnTrain + 1
                        end
                    end
                end
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
                end
                
                -- If timer exceeds despawn threshold, clean up the train
                if emptyTrainTimer >= Config.TrainDespawnTimer then
                    CleanupTrain(trainVeh, trainType)
                    trainExists = false
                    return
                end
            else
                -- Reset timer if conditions aren't met
                emptyTrainTimer = 0
            end
        end
        
        -- If we exited the loop without cleaning up (train disappeared), make sure to release the train type
        if trainExists == false and DoesEntityExist(trainVeh) == false then
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
    
    
    -- Clean up NPCs from all train cars
    local npcsRemoved = 0
    for _, car in ipairs(trainCars) do
        if DoesEntityExist(car) then
            -- Remove all passengers and NPCs from this car
            for seat = -1, 15 do -- Include driver seat (-1) and passenger seats (0-15)
                local ped = GetPedInVehicleSeat(car, seat)
                if ped and DoesEntityExist(ped) then
                    -- Delete the NPC without tracking array management (we'll clear arrays after)
                    SetEntityAsMissionEntity(ped, true, true)
                    DeleteEntity(ped)
                    npcsRemoved = npcsRemoved + 1
                end
            end
        end
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
    
    -- Clean up station NPCs
    local stationNPCsCleanedUp = 0
    for _, npc in ipairs(spawnedStationNPCs) do
        if npc and DoesEntityExist(npc) then
            SetEntityAsMissionEntity(npc, true, true)
            DeleteEntity(npc)
            stationNPCsCleanedUp = stationNPCsCleanedUp + 1
        end
    end
    
    -- Clean up any remaining train drivers
    local driversCleanedUp = 0
    for _, driver in ipairs(spawnedTrainDrivers) do
        if driver and DoesEntityExist(driver) then
            SetEntityAsMissionEntity(driver, true, true)
            DeleteEntity(driver)
            driversCleanedUp = driversCleanedUp + 1
        end
    end
    
    -- Clean up any remaining guards
    local guardsCleanedUp = 0
    for _, guard in ipairs(spawnedTrainGuards) do
        if guard and DoesEntityExist(guard) then
            SetEntityAsMissionEntity(guard, true, true)
            DeleteEntity(guard)
            guardsCleanedUp = guardsCleanedUp + 1
        end
    end
    
    -- Clean up any remaining passengers
    local passengersCleanedUp = 0
    for _, passenger in ipairs(spawnedTrainPassengers) do
        if passenger and DoesEntityExist(passenger) then
            SetEntityAsMissionEntity(passenger, true, true)
            DeleteEntity(passenger)
            passengersCleanedUp = passengersCleanedUp + 1
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