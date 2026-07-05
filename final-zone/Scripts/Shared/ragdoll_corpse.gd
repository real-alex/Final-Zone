class_name RagdollCorpse
extends RigidBody3D
## A throwaway physics corpse spawned when a character dies, so death reads
## as a real ragdoll flop rather than a canned animation. Builds a simple
## soldier-shaped body from boxes, takes the killing hit as an impulse,
## tumbles under physics, then fades out and frees itself. Independent of
## the character's respawn logic.

const LIFETIME := 5.0

var uniform_color := Color(0.30, 0.33, 0.22)


func setup(at: Transform3D, hit_dir: Vector3, tint: Color) -> void:
	global_transform = at
	uniform_color = tint
	linear_velocity = hit_dir.normalized() * randf_range(3.0, 5.0) + Vector3.UP * 2.5
	angular_velocity = Vector3(
		randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))


func _ready() -> void:
	mass = 3.0
	collision_layer = 0
	collision_mask = 1
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.15
	physics_material_override.friction = 0.9

	var skin := _mat(Color(0.62, 0.47, 0.38))
	var uniform := _mat(uniform_color)
	var gear := _mat(Color(0.09, 0.09, 0.10))
	var helmet := _mat(Color(0.34, 0.30, 0.21))

	# One capsule collider around the whole body.
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.5
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# Visual boxes roughly matching the standing soldier.
	_box(Vector3(0.42, 0.5, 0.26), Vector3(0, 1.15, 0), uniform)      # torso
	_box(Vector3(0.44, 0.4, 0.30), Vector3(0, 1.15, 0.01), gear)      # carrier
	_box(Vector3(0.19, 0.21, 0.19), Vector3(0, 1.5, 0), skin)         # head
	_box(Vector3(0.23, 0.13, 0.23), Vector3(0, 1.62, 0), helmet)      # helmet
	_box(Vector3(0.12, 0.5, 0.12), Vector3(-0.29, 1.1, 0), uniform)   # left arm
	_box(Vector3(0.12, 0.5, 0.12), Vector3(0.29, 1.1, 0), uniform)    # right arm
	_box(Vector3(0.16, 0.8, 0.17), Vector3(-0.1, 0.42, 0), uniform)   # left leg
	_box(Vector3(0.16, 0.8, 0.17), Vector3(0.1, 0.42, 0), uniform)    # right leg

	# Fade out then remove.
	await get_tree().create_timer(LIFETIME).timeout
	if not is_inside_tree():
		return
	var tween := create_tween()
	for mesh in _meshes:
		var mat: StandardMaterial3D = mesh.mesh.material
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 1.0)
	tween.tween_callback(queue_free)


var _meshes: Array[MeshInstance3D] = []


func _box(size: Vector3, pos: Vector3, material: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mi.mesh = box
	mi.position = pos
	add_child(mi)
	_meshes.append(mi)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m
