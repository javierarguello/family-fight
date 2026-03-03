# CameraFollowClamp.gd
# Godot 4.x - Supports following 1 or 2 players
extends Camera2D

@export var player1_path: NodePath
@export var player2_path: NodePath
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
# --- DYNAMIC ZOOM (for 2 players) ---
@export var enable_distance_zoom: bool = true
@export var min_player_distance: float = 50.0
@export var max_player_distance: float = 200.0
@export var max_distance_zoom_out: float = -0.3

# --- PLAYER CONTAINMENT ---
## Margin in pixels from the edge of the visible area
@export var containment_margin: float = 20.0

var _player1: CharacterBody2D
var _player2: CharacterBody2D
var _tilemap: TileMap

var _base_zoom: Vector2
var _target_zoom: Vector2

func _ready() -> void:
	_player1 = get_node_or_null(player1_path) as CharacterBody2D
	_player2 = get_node_or_null(player2_path) as CharacterBody2D
	_tilemap = get_node_or_null(tilemap_path) as TileMap

	_base_zoom = zoom
	_target_zoom = zoom

	_update_limits_from_tilemap()

func _process(delta: float) -> void:
	if _player1 == null and _player2 == null:
		return

	_update_follow(delta)
	_update_zoom(delta)
	_clamp_camera_to_limits()
	_clamp_players_to_view()

# -------------------------
# FOLLOW PLAYERS
# -------------------------
func _update_follow(delta: float) -> void:
	var target: Vector2

	if _player1 != null and _player2 != null:
		# Follow midpoint between both players
		target = (_player1.global_position + _player2.global_position) * 0.5
	elif _player1 != null:
		target = _player1.global_position
	elif _player2 != null:
		target = _player2.global_position
	else:
		return

	target += look_ahead

	if follow_speed <= 0.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))

	if pixel_snap:
		global_position = global_position.round()

# -------------------------
# ZOOM (jump + distance)
# -------------------------
func _update_zoom(delta: float) -> void:
	var zoom_modifier: float = 0.0

	# Jump zoom (any player jumping)
	if enable_jump_zoom:
		var any_jumping := false
		if _player1 != null and not _player1.is_on_floor():
			any_jumping = true
		if _player2 != null and not _player2.is_on_floor():
			any_jumping = true

		if any_jumping:
			zoom_modifier += jump_zoom_amount

	# Distance zoom (only if 2 players)
	if enable_distance_zoom and _player1 != null and _player2 != null:
		var distance := _player1.global_position.distance_to(_player2.global_position)
		var t := clampf((distance - min_player_distance) / (max_player_distance - min_player_distance), 0.0, 1.0)
		zoom_modifier += lerpf(0.0, max_distance_zoom_out, t)

	_target_zoom = _base_zoom * (1.0 + zoom_modifier)
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

# -------------------------
# CAMERA VIEW CLAMPING
# -------------------------
func _clamp_camera_to_limits() -> void:
	var vp_size := get_viewport_rect().size
	var half_w := (vp_size.x / zoom.x) * 0.5
	var half_h := (vp_size.y / zoom.y) * 0.5

	var visible_bottom := global_position.y + half_h
	if visible_bottom > limit_bottom:
		global_position.y -= visible_bottom - limit_bottom

	var visible_top := global_position.y - half_h
	if visible_top < limit_top:
		global_position.y += limit_top - visible_top

	var visible_left := global_position.x - half_w
	if visible_left < limit_left:
		global_position.x += limit_left - visible_left

	var visible_right := global_position.x + half_w
	if visible_right > limit_right:
		global_position.x -= visible_right - limit_right

# -------------------------
# PLAYER CONTAINMENT
# -------------------------
func _clamp_players_to_view() -> void:
	if _player1 == null and _player2 == null:
		return

	var vp_size := get_viewport_rect().size
	var half_w := (vp_size.x / zoom.x) * 0.5 - containment_margin
	var half_h := (vp_size.y / zoom.y) * 0.5 - containment_margin

	var cam_x := global_position.x
	var cam_y := global_position.y
	var left_bound := cam_x - half_w
	var right_bound := cam_x + half_w
	var top_bound := cam_y - half_h
	var bottom_bound := cam_y + half_h

	for player: CharacterBody2D in [_player1, _player2]:
		if player == null:
			continue
		var p := player.global_position
		p.x = clampf(p.x, left_bound, right_bound)
		p.y = clampf(p.y, top_bound, bottom_bound)
		if p != player.global_position:
			player.global_position = p
			player.velocity.x = 0.0
