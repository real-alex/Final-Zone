@tool
class_name CharacterRig
extends Node3D
## Normalizes an imported character model (any scale) to a target height
## with feet on the ground, so free GLB characters drop in cleanly.
## The model is a static statue (no skeleton), so movement life comes from
## procedural animation: walk bob, strafe lean, and a death fall. All
## Node3D children (body, held gun, gear) are posed together, pivoting at
## the feet, so attachments move with the body.
## Runs in the editor too, so scenes preview at the correct size/facing.

@export var target_height := 1.75
## Turn the model if it faces the wrong way after import.
@export var yaw_offset_deg := 180.0
## First-person body mode: meshes cast shadows but are not drawn, so the
## model never clips the camera. Becomes the third-person body later.
@export var shadow_only := false

var _base_transforms: Dictionary = {}
var _walk_time := 0.0
var _lean := 0.0
var _death_progress := 0.0
var _death_direction := 1.0
var _death_tween: Tween


func _ready() -> void:
	var model := _first_model_child()
	if model == null:
		return
	# Idempotent: the editor may have saved a previous fit (script is
	# @tool), so always normalize from identity.
	model.transform = Transform3D.IDENTITY
	var aabb := _combined_aabb(model, Transform3D.IDENTITY)
	if aabb.size.y <= 0.0:
		return

	var scale_factor := target_height / aabb.size.y
	model.scale = Vector3.ONE * scale_factor
	model.rotate_y(deg_to_rad(yaw_offset_deg))

	var fitted := _combined_aabb(model, Transform3D.IDENTITY)
	model.position.x -= fitted.get_center().x
	model.position.z -= fitted.get_center().z
	model.position.y -= fitted.position.y

	if shadow_only:
		_apply_shadow_only(model)

	for child in get_children():
		if child is Node3D:
			_base_transforms[child] = child.transform


## Procedural walk: bob with speed, lean into strafes, pitch when moving.
## local_velocity is the owner's velocity in its own space (x = strafe).
func animate_locomotion(local_velocity: Vector3, delta: float) -> void:
	if _base_transforms.is_empty() or (_death_tween != null and _death_tween.is_valid()):
		return
	var speed := Vector2(local_velocity.x, local_velocity.z).length()
	_walk_time += delta * clampf(speed, 0.0, 8.0) * 1.6

	var bob := absf(sin(_walk_time)) * 0.05 * clampf(speed / 5.0, 0.0, 1.0)
	var lean_target := clampf(-local_velocity.x * 0.035, -0.16, 0.16)
	_lean = lerpf(_lean, lean_target, minf(8.0 * delta, 1.0))
	var forward_pitch := clampf(-local_velocity.z * 0.012, -0.08, 0.08)

	_apply_pose(Basis.from_euler(Vector3(forward_pitch, 0.0, _lean)), Vector3(0, bob, 0))


## Falls over sideways and settles — used instead of vanishing on death.
func play_death() -> void:
	if _base_transforms.is_empty():
		return
	reset_pose()
	_death_direction = -1.0 if randf() < 0.5 else 1.0
	_death_tween = create_tween()
	_death_tween.tween_method(_apply_death_pose, 0.0, 1.0, 0.55) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func reset_pose() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null
	_walk_time = 0.0
	_lean = 0.0
	_death_progress = 0.0
	for child: Node3D in _base_transforms:
		child.transform = _base_transforms[child]


func _apply_death_pose(progress: float) -> void:
	var angle := deg_to_rad(84.0) * progress * _death_direction
	_apply_pose(Basis.from_euler(Vector3(0, 0, angle)), Vector3(0, 0.1 * progress, 0))


## Rotates/offsets every child around the rig origin (the feet), so the
## body and anything it holds move as one.
func _apply_pose(pose_basis: Basis, pose_offset: Vector3) -> void:
	var pose := Transform3D(pose_basis, pose_offset)
	for child: Node3D in _base_transforms:
		child.transform = pose * _base_transforms[child]


func _apply_shadow_only(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for child in node.get_children():
		_apply_shadow_only(child)


func _first_model_child() -> Node3D:
	for child in get_children():
		if child is Node3D:
			return child
	return null


func _combined_aabb(node: Node3D, parent_transform: Transform3D) -> AABB:
	var node_transform := parent_transform * node.transform
	var result := AABB()
	var has_result := false
	if node is MeshInstance3D:
		result = node_transform * node.get_aabb()
		has_result = true
	for child in node.get_children():
		if child is Node3D:
			var child_aabb := _combined_aabb(child, node_transform)
			if child_aabb.size != Vector3.ZERO:
				result = result.merge(child_aabb) if has_result else child_aabb
				has_result = true
	return result
