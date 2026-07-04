class_name WeaponController
extends Node3D
## Player weapon manager: primary/secondary WeaponData slots with runtime-
## built viewmodels, weapon switching (1 / 2 / mouse wheel), hitscan firing
## with pellets, reload, recoil, sway, and CoD/BattleBit ADS — the weapon
## raises so you aim through its optic while FOV zooms and spread collapses.
## Attached to the WeaponHolder node under the player camera.

signal ammo_changed(magazine: int, reserve: int)
signal hit_confirmed(headshot: bool, killed: bool)
signal fired
signal weapon_changed(display_name: String, fire_mode_name: String)

const RECOIL_RECOVERY := 9.0
const SWAY_AMOUNT := 0.00012
const SWAY_MAX := 0.035
const SWAY_RECOVERY := 10.0
const ADS_SWAY_MULT := 0.42
const IDLE_BOB_SPEED := 1.6
const IDLE_BOB_AMOUNT := 0.004
const ADS_EYE_RELIEF := 0.24
const SWITCH_TIME := 0.4
## Ray mask: world (layer 1) + hurtbox areas (layer 8). The bot's movement
## capsule (layer 4) is excluded so rays reach the head/body hurtboxes.
const HIT_MASK := 0b1001

@export var primary: WeaponData
@export var secondary: WeaponData
## Where the weapon sits when aiming. Leave ZERO to auto-align through the
## optic center measured on the viewmodel.
@export var ads_position_override := Vector3.ZERO

var data: WeaponData
var magazine := 0
var reserve := 0
var aim_fraction := 0.0
var is_aiming: bool:
	get:
		return aim_fraction > 0.6
var is_reloading := false

var _slot_index := 0
var _slot_ammo: Dictionary = {}
var _switching := false
var _hip_position := Vector3.ZERO
var _ads_position := Vector3.ZERO
var _fire_cooldown := 0.0
var _recoil_offset := Vector3.ZERO
var _sway_offset := Vector3.ZERO
var _idle_time := 0.0
var _reload_token := 0
var _optic_type := "red_dot"
var _viewmodel: ViewmodelRig
var _flash_light: OmniLight3D
var _impact_scene: PackedScene = preload("res://Scenes/Weapons/impact_effect.tscn")

@onready var _player: Player = owner
@onready var _camera: Camera3D = get_parent()


var _slot_paths: Array[String] = ["", ""]


func _ready() -> void:
	_hip_position = position
	# The equipped loadout wins over the scene's exported defaults.
	if _player != null:
		primary = LoadoutManager.get_primary()
		secondary = LoadoutManager.get_secondary()
		_slot_paths = [LoadoutManager.primary_path, LoadoutManager.secondary_path]
	else:
		_slot_paths = [
			primary.resource_path if primary != null else "",
			secondary.resource_path if secondary != null else "",
		]
	_equip_slot(0, true)


## ---------- weapon slots ----------

func _slot_data(index: int) -> WeaponData:
	return primary if index == 0 else secondary


func _equip_slot(index: int, instant := false) -> void:
	var new_data := _slot_data(index)
	if new_data == null:
		return
	if data != null:
		_slot_ammo[_slot_index] = {"magazine": magazine, "reserve": reserve}
	_slot_index = index
	var fitted := LoadoutManager.get_attachments(_slot_paths[index])
	data = new_data.with_attachments(fitted)
	_reload_token += 1
	is_reloading = false
	aim_fraction = 0.0

	if _viewmodel != null:
		_viewmodel.queue_free()
	var weapon_path := _slot_paths[index]
	_optic_type = LoadoutManager.get_optic(weapon_path) if weapon_path != "" else "red_dot"
	_viewmodel = ViewmodelRig.new()
	_viewmodel.body_part = data.body_part
	_viewmodel.keep_parts = data.keep_parts
	_viewmodel.scope_part = data.scope_part
	_viewmodel.build_optic = data.build_optic
	_viewmodel.optic_type = _optic_type
	_viewmodel.optic_offset = LoadoutManager.get_optic_offset(weapon_path)
	_viewmodel.aim_trim_deg = LoadoutManager.get_aim_trim(weapon_path)
	_viewmodel.attachments = fitted
	_viewmodel.target_length = data.view_length
	_viewmodel.flip_forward = data.flip_forward
	var model: Node3D = load(data.model_path).instantiate()
	_viewmodel.add_child(model)
	add_child(_viewmodel)

	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.35)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 4.0
	_viewmodel.add_child(_flash_light)

	var saved: Dictionary = _slot_ammo.get(index, {})
	magazine = saved.get("magazine", data.magazine_size)
	reserve = saved.get("reserve", data.reserve_ammo)

	_setup_ads_position.call_deferred()
	ammo_changed.emit.call_deferred(magazine, reserve)
	weapon_changed.emit.call_deferred(data.display_name, data.get_fire_mode_name())

	if not instant:
		_switching = true
		_fire_cooldown = SWITCH_TIME
		_viewmodel.play_draw.call_deferred(SWITCH_TIME * 0.9)
		get_tree().create_timer(SWITCH_TIME, false).timeout.connect(
			func() -> void: _switching = false)


func _setup_ads_position() -> void:
	if _viewmodel == null:
		return
	_flash_light.position = _viewmodel.muzzle_position
	if ads_position_override != Vector3.ZERO:
		_ads_position = ads_position_override
	elif _viewmodel.scope_center != Vector3.ZERO:
		# Put the optic center on the camera axis, one eye-relief back.
		_ads_position = Vector3(
			-_viewmodel.scope_center.x,
			-_viewmodel.scope_center.y,
			-ADS_EYE_RELIEF - _viewmodel.scope_center.z
		)
	else:
		# No optic measured: drop the rig so the top of the gun meets the
		# camera center, slightly closer than hip position.
		_ads_position = Vector3(0.0, -_viewmodel.sight_height - 0.012, _hip_position.z * 0.75)


## ---------- per-frame ----------

func _process(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	var can_control := _can_control()

	_update_aim(delta, can_control)
	_update_sway_and_position(delta)
	_update_recoil(delta)
	if _flash_light != null:
		_flash_light.light_energy = maxf(_flash_light.light_energy - 30.0 * delta, 0.0)

	if not can_control:
		return
	_handle_switch_input()
	if _switching:
		return
	if Input.is_action_just_pressed("reload"):
		_start_reload()
	if data.fire_mode == 0:
		if Input.is_action_pressed("fire"):
			_try_fire()
	elif Input.is_action_just_pressed("fire"):
		_try_fire()


func _handle_switch_input() -> void:
	if _switching:
		return
	if Input.is_action_just_pressed("weapon_1") and _slot_index != 0:
		_equip_slot(0)
	elif Input.is_action_just_pressed("weapon_2") and _slot_index != 1:
		_equip_slot(1)
	elif Input.is_action_just_pressed("weapon_next"):
		_equip_slot(1 - _slot_index)


func _can_control() -> bool:
	return (
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and _player != null
		and _player.input_enabled
		and GameManager.is_gameplay_active()
	)


func _update_aim(delta: float, can_control: bool) -> void:
	var wants_aim := (
		can_control and not _switching
		and Input.is_action_pressed("ads") and not _player.is_sprinting
	)
	var step := delta / maxf(data.ads_time, 0.05)
	aim_fraction = clampf(aim_fraction + (step if wants_aim else -step), 0.0, 1.0)


func _update_sway_and_position(delta: float) -> void:
	# Mouse sway: viewmodel lags behind the camera, damped while aiming.
	var mouse_velocity := Input.get_last_mouse_velocity()
	var sway_scale := SWAY_AMOUNT * lerpf(1.0, ADS_SWAY_MULT, aim_fraction)
	var sway_target := Vector3(
		clampf(-mouse_velocity.x * sway_scale * 0.01, -SWAY_MAX, SWAY_MAX),
		clampf(mouse_velocity.y * sway_scale * 0.01, -SWAY_MAX, SWAY_MAX),
		0.0
	)
	_sway_offset = _sway_offset.lerp(sway_target, minf(SWAY_RECOVERY * delta, 1.0))

	# Idle breathing bob, kept alive but reduced during ADS.
	_idle_time += delta
	var idle := Vector3(
		cos(_idle_time * IDLE_BOB_SPEED * 0.7),
		sin(_idle_time * IDLE_BOB_SPEED),
		0.0
	) * IDLE_BOB_AMOUNT * lerpf(1.0, 0.45, aim_fraction)

	# Smooth hip <-> ADS raise (eased, CoD-style).
	var raise := ease(aim_fraction, -2.0)
	position = _hip_position.lerp(_ads_position, raise) + _sway_offset + idle


func _update_recoil(delta: float) -> void:
	_recoil_offset = _recoil_offset.lerp(Vector3.ZERO, minf(RECOIL_RECOVERY * delta, 1.0))
	if _player != null:
		_player.recoil_node.rotation = _recoil_offset


func get_ads_fov() -> float:
	match _optic_type:
		"sniper":
			return minf(data.ads_fov, 34.0)
		"holo":
			return minf(data.ads_fov, 56.0)
	return data.ads_fov


func get_aim_fraction() -> float:
	return aim_fraction


func get_optic_type() -> String:
	return _optic_type


func get_scope_view_fraction() -> float:
	if _optic_type != "sniper":
		return 0.0
	return clampf((aim_fraction - 0.72) / 0.28, 0.0, 1.0)


func get_current_spread_deg() -> float:
	var spread := lerpf(data.hip_spread_deg, data.ads_spread_deg, aim_fraction)
	if _player != null:
		var speed_factor := clampf(_player.velocity.length() / Player.SPRINT_SPEED, 0.0, 1.0)
		spread += data.move_spread_add_deg * speed_factor * lerpf(1.0, 0.25, aim_fraction)
		if _player.is_crouching:
			spread *= 0.7
	return spread


## ---------- firing ----------

func _try_fire() -> void:
	if is_reloading or _fire_cooldown > 0.0:
		return
	if magazine <= 0:
		AudioManager.play_sfx("dry_fire", -6.0)
		_fire_cooldown = 0.25
		if reserve > 0:
			_start_reload()
		return

	magazine -= 1
	_fire_cooldown = data.get_fire_interval()
	ammo_changed.emit(magazine, reserve)
	fired.emit()

	AudioManager.play_sfx(data.fire_sound, -9.0 if data.suppressed else 0.0, 0.08)
	_flash_light.light_energy = 0.9 if data.suppressed else 2.5
	_viewmodel.add_fire_kick()

	# Recoil: pitch up plus random yaw.
	_recoil_offset.x += deg_to_rad(data.recoil_pitch_deg)
	_recoil_offset.y += deg_to_rad(randf_range(-data.recoil_yaw_deg, data.recoil_yaw_deg))

	for pellet in data.pellets:
		_fire_ray()


func _fire_ray() -> void:
	var spread_rad := deg_to_rad(get_current_spread_deg())
	var forward := -_camera.global_transform.basis.z
	# Random point in a cone around the camera forward vector.
	var angle := randf() * TAU
	var deviation := randf() * spread_rad
	var right := _camera.global_transform.basis.x
	var up := _camera.global_transform.basis.y
	var direction := (forward + (right * cos(angle) + up * sin(angle)) * tan(deviation)).normalized()

	var from := _camera.global_position
	var to := from + direction * data.max_range
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	query.collide_with_areas = true
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	_spawn_impact(hit.position, hit.normal)
	var collider: Object = hit.collider
	if collider != null and collider.has_method("take_hit"):
		var result: Dictionary = collider.take_hit(data.damage, _player, data.headshot_multiplier)
		hit_confirmed.emit(result.get("headshot", false), result.get("killed", false))


func _spawn_impact(hit_position: Vector3, hit_normal: Vector3) -> void:
	var impact: Node3D = _impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = hit_position + hit_normal * 0.01


## ---------- reload ----------

func _start_reload() -> void:
	if is_reloading or _switching or reserve <= 0 or magazine >= data.magazine_size:
		return
	is_reloading = true
	_reload_token += 1
	var token := _reload_token
	AudioManager.play_sfx(data.reload_sound, -4.0)
	_viewmodel.play_reload(data.reload_time)
	await get_tree().create_timer(data.reload_time).timeout
	if token != _reload_token or not is_inside_tree():
		return
	var needed := data.magazine_size - magazine
	var loaded := mini(needed, reserve)
	magazine += loaded
	reserve -= loaded
	is_reloading = false
	ammo_changed.emit(magazine, reserve)


## Full ammo restore on both slots and reload cancel — used on respawn.
func refill() -> void:
	_reload_token += 1
	is_reloading = false
	_slot_ammo.clear()
	magazine = data.magazine_size
	reserve = data.reserve_ammo
	if _viewmodel != null:
		_viewmodel.cancel_reload()
	ammo_changed.emit(magazine, reserve)
