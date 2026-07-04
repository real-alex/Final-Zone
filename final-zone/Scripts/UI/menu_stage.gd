extends Node3D
## Builds the lobby stage environment: a CoD Shipment-style container
## yard around the operator, with Final Zone branding on the containers.

const CONTAINER_SIZE := Vector3(2.44, 2.6, 6.06)
const ACCENT_GOLD := Color(1, 0.706, 0)

## [position, y_rotation_deg, color]
const CONTAINERS := [
	[Vector3(0.3, 1.3, -3.5), 90.0, Color(0.42, 0.16, 0.12)],    # oxide red, behind operator
	[Vector3(0.6, 3.92, -3.7), 87.0, Color(0.29, 0.32, 0.19)],   # olive, stacked on top
	[Vector3(-3.9, 1.3, -2.2), 24.0, Color(0.13, 0.21, 0.30)],   # navy, left
	[Vector3(4.1, 1.3, -2.6), -16.0, Color(0.54, 0.29, 0.11)],   # rust orange, right
	[Vector3(4.5, 3.92, -3.0), -12.0, Color(0.16, 0.28, 0.22)],  # dark green, right stack
	[Vector3(-2.8, 1.3, -6.8), 78.0, Color(0.25, 0.25, 0.27)],   # gray, far back
]


func _ready() -> void:
	_build_ground()
	for entry in CONTAINERS:
		_build_container(entry[0], entry[1], entry[2])
	_build_branding()


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(26, 0.3, 20)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.085, 0.088, 0.095)
	material.roughness = 0.85
	mesh.material = material
	ground.mesh = mesh
	ground.position = Vector3(0, -0.15, -2)
	add_child(ground)


## A shipping container: colored body, darker roof trim, dark door seam.
func _build_container(center: Vector3, yaw_deg: float, color: Color) -> void:
	var container := Node3D.new()
	container.position = center
	container.rotation_degrees = Vector3(0, yaw_deg, 0)
	add_child(container)

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = CONTAINER_SIZE
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = color
	body_material.roughness = 0.75
	body_material.metallic = 0.15
	body_mesh.material = body_material
	body.mesh = body_mesh
	container.add_child(body)

	var trim := MeshInstance3D.new()
	var trim_mesh := BoxMesh.new()
	trim_mesh.size = Vector3(CONTAINER_SIZE.x + 0.04, 0.1, CONTAINER_SIZE.z + 0.04)
	var trim_material := StandardMaterial3D.new()
	trim_material.albedo_color = color.darkened(0.45)
	trim_material.roughness = 0.6
	trim_mesh.material = trim_material
	trim.mesh = trim_mesh
	trim.position = Vector3(0, CONTAINER_SIZE.y * 0.5 - 0.05, 0)
	container.add_child(trim)

	var seam := MeshInstance3D.new()
	var seam_mesh := BoxMesh.new()
	seam_mesh.size = Vector3(0.06, CONTAINER_SIZE.y - 0.3, 0.06)
	seam_mesh.material = trim_material
	seam.mesh = seam_mesh
	seam.position = Vector3(0, 0, CONTAINER_SIZE.z * 0.5 + 0.01)
	container.add_child(seam)


func _build_branding() -> void:
	# Emblem and wordmark on the red container wall behind the operator.
	var emblem := Sprite3D.new()
	emblem.texture = load("res://Assets/UI/fz_emblem.svg")
	emblem.modulate = Color(ACCENT_GOLD, 0.55)
	emblem.pixel_size = 0.0022
	emblem.position = Vector3(-1.15, 1.55, -2.26)
	add_child(emblem)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	font.font_weight = 700

	var wordmark := Label3D.new()
	wordmark.text = "FINAL ZONE"
	wordmark.font = font
	wordmark.font_size = 150
	wordmark.pixel_size = 0.0035
	wordmark.modulate = Color(ACCENT_GOLD, 0.6)
	wordmark.position = Vector3(0.95, 1.62, -2.26)
	add_child(wordmark)

	var studio := Label3D.new()
	studio.text = "ALEXIONSTUDIOS"
	studio.font = font
	studio.font_size = 52
	studio.pixel_size = 0.0035
	studio.modulate = Color(0.75, 0.75, 0.75, 0.5)
	studio.position = Vector3(0.95, 1.18, -2.26)
	add_child(studio)
