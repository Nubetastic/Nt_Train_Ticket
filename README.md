# NT Trains Ticket System

A train ticket system for RedM RSG framework that allows players to summon a train if one does not already exist on the track.
All passangers are charged Config.TicketPrice after the train leaves each station.
Players do not need to be seated inside the train to purchase tickets.

## Train does not use native stops
Stops are designed with the train model used in config.

## Features

- Summon a train at any station, bi-directional trains.
- Passengers pay a configurable ticket price when boardingonboard and leaving the station.
- Select destination from a menu
- Train spawns in the correct direction based on config
- Handles split track logic for different station routes
- Integrates with RSG Core framework
- Advanced pathfinding for train routes
- Intelligent junction switching based on destination
- Support for both East and West train lines
- Train despawns when abandoned, will continue after destination.
- Optional tram system in Saint Denis

## Usage

1. Approach any train station ticket booth
2. Press J to interact with the ticket booth
3. Select your destination from the menu
4. Wait for the train to arrive and board it
5. Train will automatically navigate to your destination

## Train System

The script includes a sophisticated train spawning and routing system:

- **Intelligent Pathfinding**: Trains are set what direction to spawn for what station, and will find the shortest path afterwards.
- **Direction Management**: Trains spawn in the correct direction based on destination
- **Junction Control**: Automatically switches track junctions for proper routing
- **Station Management**: Trains stop at stations for a configurable duration
- **Passenger System**: NPCs can be configured to ride as passengers
- **Blip Tracking**: Real-time train location displayed on the map

## Requirements

- RSG Core framework
- rsg-menubase
- ox_lib

## Installation

1. Place this resource in your server's resources folder
2. Add `ensure Nt_train_ticket` to your server.cfg
3. Update rsg-telegram Config.lua
    Riggs Station Post Office
    vector3(-1094.35, -574.93, 82.41),
    Just moved the prompt over to the left a little so the two prompts don't overlap.
    Train Ticket npcs are set at the train ticket booths.
4. Restart your server

## Credits

- Original BGS_Trains script used as reference, and for the tram code.