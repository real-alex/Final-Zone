class_name Bot
extends CharacterBody3D
## AI opponent. State machine: PATROL waypoints -> CHASE last known player
## position -> ATTACK with strafing and difficulty-scaled aim.

enum State { PATROL, CHASE, ATTACK }

const VIEW_DISTANCE := 40.0
const VIEW_HALF_ANGLE_DEG := 70.0
const PERCEPTION_INTERVAL := 0.15
const ATTACK_RANGE_FAR := 22.0
const ATTACK_RANGE_NEAR := 6.0
const TURN_SPEED := 7.0
const AIM_TOLERANCE_DEG := 9.0

@export var display_name := "BOT"

var state: State = State.PATROL
var enabled := false
var patrol_points: Array[Vector3] = []

## Difficulty tuning, set from GameManager preset by the match scene.
var reaction_time := 0.45
var aim_spread_deg := 3.5
var damage_per_shot := 12.0
var fire_interval := 0.2
var move_speed := 4.2

var _player: Player
var _can_see_player := false
var _last_known := Vector3.ZERO
var _reaction_left := 0.0
var _perception_timer := 0.0
var _fire_cooldown := 0.0
var _strafe_timer := 0.0
var _strafe_direction := 1.0
var _patrol_target := Vector3.ZERO
var _last_hit_direction := Vector3.ZERO
var _last_hit_headshot := false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health: HealthComponent = $HealthComponent
@onready var eye: Node3D = $Eye
@onready var muzzle_light: OmniLight3D = $Eye/MuzzleLight
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
## SoldierRig (animated) or CharacterRig (static fallback) — same API.
@onready var character_rig: Node3D = $CharacterModel


func _ready() -> void:
	add_to_group("bot")
	health.damaged.connect(_on_damaged)
	muzzle_light.light_energy = 0.0


func setup(difficulty_preset: Dictionary, points: Array[Vector3]) -> void:
	reaction_time = difficulty_preset["reaction_time"]
	aim_spread_deg = difficulty_preset["aim_spread_deg"]
	damage_per_shot = difficulty_preset["damage"]
	fire_interval = difficulty_preset["fire_interval"]
	move_speed = difficulty_preset["move_speed"]
	patrol_points = points
	_reaction_left = reaction_time


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	muzzle_light.light_energy = maxf(muzzle_light.light_energy - 25.0 * delta, 0.0)
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)

	if not enabled or not health.alive:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_ensure_player()
	_update_perception(delta)

	match state:
		State.PATROL:
			_process_patrol()
		State.CHASE:
			_process_chase()
		State.ATTACK:
			_process_attack(delta)

	move_and_slide()
	character_rig.set("aiming", state == State.ATTACK)
	character_rig.animate_locomotion(global_transform.basis.inverse() * velocity, delta)


func _ensure_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")


func _update_perception(delta: float) -> void:
	_perception_timer -= delta
	if _perception_timer > 0.0:
		return
	_perception_timer = PERCEPTION_INTERVAL

	_can_see_player = _check_line_of_sight()
	if _can_see_player:
		_last_known = _player.global_position
		if state == State.ATTACK:
			return
		_reaction_left -= PERCEPTION_INTERVAL
		if _reaction_left <= 0.0:
			state = State.ATTACK
	else:
		_reaction_left = reaction_time
		if state == State.ATTACK:
			state = State.CHASE
			nav_agent.target_position = _last_known


func _check_line_of_sight() -> bool:
	if _player == null or not _player.input_enabled:
		return false
	var to_player := _player.global_position - global_position
	if to_player.length() > VIEW_DISTANCE:
		return false

	# Field of view check, ignored while already fighting.
	if state == State.PATROL:
		var forward := -global_transform.basis.z
		var flat := Vector3(to_player.x, 0.0, to_player.z).normalized()
		if forward.angle_to(flat) > deg_to_rad(VIEW_HALF_ANGLE_DEG):
			return false

	var from := eye.global_position
	var to := _player.global_position + Vector3(0, 1.4, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 0b11)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == _player


func _process_patrol() -> void:
	if patrol_points.is_empty():
		return
	if _patrol_target == Vector3.ZERO or nav_agent.is_navigation_finished():
		_patrol_target = patrol_points.pick_random()
		nav_agent.target_position = _patrol_target
	_move_along_path(move_speed * 0.6)


func _process_chase() -> void:
	nav_agent.target_position = _last_known
	if nav_agent.is_navigation_finished():
		state = State.PATROL
		_patrol_target = Vector3.ZERO
		return
	_move_along_path(move_speed)


func _process_attack(delta: float) -> void:
	if _player == null:
		state = State.PATROL
		return

	_face_position(_player.global_position, delta)

	# Strafe while fighting; push closer when far, back off when close.
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.9, 1.8)
		_strafe_direction = -1.0 if randf() < 0.5 else 1.0

	var to_player := _player.global_position - global_position
	var distance := to_player.length()
	var flat_direction := Vector3(to_player.x, 0.0, to_player.z).normalized()
	var strafe := flat_direction.cross(Vector3.UP) * _strafe_direction
	var move_direction := strafe
	if distance > ATTACK_RANGE_FAR:
		move_direction = (flat_direction + strafe * 0.5).normalized()
	elif distance < ATTACK_RANGE_NEAR:
		move_direction = (-flat_direction + strafe * 0.7).normalized()

	velocity.x = move_direction.x * move_speed * 0.8
	velocity.z = move_direction.z * move_speed * 0.8

	if _can_see_player and _fire_cooldown <= 0.0 and _is_facing(_player.global_position):
		_fire_at_player()


func _move_along_path(speed: float) -> void:
	if nav_agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var next_point := nav_agent.get_next_path_position()
	var direction := next_point - global_position
	direction.y = 0.0
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if direction.length() > 0.1:
		_face_position(global_position + direction, get_physics_process_delta_time())


func _face_position(target: Vector3, delta: float) -> void:
	var to_target := target - global_position
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, TURN_SPEED * delta)


func _is_facing(target: Vector3) -> bool:
	var to_target := target - global_position
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	return absf(angle_difference(rotation.y, desired_yaw)) < deg_to_rad(AIM_TOLERANCE_DEG)


func _fire_at_player() -> void:
	_fire_cooldown = fire_interval
	muzzle_light.light_energy = 2.0
	AudioManager.play_sfx_3d("gunshot", eye.global_position, -4.0, 0.1)

	var from := eye.global_position
	var target := _player.global_position + Vector3(0, 1.3, 0)
	var direction := (target - from).normalized()
	# Aim error cone scaled by difficulty.
	var spread := deg_to_rad(aim_spread_deg)
	var angle := randf() * TAU
	var deviation := randf() * spread
	var arbitrary_up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := direction.cross(arbitrary_up).normalized()
	var up := right.cross(direction)
	direction = (direction + (right * cos(angle) + up * sin(angle)) * tan(deviation)).normalized()

	var query := PhysicsRayQueryParameters3D.create(from, from + direction * VIEW_DISTANCE, 0b11)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider == _player:
		_player.take_hit(damage_per_shot, self)


func _on_damaged(_amount: float, attacker: Node, _headshot: bool) -> void:
	# Getting shot reveals the shooter.
	if attacker is Node3D and health.alive:
		_last_known = (attacker as Node3D).global_position
		if state == State.PATROL:
			state = State.CHASE
			nav_agent.target_position = _last_known
			_reaction_left = 0.0


## Weapon hits arrive here from the hurtboxes.
func receive_damage(amount: float, attacker: Node, headshot: bool) -> Dictionary:
	var was_alive := health.alive
	if attacker is Node3D:
		_last_hit_direction = (global_position - (attacker as Node3D).global_position).normalized()
	_last_hit_headshot = headshot
	health.take_damage(amount, attacker, headshot)
	return {"killed": was_alive and not health.alive, "headshot": headshot}


func set_active(active: bool) -> void:
	enabled = active
	visible = active
	collision_shape.set_deferred("disabled", not active)
	for hurtbox: Hurtbox in [$BodyHurtbox, $HeadHurtbox]:
		hurtbox.get_node("CollisionShape3D").set_deferred("disabled", not active)
	if active:
		velocity = Vector3.ZERO


## Death: stays visible and falls over; collisions turn off immediately.
func play_death() -> void:
	enabled = false
	collision_shape.set_deferred("disabled", true)
	for hurtbox: Hurtbox in [$BodyHurtbox, $HeadHurtbox]:
		hurtbox.get_node("CollisionShape3D").set_deferred("disabled", true)
	character_rig.play_death(_last_hit_direction, _last_hit_headshot)


func respawn_at(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	health.reset()
	state = State.PATROL
	_patrol_target = Vector3.ZERO
	_can_see_player = false
	_reaction_left = reaction_time
	character_rig.reset_pose()
	set_active(true)
