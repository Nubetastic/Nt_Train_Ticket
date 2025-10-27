Config = {}

-- Enables some printouts.
Config.Debug = true

Config.TicketPrice = 1 -- charged every time the train leaves the station.
Config.TrainMaxSpeed = 15.0
Config.StopDistance = 75
Config.EaseToStop = 5
Config.StopSpeed = .25
Config.UsePassengers = true
Config.UsePassengersTram = true
Config.UseTrainBlips = true
Config.TrainBlipNameEast = "East Line"
Config.TrainBlipNameWest = "West Line"
Config.StationWaitTime = 60000 -- (1 minute)
Config.TrainDespawnTimer = 60000 -- (1 minute) while moving
Config.ProtectTrainDrivers = true
Config.EnableTram = true
Config.TramSpawnLocation = vec3(2608.38, -1203.12, 53.16)
Config.StationNPCRadius = 300 -- used for npc cleanup

-- Values are Train center value, test at riggs.
-- find the value where the train stops at the riggs platform.
-- riggs to flatnet, all stop at the same point.
-- List can be found at https://alloc8or.re/rdr3/doc/enums/eTrainConfig.txt
Config.EastTrains = {
    [0x10461E19] = 70.2, -- large passenger train
    [0x1C043595] = 70.5, -- large passenger train
    [0x3ADC4DA9] = 70.2, -- large passenger train with beds
    [0x35D17C43] = 82.74, -- large passenger train and cargo
    [0xFAB2FFB9] = 72.4, -- large passenger train
    [0x1C9936BB] = 70.45, -- passenger train with guards
    [0xCD2C7CA1] = 59, -- passenger train with private rooms
}

Config.WestTrains = {
    [0xCA19C62A] = 89, -- long 2 class central train
    [0x2D3645FA] = 72.45, -- large passenger train
    [0x4A73E49C] = 72.445, -- large passenger train, lower class
    [0x4C9CCB22] = 70.45, -- passenger train
    [0xE16CA3EF] = 70.5, -- passenger train with guards
}

Config.Trams = {
    0x73722125,
    0x90CB53CA,
    0x9E096E46,
    0xAEE0ECF5,
    0xEFBFBDD8,
    0x09B679D6,
}

--[[
Trains do not use native stops. They all stop at station coords with the added offset.

models
s_m_m_trainstationworker_01
u_m_m_rhdtrainstationworker_01
u_m_m_blwtrainstationworker_01
u_m_m_tumtrainstationworker_01
u_m_o_rigtrainstationworker_01
cs_cornwalltrainconductor

Each track has 3 configs for it, for example: East.
EastStations
EastRouteSpawns
EastStationsList

If you add or remove a location you need to do it for all three. This is done to simplify the code and make things more reliable.
]]

Config.EastStations = {
    ['Flatneck'] = {
        npcModel = 's_m_m_trainstationworker_01',
        npcCoords = vector4(-335.7726, -361.2146, 88.0802, 55.3916),
        ticketCoords = vector3(-337.29, -360.38, 88.07),
        SpawnBack = vector3(-138.08, -206.63, 95.33),
        SpawnForward = vector3(-555.15, -457.78, 80.72),
        stationCoords = vector3(-340.01, -349.59, 87.83), -- Used to stop the train, put this where you want passengers to board.
        ForwardOffset = 7.5,  -- Train offset when going forward
        BackwardOffset = 28.5, -- Train offset when going backward
        ForwardStation = { 'Valentine', 'Rhodes'},
        BackwardStation = { 'Riggs' },
    },
    ['Valentine'] = {
        npcModel = 'u_m_m_rhdtrainstationworker_01',
        npcCoords = vector4(-175.34, 631.94, 114.08, 334.5),
        ticketCoords = vector3(-174.44, 633.37, 114.08),
        SpawnBack = vector3(121.71, 610, 119.09),
        stationCoords = vector3(-164.01, 627.4, 113.51),
        SpawnForward = vector3(-73.77, 411.81, 112.81),
        ForwardOffset = 24.1,
        BackwardOffset = 8.8,
        ForwardStation = { 'Emerald' },
        BackwardStation = { 'Flatneck', 'Rhodes' },
        FlipDirectionIf = { 'Rhodes' }, -- This is for going between Rhodes and Valentine, both are backwards to each other but should arrive forward.
    },
    ['Emerald'] = {
        npcModel = 'cs_cornwalltrainconductor',
        npcCoords = vector4(1523.59, 442.58, 90.67, 271.96),
        ticketCoords = vector3(1525.11, 442.65, 90.68),
        SpawnBack = vector3(1398.34, 86.97, 92.31),
        stationCoords = vector3(1529.44, 438.96, 90.22),
        SpawnForward = vector3(1518.09, 604.74, 92.57),
        ForwardOffset = 9,
        BackwardOffset = 9.1,
        ForwardStation = { "Saint Denis" },
        BackwardStation = { 'Valentine' },
        SpawnDirectionReverse = true, -- Some tracks have a reverse spawn for some reason, this only affects the spawn.
    },
    ['Rhodes'] = {
        npcModel = 'u_m_m_rhdtrainstationworker_01',
        npcCoords = vector4(1230.17, -1298.63, 76.9, 228),
        ticketCoords = vector3(1231.42, -1299.64, 76.9),
        SpawnBack = vector3(1545.39, -1565.29, 67.93),
        stationCoords = vector3(1225.26, -1309.82, 76.42),
        SpawnForward = vector3(1034.82, -994.45, 67.45),
        ForwardOffset = 0,
        BackwardOffset = 0,
        ForwardStation = { "Saint Denis" },
        BackwardStation = { 'Valentine', 'Flatneck' },
        FlipDirectionIf = { 'Valentine' },
    },
    ['Saint Denis'] = {
        npcModel = 'u_m_m_blwtrainstationworker_01',
        npcCoords = vector4(2747.87, -1396.47, 46.18, 13.87),
        ticketCoords = vector3(2747.11, -1395.09, 46.18),
        stationCoords = vector3(2704.32, -1459.04, 45.74),
        SpawnBack = vector3(2897.75, -1202.78, 45.93),
        SpawnForward = vector3(2249.89, -1509.82, 45.77),
        ForwardOffset = 0,
        BackwardOffset = 0,
        ForwardStation = { 'Annesburg' },
        BackwardStation = { 'Rhodes', 'Emerald' },
    },
    ['Annesburg'] = {
        npcModel = 'u_m_m_rhdtrainstationworker_01',
        npcCoords = vector4(2933.14, 1282.57, 44.65, 69.52),
        ticketCoords = vector3(2931.58, 1283.03, 44.65),
        SpawnBack = vector3(3109.18, 1536.84, 57.99),
        stationCoords = vector3(2953.54, 1274.98, 43.92),
        SpawnForward = vector3(2900.11, 804.85, 50.6),
        ForwardOffset = 5,
        BackwardOffset = 10,
        ForwardStation = { 'Bacchus' },
        BackwardStation = { "Saint Denis" },
    },
    ['Bacchus'] = {
        npcModel = 'u_m_o_rigtrainstationworker_01',
        npcCoords = vector4(577.7686, 1677.2504, 187.9282, 306.5589), -- outside vector4(581.49, 1682.64, 187.78, 313.04),
        ticketCoords = vector3(578.8300, 1678.2676, 187.9282), -- outside vector3(582.25, 1683.68, 187.79),
        SpawnBack = vector3(387.65, 1786.92, 187.53),
        stationCoords = vector3(587.37, 1685.58, 187.52),
        SpawnForward = vector3(807.1, 1602.46, 192.91),
        ForwardOffset = -9,
        BackwardOffset = 5,
        ForwardStation = { 'Wallace' },
        BackwardStation = { 'Annesburg' },
    },
    ['Wallace'] = {
        npcModel = 's_m_m_trainstationworker_01',
        npcCoords = vector4(-1300.31, 400.15, 95.45, 147.54),
        ticketCoords = vector3(-1301.15, 398.87, 95.42),
        SpawnBack = vector3(-1511.87, 187.46, 104.43),
        stationCoords = vector3(-1309.62, 404.32, 95.02),
        SpawnForward = vector3(-1221.07, 556.99, 93.36),
        ForwardOffset = 7,
        BackwardOffset = 9,
        ForwardStation = { 'Riggs' },
        BackwardStation = { 'Bacchus' },
    },
    ['Riggs'] = {
        npcModel = 'u_m_o_rigtrainstationworker_01',
        npcCoords = vector4(-1094.36, -577.74, 82.4, 42.35),
        ticketCoords = vector3(-1095, -576.75, 82.4),
        SpawnBack = vector3(-903.51, -630.11, 72.33),
        stationCoords = vector3(-1102.6, -579.41, 81.92),
        SpawnForward = vector3(-1266.7, -425.11, 98.21),
        ForwardOffset = 0.0,
        BackwardOffset = 0.0,
        ForwardStation = { 'Flatneck' },
        BackwardStation = { 'Wallace' },
    }
}

Config.EastRouteSpawns = {
    ["Flatneck"] = {
        ["Valentine"] = "Forward",
        ["Emerald"] = "Forward",
        ["Rhodes"] = "Forward",
        ["Saint Denis"] = "Forward",
        ["Annesburg"] = "Forward",
        ["Bacchus"] = "Backward",
        ["Wallace"] = "Backward",
        ["Riggs"] = "Backward"
    },
    ["Valentine"] = {
        ["Flatneck"] = "Backward",
        ["Emerald"] = "Forward",
        ["Rhodes"] = "Backward",
        ["Saint Denis"] = "Forward",
        ["Annesburg"] = "Forward",
        ["Bacchus"] = "Backward",
        ["Wallace"] = "Backward",
        ["Riggs"] = "Backward"
    },
    ["Emerald"] = {
        ["Flatneck"] = "Backward",
        ["Valentine"] = "Backward",
        ["Rhodes"] = "Backward",
        ["Saint Denis"] = "Forward",
        ["Annesburg"] = "Forward",
        ["Bacchus"] = "Backward",
        ["Wallace"] = "Backward",
        ["Riggs"] = "Backward"
    },
    ["Rhodes"] = {
        ["Flatneck"] = "Backward",
        ["Valentine"] = "Backward",
        ["Emerald"] = "Backward",
        ["Saint Denis"] = "Forward",
        ["Annesburg"] = "Forward",
        ["Bacchus"] = "Backward",
        ["Wallace"] = "Backward",
        ["Riggs"] = "Backward"
    },
    ["Saint Denis"] = {
        ["Flatneck"] = "Backward",
        ["Valentine"] = "Backward",
        ["Emerald"] = "Backward",
        ["Rhodes"] = "Backward",
        ["Annesburg"] = "Forward",
        ["Bacchus"] = "Forward",
        ["Wallace"] = "Backward",
        ["Riggs"] = "Backward"
    },
    ["Annesburg"] = {
        ["Flatneck"] = "Backward",
        ["Valentine"] = "Backward",
        ["Emerald"] = "Backward",
        ["Rhodes"] = "Backward",
        ["Saint Denis"] = "Backward",
        ["Bacchus"] = "Forward",
        ["Wallace"] = "Forward",
        ["Riggs"] = "Backward"
    },
    ["Bacchus"] = {
        ["Flatneck"] = "Forward",
        ["Valentine"] = "Forward",
        ["Emerald"] = "Backward",
        ["Rhodes"] = "Backward",
        ["Saint Denis"] = "Backward",
        ["Annesburg"] = "Backward",
        ["Wallace"] = "Forward",
        ["Riggs"] = "Forward"
    },
    ["Wallace"] = {
        ["Flatneck"] = "Forward",
        ["Valentine"] = "Forward",
        ["Emerald"] = "Forward",
        ["Rhodes"] = "Forward",
        ["Saint Denis"] = "Forward",
        ["Annesburg"] = "Backward",
        ["Bacchus"] = "Backward",
        ["Riggs"] = "Forward"
    },
    ["Riggs"] = {
        ["Flatneck"] = "Forward",
        ["Valentine"] = "Forward",
        ["Emerald"] = "Forward",
        ["Rhodes"] = "Forward",
        ["Saint Denis"] = "Forward",
        ["Annesburg"] = "Forward",
        ["Bacchus"] = "Backward",
        ["Wallace"] = "Backward"
    }
}




Config.WestStations = {
    ["Macfarlane"] = {
        npcModel = 'cs_cornwalltrainconductor',
        npcCoords = vector4(-2494.1836, -2424.1868, 60.5994, 194.8784),
        ticketCoords = vector3(-2493.89, -2425.76, 60.59),
        stationCoords = vector3(-2499.6445, -2431.6990, 60.2028),
        SpawnBack = vector3(-2806.5178, -2037.0980, 77.7363),
        SpawnForward = vector3(-2022.2163, -2589.6052, 68.4512),
        ForwardOffset = 0.5,
        BackwardOffset = 0.5,
        ForwardStation = { "Armadillo" },
        BackwardStation = { "Macfarlane" },
        SpawnDirectionReverse = true,
    },
    ["Armadillo"] = {
        npcModel = 's_m_m_trainstationworker_01',
        npcCoords = vector4(-3729.21, -2601.34, -12.94, 183.15),
        ticketCoords = vector3(-3729.09, -2602.97, -12.94),
        stationCoords = vector3(-3749.28, -2606.64, -13.72),
        SpawnBack = vector3(-3968.1794, -2887.1396, -14.3250),
        SpawnForward = vector3(-3734.6736, -2245.9814, -10.2932),
        ForwardOffset = 5,
        BackwardOffset = 5,
        ForwardStation = { "Benedict Point" },
        BackwardStation = { 'Macfarlane' },
        SpawnDirectionReverse = true,
    },
    ["Benedict Point"] = {
        npcModel = 'u_m_m_tumtrainstationworker_01',
        npcCoords = vector4(-5228.6211, -3468.3896, -20.5697, 87.6982),
        ticketCoords = vector3(-5230.0981, -3468.2148, -20.5783),
        stationCoords = vector3(-5235.1777, -3472.4907, -21.2528),
        SpawnBack = vector3(-5362.6768, -3686.9006, -22.3792),
        SpawnForward = vector3(-5233.8848, -3298.8396, -17.1361),
        ForwardOffset = 0,
        BackwardOffset = 0,
        ForwardStation = { "Armadillo" },
        BackwardStation = { "Armadillo" },
        FlipDirectionIf = { 'Armadillo' },
    },
    -- Add more unique stations as needed
}


Config.WestRouteSpawns = {
    ["Macfarlane"] = {
        ["Armadillo"] = "Forward",
        ["Benedict Point"] = "Forward"
    },
    ["Armadillo"] = {
        ["Macfarlane"] = "Backward",
        ["Benedict Point"] = "Forward"
    },
    ["Benedict Point"] = {
        ["Macfarlane"] = "Backward",
        ["Armadillo"] = "Backward"
    }
}


Config.EastStationsList = {
    -- Route Main
    "Flatneck",
    
    -- Split 1
    "Valentine",
    "Emerald",

    -- Split 2
    "Rhodes",

    -- Route Main
    "Saint Denis",
    "Annesburg",
    "Bacchus",
    "Wallace",
    "Riggs"
}

Config.WestStationsList = {
    "Macfarlane",
    "Armadillo",
    "Benedict Point"
}



    ---------------------------------------------------------------------
    -- DO NOT TOUCH BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING --
    ---------------------------------------------------------------------
    --[[
        Cords can be taken from player standing on the track, best away from junctions.
        traintrack id's can be different on either side of the junction.
        Junction Index was obtained from commented out togglejunction in client.lua
            Pick a track and batch toggle them on an off 1-30 to find the right track id, then reduce 1-30 until you find the right one.
            This scrip does auto toggle junction after leaving each station, and they may not toggle if the train is to close to them.
        Its 1 or 0, different for each junction on what way to go.
    ]]

Config.RouteOneTramSwitches = {

    { coords = vector3(2775.01, -1350.06, 46.14),       trainTrack = -1739625337,  junctionIndex = 0,  enabled = 0 },
    -- { coords = vector3(2686.55, -1385.46, 46.36679),    trainTrack = -1739625337,  junctionIndex = 3,  enabled = 1 },
    { coords = vector3(2621.25, -1295.36, 52.01),       trainTrack = -1739625337,  junctionIndex = 5,  enabled = 0 },
    -- { coords = vector3(2615.05, -1281.2, 52.34358),     trainTrack = -1739625337,  junctionIndex = 6,  enabled = 1 },
    -- { coords = vector3(2608.49, -1254.66, 52.66566),    trainTrack = -1739625337,  junctionIndex = 7,  enabled = 1 },
    { coords = vector3(2608.6, -1155.59, 51.69),        trainTrack = -1739625337,  junctionIndex = 10, enabled = 1 },
    { coords = vector3(2624.4, -1139.85, 51.51707),     trainTrack = -1739625337,  junctionIndex = 11, enabled = 1 },
    { coords = vector3(2700.96, -1139.82, 50.29),       trainTrack = -1739625337,  junctionIndex = 13, enabled = 1 },
    { coords = vector3(2625.46, -1284.62, 52.14),       trainTrack = 1751550675,   junctionIndex = 1,  enabled = 1 },
    -- { coords = vector3(2738.41, -1414.91, 45.85),       trainTrack = -1748581154,  junctionIndex = 1,  enabled = 1 },
    -- { coords = vector3(2599.47, -1137.39, 51.3),        trainTrack = -1716490906,  junctionIndex = 4,  enabled = 1 },

}

Config.JunctionEast = {
    -- East
    { coords = vector3(2855.73, -1314.1, 45.93), trainTrack = -705539859, junctionIndex = 15, enabled = 1 },
    { coords = vector3(2749.89, -1432.86, 45.85), trainTrack = -1242669618, junctionIndex = 1, enabled = 1 },
    { coords = vector3(2855.73, -1314.1, 45.93), trainTrack = -705539859, junctionIndex = 19, enabled = 0 },
    { coords = vector3(2656.8, -1477.09, 45.75), trainTrack = -1242669618, junctionIndex = 2, enabled = 1 },
    { coords = vector3(2585.15, -1491.9, 46.06), trainTrack = -705539859, junctionIndex = 18, enabled = 1 },
    { coords = vector3(614.71, 683.91, 115.35), trainTrack = 1499637393, junctionIndex = 3, enabled = 1 },
    { coords = vector3(357.49, 596.14, 115.68), trainTrack = 1499637393, junctionIndex = 4, enabled = 1 },
    { coords = vector3(1483.05, 647.26, 92.32), trainTrack = 1499637393, junctionIndex = 2, enabled = 1 },
    { coords = vector3(1530.18, 468, 90.23), trainTrack = -760570040, junctionIndex = 1, enabled = 1 },
    { coords = vector3(2659.7, -433.01, 43.44), trainTrack = -705539859, junctionIndex = 13, enabled = 0 },
    { coords = vector3(2873.58, 1200, 45.11), trainTrack = -705539859, junctionIndex = 11, enabled = 0 },
    { coords = vector3(3033.32, 1482.84, 49.63), trainTrack = -705539859, junctionIndex = 10, enabled = 0 },
    { coords = vector3(610.46, 1661.44, 187.38), trainTrack = -705539859, junctionIndex = 8, enabled = 1 },
    { coords = vector3(555.76, 1727.11, 187.8), trainTrack = -705539859, junctionIndex = 7, enabled = 1 },
}

Config.JunctionWest = {
    -- West
    { coords = vector3(-4849.69, -3086.4, -15.76), trainTrack = -1763976500, junctionIndex = 6, enabled = 0 },
    { coords = vector3(-4950.0, -3083.59, -17.47), trainTrack = -1467515357, junctionIndex = 5, enabled = 1 },
    { coords = vector3(-2187.18, -2517.21, 65.7),       trainTrack = -988268728,  junctionIndex = 0,  enabled = 1 },
    { coords = vector3(-2214.62, -2519.47, 65.51),      trainTrack = -1763976500,  junctionIndex = 1,  enabled = 1 },
    { coords = vector3(-2214.62, -2519.47, 65.51),      trainTrack = -1467515357,  junctionIndex = 0,  enabled = 1 },
}

Config.JunctionSwitch = {
     ["Flatneck"] = {-- From Flatneck 1 Valentine, 0 Rhodes
        Valentine = { coords = vector3(-277.118, -316.180, 87.916), trainTrack = -705539859, junctionIndex = 2, enabled = 1 },
        Rhodes = { coords = vector3(-277.118, -316.180, 87.916), trainTrack = -705539859, junctionIndex = 2, enabled = 0 },
    },
    ["Valentine"] = {
        -- From Valentine 1 Rhodes, 0 Flatneck
        Flatneck = { coords = vector3(30.95, 29.84, 103.33), trainTrack = 1499637393, junctionIndex = 5, enabled = 0 },
        Rhodes = { coords = vector3(30.95, 29.84, 103.33), trainTrack = 1499637393, junctionIndex = 5, enabled = 1 },
    },

    ["Rhodes"] = {
        -- From Rhodes - 1 Valentine, 0 Flatneck
       Flatneck = { coords = vector3(71.12, -376.28, 90.92), trainTrack = -705539859, junctionIndex = 1, enabled = 0 },
       Valentine = { coords = vector3(71.12, -376.28, 90.92), trainTrack = -705539859, junctionIndex = 1, enabled = 1 },
    },

    ["Saint Denis"] ={
        -- From Saint Denis - 1 Rhodes, 0 Emerald
       Rhodes = { coords = vector3(2629.92, -1477.18, 45.89), trainTrack = -1242669618, junctionIndex = 3, enabled = 1 },
       Emerald = { coords = vector3(2629.92, -1477.18, 45.89), trainTrack = -1242669618, junctionIndex = 3, enabled = 0 },
    }

}