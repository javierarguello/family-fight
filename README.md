# Family Fight

A retro 2D fighting game (Street Fighter style) built with Godot 4, designed for Batocera on Raspberry Pi 5.

## Project Structure

```
family-fight/
├── scenes/
│   ├── game.tscn          # Main game scene (arena, players, camera)
│   └── player.tscn        # Reusable player scene (controller + sprite + collision)
├── scripts/
│   ├── player.gd          # Parametrizable fighter controller (handles input, movement, attacks)
│   ├── character_data.gd  # CharacterData resource class (stats, audio, sprite_frames)
│   └── camera_2d.gd       # Camera that follows both players
├── characters/
│   ├── mila/
│   │   ├── mila.tres          # CharacterData resource
│   │   ├── mila_frames.tres   # SpriteFrames resource (references sprites/)
│   │   └── audio/             # punch.wav, double_punch.wav, kick.wav, jump.wav
│   └── pilar/
│       ├── pilar.tres         # CharacterData resource
│       ├── sprites/           # Pilar's sprite sheets (when available)
│       └── audio/             # punch.wav, kick.wav, jump.wav, etc.
├── sprites/                   # Mila's sprite sheets + level backgrounds
└── audio/                     # Level audio (kids_room_track_sound.wav)
```

## Architecture

### CharacterData Resource System

Each character is defined by a `CharacterData` resource (`.tres`) that contains:

- **Identity**: character name
- **Stats**: speed, jump velocity
- **Visuals**: SpriteFrames resource with all animations (idle, walk, jump, punch, kick)
- **Audio**: punch, double punch, kick, and jump sound effects
- **Animation triggers**: frame numbers when sounds play

### Player Scene

`player.tscn` is a generic, reusable fighter scene. It uses `player.gd` which:

- Reads all parameters from the assigned `CharacterData` resource
- Falls back to embedded defaults if no `CharacterData` is assigned
- Supports 2-player input via `player_id` (1 or 2), mapping to `p1_*` / `p2_*` input actions
- Auto-faces opponent, supports walk forward/backward, jump, punch, kick
- Clamps position within TileMap bounds

### Game Scene

`game.tscn` instantiates two `player.tscn` nodes and assigns different `CharacterData` to each, plus a TileMap arena, camera, and background music.

## How to Add a New Character

1. Create a folder: `characters/your_character/`
2. Add sprite sheets to `characters/your_character/sprites/` (same atlas layout as existing characters)
3. Add audio files to `characters/your_character/audio/` using generic names: `punch.wav`, `double_punch.wav`, `kick.wav`, `jump.wav`
4. Create a `SpriteFrames` resource (`.tres`) pointing to the new sprites — copy an existing `*_frames.tres` and update paths
5. Create a `CharacterData` resource (`.tres`) referencing the SpriteFrames and audio
6. In `game.tscn`, set the player node's `character_data` to your new `.tres`

## How to Add a New Level

1. Create a new scene based on `game.tscn` or create a fresh `Node2D` scene
2. Add a `TileMap` with your background/floor tiles
3. Instance two `player.tscn` nodes, assign `character_data`, `opponent_path`, and `tilemap_path`
4. Add a `Camera2D` with `camera_2d.gd` and configure player/tilemap paths
5. Add a `StaticBody2D` floor collider

## Design Rules

- **Generic design**: All scripts are parametrizable via resources — no character-specific logic in code
- **No script duplication**: One `player.gd` serves all characters; differences come from `CharacterData`
- **Resource-driven**: Characters, stats, and visuals are configured via `.tres` files, not code
- **Reusable scenes**: `player.tscn` is instanced multiple times with different data

## Running

Open in Godot 4.x and run the project. Player 1 uses `p1_*` input actions, Player 2 uses `p2_*` input actions (configure in Project > Project Settings > Input Map).
