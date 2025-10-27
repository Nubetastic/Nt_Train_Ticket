-- tram_server.lua
-- Server-side tram management for ticket system

local tramNetId = nil
local tramConductorNetId = nil

-- Utility: Check if tram exists
local function TramExists()
    return tramNetId ~= nil
end

-- Handle tram spawn requests from clients
RegisterNetEvent("Tram:RequestSpawn", function()
    local src = source
    if not TramExists() then
        -- Allow this client to spawn the tram
        TriggerClientEvent("Tram:AllowSpawn", src)
    else
        -- Tell client to use the existing tram
        TriggerClientEvent("Tram:SyncTram", src, tramNetId, tramConductorNetId)
    end
end)

-- Store tram network IDs when spawned by a client
RegisterNetEvent("Tram:StoreNetIds", function(tramId, conductorId)
    tramNetId = tramId
    tramConductorNetId = conductorId
    -- Sync to all clients
    TriggerClientEvent("Tram:SyncTram", -1, tramNetId, tramConductorNetId)
end)

-- Handle tram despawn (e.g., if deleted or abandoned)
RegisterNetEvent("Tram:Despawn", function()
    tramNetId = nil
    tramConductorNetId = nil
    -- Notify all clients
    TriggerClientEvent("Tram:Despawned", -1)
end)

-- On player join, sync tram if it exists
AddEventHandler('playerJoining', function(playerId)
    if TramExists() then
        TriggerClientEvent("Tram:SyncTram", playerId, tramNetId, tramConductorNetId)
    end
end)

-- Optionally, add a command to force tram reset
RegisterCommand('tramreset', function(source)
    tramNetId = nil
    tramConductorNetId = nil
    TriggerClientEvent("Tram:Despawned", -1)
end, true)
