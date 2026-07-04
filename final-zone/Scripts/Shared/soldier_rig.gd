class_name SoldierRig
extends Node3D
## Animated character rig for the Mixamo soldier pack. Same API as
## CharacterRig (animate_locomotion / play_death / reset_pose) so it drops
## into the bot, lobby, and player shadow body — but drives real skeletal
## clips from soldier_anims.res: 8-way walk/run/sprint, crouch and aiming
## variants, and direction-based deaths. A BoneAttachment3D on the right
## hand carries the weapon so it follows the animation.

## Loaded lazily in _ready — const preloads break when this script is
## compiled on the loading screen's background thread.
const CHARACTER_SCENE_PATH := "res://Assets/Characters/newcharater/Characterpack/black-squad-soldier-character.fbx"
const ANIM_LIBRARY_PATH := "res://Assets/Characters/soldier_anims.res"
const HAND_BONE := "mixamorig_RightHand"
const BLEND_TIME := 0.22

@export var target_height := 1.78
## Mixamo characters face +Z; gameplay forward is -Z.
@export var yaw_offset_deg := 180.0
## First-person body mode: casts shadows but is not drawn.
@export var shadow_only := false
## Clip to play on spawn (lobby uses "idle_aiming").
@export var initial_clip := "idle"
## Local pose of the weapon inside the right hand; tune per weapon.
@export var weapon_offset_pos := Vector3(0.02, 0.06, 0.04)
@export var weapon_offset_rot_deg := Vector3(78.0, 88.0, 0.0)

var aiming := false
var crouching := false

var _instance: Node3D
var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _hand_attachment: BoneAttachment3D
var _current_clip := ""
var _dead := false


func _ready() -> void:
	var character_scene: PackedScene = load(CHARACTER_SCENE_PATH)
	_instance = character_scene.instantiate()
	add_child(_instance)
	_skeleton = _instance.find_child("Skeleton3D", true, false)

	_normalize_size()
	if shadow_only:
		_apply_shadow_only(_instance)

	_anim_player = AnimationPlayer.new()
	add_child(_anim_player)
	_anim_player.root_node = _anim_player.get_path_to(_instance)
	_anim_player.add_animation_library("", load(ANIM_LIBRARY_PATH))

	if _skeleton != null:
		_hand_attachment = BoneAttachment3D.new()
		_skeleton.add_child(_hand_attachment)
		_hand_attachment.bone_name = HAND_BONE
		# Any weapon rig placed under this node moves into the hand so it
		# follows the animations.
		for child in get_children():
			if child is ViewmodelRig:
				attach_weapon(child)

	_play(initial_clip, 0.0)


## Reparents a weapon into the right hand with the exported grip pose.
func attach_weapon(weapon: Node3D) -> void:
	if _hand_attachment == null:
		return
	weapon.get_parent().remove_child(weapon)
	_hand_attachment.add_child(weapon)
	weapon.position = weapon_offset_pos
	weapon.rotation_degrees = weapon_offset_rot_deg
	# Undo the skeleton's inherited scale so the gun keeps its fitted size.
	var parent_scale := _hand_attachment.global_transform.basis.get_scale()
	if parent_scale.x > 0.0001:
		weapon.scale = Vector3.ONE / parent_scale.x
	if weapon.has_method("rebase_rest"):
		weapon.rebase_rest()


## Skinned mesh AABBs are unreliable before the first pose, so size and
## ground placement come from the skeleton's bone rest positions.
func _normalize_size() -> void:
	if _skeleton == null:
		return
	var bounds := _bone_bounds()
	var height := bounds[1].y - bounds[0].y
	if height <= 0.0:
		return
	# Bones stop at the head joint; pad a little for the skull.
	var scale_factor := target_height / (height * 1.06)
	_instance.scale *= scale_factor
	_instance.rotate_y(deg_to_rad(yaw_offset_deg))
	var fitted := _bone_bounds()
	_instance.position.x -= (fitted[0].x + fitted[1].x) * 0.5
	_instance.position.z -= (fitted[0].z + fitted[1].z) * 0.5
	_instance.position.y -= fitted[0].y


## [min, max] of all bone rest positions, in rig space.
func _bone_bounds() -> Array[Vector3]:
	var to_rig := global_transform.affine_inverse() * _skeleton.global_transform
	var min_bound := Vector3.INF
	var max_bound := -Vector3.INF
	for bone in _skeleton.get_bone_count():
		var bone_position := to_rig * _skeleton.get_bone_global_rest(bone).origin
		min_bound = min_bound.min(bone_position)
		max_bound = max_bound.max(bone_position)
	return [min_bound, max_bound]


## The node weapons attach to so they follow the hand animation.
func get_hand_attachment() -> Node3D:
	return _hand_attachment


## ---------- CharacterRig-compatible API ----------

## Picks the locomotion clip from the owner's local-space velocity
## (x = strafe right, z = backward). delta kept for API compatibility.
func animate_locomotion(local_velocity: Vector3, _delta: float) -> void:
	if _dead:
		return
	var strafe := local_velocity.x
	var forward := -local_velocity.z
	var speed := Vector2(strafe, forward).length()
	if speed < 0.5:
		_play(_idle_clip())
		return

	var prefix := "walk"
	if crouching:
		prefix = "walk_crouching"
	elif speed > 5.5:
		prefix = "sprint"
	elif speed > 2.6:
		prefix = "run"
	_play(prefix + "_" + _direction_suffix(strafe / speed, forward / speed))


## hit_direction is the bullet travel direction in world space; picks the
## matching death clip (front/back/side, headshot variants).
func play_death(hit_direction := Vector3.ZERO, headshot := false) -> void:
	if _dead:
		return
	_dead = true
	var clip := "death_from_the_front"
	if hit_direction != Vector3.ZERO:
		var local_hit := global_transform.basis.inverse() * hit_direction
		# Bullet flying toward -Z hits our back; toward +Z hits our front.
		if absf(local_hit.x) > absf(local_hit.z):
			clip = "death_from_right"
		elif local_hit.z < 0.0:
			clip = "death_from_back_headshot" if headshot else "death_from_the_back"
		else:
			clip = "death_from_front_headshot" if headshot else "death_from_the_front"
	elif headshot:
		clip = "death_from_front_headshot"
	if crouching:
		clip = "death_crouching_headshot_front"
	_play(clip, 0.12)


func reset_pose() -> void:
	_dead = false
	_current_clip = ""
	aiming = false
	crouching = false
	_play(initial_clip, 0.0)


## ---------- internals ----------

func _idle_clip() -> String:
	if crouching:
		return "idle_crouching_aiming" if aiming else "idle_crouching"
	return "idle_aiming" if aiming else "idle"


func _direction_suffix(strafe: float, forward: float) -> String:
	var parts := PackedStringArray()
	if forward > 0.38:
		parts.append("forward")
	elif forward < -0.38:
		parts.append("backward")
	if strafe < -0.38:
		parts.append("left")
	elif strafe > 0.38:
		parts.append("right")
	if parts.is_empty():
		parts.append("forward")
	return "_".join(parts)


func _play(clip_name: String, blend := BLEND_TIME) -> void:
	if _current_clip == clip_name or _anim_player == null:
		return
	if not _anim_player.has_animation(clip_name):
		push_warning("SoldierRig: missing clip '%s'" % clip_name)
		return
	_current_clip = clip_name
	_anim_player.play(clip_name, blend)


func _apply_shadow_only(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for child in node.get_children():
		_apply_shadow_only(child)


func _rig_space_aabb(branch: Node3D) -> AABB:
	var to_rig := global_transform.affine_inverse()
	var result := AABB()
	var has_result := false
	var stack: Array[Node] = [branch]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_aabb: AABB = (to_rig * node.global_transform) * node.get_aabb()
			result = result.merge(mesh_aabb) if has_result else mesh_aabb
			has_result = true
		for child in node.get_children():
			if child is Node3D:
				stack.push_back(child)
	return result
