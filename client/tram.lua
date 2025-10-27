-- tram.lua
-- Handles tram spawning and despawning for ticket system


local tram
local tramConductor
local canSpawnTram = false
local tramNetId = nil
local tramConductorNetId = nil

-- Utility: Create tram vehicle and conductor
local tramPassengers = {}

local function CleanupTramEntities()
    if tram and DoesEntityExist(tram) then
        DeleteEntity(tram)
    end
    tram = nil
    if tramConductor and DoesEntityExist(tramConductor) then
        DeleteEntity(tramConductor)
    end
    tramConductor = nil
    if tramPassengers then
        for _, ped in ipairs(tramPassengers) do
            if ped and DoesEntityExist(ped) then
                DeleteEntity(ped)
            end
        end
    end
    tramPassengers = {}
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        CleanupTramEntities()
    end
end)

local function CreateTram()
    tramPassengers = {}
    -- Prevent multiple trams
    local tramModel = Config.Trolley
    if Config.Trams and type(Config.Trams) == "table" then
        local keys = {}
        for hash, _ in pairs(Config.Trams) do table.insert(keys, hash) end
        if #keys > 0 then tramModel = Config.Trams[math.random(#keys)] end
    end

    local numWagons = Citizen.InvokeNative(0x635423d55ca84fc8, tramModel)
    for i = 0, numWagons - 1 do
        local wagonModel = Citizen.InvokeNative(0x8df5f6a19f99f0d5, tramModel, i)
        RequestModel(wagonModel)
        while not HasModelLoaded(wagonModel) do
            Wait(100)
        end
    end
    -- Spawn tram
    tram = Citizen.InvokeNative(0xC239DBD9A57D2A71, tramModel, Config.TramSpawnLocation, true, Config.UsePassengersTram, false, true)
    SetTrainSpeed(tram, 2.0)
    Citizen.InvokeNative(0x4182C037AA1F0091, tram, true)
    Citizen.InvokeNative(0x8EC47DD4300BF063, tram, 0.0)

    -- Network tram entity
    NetworkRegisterEntityAsNetworked(tram)

    -- Get conductor
    tramConductor = GetPedInVehicleSeat(tram, -1)
    while not DoesEntityExist(tramConductor) do
        tramConductor = GetPedInVehicleSeat(tram, -1)
        SetEntityAsMissionEntity(tramConductor, true, true)
        Wait(1000)
    end
    -- Network conductor
    NetworkRegisterEntityAsNetworked(tramConductor)
    if NetworkDoesNetworkIdExist(NetworkGetNetworkIdFromEntity(tramConductor)) then
        SetNetworkIdExistsOnAllMachines(NetworkGetNetworkIdFromEntity(tramConductor), true)
    end
    -- Protect conductor
    SetPedCanBeKnockedOffVehicle(tramConductor, 1)
    SetEntityInvincible(tramConductor, true)
    Citizen.InvokeNative(0x9F8AA94D6D97DBF4, tramConductor, true)
    SetEntityAsMissionEntity(tramConductor, true, true)
    SetEntityCanBeDamaged(tramConductor, false)

    -- Network all passengers (if any) - scan NPCs near spawn and keep those in a train
    local passengerNetIds = {}
    local spawnLocation = Config.TramSpawnLocation
    local peds = GetGamePool and GetGamePool("CPed") or {}
    for _, ped in ipairs(peds) do
        if ped and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local coords = GetEntityCoords(ped)
            if #(coords - spawnLocation) <= 100.0 then
                if Citizen.InvokeNative(0x6F972C1AB75A1ED0, ped) then -- IS_PED_IN_ANY_TRAIN
                    NetworkRegisterEntityAsNetworked(ped)
                    if NetworkDoesNetworkIdExist(NetworkGetNetworkIdFromEntity(ped)) then
                        SetNetworkIdExistsOnAllMachines(NetworkGetNetworkIdFromEntity(ped), true)
                        table.insert(passengerNetIds, NetworkGetNetworkIdFromEntity(ped))
                    end
                    table.insert(tramPassengers, ped)
                end
            end
        end
    end

    -- Store network IDs on server (tram, conductor, passengers)
    local tramNetId = NetworkGetNetworkIdFromEntity(tram)
    local conductorNetId = NetworkGetNetworkIdFromEntity(tramConductor)
    TriggerServerEvent("Tram:StoreNetIds", tramNetId, conductorNetId, passengerNetIds)
end

-- Tram despawn logic: despawn if stuck/abandoned for X minutes

function TramDespawnMonitor()
    local lastCoords = nil
    local stoppedTime = 0
    local checkInterval = 5000 -- milliseconds (5 seconds)
    local abandonTime = 60000 -- milliseconds (1 minute)
    while true do
        Wait(checkInterval)
        if tram and DoesEntityExist(tram) then
            local tramCoords = GetEntityCoords(tram)
            if lastCoords then
                local dist = #(tramCoords - lastCoords)
                if dist < 0.5 then -- tram hasn't moved
                    stoppedTime = stoppedTime + checkInterval
                else
                    stoppedTime = 0
                end
            end
            lastCoords = tramCoords
            if stoppedTime >= abandonTime then
                -- Despawn tram
                CleanupTramEntities()
                -- Notify server
                TriggerServerEvent("Tram:Despawn")
                -- Respawn tram
                Wait(2000)
                RequestTramSpawn()
                stoppedTime = 0
                lastCoords = nil
            end
        else
            stoppedTime = 0
            lastCoords = nil
        end
    end
end

-- Only allow one tram at a time

-- Request to spawn tram (networked)
function RequestTramSpawn()
    -- Only request spawn if no tram exists locally
    if not tram or not DoesEntityExist(tram) then
        TriggerServerEvent("Tram:RequestSpawn")
    end
end

-- Server allows this client to spawn tram
RegisterNetEvent("Tram:AllowSpawn", function()
    CreateTram()
end)

-- Server syncs tram to this client
RegisterNetEvent("Tram:SyncTram", function(tramNetId, conductorNetId)
    if tramNetId and NetworkDoesNetworkIdExist(tramNetId) then
        tram = NetworkGetEntityFromNetworkId(tramNetId)
    end
    if conductorNetId and NetworkDoesNetworkIdExist(conductorNetId) then
        tramConductor = NetworkGetEntityFromNetworkId(conductorNetId)
    end
end)

-- Server notifies tram despawned
RegisterNetEvent("Tram:Despawned", function()
    CleanupTramEntities()
end)

-- Spawn tram on start and monitor for abandonment
CreateThread(function()
    local spawnLocation = Config.TramSpawnLocation
    if Config.EnableTram then
        while true do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local distToSpawn = #(playerCoords - spawnLocation)

            -- Tram spawn logic: only spawn if player is within 500 units
            if (not tram or not DoesEntityExist(tram)) and distToSpawn <= 500.0 then
                RequestTramSpawn()
            end

            -- Tram despawn logic: despawn if no players within 600 units
            if tram and DoesEntityExist(tram) then
                local playersNearby = false
                for _, playerId in ipairs(GetActivePlayers()) do
                    local ped = GetPlayerPed(playerId)
                    if ped and DoesEntityExist(ped) then
                        local coords = GetEntityCoords(ped)
                        local dist = #(coords - spawnLocation)
                        if dist <= 600.0 then
                            playersNearby = true
                            break
                        end
                    end
                end
                if not playersNearby then
                    CleanupTramEntities()
                    TriggerServerEvent("Tram:Despawn")
                end
            end
            Wait(60000) -- Check every 1 minute
        end
    end
end)
