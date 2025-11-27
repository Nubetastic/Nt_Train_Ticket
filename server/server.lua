local RSGCore = exports['rsg-core']:GetCoreObject()

-- Server-side train tracking
local activeTrains = {
    east = { active = false, owner = nil, netId = nil, candidates = {}, route = nil },
    west = { active = false, owner = nil, netId = nil, candidates = {}, route = nil }
}

local trackedTrains = {}

local function ensureTracked(netId, trainType)
    if not netId then return end
    trackedTrains[netId] = trackedTrains[netId] or { type = trainType, last = GetGameTimer(), players = 0 }
    if trainType then trackedTrains[netId].type = trainType end
end

local function isPlayerOnline(id)
    for _, pid in ipairs(GetPlayers()) do
        if tonumber(pid) == tonumber(id) then return true end
    end
    return false
end

local function addCandidate(trainType, playerId)
    local data = activeTrains[trainType]
    if not data then return end
    data.candidates = data.candidates or {}
    for _, c in ipairs(data.candidates) do
        if c.id == playerId then return end
    end
    table.insert(data.candidates, { id = playerId, t = GetGameTimer() })
end

local function removeCandidate(trainType, playerId)
    local data = activeTrains[trainType]
    if not data or not data.candidates then return end
    for i = #data.candidates, 1, -1 do
        if data.candidates[i].id == playerId then
            table.remove(data.candidates, i)
        end
    end
end

local function pruneCandidates()
    local now = GetGameTimer()
    local ttl = 10 * 60 * 1000
    for t, data in pairs(activeTrains) do
        if data.candidates then
            for i = #data.candidates, 1, -1 do
                local c = data.candidates[i]
                if (not isPlayerOnline(c.id)) or (now - (c.t or 0) > ttl) then
                    table.remove(data.candidates, i)
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(600000)
        pruneCandidates()
    end
end)

RegisterNetEvent('nt_trains_ticket:server:trainHeartbeat')
AddEventHandler('nt_trains_ticket:server:trainHeartbeat', function(trainType, trainNetId, playersOnTrain)
    if trainNetId and trainNetId ~= 0 then
        ensureTracked(trainNetId, trainType)
        trackedTrains[trainNetId].last = GetGameTimer()
        trackedTrains[trainNetId].players = playersOnTrain or 0
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        local now = GetGameTimer()
        for netId, info in pairs(trackedTrains) do
            if now - (info.last or 0) > 60000 then
                local t = info.type
                -- Check if train owner is still online before orphaning
                if t and activeTrains[t] and activeTrains[t].netId == netId then
                    local ownerOnline = activeTrains[t].owner and isPlayerOnline(activeTrains[t].owner)
                    
                    if ownerOnline then
                        -- Owner is still online - don't orphan
                        print("[SERVER] Train " .. t .. " (netId: " .. netId .. ") timed out but owner " .. activeTrains[t].owner .. " is still online. Skipping orphan cleanup.")
                    else
                        -- Owner is offline - check if entity still exists on any client
                        print("[SERVER] Train " .. t .. " (netId: " .. netId .. ") orphaned - owner offline. Sending cleanup to one player to verify and cleanup.")
                        local players = GetPlayers()
                        if #players > 0 then
                            local targetPlayer = tonumber(players[1])
                            TriggerClientEvent('nt_trains_ticket:client:cleanupOrphanedTrain', targetPlayer, t, netId)
                        else
                            print("[SERVER] No players online to handle orphan cleanup for train " .. t .. " (netId: " .. netId .. ").")
                        end
                    end
                    
                    -- Cleanup server-side tracking
                    activeTrains[t].active = false
                    activeTrains[t].owner = nil
                    activeTrains[t].netId = nil
                    activeTrains[t].candidates = {}
                    activeTrains[t].route = nil
                    TriggerClientEvent('nt_trains_ticket:client:removeTrainBlip', -1, t)
                end
                trackedTrains[netId] = nil
            end
        end
    end
end)

local function assignTrainMonitor(trainType, excludeSrc)
    local data = activeTrains[trainType]
    if not data or not data.active or not data.netId then return end
    local newOwner = nil
    if data.candidates and #data.candidates > 0 then
        for i, c in ipairs(data.candidates) do
            if c.id ~= excludeSrc and isPlayerOnline(c.id) then
                newOwner = c.id
                table.remove(data.candidates, i)
                break
            end
        end
    end
    if not newOwner then
        for _, pid in ipairs(GetPlayers()) do
            local id = tonumber(pid)
            if id and id ~= excludeSrc then
                newOwner = id
                break
            end
        end
    end
    if newOwner then
        data.owner = newOwner
        local r = data.route or {}
        print("[SERVER] Assigning train " .. trainType .. " (netId: " .. data.netId .. ") to replacement owner: " .. newOwner)
        TriggerClientEvent('nt_trains_ticket:client:assignTrainMonitor', newOwner, trainType, data.netId, r.current, r.destination, r.direction, r.model)
    else
        -- No replacement owner found - cleanup the train
        local netId = data.netId
        print("[SERVER] No replacement owner found for train " .. trainType .. " (netId: " .. netId .. "). Cleaning up.")
        
        -- Only send cleanup to one player if there are any online
        local players = GetPlayers()
        if #players > 0 then
            local targetPlayer = tonumber(players[1])
            TriggerClientEvent('nt_trains_ticket:client:cleanupOrphanedTrain', targetPlayer, trainType, netId)
        end
        
        data.active = false
        data.owner = nil
        data.netId = nil
        data.candidates = {}
        data.route = nil
        TriggerClientEvent('nt_trains_ticket:client:removeTrainBlip', -1, trainType)
        
        -- Also clean up from tracked trains so it won't trigger orphan cleanup later
        if netId then
            trackedTrains[netId] = nil
        end
    end
end


-- Event to check if a train type is available
RegisterNetEvent('nt_trains_ticket:server:checkTrainAvailable')
AddEventHandler('nt_trains_ticket:server:checkTrainAvailable', function(trainType)
    local src = source
    local isAvailable = not activeTrains[trainType].active
    
    TriggerClientEvent('nt_trains_ticket:client:trainAvailabilityResponse', src, trainType, isAvailable)
   --print("[SERVER] Train availability check for " .. trainType .. ": " .. tostring(isAvailable))
end)

-- Event to lock a train type for a player
RegisterNetEvent('nt_trains_ticket:server:lockTrainType')
AddEventHandler('nt_trains_ticket:server:lockTrainType', function(trainType, trainNetId)
    local src = source
    
    -- Double check it's not already locked
    if not activeTrains[trainType].active then
        activeTrains[trainType].active = true
        activeTrains[trainType].owner = src
        activeTrains[trainType].netId = trainNetId
        
        TriggerClientEvent('nt_trains_ticket:client:trainLockResponse', src, trainType, true)
       --print("[SERVER] Train type " .. trainType .. " locked by player " .. src .. " with NetID: " .. tostring(trainNetId))
    else
        TriggerClientEvent('nt_trains_ticket:client:trainLockResponse', src, trainType, false)
       --print("[SERVER] Train type " .. trainType .. " lock failed - already in use")
    end
end)

-- Event to release a train type
RegisterNetEvent('nt_trains_ticket:server:releaseTrainType')
AddEventHandler('nt_trains_ticket:server:releaseTrainType', function(trainType)
    local src = source
    
    -- Only allow the owner or server to release the lock
    if activeTrains[trainType].active and (activeTrains[trainType].owner == src or src == 0) then
        activeTrains[trainType].active = false
        activeTrains[trainType].owner = nil
        activeTrains[trainType].netId = nil
        activeTrains[trainType].candidates = {}
        activeTrains[trainType].route = nil
        
       --print("[SERVER] Train type " .. trainType .. " released by player " .. src)
    else
       --print("[SERVER] Train type " .. trainType .. " release failed - not owner or not active")
    end
end)

-- Event to handle train spawning (now just forwards to client after checking availability)
RegisterNetEvent('nt_trains_ticket:server:spawnTrain')
AddEventHandler('nt_trains_ticket:server:spawnTrain', function(coords, direction, destinationStation, trainType)
    local src = source
    
    -- Check if this train type is available
    if not activeTrains[trainType].active then
        -- Forward spawn request to client
        TriggerClientEvent('nt_trains_ticket:client:spawnTrain', src, coords, direction, destinationStation, trainType)
       --print("[SERVER] Forwarding train spawn request to player " .. src)
    else
        -- Notify client that train is already active
        TriggerClientEvent('nt_trains_ticket:client:trainAlreadyActive', src, trainType)
       --print("[SERVER] Train spawn request denied - train type " .. trainType .. " already active")
    end
end)

-- Broadcast station blips to all clients when resource starts

-- Robust cleanup on resource stop (BGS style)
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        for trainType, data in pairs(activeTrains) do
            if data.active and data.netId then
                -- Notify one client to clean up orphaned trains during resource stop
                local players = GetPlayers()
                if #players > 0 then
                    local targetPlayer = tonumber(players[1])
                    TriggerClientEvent('nt_trains_ticket:client:cleanupOrphanedTrain', targetPlayer, trainType, data.netId)
                end
            end
            activeTrains[trainType].active = false
            activeTrains[trainType].owner = nil
            activeTrains[trainType].netId = nil
        end
        print("[SERVER] All trains cleaned up on resource stop.")
    end
end)

-- Still broadcast station blips on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        TriggerClientEvent('nt_trains_ticket:client:createStationBlips', -1)
        -- Reset train tracking on resource start
        activeTrains = {
            east = { active = false, owner = nil, netId = nil, candidates = {}, route = nil },
            west = { active = false, owner = nil, netId = nil, candidates = {}, route = nil }
        }
    end
end)

-- Handle player disconnect - release any trains they owned
AddEventHandler('playerDropped', function()
    local src = source
    print("[SERVER] Player " .. src .. " disconnected.")
    for trainType, data in pairs(activeTrains) do
        if data.active and data.owner == src then
            if data.netId then
                print("[SERVER] Player " .. src .. " was owner of train type: " .. trainType .. " (netId: " .. data.netId .. "). Attempting to assign replacement.")
                assignTrainMonitor(trainType, src)
                if data.active == false then
                    print("[SERVER] No replacement owner found. Train " .. trainType .. " immediately cleaned up.")
                end
            end
        end
        removeCandidate(trainType, src)
    end
end)

AddEventHandler('playerJoining', function(playerId)
    print("[SERVER] Player " .. playerId .. " joining. Checking for unowned trains.")
    for trainType, data in pairs(activeTrains) do
        if data.active and data.owner == nil and data.netId then
            print("[SERVER] Found unowned train " .. trainType .. " (netId: " .. data.netId .. "). Assigning to new player.")
            assignTrainMonitor(trainType, -1)
        end
    end
end)

-- Charge all players on a train the ticket price
RegisterNetEvent('nt_trains_ticket:server:playerTicketCharge')
AddEventHandler('nt_trains_ticket:server:playerTicketCharge', function(playerId, current, trainType, trainNetId)
    local ticketPrice = Config.TicketPrice
    local Player = RSGCore.Functions.GetPlayer(playerId)
    if Player then
        Player.Functions.RemoveMoney('cash', ticketPrice)
        TriggerClientEvent('ox_lib:notify', playerId, {
            title = 'Next Station',
            description = current,
            type = 'inform',
            duration = 10000
        })
        if trainType and activeTrains[trainType] then
            if not activeTrains[trainType].netId or not trainNetId or activeTrains[trainType].netId == trainNetId then
                addCandidate(trainType, playerId)
            end
        end
    end
end)

RegisterNetEvent('nt_trains_ticket:server:registerRoute')
AddEventHandler('nt_trains_ticket:server:registerRoute', function(trainType, trainNetId, currentStation, destinationStation, direction, model)
    if not activeTrains[trainType] then return end
    if trainNetId and trainNetId ~= 0 then
        activeTrains[trainType].netId = trainNetId
    end
    activeTrains[trainType].route = {
        current = currentStation,
        destination = destinationStation,
        direction = direction,
        model = model
    }
end)

RegisterNetEvent('nt_trains_ticket:server:createTrainBlip')
AddEventHandler('nt_trains_ticket:server:createTrainBlip', function(trainNetId, trainType)
    local src = source
    
    -- Validate the network ID
    if not trainNetId or trainNetId == 0 then
        print("[SERVER] Invalid train network ID received from player " .. src)
        return
    end
    
    -- Update the netId in our tracking
    if activeTrains[trainType] then
        activeTrains[trainType].netId = trainNetId
        ensureTracked(trainNetId, trainType)
        
        -- Log successful tracking update
        if Config.Debug then
            print("[SERVER] Updated train tracking for " .. trainType .. " with NetID: " .. trainNetId)
        end
    else
        if Config.Debug then
            print("[SERVER] Warning: Tried to update netId for non-active train type: " .. trainType)
        end
    end
    
    -- Broadcast to ALL clients to create the networked blip
    TriggerClientEvent('nt_trains_ticket:client:createTrainBlip', -1, trainNetId, trainType)
    
    if Config.Debug then
        print("[SERVER] Broadcasted train blip creation to all clients for NetID: " .. trainNetId .. " (Type: " .. trainType .. ")")
    end
end)

RegisterNetEvent('nt_trains_ticket:server:removeTrainBlip')
AddEventHandler('nt_trains_ticket:server:removeTrainBlip', function(trainType, trainNetId)
    local src = source
    print("[SERVER] Received train blip removal request from player " .. src .. " for trainType: " .. trainType .. " netId: " .. tostring(trainNetId))
    
    -- Release the train type and notify clients to clean up orphaned train
    if trainType and activeTrains[trainType] then
        -- Only cleanup if the network IDs match (or trainNetId is provided)
        -- This prevents cleaning up a newly spawned train of the same type
        if trainNetId and activeTrains[trainType].netId == trainNetId and activeTrains[trainType].netId then
            print("[SERVER] Train " .. trainType .. " (netId: " .. trainNetId .. ") cleanup confirmed. Sending to one player.")
            
            -- Send to one player instead of all clients
            local players = GetPlayers()
            if #players > 0 then
                local targetPlayer = tonumber(players[1])
                TriggerClientEvent('nt_trains_ticket:client:cleanupOrphanedTrain', targetPlayer, trainType, activeTrains[trainType].netId)
            end
            
            activeTrains[trainType].active = false
            activeTrains[trainType].owner = nil
            activeTrains[trainType].netId = nil
            activeTrains[trainType].candidates = {}
            activeTrains[trainType].route = nil
            
            -- Broadcast blip removal to all clients
            TriggerClientEvent('nt_trains_ticket:client:removeTrainBlip', -1, trainType)
            print("[SERVER] Released train type " .. trainType)
        elseif not trainNetId and activeTrains[trainType].netId then
            -- Fallback for older calls without network ID
            print("[SERVER] Train " .. trainType .. " cleanup (legacy, no netId). Sending to one player.")
            
            local players = GetPlayers()
            if #players > 0 then
                local targetPlayer = tonumber(players[1])
                TriggerClientEvent('nt_trains_ticket:client:cleanupOrphanedTrain', targetPlayer, trainType, activeTrains[trainType].netId)
            end
            
            activeTrains[trainType].active = false
            activeTrains[trainType].owner = nil
            activeTrains[trainType].netId = nil
            activeTrains[trainType].candidates = {}
            activeTrains[trainType].route = nil
            
            -- Broadcast blip removal to all clients
            TriggerClientEvent('nt_trains_ticket:client:removeTrainBlip', -1, trainType)
            print("[SERVER] Released train type " .. trainType)
        else
            print("[SERVER] NetID mismatch - ignoring cleanup. Expected: " .. tostring(activeTrains[trainType].netId) .. " Got: " .. tostring(trainNetId))
        end
    end
end)