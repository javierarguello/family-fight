class_name CharacterData
extends Resource

## Character configuration resource for parametrizable fighters

@export_group("Identity")
@export var character_name: String = "Fighter"

@export_group("Stats")
@export var speed: float = 130.0
@export var jump_velocity: float = -300.0

@export_group("Visuals")
@export var sprite_frames: SpriteFrames
## Overall scale multiplier for sprite and collider (1.0 = fit to default collider)
@export_range(0.1, 5.0, 0.05) var scale_factor: float = 1.0

@export_group("Audio")
@export var punch_sound: AudioStream
@export var double_punch_sound: AudioStream
@export var kick_sound: AudioStream
@export var jump_sound: AudioStream

@export_group("Animation Sound Triggers")
## Frame number when punch sound plays
@export var punch_sound_frame: int = 2
## Frame number when kick sound plays
@export var kick_sound_frame: int = 1
## Frame number when jump sound plays
@export var jump_sound_frame: int = 1
