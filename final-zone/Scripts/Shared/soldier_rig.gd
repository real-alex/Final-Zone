class_name SoldierRig
extends Node3D
## Procedural low-poly soldier built entirely from primitive boxes — no
## imported model, so it has zero asset-import cost (the imported FBX
## crashed low-end machines). BattleBit-style blocky proportions.
## Same API as before (animate_locomotion / play_death / reset_pose /
## aiming / get_hand_attachment) so the bot, lobby and player drop in
## unchanged. Limbs are pivot nodes so walking swings them procedurally.

const HAND_BONE := "hand_r"  ## kept for API compatibility

@export var target_height := 1.8
@export var yaw_offset_deg := 0.0
## First-person body mode: casts shadows but is not drawn.
@export var shadow_only := false
## Unused now (was the anim clip name); kept so scenes don't error.
@export var initial_clip := "idle"
@export var weapon_offset_pos := Vector3(0.0, 0.0, 0.0)
@export var weapon_offset_rot_deg := Vector3(0.0, 0.0, 0.0)

## Team tint for the uniform (bot = enemy red-brown, player = neutral).
@export var uniform_color := Color(0.30, 0.33, 0.22)
## Customization toggles (driven by the Customize screen / CustomizeManager).
@export var show_helmet := true
@export var show_armor := true      ## plate carrier + pouches
@export var helmet_color := Color(0.34, 0.30, 0.21)
@export var armor_color := Color(0.44, 0.37, 0.25)
## T-pose (arms straight out) for exporting a rig-friendly GLB to Mixamo.
@export var tpose := false
## Player-controlled characters (lobby, player body) pull their look from
## CustomizeManager; bots keep their scene-set look.
@export var use_player_customization := false

var aiming := false
var crouching := false

var _root: Node3D               ## whole-body offset/rotation pivot
var _facing: Node3D             ## 180° base so the body faces -Z (forward)
var _torso: Node3D
var _head: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _hand_attachment: Node3D
var _walk_cycle := 0.0
var _aim_blend := 0.0
var _dead := false
var _death_tween: Tween
var _mesh_nodes: Array[MeshInstance3D] = []


func _ready() -> void:
	if use_player_customization:
		var cm := get_node_or_null("/root/CustomizeManager")
		if cm != null:
			cm.apply_to(self)
	_build_body()
	if tpose:
		# Arms straight out to the sides — a rig-friendly pose for Mixamo.
		_left_arm.rotation_degrees = Vector3(0, 0, 78)
		_right_arm.rotation_degrees = Vector3(0, 0, -78)
	if shadow_only:
		for mesh in _mesh_nodes:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	rotate_y(deg_to_rad(yaw_offset_deg))
	# Any ViewmodelRig placed under us (bot/lobby held gun) goes in the hand.
	for child in get_children():
		if child is ViewmodelRig:
			attach_weapon(child)


## ---------- body construction ----------

func _build_body() -> void:
	# Tactical operator palette — coyote/olive kit, dark gear, matching the
	# old soldier model in a clean Minecraft/voxel style.
	var skin := _mat(Color(0.62, 0.47, 0.38), 0.75)
	var uniform := _mat(uniform_color, 0.85)
	var carrier := _mat(armor_color, 0.8)                      # plate carrier
	var gear := _mat(Color(0.09, 0.09, 0.10), 0.6)             # pouches / straps
	var glove := _mat(Color(0.07, 0.07, 0.08), 0.6)
	var boots := _mat(Color(0.05, 0.05, 0.06), 0.7)
	var helmet := _mat(helmet_color, 0.8)
	var goggles := _mat(Color(0.08, 0.10, 0.14), 0.2, 0.4)

	_root = Node3D.new()
	add_child(_root)
	# Body visual faces -Z (same way the character moves and aims). Kept in
	# a separate node so locomotion lean / death rotation on _root never
	# clobbers this base facing.
	_facing = Node3D.new()
	_facing.rotation_degrees = Vector3(0, 180, 0)
	_root.add_child(_facing)

	# Pelvis + belt + drop-leg pouch.
	_box(Vector3(0.36, 0.20, 0.22), Vector3(0, 0.92, 0), uniform, _facing)
	_box(Vector3(0.38, 0.06, 0.24), Vector3(0, 0.86, 0), gear, _facing)          # belt
	_box(Vector3(0.10, 0.14, 0.08), Vector3(0.16, 0.80, 0.02), gear, _facing)    # thigh pouch

	# Torso: fatigue shirt + plate carrier with pouches + shoulder straps.
	_torso = Node3D.new()
	_torso.position = Vector3(0, 1.02, 0)
	_facing.add_child(_torso)
	_box(Vector3(0.42, 0.50, 0.24), Vector3(0, 0.20, 0), uniform, _torso)      # chest/shirt
	if show_armor:
		_box(Vector3(0.44, 0.40, 0.29), Vector3(0, 0.20, 0.01), carrier, _torso)   # plate carrier
		_box(Vector3(0.12, 0.14, 0.06), Vector3(-0.10, 0.16, 0.15), gear, _torso)  # mag pouch L
		_box(Vector3(0.12, 0.14, 0.06), Vector3(0.10, 0.16, 0.15), gear, _torso)   # mag pouch R
		_box(Vector3(0.10, 0.10, 0.06), Vector3(0, 0.02, 0.15), gear, _torso)      # admin pouch
		_box(Vector3(0.10, 0.30, 0.05), Vector3(-0.16, 0.30, 0.02), gear, _torso)  # strap L
		_box(Vector3(0.10, 0.30, 0.05), Vector3(0.16, 0.30, 0.02), gear, _torso)   # strap R
	_box(Vector3(0.14, 0.10, 0.22), Vector3(0, 0.42, 0), uniform, _torso)      # neck/collar base

	# Head: face + helmet shell + brim + goggles + lower face cover.
	_head = Node3D.new()
	_head.position = Vector3(0, 0.52, 0)
	_torso.add_child(_head)
	_box(Vector3(0.19, 0.21, 0.19), Vector3(0, 0.11, 0), skin, _head)          # face
	if show_helmet:
		_box(Vector3(0.23, 0.13, 0.23), Vector3(0, 0.22, 0), helmet, _head)        # helmet dome
		_box(Vector3(0.24, 0.05, 0.10), Vector3(0, 0.17, -0.09), helmet, _head)    # rear shroud
		_box(Vector3(0.21, 0.05, 0.06), Vector3(0, 0.185, 0.075), goggles, _head)  # goggles pushed up
	else:
		_box(Vector3(0.20, 0.10, 0.20), Vector3(0, 0.24, 0), _mat(Color(0.15, 0.11, 0.08), 0.9), _head)  # hair
	# Minecraft-style face: eyes (white + dark pupil) + nose.
	var white := _mat(Color(0.92, 0.92, 0.90), 0.5)
	var pupil := _mat(Color(0.10, 0.09, 0.12), 0.4)
	for sx in [-0.045, 0.045]:
		_box(Vector3(0.05, 0.045, 0.02), Vector3(sx, 0.135, 0.096), white, _head)   # eye white
		_box(Vector3(0.022, 0.03, 0.02), Vector3(sx, 0.135, 0.102), pupil, _head)    # pupil
	_box(Vector3(0.035, 0.05, 0.035), Vector3(0, 0.09, 0.098), skin, _head)          # nose
	_box(Vector3(0.13, 0.045, 0.03), Vector3(0, 0.04, 0.095), _mat(Color(0.4, 0.3, 0.26), 0.6), _head)  # mouth/chin strap

	# Arms — pivot at shoulder; upper/lower/glove + elbow pad.
	_left_arm = _build_arm(Vector3(-0.29, 0.40, 0), uniform, glove, gear)
	_right_arm = _build_arm(Vector3(0.29, 0.40, 0), uniform, glove, gear)

	# Legs — pivot at hip; thigh/knee pad/shin/boot.
	_left_leg = _build_leg(Vector3(-0.10, 0.0, 0), uniform, boots, gear)
	_right_leg = _build_leg(Vector3(0.10, 0.0, 0), uniform, boots, gear)

	# Held weapon mounts at the chest, under _root (NOT the 180° _facing) so
	# its barrel points -Z — the same way the character aims and moves.
	_hand_attachment = Node3D.new()
	_root.add_child(_hand_attachment)
	_hand_attachment.position = Vector3(0.12, 1.06, -0.22)
	_hand_attachment.rotation_degrees = Vector3(-6, 0, 0)


func _build_arm(shoulder: Vector3, uniform: StandardMaterial3D, glove: StandardMaterial3D, gear: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = shoulder
	_torso.add_child(pivot)
	_box(Vector3(0.13, 0.24, 0.13), Vector3(0, -0.13, 0), uniform, pivot)      # upper arm
	_box(Vector3(0.13, 0.06, 0.14), Vector3(0, -0.26, 0.005), gear, pivot)     # elbow pad
	_box(Vector3(0.115, 0.24, 0.115), Vector3(0, -0.40, 0), uniform, pivot)    # forearm
	_box(Vector3(0.11, 0.11, 0.13), Vector3(0, -0.54, 0.01), glove, pivot)     # glove/hand
	return pivot


func _build_leg(hip: Vector3, uniform: StandardMaterial3D, boots: StandardMaterial3D, gear: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(hip.x, 0.82, hip.z)
	_facing.add_child(pivot)
	_box(Vector3(0.17, 0.42, 0.18), Vector3(0, -0.21, 0), uniform, pivot)      # thigh
	_box(Vector3(0.16, 0.10, 0.17), Vector3(0, -0.40, 0.02), gear, pivot)      # knee pad
	_box(Vector3(0.15, 0.38, 0.16), Vector3(0, -0.60, 0), uniform, pivot)      # shin
	_box(Vector3(0.17, 0.13, 0.30), Vector3(0, -0.82, 0.05), boots, pivot)     # boot
	return pivot


func _box(size: Vector3, pos: Vector3, material: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = pos
	parent.add_child(mesh_instance)
	_mesh_nodes.append(mesh_instance)
	return mesh_instance


func _mat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


## ---------- API (unchanged for callers) ----------

func get_hand_attachment() -> Node3D:
	return _hand_attachment


func attach_weapon(weapon: Node3D) -> void:
	if _hand_attachment == null:
		return
	if weapon.get_parent() != null:
		weapon.get_parent().remove_child(weapon)
	_hand_attachment.add_child(weapon)
	weapon.position = weapon_offset_pos
	weapon.rotation_degrees = weapon_offset_rot_deg
	if weapon.has_method("rebase_rest"):
		weapon.rebase_rest()


## Procedural locomotion: swing limbs by speed, bob and lean; raise arms
## toward a rifle-ready pose while aiming.
func animate_locomotion(local_velocity: Vector3, delta: float) -> void:
	if _dead or _root == null:
		return
	var speed := Vector2(local_velocity.x, local_velocity.z).length()
	_walk_cycle += delta * clampf(speed, 0.0, 8.0) * 2.2
	var swing := sin(_walk_cycle) * clampf(speed / 4.0, 0.0, 1.0) * 0.7

	_left_leg.rotation.x = swing
	_right_leg.rotation.x = -swing

	# Aim blend: arms come up and forward when aiming/attacking.
	var want_aim := 1.0 if aiming else 0.0
	_aim_blend = lerpf(_aim_blend, want_aim, minf(10.0 * delta, 1.0))
	var arm_ready := deg_to_rad(-75.0) * _aim_blend
	_right_arm.rotation.x = arm_ready - swing * (1.0 - _aim_blend)
	_left_arm.rotation.x = arm_ready + swing * (1.0 - _aim_blend)
	_left_arm.rotation.y = deg_to_rad(18.0) * _aim_blend
	_right_arm.rotation.y = deg_to_rad(-18.0) * _aim_blend

	# Bob + strafe lean on the whole body.
	_root.position.y = absf(sin(_walk_cycle)) * 0.04 * clampf(speed / 4.0, 0.0, 1.0)
	_root.rotation.z = lerp_angle(_root.rotation.z, clampf(-local_velocity.x * 0.03, -0.12, 0.12), minf(8.0 * delta, 1.0))
	var crouch_drop := -0.28 if crouching else 0.0
	_root.position.y += crouch_drop


func play_death(hit_direction := Vector3.ZERO, _headshot := false) -> void:
	if _dead:
		return
	_dead = true
	var fall_dir := 1.0
	if hit_direction != Vector3.ZERO:
		var local_hit := global_transform.basis.inverse() * hit_direction
		fall_dir = signf(local_hit.z) if absf(local_hit.z) > 0.01 else 1.0
	_death_tween = create_tween()
	_death_tween.tween_property(_root, "rotation:x", deg_to_rad(88.0) * fall_dir, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.parallel().tween_property(_root, "position:y", -0.1, 0.5)


func reset_pose() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_dead = false
	_aim_blend = 0.0
	_walk_cycle = 0.0
	if _root != null:
		_root.rotation = Vector3.ZERO
		_root.position = Vector3.ZERO
	for limb in [_left_arm, _right_arm, _left_leg, _right_leg]:
		if limb != null:
			limb.rotation = Vector3.ZERO
