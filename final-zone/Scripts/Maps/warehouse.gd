extends Node3D
## Greybox warehouse killhouse (~40x30 m). Geometry is generated from the
## layout tables below so the map is easy to tweak, then the navmesh is
## baked at runtime for the bot.

signal navmesh_ready

const ACCENT_GOLD := Color(1.0, 0.706, 0.0)

@onready var nav_region: NavigationRegion3D = $NavRegion
@onready var geometry_root: Node3D = $NavRegion/Geometry

var _materials: Dictionary = {}


func _ready() -> void:
	_create_materials()
	_build_geometry()
	_build_banners()
	nav_region.bake_finished.connect(func() -> void: navmesh_ready.emit())
	nav_region.bake_navigation_mesh()


func _create_materials() -> void:
	_materials = {
		"floor": _flat_material(Color(0.36, 0.36, 0.37), 0.95),
		"wall": _flat_material(Color(0.46, 0.47, 0.5), 0.9),
		"roof": _flat_material(Color(0.3, 0.31, 0.33), 0.9),
		"crate": _flat_material(Color(0.32, 0.36, 0.26), 0.85),
		"crate_dark": _flat_material(Color(0.26, 0.29, 0.21), 0.85),
		"metal": _flat_material(Color(0.22, 0.23, 0.25), 0.6),
		"barrel": _flat_material(Color(0.45, 0.27, 0.16), 0.7),
		"banner": _flat_material(Color(0.055, 0.055, 0.06), 0.8),
	}


func _flat_material(albedo: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	return material


func _build_geometry() -> void:
	# [size, center, material, optional rotation_degrees]
	var boxes := [
		# Floor and perimeter (walls sit just outside the 40x30 play area).
		[Vector3(41, 0.4, 31), Vector3(0, -0.2, 0), "floor"],
		[Vector3(41, 6, 0.4), Vector3(0, 3, -15.2), "wall"],
		[Vector3(41, 6, 0.4), Vector3(0, 3, 15.2), "wall"],
		[Vector3(0.4, 6, 31), Vector3(20.2, 3, 0), "wall"],
		[Vector3(0.4, 6, 31), Vector3(-20.2, 3, 0), "wall"],
		# Roof strips with two skylight gaps.
		[Vector3(41, 0.4, 10), Vector3(0, 6.2, -10), "roof"],
		[Vector3(16, 0.4, 10), Vector3(-12.5, 6.2, 0), "roof"],
		[Vector3(16, 0.4, 10), Vector3(12.5, 6.2, 0), "roof"],
		[Vector3(10, 0.4, 10), Vector3(-15.5, 6.2, 10), "roof"],
		[Vector3(22, 0.4, 10), Vector3(9.5, 6.2, 10), "roof"],
		# Mezzanine catwalk along the north wall + two ramps.
		[Vector3(16, 0.3, 4), Vector3(0, 2.85, -12.8), "metal"],
		[Vector3(6, 0.3, 2), Vector3(10.5, 1.4, -12.8), "metal", Vector3(0, 0, -27)],
		[Vector3(6, 0.3, 2), Vector3(-10.5, 1.4, -12.8), "metal", Vector3(0, 0, 27)],
		[Vector3(16, 0.9, 0.06), Vector3(0, 3.45, -10.85), "metal"],
		# Central crate cluster.
		[Vector3(2.4, 1.2, 1.2), Vector3(0, 0.6, 0), "crate"],
		[Vector3(1.2, 1.2, 1.2), Vector3(0.6, 1.8, 0), "crate_dark"],
		[Vector3(1.2, 1.2, 1.2), Vector3(3, 0.6, 2), "crate"],
		[Vector3(1.6, 1.6, 1.6), Vector3(-3, 0.8, -2), "crate_dark"],
		[Vector3(1.2, 1.2, 1.2), Vector3(-1, 0.6, 4), "crate"],
		[Vector3(1.2, 1.2, 1.2), Vector3(-1, 1.8, 4), "crate_dark"],
		[Vector3(1.2, 1.2, 1.2), Vector3(-4.2, 0.6, 3), "crate"],
		# Low cover walls.
		[Vector3(2.4, 1.1, 0.3), Vector3(7, 0.55, -4), "metal"],
		[Vector3(2.4, 1.1, 0.3), Vector3(-7, 0.55, 4), "metal"],
		[Vector3(0.3, 1.1, 2.4), Vector3(-9, 0.55, -6), "metal"],
		[Vector3(3, 0.9, 0.4), Vector3(0, 0.45, 9), "crate_dark"],
		# South-east room (x 10..18, z 7..13) with two door gaps.
		[Vector3(6, 3, 0.3), Vector3(15, 1.5, 7), "wall"],
		[Vector3(0.3, 3, 1), Vector3(10, 1.5, 7.5), "wall"],
		[Vector3(0.3, 3, 3.5), Vector3(10, 1.5, 11.25), "wall"],
		[Vector3(8.6, 0.3, 6.6), Vector3(14, 3.15, 10), "roof"],
		# South-west room (mirror).
		[Vector3(6, 3, 0.3), Vector3(-15, 1.5, 7), "wall"],
		[Vector3(0.3, 3, 1), Vector3(-10, 1.5, 7.5), "wall"],
		[Vector3(0.3, 3, 3.5), Vector3(-10, 1.5, 11.25), "wall"],
		[Vector3(8.6, 0.3, 6.6), Vector3(-14, 3.15, 10), "roof"],
	]

	# Wall support columns for warehouse feel.
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		boxes.append([Vector3(0.3, 6, 0.3), Vector3(x, 3, -14.8), "metal"])
		boxes.append([Vector3(0.3, 6, 0.3), Vector3(x, 3, 14.8), "metal"])

	for entry in boxes:
		var rotation_deg: Vector3 = entry[3] if entry.size() > 3 else Vector3.ZERO
		_add_box(entry[0], entry[1], entry[2], rotation_deg)

	# Barrels.
	for barrel_pos in [
		Vector3(5, 0.55, 8), Vector3(5.8, 0.55, 8.5), Vector3(-5, 0.55, -8),
		Vector3(14, 0.55, -6), Vector3(-14, 0.55, -6), Vector3(17, 0.55, 2),
	]:
		_add_cylinder(0.4, 1.1, barrel_pos, "barrel")


func _add_box(size: Vector3, center: Vector3, material_key: String, rotation_deg := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	body.rotation_degrees = rotation_deg
	# Crates are breakable cover — grenades blow them apart.
	if material_key == "crate" or material_key == "crate_dark":
		body.add_to_group("destructible")

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = _materials[material_key]
	mesh_instance.mesh = box_mesh
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	geometry_root.add_child(body)


func _add_cylinder(radius: float, height: float, center: Vector3, material_key: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	# Barrels are destructible — grenades can blow them up.
	if material_key == "barrel":
		body.add_to_group("destructible")

	var mesh_instance := MeshInstance3D.new()
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = radius
	cylinder_mesh.bottom_radius = radius
	cylinder_mesh.height = height
	cylinder_mesh.material = _materials[material_key]
	mesh_instance.mesh = cylinder_mesh
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)

	geometry_root.add_child(body)


func _build_banners() -> void:
	_add_banner(Vector3(0, 4.3, -14.95), 0.0, "FINAL ZONE", "TACTICAL. TEAMWORK. VICTORY.", true)
	_add_banner(Vector3(0, 4.3, 14.95), 180.0, "ALEXIONSTUDIOS", "", false)
	_add_banner(Vector3(19.95, 3.6, 0), 90.0, "ALEXIONSTUDIOS", "", false)
	_add_banner(Vector3(-19.95, 3.6, 0), -90.0, "FINAL ZONE", "", true)


## A dark cloth quad with emblem and Label3D text, hung on a wall.
## yaw_deg turns the banner to face into the map.
func _add_banner(center: Vector3, yaw_deg: float, title: String, subtitle: String, with_emblem: bool) -> void:
	var banner := Node3D.new()
	banner.position = center
	banner.rotation_degrees = Vector3(0, yaw_deg, 0)
	add_child(banner)

	var backdrop := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(6.4, 2.6)
	quad.material = _materials["banner"]
	backdrop.mesh = quad
	backdrop.position = Vector3(0, 0, 0.02)
	banner.add_child(backdrop)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	font.font_weight = 700

	var title_label := Label3D.new()
	title_label.text = title
	title_label.font = font
	title_label.font_size = 220
	title_label.pixel_size = 0.004
	title_label.modulate = ACCENT_GOLD
	title_label.outline_size = 0
	title_label.position = Vector3(0.55 if with_emblem else 0.0, 0.25 if subtitle != "" else 0.0, 0.05)
	banner.add_child(title_label)

	if subtitle != "":
		var subtitle_label := Label3D.new()
		subtitle_label.text = subtitle
		subtitle_label.font = font
		subtitle_label.font_size = 80
		subtitle_label.pixel_size = 0.004
		subtitle_label.modulate = Color(0.85, 0.85, 0.85)
		subtitle_label.position = Vector3(0.55 if with_emblem else 0.0, -0.45, 0.05)
		banner.add_child(subtitle_label)

	if with_emblem:
		var emblem := Sprite3D.new()
		emblem.texture = load("res://Assets/UI/fz_emblem.svg")
		emblem.pixel_size = 0.0014
		emblem.position = Vector3(-2.2, 0, 0.05)
		banner.add_child(emblem)


func get_player_spawns() -> Array[Marker3D]:
	var spawns: Array[Marker3D] = []
	for child in $SpawnPoints/PlayerSpawns.get_children():
		spawns.append(child)
	return spawns


func get_bot_spawns() -> Array[Marker3D]:
	var spawns: Array[Marker3D] = []
	for child in $SpawnPoints/BotSpawns.get_children():
		spawns.append(child)
	return spawns


func get_patrol_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for child in $PatrolPoints.get_children():
		points.append(child.global_position)
	return points
