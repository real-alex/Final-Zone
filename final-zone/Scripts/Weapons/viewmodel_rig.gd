@tool
class_name ViewmodelRig
extends Node3D
## Procedural gun built from primitive boxes/cylinders — no imported model,
## so zero asset-import cost. Shape scales with `target_length` and varies
## by `category` (AR / SMG / DMR / sniper / shotgun / pistol). Builds a
## working optic on the rail and procedural attachments, and owns the
## viewmodel animations (fire kick, reload, draw). Barrel points -Z.

## Stock-to-muzzle length in meters.
@export var target_length := 0.85
## 0 AR, 1 SMG, 2 DMR, 3 SNIPER, 4 SHOTGUN, 5 PISTOL — sets the silhouette.
@export var category := 0
## Builds a functional sight on the rail; ADS aligns through it.
@export var build_optic := true
## red_dot / holo / sniper.
@export var optic_type := "red_dot"
## User optic mount correction (y = height, z = depth).
@export var optic_offset := Vector3.ZERO
## User barrel-angle correction so the gun points where you aim.
@export var aim_trim_deg := Vector3.ZERO
## Fitted attachments: suppressor, foregrip, laser, extended_mag.
@export var attachments := PackedStringArray()

## Legacy fields kept so old scene/tres references don't error.
@export var body_part := ""
@export var keep_parts := PackedStringArray()
@export var scope_part := ""
@export var flip_forward := false

## Filled after build, all in rig space.
var muzzle_position := Vector3(0, 0, -0.4)
var scope_center := Vector3.ZERO
var sight_height := 0.06

var _gun_root: Node3D
var _mag_node: Node3D
var _mag_rest_transform: Transform3D
var _kick_offset := 0.0
var _dip_angle := 0.0
var _cant_angle := 0.0
var _rest_position := Vector3.ZERO
var _rest_rotation := Vector3.ZERO
var _reload_tween: Tween


func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation
	_build_gun()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_kick_offset = maxf(_kick_offset - 0.5 * delta, 0.0)
	position = _rest_position + Vector3(0, 0, _kick_offset)
	rotation = _rest_rotation + Vector3(-_dip_angle + _kick_offset * 1.6, 0.0, _cant_angle)


## ---------- construction ----------

func _build_gun() -> void:
	# Clear any prior build (this script is @tool / can rebuild).
	if _gun_root != null and is_instance_valid(_gun_root):
		_gun_root.queue_free()
	_gun_root = Node3D.new()
	_gun_root.rotation_degrees = aim_trim_deg
	add_child(_gun_root)

	if category == 5:
		_build_pistol()
		return

	# --- Rifle family (M4-style), scaled by length ---
	var metal := _mat(Color(0.07, 0.07, 0.08), 0.4, 0.5)   # gunmetal
	var poly := _mat(Color(0.11, 0.11, 0.12), 0.75, 0.05)  # polymer furniture
	var rail := _mat(Color(0.05, 0.05, 0.06), 0.5, 0.4)

	var length := target_length
	var body_len := length * 0.30
	var barrel_len := length * 0.40
	var handguard_len := barrel_len * 0.62
	var body_z := 0.0
	var handguard_z := -body_len * 0.5 - handguard_len * 0.5
	var muzzle_z := -body_len * 0.5 - barrel_len

	# Lower + upper receiver (the bulk).
	_add_box(Vector3(0.05, 0.085, body_len), Vector3(0, 0, body_z), metal)
	# Flat-top Picatinny rail on top (segmented look via a low box + ridges).
	_add_box(Vector3(0.026, 0.014, body_len * 0.9), Vector3(0, 0.052, body_z), rail)
	for i in 5:
		_add_box(Vector3(0.03, 0.006, 0.008),
			Vector3(0, 0.060, body_z - body_len * 0.35 + i * body_len * 0.18), rail)
	# Ejection port bump + forward assist.
	_add_box(Vector3(0.055, 0.03, 0.06), Vector3(0.005, 0.02, body_z - 0.02), metal)
	# Charging handle at the rear.
	_add_box(Vector3(0.06, 0.02, 0.03), Vector3(0, 0.045, body_z + body_len * 0.5 + 0.01), metal)

	# Ribbed handguard around the barrel.
	_add_box(Vector3(0.05, 0.055, handguard_len), Vector3(0, -0.006, handguard_z), poly)
	for i in 4:
		_add_box(Vector3(0.056, 0.01, 0.01),
			Vector3(0, -0.006, handguard_z - handguard_len * 0.35 + i * handguard_len * 0.22), rail)
	# Barrel + front sight post + flash hider.
	_add_cylinder(0.011, barrel_len * 0.5, Vector3(0, 0.006, muzzle_z + barrel_len * 0.28), metal)
	_add_box(Vector3(0.02, 0.06, 0.03), Vector3(0, 0.03, muzzle_z + 0.06), metal)      # front sight
	_add_cylinder(0.017, 0.05, Vector3(0, 0.006, muzzle_z + 0.01), metal)              # flash hider

	# Pistol grip (angled back).
	var grip := _add_box(Vector3(0.042, 0.13, 0.055), Vector3(0, -0.10, body_z + body_len * 0.30), poly)
	grip.rotation_degrees = Vector3(18, 0, 0)
	# Trigger guard.
	_add_box(Vector3(0.02, 0.035, 0.055), Vector3(0, -0.06, body_z + body_len * 0.12), metal)

	# Curved STANAG magazine (two angled segments), animatable.
	_mag_node = Node3D.new()
	_gun_root.add_child(_mag_node)
	var mag_top := _add_box(Vector3(0.032, 0.10, 0.055), Vector3(0, -0.085, body_z), metal, _mag_node)
	mag_top.rotation_degrees = Vector3(-10, 0, 0)
	var mag_bot := _add_box(Vector3(0.03, 0.09, 0.05), Vector3(0, -0.17, body_z + 0.03), metal, _mag_node)
	mag_bot.rotation_degrees = Vector3(-22, 0, 0)
	_mag_rest_transform = _mag_node.transform

	# Buffer tube + collapsible stock.
	var tube_z := body_z + body_len * 0.5
	_add_cylinder(0.018, length * 0.20, Vector3(0, 0.01, tube_z + length * 0.10), metal)
	_add_box(Vector3(0.055, 0.09, 0.08), Vector3(0, 0.0, tube_z + length * 0.18), poly)   # stock
	_add_box(Vector3(0.05, 0.11, 0.03), Vector3(0, -0.01, tube_z + length * 0.22), poly)  # butt pad

	# DMR/sniper: longer barrel already via length; add a bolt handle.
	if category == 3:
		var bolt := _add_box(Vector3(0.10, 0.018, 0.018), Vector3(0.055, 0.02, body_z - 0.03), metal)
		bolt.rotation_degrees = Vector3(0, 0, -22)

	muzzle_position = Vector3(0, 0.006, muzzle_z)
	sight_height = 0.06
	scope_center = Vector3(0, 0.075, body_z - body_len * 0.1)

	if build_optic:
		_build_optic()
	_build_attachments()


func _build_pistol() -> void:
	var metal := _mat(Color(0.07, 0.07, 0.08), 0.4, 0.5)
	var poly := _mat(Color(0.11, 0.11, 0.12), 0.75, 0.05)
	var slide_len := target_length * 0.62
	# Slide + frame.
	_add_box(Vector3(0.035, 0.05, slide_len), Vector3(0, 0.01, -slide_len * 0.2), metal)
	_add_box(Vector3(0.03, 0.03, slide_len * 0.7), Vector3(0, -0.03, -slide_len * 0.1), metal)
	# Grip (angled).
	var grip := _add_box(Vector3(0.036, 0.13, 0.05), Vector3(0, -0.10, slide_len * 0.18), poly)
	grip.rotation_degrees = Vector3(14, 0, 0)
	# Trigger guard.
	_add_box(Vector3(0.018, 0.03, 0.045), Vector3(0, -0.05, slide_len * 0.04), metal)
	# Magazine in the grip (animatable).
	_mag_node = Node3D.new()
	_gun_root.add_child(_mag_node)
	_add_box(Vector3(0.03, 0.10, 0.04), Vector3(0, -0.11, slide_len * 0.18), metal, _mag_node)
	_mag_rest_transform = _mag_node.transform
	# Iron sights.
	_add_box(Vector3(0.02, 0.012, 0.012), Vector3(0, 0.04, slide_len * 0.28), metal)
	_add_box(Vector3(0.012, 0.014, 0.012), Vector3(0, 0.04, -slide_len * 0.62), metal)

	muzzle_position = Vector3(0, 0.01, -slide_len * 0.72)
	sight_height = 0.045
	scope_center = Vector3(0, 0.05, -slide_len * 0.1)
	if build_optic:
		_build_optic()
	_build_attachments()


func _build_optic() -> void:
	var mount_top := 0.05
	var optic := Node3D.new()
	optic.name = "BuiltOptic"
	optic.position = Vector3(0, mount_top, -sight_height_z()) + optic_offset
	_gun_root.add_child(optic)

	var housing := _mat(Color(0.06, 0.06, 0.07), 0.4, 0.6)
	# Base riser.
	_add_box(Vector3(0.03, 0.02, 0.05), Vector3(0, 0.008, 0), housing, optic)

	var ring_r := 0.018
	var tube_len := 0.05
	if optic_type == "sniper":
		ring_r = 0.026
		tube_len = 0.12
	elif optic_type == "holo":
		ring_r = 0.022
		tube_len = 0.035

	if optic_type == "sniper":
		# Long scope tube.
		var tube := _add_cylinder(ring_r, tube_len, Vector3(0, 0.03, 0), housing, optic)
		tube.rotation_degrees = Vector3(90, 0, 0)
	else:
		# Ring housing for red-dot / holo.
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = ring_r * 0.85
		torus.outer_radius = ring_r
		torus.material = housing
		ring.mesh = torus
		ring.rotation_degrees = Vector3(90, 0, 0)
		ring.position = Vector3(0, 0.03, 0)
		optic.add_child(ring)

	# Glass lens.
	var lens := MeshInstance3D.new()
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = ring_r * 0.82
	lens_mesh.bottom_radius = ring_r * 0.82
	lens_mesh.height = 0.002
	# Tinted glass: see-through, glossy, faint blue-green coating sheen.
	var lens_mat := _mat(Color(0.18, 0.32, 0.42, 0.16), 0.02, 0.6)
	lens_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lens_mat.rim_enabled = true
	lens_mat.rim = 0.6
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(0.1, 0.2, 0.35)
	lens_mat.emission_energy_multiplier = 0.25
	lens_mesh.material = lens_mat
	lens.mesh = lens_mesh
	lens.rotation_degrees = Vector3(90, 0, 0)
	lens.position = Vector3(0, 0.03, tube_len * 0.5 - 0.001 if optic_type == "sniper" else 0.0)
	optic.add_child(lens)

	# Reticle dot (small; sniper uses the screen overlay so keep dot tiny).
	var dot := MeshInstance3D.new()
	var dot_mesh := SphereMesh.new()
	var dot_r := 0.0011 if optic_type == "sniper" else 0.0016
	dot_mesh.radius = dot_r
	dot_mesh.height = dot_r * 2.0
	var dot_mat := _mat(Color(1, 0.1, 0.05), 0.5, 0.0)
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(1, 0.12, 0.05)
	dot_mat.emission_energy_multiplier = 2.6
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mesh.material = dot_mat
	dot.mesh = dot_mesh
	dot.position = Vector3(0, 0.03, 0.004)
	optic.add_child(dot)

	scope_center = optic.position + Vector3(0, 0.03, 0)


func sight_height_z() -> float:
	return -scope_center.z


func _build_attachments() -> void:
	if attachments.is_empty():
		return
	var metal := _mat(Color(0.07, 0.07, 0.08), 0.5, 0.4)
	if attachments.has("suppressor"):
		var supp := _add_cylinder(0.02, 0.14, muzzle_position + Vector3(0, 0, 0.05), metal)
		supp.rotation_degrees = Vector3(90, 0, 0)
		muzzle_position.z -= 0.12
	if attachments.has("foregrip"):
		var grip := _add_box(Vector3(0.026, 0.09, 0.03), Vector3(0, -0.075, muzzle_position.z * 0.55), metal)
		grip.rotation_degrees = Vector3(4, 0, 0)
	if attachments.has("laser"):
		_add_box(Vector3(0.02, 0.02, 0.045), Vector3(0.03, 0.02, -0.05), metal)
		var laser_mat := _mat(Color(1, 0.1, 0.05), 0.4, 0.0)
		laser_mat.emission_enabled = true
		laser_mat.emission = Color(1, 0.1, 0.05)
		laser_mat.emission_energy_multiplier = 5.0
		laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		laser_mat.albedo_color = Color(1, 0.1, 0.05, 0.5)
		# Emitter lens.
		var lens := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.006
		s.height = 0.012
		s.material = laser_mat
		lens.mesh = s
		lens.position = Vector3(0.03, 0.02, -0.075)
		_gun_root.add_child(lens)
		# Long red beam projecting downrange (CoD-style).
		var beam := MeshInstance3D.new()
		var beam_mesh := CylinderMesh.new()
		beam_mesh.top_radius = 0.0016
		beam_mesh.bottom_radius = 0.0016
		beam_mesh.height = 30.0
		beam_mesh.material = laser_mat
		beam.mesh = beam_mesh
		beam.rotation_degrees = Vector3(90, 0, 0)
		beam.position = Vector3(0.03, 0.02, -0.075 - 15.0)
		_gun_root.add_child(beam)
	if attachments.has("extended_mag") and _mag_node != null:
		for child in _mag_node.get_children():
			if child is MeshInstance3D:
				child.scale = Vector3(1, 1.4, 1)


func _add_box(size: Vector3, pos: Vector3, material: StandardMaterial3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mi.mesh = box
	mi.position = pos
	(parent if parent != null else _gun_root).add_child(mi)
	return mi


func _add_cylinder(radius: float, height: float, pos: Vector3, material: StandardMaterial3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.material = material
	mi.mesh = cyl
	mi.position = pos
	mi.rotation_degrees = Vector3(90, 0, 0)
	(parent if parent != null else _gun_root).add_child(mi)
	return mi


func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## ---------- animations (unchanged API) ----------

func rebase_rest() -> void:
	_rest_position = position
	_rest_rotation = rotation


func add_fire_kick() -> void:
	_kick_offset = minf(_kick_offset + 0.028, 0.09)


func play_reload(duration: float) -> void:
	cancel_reload()
	if _mag_node == null:
		return
	_reload_tween = create_tween()
	var dropped := _mag_rest_transform.translated_local(Vector3(0, -0.25, 0.05))
	_reload_tween.tween_method(_set_dip, 0.0, 1.0, duration * 0.16)
	_reload_tween.parallel().tween_property(_mag_node, "transform", dropped, duration * 0.3) \
		.set_delay(duration * 0.06)
	_reload_tween.tween_interval(duration * 0.2)
	_reload_tween.tween_property(_mag_node, "transform", _mag_rest_transform, duration * 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reload_tween.tween_callback(func() -> void: _kick_offset = minf(_kick_offset + 0.03, 0.09))
	_reload_tween.tween_method(_set_dip, 1.0, 0.0, duration * 0.14)


func cancel_reload() -> void:
	if _reload_tween != null and _reload_tween.is_valid():
		_reload_tween.kill()
	_dip_angle = 0.0
	_cant_angle = 0.0
	if _mag_node != null:
		_mag_node.transform = _mag_rest_transform


func play_draw(duration: float = 0.35) -> void:
	cancel_reload()
	var tween := create_tween()
	tween.tween_method(_set_dip, 1.6, 0.0, duration)


func _set_dip(fraction: float) -> void:
	_dip_angle = fraction * deg_to_rad(20.0)
	_cant_angle = fraction * deg_to_rad(10.0)
