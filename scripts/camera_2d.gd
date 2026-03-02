# CameraFollowClamp.gd
# Godot 4.x
extends Camera2D

@export var player_path: NodePath
@export var tilemap_path: NodePath

# --- FOLLOW ---
@export_range(0.0, 50.0, 0.1) var follow_speed: float = 10.0
@export var look_ahead: Vector2 = Vector2.ZERO
@export var pixel_snap: bool = false

# --- LIMITS ---
@export var use_used_rect: bool = true
@export var bounds_padding: Vector2 = Vector2.ZERO

# --- JUMP ZOOM ---
@export var enable_jump_zoom: bool = true
@export var jump_zoom_amount: float = -0.15   # 0.15 = 15% zoom out
@export_range(0.0, 20.0, 0.1) var zoom_speed: float = 6.0

var _player: CharacterBody2D
var _tilemap: TileMap

var _base_zoom: Vector2
var _target_zoom: Vector2

func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody2D
	_tilemap = get_node_or_null(tilemap_path) as TileMap

	_base_zoom = zoom
	_target_zoom = zoom

	_update_limits_from_tilemap()

func _process(delta: float) -> void:
	if _player == null:
		return

	_update_follow(delta)
	_update_jump_zoom(delta)

# -------------------------
# FOLLOW PLAYER
# -------------------------
func _update_follow(delta: float) -> void:
	var target: Vector2 = _player.global_position + look_ahead

	if follow_speed <= 0.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))

	if pixel_snap:
		global_position = global_position.round()

# -------------------------
# JUMP ZOOM
# -------------------------
func _update_jump_zoom(delta: float) -> void:
	if not enable_jump_zoom:
		return

	var is_jumping := not _player.is_on_floor()

	if is_jumping:
		var zoom_out := 1.0 + jump_zoom_amount
		_target_zoom = _base_zoom * zoom_out
	else:
		_target_zoom = _base_zoom

	zoom = zoom.lerp(_target_zoom, 1.0 - exp(-zoom_speed * delta))

# -------------------------
# LIMITS FROM TILEMAP
# -------------------------
func _update_limits_from_tilemap() -> void:
	if _tilemap == null:
		return

	var rect_cells: Rect2i = _tilemap.get_used_rect()
	if rect_cells.size.x <= 0 or rect_cells.size.y <= 0:
		return

	var tile_size: Vector2 = _tilemap.tile_set.tile_size

	var local_min_px: Vector2 = Vector2(rect_cells.position) * tile_size
	var local_max_px: Vector2 = Vector2(rect_cells.position + rect_cells.size) * tile_size

	var min_global: Vector2 = _tilemap.to_global(local_min_px)
	var max_global: Vector2 = _tilemap.to_global(local_max_px)

	var left: float   = min(min_global.x, max_global.x) - bounds_padding.x
	var right: float  = max(min_global.x, max_global.x) + bounds_padding.x
	var top: float    = min(min_global.y, max_global.y) - bounds_padding.y
	var bottom: float = max(min_global.y, max_global.y) + bounds_padding.y

	limit_left = int(floor(left))
	limit_right = int(ceil(right))
	limit_top = int(floor(top))
	limit_bottom = int(ceil(bottom))
