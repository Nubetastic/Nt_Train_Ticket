# NT Train Ticket System

A lightweight train ticket system for RedM (RSG framework).
NPC's are added to each train station at the stations ticket booth.
Player can then interact with them, hold J, to bring up a menu to pick a station to go to.
A train then spawns for players to ride to the destination station, and it will continue until no players are onboard anymore.
All players on board will be charged the config ticket price when the train leaves each station.

Train and Trams have a list of models to use to spawn from. Giving players variety in trains they get to ride.
Passengers spawn with the train, and can have sync issues. Passengers can be disabled.

## Features
- Player spawned train system for travel
- Custom Stop system, no native stops used.
- Multiple models picked at random
- Trains designed to take shortest route, forward or backwards.

## Dependencies
- RSG Core framework
- rsg-menubase
- ox_lib
**Optional**
- YMap for Bacchus
    - NPC set inside by default
    https://forum.cfx.re/t/free-mlo-bacchus-station-mlo/5253923


## Installation
1. Place this resource in your server's resources folder.
2. Add `ensure Nt_train_ticket` to your server.cfg.
3. Update rsg-telegram Config.lua
    Riggs Station Post Office
    vector3(-1094.35, -574.93, 82.41),
    Just moved the prompt over to the left a little so the two prompts don't overlap.
    Train Ticket npcs are set at the train ticket booths.
4. Restart your server.

## Suggestions
- YMap for Bacchus
- NPC set inside by default
https://forum.cfx.re/t/free-mlo-bacchus-station-mlo/5253923

## Credits
- Original BGS_Trains script referenced, including tram code.
