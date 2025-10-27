local RSGCore = exports['rsg-core']:GetCoreObject()

-- Server-side train tracking
local activeTrains = {
    east = { active = false, owner = nil, netId = nil },
    west = { active = false, owner = nil, netId = nil }
}

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
                -- Notify all clients to clean up orphaned trains
                TriggerClientEvent('nt_trains_ticket:client:cleanupOrphanedTrain', -1, trainType, data.netId)
            end
            activeTrains[trainType].active = false
            activeTrains[trainType].owner = nil
            activeTrains[trainType].netId = nil
        end
       --print("[SERVER] All trains cleaned up on resource stop.")
    end
end)

-- Still broadcast station blips on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        TriggerClientEvent('nt_trains_ticket:client:createStationBlips', -1)
        -- Reset train tracking on resource start
        activeTrains = {
            east = { active = false, owner = nil, netId = nil },
            west = { active = false, owner = nil, netId = nil }
        }
    end
end)

-- Handle player disconnect - release any trains they owned
AddEventHandler('playerDropped', function()
    local src = source
    for trainType, data in pairs(activeTrains) do
        if data.active and data.owner == src then
            -- Notify all clients to clean up orphaned train
            if data.netId then
                TriggerClientEvent('nt_trains_ticket:client:cleanupOrphanedTrain', -1, trainType, data.netId)
            end
            activeTrains[trainType].active = false
            activeTrains[trainType].owner = nil
            activeTrains[trainType].netId = nil
           --print("[SERVER] Released train type " .. trainType .. " after player " .. src .. " disconnected")
        end
    end
end)

-- Charge all players on a train the ticket price
RegisterNetEvent('nt_trains_ticket:server:playerTicketCharge')
AddEventHandler('nt_trains_ticket:server:playerTicketCharge', function(playerId, current)
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
    end
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
AddEventHandler('nt_trains_ticket:server:removeTrainBlip', function(trainType)
    local src = source
   --print("[SERVER] Received train blip removal request from player " .. src)
    -- Release the train type and notify all clients to clean up orphaned train
    if trainType and activeTrains[trainType] then
        if activeTrains[trainType].netId then
            TriggerClientEvent('nt_trains_ticket:client:cleanupOrphanedTrain', -1, trainType, activeTrains[trainType].netId)
        end
        activeTrains[trainType].active = false
        activeTrains[trainType].owner = nil
        activeTrains[trainType].netId = nil
       --print("[SERVER] Released train type " .. trainType)
    end
    -- Broadcast to ALL clients to remove the train blip
    TriggerClientEvent('nt_trains_ticket:client:removeTrainBlip', -1, trainType)
   --print("[SERVER] Broadcasted train blip removal to all clients for type: " .. trainType)
end)