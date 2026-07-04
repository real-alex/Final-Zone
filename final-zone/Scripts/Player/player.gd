class_name Player
extends CharacterBody3D
## First-person controller: look, walk/sprint/jump/crouch, stamina,
## head bob, footsteps. Health lives in a HealthComponent child.

signal died(attacker: Node)
signal damaged(amount: float, attacker: Node)
signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 2.8
const JUMP_VELOCITY := 4.6
const GROUND_ACCEL := 12.0
const AIR_ACCEL := 3.0

const STAND_SHAPE_HEIGHT := 1.8
const CROUCH_SHAPE_HEIGHT := 1.2
const HEAD_STAND_Y := 1.62
const HEAD_CROUCH_Y := 1.02

const BASE_FOV := 90.0
const SPRINT_FOV := 97.0

const MAX_STAMINA := 100.0
const STAMINA_DRAIN := 22.0
const STAMINA_REGEN := 16.0
const SPRINT_MIN_STAMINA := 8.0

const BOB_FREQUENCY := 2.4
const BOB_AMPLITUDE := 0.05

@onready var head: Node3D = $Head
@onready var recoil_node: Node3D = $Head/Recoil
@onready var camera: Camera3D = $Head/Recoil/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var health: HealthComponent = $HealthComponent
@onready var uncrouch_ray: RayCast3D = $UncrouchRay

var stamina := MAX_STAMINA
var is_crouching := false
var is_sprinting := false
var input_enabled := true

var _pitch := 0.0
var _bob_time := 0.0
var _last_bob_sin := 0.0
var _was_on_floor := true
var _weapon: Node = null


func _ready() -> void:
	add_to_group("player")
	camera.fov = BASE_FOV
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.health_changed.connect(func(c: float, m: float) -> void: health_changed.emit(c, m))
	_weapon = get_node_or_null("Head/Recoil/Camera3D/WeaponHolder")


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var sensitivity: float = SettingsManager.get_value("controls", "mouse_sensitivity") * 0.01
		if _is_aiming():
			sensitivity *= SettingsManager.get_value("controls", "ads_sensitivity_mult")
		rotate_y(-event.relative.x * sensitivity)
		_pitch = clampf(_pitch - event.relative.y * sensitivity, deg_to_rad(-89.0), deg_to_rad(89.0))
		head.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Vector2.ZERO
	var wants_sprint := false
	var wants_crouch := false
	if input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wants_sprint = Input.is_action_pressed("sprint")
		wants_crouch = Input.is_action_pressed("crouch")
		if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
			velocity.y = JUMP_VELOCITY

	_update_crouch(wants_crouch, delta)
	_update_sprint(wants_sprint, input_dir, delta)

	var target_speed := WALK_SPEED
	if is_crouching:
		target_speed = CROUCH_SPEED
	elif is_sprinting:
		target_speed = SPRINT_SPEED

	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var target_velocity := direction * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, accel * target_speed * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, accel * target_speed * delta)

	move_and_slide()

	_update_head_bob(delta)
	_update_fov(delta)

	if not _was_on_floor and is_on_floor():
		AudioManager.play_sfx_3d("footstep", global_position, -2.0, 0.1)
	_was_on_floor = is_on_floor()


func _update_crouch(wants_crouch: bool, _delta: float) -> void:
	if wants_crouch and not is_crouching:
		is_crouching = true
		_apply_crouch_shape(true)
	elif not wants_crouch and is_crouching and not uncrouch_ray.is_colliding():
		is_crouching = false
		_apply_crouch_shape(false)

	var target_head_y := HEAD_CROUCH_Y if is_crouching else HEAD_STAND_Y
	head.position.y = lerpf(head.position.y, target_head_y, 0.25)


func _apply_crouch_shape(crouched: bool) -> void:
	var capsule: CapsuleShape3D = collision_shape.shape
	capsule.height = CROUCH_SHAPE_HEIGHT if crouched else STAND_SHAPE_HEIGHT
	collision_shape.position.y = capsule.height * 0.5


func _update_sprint(wants_sprint: bool, input_dir: Vector2, delta: float) -> void:
	var moving_forward := input_dir.y < -0.1
	var firing := Input.is_action_pressed("fire")
	if wants_sprint and moving_forward and is_on_floor() and not is_crouching \
			and not _is_aiming() and not firing and stamina > SPRINT_MIN_STAMINA:
		is_sprinting = true
	elif not wants_sprint or not moving_forward or stamina <= 0.0 or is_crouching \
			or _is_aiming() or firing:
		is_sprinting = false

	if is_sprinting:
		stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
		if stamina <= 0.0:
			is_sprinting = false
	else:
		stamina = minf(stamina + STAMINA_REGEN * delta, MAX_STAMINA)
	stamina_changed.emit(stamina, MAX_STAMINA)


func _update_head_bob(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal_speed > 0.8:
		_bob_time += delta * horizontal_speed
		var bob_sin := sin(_bob_time * BOB_FREQUENCY)
		camera.position.y = bob_sin * BOB_AMPLITUDE
		camera.position.x = cos(_bob_time * BOB_FREQUENCY * 0.5) * BOB_AMPLITUDE * 0.6
		# Footstep at the bottom of each bob cycle.
		if _last_bob_sin > -0.9 and bob_sin <= -0.9:
			AudioManager.play_sfx_3d("footstep", global_position, -8.0, 0.15)
		_last_bob_sin = bob_sin
	else:
		camera.position.x = lerpf(camera.position.x, 0.0, 8.0 * delta)
		camera.position.y = lerpf(camera.position.y, 0.0, 8.0 * delta)


func _update_fov(delta: float) -> void:
	# FOV zoom tracks the weapon raise so the sight-up and zoom land
	# together, CoD-style.
	var hip_fov := SPRINT_FOV if is_sprinting else BASE_FOV
	var target_fov := hip_fov
	if _weapon != null and _weapon.has_method("get_aim_fraction"):
		target_fov = lerpf(hip_fov, _weapon.get_ads_fov(), _weapon.get_aim_fraction())
	camera.fov = lerpf(camera.fov, target_fov, 14.0 * delta)


func _is_aiming() -> bool:
	return _weapon != null and _weapon.has_method("get_ads_fov") and _weapon.get("is_aiming")


## Called by bot hitscan. Returns kill info like the bot's take_hit does.
func take_hit(damage: float, attacker: Node, _headshot_multiplier: float = 1.0) -> Dictionary:
	var was_alive := health.alive
	health.take_damage(damage, attacker, false)
	return {"killed": was_alive and not health.alive, "headshot": false, "damage": damage}


func _on_damaged(amount: float, attacker: Node, _headshot: bool) -> void:
	damaged.emit(amount, attacker)


func _on_died(attacker: Node) -> void:
	died.emit(attacker)


## Enables/disables the player body between death and respawn.
func set_active(active: bool) -> void:
	input_enabled = active
	visible = active
	set_physics_process(active)
	collision_shape.disabled = not active
	if active:
		velocity = Vector3.ZERO


func respawn_at(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	_pitch = 0.0
	head.rotation.x = 0.0
	stamina = MAX_STAMINA
	health.reset()
	set_active(true)
	if _weapon != null and _weapon.has_method("refill"):
		_weapon.refill()
