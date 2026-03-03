extends CharacterBody2D

## Parametrizable fighter controller for 2-player support

# ---- PLAYER IDENTITY ----
@export_range(1, 2) var player_id: int = 1

# ---- OPPONENT REFERENCE ----
@export var opponent_path: NodePath
var _opponent: CharacterBody2D

# ---- CHARACTER DATA ----
@export var character_data: CharacterData

# ---- FALLBACK CONSTANTS (used if no character_data) ----
const DEFAULT_SPEED := 130.0
const DEFAULT_JUMP_VELOCITY := -300.0
const DEFAULT_MAX_STAMINA := 100.0
const DEFAULT_PUNCH_DAMAGE := 8.0
const DEFAULT_KICK_DAMAGE := 12.0
const DEFAULT_HIT_RANGE := 25.0

# ---- STAMINA ----
var max_stamina: float = DEFAULT_MAX_STAMINA
var stamina: float = DEFAULT_MAX_STAMINA

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

var is_attacking := false
var current_attack: StringName = ""
var _hit_landed := false

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

# ---- INPUT ACTIONS (computed from player_id) ----
var _input_left: StringName
var _input_right: StringName
var _input_jump: StringName
var _input_punch: StringName
var _input_kick: StringName


# =========================================================
# COMPUTED PROPERTIES
# =========================================================

func get_character_name() -> String:
	if character_data:
		return character_data.character_name
	return "P%d" % player_id


func _get_speed() -> float:
	if character_data:
		return character_data.speed
	return DEFAULT_SPEED


func _get_jump_velocity() -> float:
	if character_data:
		return character_data.jump_velocity
	return DEFAULT_JUMP_VELOCITY


func _get_punch_damage() -> float:
	if character_data:
		return character_data.punch_damage
	return DEFAULT_PUNCH_DAMAGE


func _get_kick_damage() -> float:
	if character_data:
		return character_data.kick_damage
	return DEFAULT_KICK_DAMAGE


func _get_hit_range() -> float:
	if character_data:
		return character_data.hit_range
	return DEFAULT_HIT_RANGE


func _get_punch_sound() -> AudioStream:
	if character_data:
		return character_data.double_punch_sound
	return null


func _get_kick_sound() -> AudioStream:
	if character_data:
		return character_data.kick_sound
	return null


func _get_jump_sound() -> AudioStream:
	if character_data:
		return character_data.jump_sound
	return null


func _get_punch_sound_frame() -> int:
	if character_data:
		return character_data.punch_sound_frame
	return 2


func _get_kick_sound_frame() -> int:
	if character_data:
		return character_data.kick_sound_frame
	return 1


func _get_jump_sound_frame() -> int:
	if character_data:
		return character_data.jump_sound_frame
	return 1


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	_setup_input_actions()
	_opponent = get_node_or_null(opponent_path) as CharacterBody2D

	if anim == null:
		push_error("AnimatedSprite2D no encontrado.")
		return

	if anim.sprite_frames == null:
		push_error("SpriteFrames no asignado.")
		return

	# Apply character data
	if character_data:
		if character_data.sprite_frames:
			anim.sprite_frames = character_data.sprite_frames
		max_stamina = character_data.max_stamina
		stamina = max_stamina

	_fit_sprite_to_collider()
	_half_width = _compute_half_width_from_collider()
	call_deferred("_update_bounds_from_tilemap")

	_play_if_changed("idle")


func _setup_input_actions() -> void:
	var prefix := "p%d_" % player_id
	_input_left = StringName(prefix + "left")
	_input_right = StringName(prefix + "right")
	_input_jump = StringName(prefix + "jump")
	_input_punch = StringName(prefix + "punch")
	_input_kick = StringName(prefix + "kick")


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

	if Input.is_action_just_pressed(_input_kick):
		kick_buffer = attack_buffer_seconds

	if Input.is_action_just_pressed(_input_punch):
		punch_buffer = attack_buffer_seconds

	# -------------------------
	# GRAVITY
	# -------------------------
	if not is_on_floor():
		velocity += get_gravity() * delta

	# -------------------------
	# JUMP
	# -------------------------
	if Input.is_action_just_pressed(_input_jump) and is_on_floor() and not is_attacking:
		velocity.y = _get_jump_velocity()

	# -------------------------
	# FACING DIRECTION (always face opponent)
	# -------------------------
	var facing_right := true
	if _opponent != null:
		facing_right = global_position.x < _opponent.global_position.x
	anim.flip_h = not facing_right

	# -------------------------
	# MOVEMENT
	# -------------------------
	var direction := Input.get_axis(_input_left, _input_right)

	if not is_attacking:
		if direction != 0.0:
			velocity.x = direction * _get_speed()
		else:
			velocity.x = move_toward(velocity.x, 0.0, _get_speed())
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
	# GROUND STATE (forward = toward opponent, back = away from opponent)
	# -------------------------
	if not is_attacking:
		if direction != 0.0:
			# Determine if walking toward or away from opponent
			var walking_toward_opponent := (direction > 0.0 and facing_right) or (direction < 0.0 and not facing_right)
			if walking_toward_opponent:
				_play_walk_forward()
			else:
				_play_walk_back(delta)
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

func _do_attack(attack_name: StringName) -> void:
	if not anim.sprite_frames.has_animation(attack_name):
		return

	is_attacking = true
	current_attack = attack_name
	_hit_landed = false
	velocity.x = 0.0
	_stop_walk_back()

	anim.speed_scale = 1.0
	anim.play(attack_name)


func take_damage(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)


func _try_hit(damage: float) -> void:
	if _hit_landed or _opponent == null:
		return

	var dist := global_position.distance_to(_opponent.global_position)
	# hit_range is in local space, multiply by scale to get world distance
	var world_range := _get_hit_range() * scale.x
	if dist <= world_range:
		_hit_landed = true
		_opponent.take_damage(damage)


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
# SPRITE FITTING
# =========================================================

func _fit_sprite_to_collider() -> void:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null or anim.sprite_frames == null:
		return

	var collider_height := _get_collider_height(cs.shape)
	if collider_height <= 0.0:
		return

	if not anim.sprite_frames.has_animation("idle"):
		return

	var frame_tex: Texture2D = anim.sprite_frames.get_frame_texture("idle", 0)
	if frame_tex == null:
		return

	var frame_height := float(frame_tex.get_height())
	if frame_height <= 0.0:
		return

	var factor := 1.0
	if character_data:
		factor = character_data.scale_factor

	var s := (collider_height / frame_height) * factor
	anim.scale = Vector2(s, s)
	cs.scale = Vector2(factor, factor)


func _get_collider_height(shape: Shape2D) -> float:
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.y
	if shape is CapsuleShape2D:
		return (shape as CapsuleShape2D).height
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius * 2.0
	return 0.0


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


func _play_voice(stream: AudioStream) -> void:
	if stream:
		voice.stream = stream
		voice.play()


func _on_animated_sprite_2d_frame_changed() -> void:
	if anim and anim.animation == "punch" and anim.frame == _get_punch_sound_frame():
		_play_voice(_get_punch_sound())
		_try_hit(_get_punch_damage())
	elif anim and anim.animation == "kick" and anim.frame == _get_kick_sound_frame():
		_play_voice(_get_kick_sound())
		_try_hit(_get_kick_damage())
	elif anim and anim.animation == "jump" and anim.frame == _get_jump_sound_frame():
		_play_voice(_get_jump_sound())
