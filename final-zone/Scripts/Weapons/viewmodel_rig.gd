@tool
class_name ViewmodelRig
extends Node3D
## Prepares an imported "attachment set" gun GLB for use: keeps only the
## assembled-rifle parts, normalizes scale/orientation (barrel down -Z),
## optionally mounts a cosmetic scope part, and can BUILD a working red
## dot optic (housing + glass + emissive dot) on the top rail for ADS.
## Owns the procedural viewmodel animations (fire kick, reload, draw).
## Runs in the editor too, so scenes preview at the correct size.

## Desired stock-to-muzzle length in meters after normalization.
@export var target_length := 0.85
## Branch that is the assembled rifle. Empty keeps every part visible.
@export var body_part := "M4"
## Extra branches kept exactly where the artist placed them (e.g. a
## magazine already sitting in the mag well).
@export var keep_parts := PackedStringArray(["Mag"])
## Cosmetic branch auto-mounted onto the top rail. Empty mounts nothing.
@export var scope_part := "Scope"
## Builds a functional optic on the rail; ADS aligns through it.
@export var build_optic := false
@export_enum("red_dot", "holo", "sniper") var optic_type := "red_dot"
## User correction for the optic mount (set from the loadout editor when
## the auto-placement doesn't sit right on a model). y = height, z = depth.
@export var optic_offset := Vector3.ZERO
## Small per-weapon visual correction so the barrel/scope points at camera aim.
@export var aim_trim_deg := Vector3.ZERO
## Fitted attachments, built procedurally so they work on any gun model:
## suppressor, foregrip, laser, extended_mag.
@export var attachments := PackedStringArray()
## Set true if the model faces backwards after auto-fit.
@export var flip_forward := false

## Filled after _ready, all in rig space.
var muzzle_position := Vector3(0, 0, -0.4)
var scope_center := Vector3.ZERO
var sight_height := 0.06

var _mag_node: Node3D
var _mag_rest_transform: Transform3D
var _kick_offset := 0.0
var _reload_tween: Tween
var _dip_angle := 0.0
var _cant_angle := 0.0
var _rest_position := Vector3.ZERO
var _rest_rotation := Vector3.ZERO


func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation

	var model := _first_model_child()
	if model == null:
		return

	# Fitting must be idempotent: the editor may have saved a previous
	# fit into the scene (this script is @tool), so start from identity
	# and drop any optic built by an earlier run.
	model.transform = Transform3D.IDENTITY
	_clear_generated_nodes()

	var branches := _collect_part_branches(model)
	if body_part != "" and branches.has(body_part):
		_apply_whitelist(branches)

	var rifle: Node3D = branches.get(body_part, model)
	_fit_model(model, rifle)
	_apply_aim_trim(model)
	_mount_scope(branches.get(scope_part), rifle)
	if build_optic:
		_build_optic(rifle)
	_measure(rifle)
	_build_attachments(rifle)

	_mag_node = branches.get("Mag")
	if _mag_node != null:
		_mag_rest_transform = _mag_node.transform


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Fire kick pushes the gun back along +Z and eases out; reload / draw
	# dip and cant rotate it. Everything offsets from the rest transform.
	_kick_offset = maxf(_kick_offset - 0.5 * delta, 0.0)
	position = _rest_position + Vector3(0, 0, _kick_offset)
	rotation = _rest_rotation + Vector3(-_dip_angle + _kick_offset * 1.6, 0.0, _cant_angle)


## Re-captures the rest transform after the rig has been reparented or
## repositioned (e.g. moved into a character's hand).
func rebase_rest() -> void:
	_rest_position = position
	_rest_rotation = rotation


## ---------- procedural animations ----------

func add_fire_kick() -> void:
	_kick_offset = minf(_kick_offset + 0.028, 0.09)


## Reload: gun cants and dips, mag drops away fast, new mag slams in from
## below, charging handle jerk, gun settles with a small overshoot.
func play_reload(duration: float) -> void:
	cancel_reload()
	_reload_tween = create_tween()
	_reload_tween.tween_method(_set_reload_pose, 0.0, 1.0, duration * 0.14) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _mag_node != null:
		var dropped := _mag_rest_transform.translated_local(Vector3(0, -2.4, 0.8))
		dropped.basis = dropped.basis.rotated(Vector3(1, 0, 0), deg_to_rad(45.0))
		_reload_tween.parallel().tween_property(_mag_node, "transform", dropped, duration * 0.24) \
			.set_delay(duration * 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_reload_tween.tween_interval(duration * 0.16)
		_reload_tween.tween_callback(func() -> void:
			_mag_node.transform = _mag_rest_transform.translated_local(Vector3(0, -1.6, 0.3)))
		_reload_tween.tween_property(_mag_node, "transform", _mag_rest_transform, duration * 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_reload_tween.tween_interval(duration * 0.56)
	# Charging handle slap reads as a sharp backwards jolt.
	_reload_tween.tween_callback(func() -> void: _kick_offset = minf(_kick_offset + 0.035, 0.09))
	_reload_tween.tween_method(_set_reload_pose, 1.0, -0.12, duration * 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_reload_tween.tween_method(_set_reload_pose, -0.12, 0.0, duration * 0.08)


func cancel_reload() -> void:
	if _reload_tween != null and _reload_tween.is_valid():
		_reload_tween.kill()
	_dip_angle = 0.0
	_cant_angle = 0.0
	if _mag_node != null:
		_mag_node.transform = _mag_rest_transform


## Quick raise from below on spawn / weapon draw.
func play_draw(duration: float = 0.35) -> void:
	cancel_reload()
	var tween := create_tween()
	tween.tween_method(_set_reload_pose, 1.6, -0.1, duration * 0.75) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_reload_pose, -0.1, 0.0, duration * 0.25)


func _set_reload_pose(fraction: float) -> void:
	_dip_angle = fraction * deg_to_rad(22.0)
	_cant_angle = fraction * deg_to_rad(12.0)


## ---------- model preparation ----------

func _first_model_child() -> Node3D:
	for child in get_children():
		if (
			child is Node3D
			and child.name != "BuiltOptic"
			and not String(child.name).begins_with("Attachment")
		):
			return child
	return null


func _clear_generated_nodes() -> void:
	for child in get_children():
		var child_name := String(child.name)
		if child_name == "BuiltOptic" or child_name.begins_with("Attachment"):
			child.name = "Stale%s" % child_name
			child.queue_free()


## Finds named branches: descendants that directly hold mesh instances
## (in Sketchfab GLBs each part like "M4", "Mag", "Scope" is one such node).
func _collect_part_branches(model: Node3D) -> Dictionary:
	var branches: Dictionary = {}
	_collect_recursive(model, branches)
	return branches


func _collect_recursive(node: Node3D, branches: Dictionary) -> void:
	var has_direct_mesh := false
	for child in node.get_children():
		if child is MeshInstance3D:
			has_direct_mesh = true
			break
	if has_direct_mesh:
		branches[String(node.name)] = node
		return
	for child in node.get_children():
		if child is Node3D:
			_collect_recursive(child, branches)


func _apply_whitelist(branches: Dictionary) -> void:
	var visible_names := PackedStringArray([body_part, scope_part])
	visible_names.append_array(keep_parts)
	for branch_name: String in branches:
		branches[branch_name].visible = visible_names.has(branch_name)


## Rotates the barrel onto -Z and scales the rifle to target_length,
## then centers the rifle on the rig origin.
func _fit_model(model: Node3D, rifle: Node3D) -> void:
	var rifle_aabb := _rig_space_aabb(rifle)
	if rifle_aabb.size == Vector3.ZERO:
		return

	var longest_axis := rifle_aabb.get_longest_axis_index()
	if longest_axis == Vector3.AXIS_X:
		model.rotate_y(deg_to_rad(-90.0))
	elif longest_axis == Vector3.AXIS_Y:
		model.rotate_x(deg_to_rad(90.0))
	if flip_forward:
		model.rotate_y(deg_to_rad(180.0))

	var length := rifle_aabb.get_longest_axis_size()
	model.scale = Vector3.ONE * (target_length / length)

	var fitted := _rig_space_aabb(rifle)
	model.position -= fitted.get_center()


func _apply_aim_trim(model: Node3D) -> void:
	if aim_trim_deg == Vector3.ZERO:
		return
	model.rotation_degrees += aim_trim_deg


## Drops the cosmetic scope onto the rifle's top rail: centered on width,
## sunk slightly into the rail, above the rear half of the receiver.
func _mount_scope(scope: Node3D, rifle: Node3D) -> void:
	if scope == null or scope == rifle or not scope.visible:
		return
	var rifle_aabb := _rig_space_aabb(rifle)
	var scope_aabb := _rig_space_aabb(scope)
	if rifle_aabb.size == Vector3.ZERO or scope_aabb.size == Vector3.ZERO:
		return

	var target := Vector3(
		rifle_aabb.get_center().x - scope_aabb.get_center().x,
		(rifle_aabb.end.y - rifle_aabb.size.y * 0.14) - scope_aabb.position.y,
		(rifle_aabb.position.z + rifle_aabb.size.z * 0.62) - scope_aabb.get_center().z
	)
	scope.global_position += global_transform.basis * target


## Constructs a working red dot / holo / sniper optic. ADS aligns the
## camera through scope_center, so every optic type can be zeroed.
func _build_optic(rifle: Node3D) -> void:
	var rifle_aabb := _rig_space_aabb(rifle)
	if rifle_aabb.size == Vector3.ZERO:
		return
	var optic := Node3D.new()
	optic.name = "BuiltOptic"
	optic.position = _socket_position(
		rifle,
		"ScopeSocket",
		Vector3(
			rifle_aabb.get_center().x,
			rifle_aabb.end.y - rifle_aabb.size.y * 0.12,
			rifle_aabb.position.z + rifle_aabb.size.z * 0.70
		)
	) + optic_offset
	add_child(optic)

	var housing_material := StandardMaterial3D.new()
	housing_material.albedo_color = Color(0.08, 0.08, 0.09)
	housing_material.roughness = 0.45
	housing_material.metallic = 0.55

	match optic_type:
		"holo":
			_build_holo_optic(optic, housing_material)
		"sniper":
			_build_sniper_optic(optic, housing_material)
		_:
			_build_red_dot_optic(optic, housing_material)


func _build_red_dot_optic(optic: Node3D, housing_material: StandardMaterial3D) -> void:
	var center := Vector3(0, 0.042, 0)

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.03, 0.014, 0.055)
	base_mesh.material = housing_material
	base.mesh = base_mesh
	base.position = Vector3(0, 0.007, 0)
	optic.add_child(base)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.025
	ring_mesh.outer_radius = 0.0295
	ring_mesh.material = housing_material
	ring.mesh = ring_mesh
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = center
	optic.add_child(ring)

	var lens := MeshInstance3D.new()
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = 0.024
	lens_mesh.bottom_radius = 0.024
	lens_mesh.height = 0.002
	var lens_material := StandardMaterial3D.new()
	lens_material.albedo_color = Color(0.15, 0.25, 0.45, 0.11)
	lens_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens_material.roughness = 0.05
	lens_material.metallic = 0.3
	lens_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	lens_mesh.material = lens_material
	lens.mesh = lens_mesh
	lens.rotation_degrees = Vector3(90, 0, 0)
	lens.position = center
	optic.add_child(lens)

	var dot := MeshInstance3D.new()
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.0014
	dot_mesh.height = 0.0028
	var dot_material := StandardMaterial3D.new()
	dot_material.albedo_color = Color(1.0, 0.1, 0.05)
	dot_material.emission_enabled = true
	dot_material.emission = Color(1.0, 0.12, 0.05)
	dot_material.emission_energy_multiplier = 2.6
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mesh.material = dot_material
	dot.mesh = dot_mesh
	dot.position = center + Vector3(0, 0, 0.004)
	optic.add_child(dot)

	scope_center = optic.position + center


func _build_holo_optic(optic: Node3D, housing_material: StandardMaterial3D) -> void:
	var center := Vector3(0, 0.047, -0.002)

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.06, 0.016, 0.075)
	base_mesh.material = housing_material
	base.mesh = base_mesh
	base.position = Vector3(0, 0.008, 0)
	optic.add_child(base)

	var hood := MeshInstance3D.new()
	var hood_mesh := BoxMesh.new()
	hood_mesh.size = Vector3(0.06, 0.052, 0.018)
	hood_mesh.material = housing_material
	hood.mesh = hood_mesh
	hood.position = center
	optic.add_child(hood)

	var lens := MeshInstance3D.new()
	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(0.044, 0.032, 0.002)
	var lens_material := StandardMaterial3D.new()
	lens_material.albedo_color = Color(0.12, 0.36, 0.42, 0.16)
	lens_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens_material.roughness = 0.04
	lens_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	lens_mesh.material = lens_material
	lens.mesh = lens_mesh
	lens.position = center + Vector3(0, 0, -0.010)
	optic.add_child(lens)

	var reticle := MeshInstance3D.new()
	var reticle_mesh := TorusMesh.new()
	reticle_mesh.inner_radius = 0.004
	reticle_mesh.outer_radius = 0.0055
	var reticle_material := StandardMaterial3D.new()
	reticle_material.albedo_color = Color(1.0, 0.18, 0.06)
	reticle_material.emission_enabled = true
	reticle_material.emission = Color(1.0, 0.18, 0.06)
	reticle_material.emission_energy_multiplier = 2.4
	reticle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	reticle_mesh.material = reticle_material
	reticle.mesh = reticle_mesh
	reticle.rotation_degrees = Vector3(90, 0, 0)
	reticle.position = center + Vector3(0, 0, -0.012)
	optic.add_child(reticle)

	scope_center = optic.position + center


func _build_sniper_optic(optic: Node3D, housing_material: StandardMaterial3D) -> void:
	var center := Vector3(0, 0.055, 0)

	var mount := MeshInstance3D.new()
	var mount_mesh := BoxMesh.new()
	mount_mesh.size = Vector3(0.034, 0.02, 0.16)
	mount_mesh.material = housing_material
	mount.mesh = mount_mesh
	mount.position = Vector3(0, 0.017, 0)
	optic.add_child(mount)

	var tube := MeshInstance3D.new()
	var tube_mesh := CylinderMesh.new()
	tube_mesh.top_radius = 0.028
	tube_mesh.bottom_radius = 0.028
	tube_mesh.height = 0.23
	tube_mesh.material = housing_material
	tube.mesh = tube_mesh
	tube.rotation_degrees = Vector3(90, 0, 0)
	tube.position = center
	optic.add_child(tube)

	for z in [-0.084, 0.084]:
		var ring := MeshInstance3D.new()
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = 0.034
		ring_mesh.bottom_radius = 0.034
		ring_mesh.height = 0.026
		ring_mesh.material = housing_material
		ring.mesh = ring_mesh
		ring.rotation_degrees = Vector3(90, 0, 0)
		ring.position = center + Vector3(0, 0, z)
		optic.add_child(ring)

	var glass_material := StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.10, 0.18, 0.28, 0.22)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.roughness = 0.02
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	for z in [-0.116, 0.116]:
		var lens := MeshInstance3D.new()
		var lens_mesh := CylinderMesh.new()
		lens_mesh.top_radius = 0.027
		lens_mesh.bottom_radius = 0.027
		lens_mesh.height = 0.002
		lens_mesh.material = glass_material
		lens.mesh = lens_mesh
		lens.rotation_degrees = Vector3(90, 0, 0)
		lens.position = center + Vector3(0, 0, z)
		optic.add_child(lens)

	scope_center = optic.position + center


## Procedural attachment meshes, sized/placed from the rifle's bounds so
## the same names fit every gun in the arsenal.
func _build_attachments(rifle: Node3D) -> void:
	if attachments.is_empty():
		return
	var rifle_aabb := _rig_space_aabb(rifle)
	if rifle_aabb.size == Vector3.ZERO:
		return

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.07, 0.07, 0.08)
	metal.roughness = 0.5
	metal.metallic = 0.4

	var muzzle_socket := _socket_position(
		rifle,
		"MuzzleSocket",
		Vector3(0.0, rifle_aabb.position.y + rifle_aabb.size.y * 0.62, rifle_aabb.position.z)
	)
	var laser_socket := _socket_position(
		rifle,
		"LaserSocket",
		Vector3(
			rifle_aabb.end.x + 0.013,
			rifle_aabb.position.y + rifle_aabb.size.y * 0.62,
			rifle_aabb.position.z + rifle_aabb.size.z * 0.30
		)
	)
	var underbarrel_socket := _socket_position(
		rifle,
		"UnderbarrelSocket",
		Vector3(
			rifle_aabb.get_center().x,
			rifle_aabb.position.y - 0.03,
			rifle_aabb.position.z + rifle_aabb.size.z * 0.30
		)
	)

	if attachments.has("suppressor"):
		var suppressor := MeshInstance3D.new()
		suppressor.name = "AttachmentSuppressor"
		var tube := CylinderMesh.new()
		tube.top_radius = 0.021
		tube.bottom_radius = 0.021
		tube.height = 0.15
		tube.material = metal
		suppressor.mesh = tube
		suppressor.rotation_degrees = Vector3(90, 0, 0)
		suppressor.position = muzzle_socket + Vector3(0, 0, -0.075)
		add_child(suppressor)
		muzzle_position = muzzle_socket + Vector3(0, 0, -0.15)

	if attachments.has("foregrip"):
		var grip := MeshInstance3D.new()
		grip.name = "AttachmentForegrip"
		var grip_mesh := BoxMesh.new()
		grip_mesh.size = Vector3(0.026, 0.095, 0.034)
		grip_mesh.material = metal
		grip.mesh = grip_mesh
		grip.position = underbarrel_socket + Vector3(0, -0.04, 0)
		add_child(grip)

	if attachments.has("laser"):
		var laser_box := MeshInstance3D.new()
		laser_box.name = "AttachmentLaser"
		var box := BoxMesh.new()
		box.size = Vector3(0.022, 0.022, 0.05)
		box.material = metal
		laser_box.mesh = box
		laser_box.position = laser_socket
		add_child(laser_box)

		var lens := MeshInstance3D.new()
		lens.name = "AttachmentLaserLens"
		var lens_mesh := SphereMesh.new()
		lens_mesh.radius = 0.005
		lens_mesh.height = 0.01
		var lens_material := StandardMaterial3D.new()
		lens_material.albedo_color = Color(1, 0.1, 0.05)
		lens_material.emission_enabled = true
		lens_material.emission = Color(1, 0.1, 0.05)
		lens_material.emission_energy_multiplier = 2.0
		lens_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lens_mesh.material = lens_material
		lens.mesh = lens_mesh
		lens.position = laser_box.position + Vector3(0, 0, -0.028)
		add_child(lens)

		var beam := MeshInstance3D.new()
		beam.name = "AttachmentLaserBeam"
		var beam_mesh := CylinderMesh.new()
		beam_mesh.top_radius = 0.0014
		beam_mesh.bottom_radius = 0.0014
		beam_mesh.height = 0.42
		var beam_material := StandardMaterial3D.new()
		beam_material.albedo_color = Color(1.0, 0.05, 0.04, 0.24)
		beam_material.emission_enabled = true
		beam_material.emission = Color(1.0, 0.05, 0.04)
		beam_material.emission_energy_multiplier = 0.9
		beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mesh.material = beam_material
		beam.mesh = beam_mesh
		beam.rotation_degrees = Vector3(90, 0, 0)
		beam.position = lens.position + Vector3(0, 0, -0.21)
		add_child(beam)

	if attachments.has("extended_mag") and _first_model_child() != null:
		var branches := _collect_part_branches(_first_model_child())
		var mag: Node3D = branches.get("Mag")
		if mag != null and mag.visible:
			mag.scale = mag.scale * Vector3(1.0, 1.3, 1.0)
		else:
			var mag_box := MeshInstance3D.new()
			mag_box.name = "AttachmentExtendedMag"
			var mag_mesh := BoxMesh.new()
			mag_mesh.size = Vector3(0.042, 0.12, 0.036)
			mag_mesh.material = metal
			mag_box.mesh = mag_mesh
			mag_box.position = _socket_position(
				rifle,
				"MagazineSocket",
				Vector3(rifle_aabb.get_center().x, rifle_aabb.position.y - 0.05, rifle_aabb.get_center().z)
			)
			add_child(mag_box)


func _measure(rifle: Node3D) -> void:
	var rifle_aabb := _rig_space_aabb(rifle)
	muzzle_position = _socket_position(
		rifle,
		"MuzzleSocket",
		Vector3(0.0, rifle_aabb.position.y + rifle_aabb.size.y * 0.62, rifle_aabb.position.z)
	)
	sight_height = rifle_aabb.end.y

	if build_optic or scope_part == "":
		return
	var branches := _collect_part_branches(_first_model_child())
	var scope: Node3D = branches.get(scope_part)
	if scope != null and scope.visible:
		var scope_aabb := _rig_space_aabb(scope)
		scope_center = scope_aabb.get_center()
		scope_center.y = scope_aabb.position.y + scope_aabb.size.y * 0.74


func _socket_position(rifle: Node3D, socket_name: String, fallback: Vector3) -> Vector3:
	var socket := _find_socket(rifle, socket_name)
	if socket == null:
		return fallback
	var to_rig := global_transform.affine_inverse()
	return to_rig * socket.global_position


func _find_socket(root: Node3D, socket_name: String) -> Node3D:
	var names := _socket_aliases(socket_name)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D and names.has(String(node.name).to_lower()):
			return node
		for child in node.get_children():
			if child is Node3D:
				stack.push_back(child)
	return null


func _socket_aliases(socket_name: String) -> PackedStringArray:
	match socket_name:
		"MuzzleSocket":
			return PackedStringArray(["muzzlesocket", "muzzle_socket", "muzzle", "barrel", "barrelsocket"])
		"ScopeSocket":
			return PackedStringArray(["scopesocket", "scope_socket", "scope", "optic", "opticsocket", "rail"])
		"LaserSocket":
			return PackedStringArray(["lasersocket", "laser_socket", "laser", "lazer", "side_rail", "siderail"])
		"UnderbarrelSocket":
			return PackedStringArray(["underbarrelsocket", "underbarrel_socket", "underbarrel", "foregrip", "grip"])
		"MagazineSocket":
			return PackedStringArray(["magazinesocket", "magazine_socket", "mag", "magazine"])
		_:
			return PackedStringArray([socket_name.to_lower()])


## AABB of a branch in rig space, using live global transforms.
func _rig_space_aabb(branch: Node3D) -> AABB:
	var to_rig := global_transform.affine_inverse()
	var result := AABB()
	var has_result := false
	var stack: Array[Node] = [branch]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.visible:
			var mesh_aabb: AABB = (to_rig * node.global_transform) * node.get_aabb()
			result = result.merge(mesh_aabb) if has_result else mesh_aabb
			has_result = true
		for child in node.get_children():
			if child is Node3D and child.visible:
				stack.push_back(child)
	return result
