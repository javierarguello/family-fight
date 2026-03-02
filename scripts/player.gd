extends CharacterBody2D

const SPEED := 130.0
const JUMP_VELOCITY := -300.0

@export var anim_path: NodePath = ^"AnimatedSprite2D"
@onready var voice: AudioStreamPlayer2D = $AudioStreamPlayer2D
@export var tilemap_path: NodePath

# ---- BOUNDING ----
@export var clamp_margin_left: float = 16.0
@export var clamp_margin_right: float = 16.0
@export var clamp_debug_print: bool = false

# ---- ATTACK FEELING ----
@export_range(0.0, 0.2, 0.01) var attack_buffer_seconds: float = 0.08
@export_range(0.0, 1.0, 0.01) var last_frame_unlock_progress: float = 0.9

# ---- WALK BACK SPEED ----
@export_range(1.0, 30.0, 1.0) var walk_fps: float = 12.0

@onready var anim: AnimatedSprite2D = get_node_or_null(anim_path) as AnimatedSprite2D

# ---- SOUNDS ----
var punch_sound := preload("res://audio/mila_punch.wav")
var double_punch_sound := preload("res://audio/mila_double_punch.wav")
var power_kick_sound := preload("res://audio/mila_power_kick.wav")
var jump_sound := preload("res://audio/mila_jump.wav")

var is_attacking := false
var current_attack: StringName = ""

var kick_buffer := 0.0
var punch_buffer := 0.0

# walk back control
var _walk_back_timer := 0.0
var _walking_back := false

# bounds
var _has_bounds := false
var _min_x: float = 0.0
var _max_x: float = 0.0
var _half_width: float = 0.0


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	if anim == null:
		push_error("AnimatedSprite2D no encontrado.")
		return

	if anim.sprite_frames == null:
		push_error("SpriteFrames no asignado.")
		return

	_half_width = _compute_half_width_from_collider()
	call_deferred("_update_bounds_from_tilemap")

	_play_if_changed("idle")


# =========================================================
# MAIN LOOP
# =========================================================

func _physics_process(delta: float) -> void:
	if anim == null:
		return

	# -------------------------
	# ATTACK BUFFER
	# -------------------------
	kick_buffer = maxf(0.0, kick_buffer - delta)
	punch_buffer = maxf(0.0, punch_buffer - delta)

	if Input.is_action_just_pressed("kick"):
		kick_buffer = attack_buffer_seconds

	if Input.is_action_just_pressed("punch"):
		punch_buffer = attack_buffer_seconds

	# -------------------------
	# GRAVITY
	# -------------------------
	if not is_on_floor():
		velocity += get_gravity() * delta

	# -------------------------
	# JUMP
	# -------------------------
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_attacking:
		velocity.y = JUMP_VELOCITY

	# -------------------------
	# MOVEMENT
	# -------------------------
	var direction := Input.get_axis("ui_left", "ui_right")

	if not is_attacking:
		if direction != 0.0:
			velocity.x = direction * SPEED
			anim.flip_h = direction < 0.0
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)
	else:
		velocity.x = 0.0

	move_and_slide()
	_clamp_to_bounds()

	# -------------------------
	# AIR STATE
	# -------------------------
	if not is_on_floor() and not is_attacking:
		_stop_walk_back()
		_play_if_changed("jump")
		return

	# -------------------------
	# GROUND STATE
	# -------------------------
	if not is_attacking:
		if direction != 0.0:
			if direction < 0.0:
				_play_walk_back(delta)
			else:
				_play_walk_forward()
		else:
			_stop_walk_back()
			_play_if_changed("idle")

	# -------------------------
	# UNLOCK ATTACK
	# -------------------------
	if is_attacking and anim.animation == current_attack:
		var total := anim.sprite_frames.get_frame_count(current_attack)
		if total > 0:
			var last_index := total - 1
			if anim.frame >= last_index and anim.frame_progress >= last_frame_unlock_progress:
				is_attacking = false
				current_attack = ""

	# -------------------------
	# EXECUTE ATTACK (priority punch > kick)
	# -------------------------
	if not is_attacking:
		if punch_buffer > 0.0:
			punch_buffer = 0.0
			_do_attack("punch")
		elif kick_buffer > 0.0:
			kick_buffer = 0.0
			_do_attack("kick")


# =========================================================
# ATTACK
# =========================================================

func _do_attack(name: StringName) -> void:
	if not anim.sprite_frames.has_animation(name):
		return

	is_attacking = true
	current_attack = name
	velocity.x = 0.0
	_stop_walk_back()

	anim.speed_scale = 1.0
	anim.play(name)


# =========================================================
# WALK FORWARD
# =========================================================

func _play_walk_forward() -> void:
	_stop_walk_back()

	if not anim.sprite_frames.has_animation("walk"):
		return

	if anim.animation != "walk" or not anim.is_playing():
		anim.speed_scale = 1.0
		anim.play("walk")


# =========================================================
# WALK BACK
# =========================================================

func _play_walk_back(delta: float) -> void:
	if not anim.sprite_frames.has_animation("walk"):
		return

	var total := anim.sprite_frames.get_frame_count("walk")
	if total <= 1:
		return

	if anim.animation != "walk":
		anim.play("walk")
		anim.stop()
		anim.set_frame_and_progress(total - 1, 0.0)
		_walking_back = true
		_walk_back_timer = 0.0
	elif anim.is_playing():
		anim.stop()

	if not _walking_back:
		_walking_back = true
		_walk_back_timer = 0.0
		anim.set_frame_and_progress(total - 1, 0.0)

	_walk_back_timer += delta
	var step := 1.0 / walk_fps

	while _walk_back_timer >= step:
		_walk_back_timer -= step
		var f := anim.frame - 1
		if f < 0:
			f = total - 1
		anim.set_frame_and_progress(f, 0.0)


func _stop_walk_back() -> void:
	_walking_back = false
	_walk_back_timer = 0.0


# =========================================================
# TILEMAP BOUNDS
# =========================================================

func _compute_half_width_from_collider() -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return 0.0

	if cs.shape is RectangleShape2D:
		return (cs.shape as RectangleShape2D).size.x * 0.5
	if cs.shape is CapsuleShape2D:
		return (cs.shape as CapsuleShape2D).radius
	if cs.shape is CircleShape2D:
		return (cs.shape as CircleShape2D).radius

	return 0.0


func _update_bounds_from_tilemap() -> void:
	var tm := get_node_or_null(tilemap_path) as TileMap
	if tm == null:
		_has_bounds = false
		return

	var rect: Rect2i = tm.get_used_rect()
	if rect.size.x <= 0:
		_has_bounds = false
		return

	var tile_size: Vector2 = tm.tile_set.tile_size

	var min_cell := rect.position
	var max_cell := rect.position + Vector2i(rect.size.x, 0)

	var min_local := tm.map_to_local(min_cell) - Vector2(tile_size.x * 0.5, 0.0)
	var max_local := tm.map_to_local(max_cell) - Vector2(tile_size.x * 0.5, 0.0)

	var min_global_x := tm.to_global(min_local).x
	var max_global_x := tm.to_global(max_local).x

	var left_edge: float = minf(min_global_x, max_global_x)
	var right_edge: float = maxf(min_global_x, max_global_x)

	_min_x = left_edge + clamp_margin_left + _half_width
	_max_x = right_edge - clamp_margin_right - _half_width

	_has_bounds = _max_x > _min_x


func _clamp_to_bounds() -> void:
	if not _has_bounds:
		return

	var p := global_position

	if p.x < _min_x:
		p.x = _min_x
		velocity.x = 0.0
	elif p.x > _max_x:
		p.x = _max_x
		velocity.x = 0.0

	global_position = p


# =========================================================
# SAFE PLAY
# =========================================================

func _play_if_changed(name: StringName) -> void:
	if not anim.sprite_frames.has_animation(name):
		return

	if anim.animation == name and anim.is_playing():
		return

	anim.speed_scale = 1.0
	anim.play(name)

func _on_animated_sprite_2d_frame_changed() -> void:
	if anim and anim.animation == "punch" and anim.frame == 2:
		voice.stream = double_punch_sound
		voice.play()
	elif anim and anim.animation == "kick" and anim.frame == 1:
		voice.stream = power_kick_sound
		voice.play()
	elif anim and anim.animation == "jump" and anim.frame == 1:
		voice.stream = jump_sound
		voice.play()
