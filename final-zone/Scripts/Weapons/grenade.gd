class_name Grenade
extends RigidBody3D
## Thrown frag or flashbang. Arcs with physics, cooks for FUSE seconds, then
## explodes: frag deals radial damage with distance falloff, destroys nearby
## barrels, and spawns a particle burst; flashbang blinds anyone in line of
## sight. Fully procedural — builds its own mesh, no imported asset.

const FUSE := 2.2
const FRAG_RADIUS := 6.0
const FRAG_DAMAGE := 120.0
const FLASH_RADIUS := 14.0

@export var is_flash := false

var thrower: Node = null


func _ready() -> void:
	# Small procedural body (frag = dark green, flashbang = grey/steel).
	var mesh := MeshInstance3D.new()
	var body: Mesh
	if is_flash:
		var box := BoxMesh.new()
		box.size = Vector3(0.07, 0.11, 0.07)
		body = box
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.045
		cyl.bottom_radius = 0.05
		cyl.height = 0.11
		body = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.52, 0.55) if is_flash else Color(0.18, 0.22, 0.14)
	mat.metallic = 0.5
	mat.roughness = 0.5
	body.surface_set_material(0, mat)
	mesh.mesh = body
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.11   # bigger so it can't tunnel through thin floors
	col.shape = shape
	add_child(col)

	mass = 0.4
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.55   # bounces off walls/floor
	physics_material_override.friction = 0.4
	# Report contacts so we can play a bounce clink.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_bounce)

	_cook()


func _on_bounce(_body: Node) -> void:
	if linear_velocity.length() > 1.5:
		AudioManager.play_sfx_3d("grenade_bounce", global_position, -6.0, 0.1)


## Safety net against tunnelling: if it's dropping fast, ray-check the
## ground just below and bounce it off instead of passing through.
func _physics_process(_delta: float) -> void:
	if linear_velocity.y >= -2.0:
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3(0, -0.25, 0), 1)
	query.exclude = [self]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = hit.position.y + 0.12
		linear_velocity.y = -linear_velocity.y * 0.4
		AudioManager.play_sfx_3d("grenade_bounce", global_position, -8.0, 0.1)


func _cook() -> void:
	await get_tree().create_timer(FUSE).timeout
	if not is_inside_tree():
		return
	if is_flash:
		_explode_flash()
	else:
		_explode_frag()


func _explode_frag() -> void:
	var origin := global_position
	_spawn_burst(origin, Color(1.0, 0.6, 0.2), 42, 6.0)
	AudioManager.play_sfx_3d("grenade_explosion", origin, 4.0, 0.05)
	_shake_nearby(origin, FRAG_RADIUS * 1.5, 1.0)

	# Radial damage with falloff to player and bots.
	for group in ["player", "bot"]:
		for node in get_tree().get_nodes_in_group(group):
			if not node is Node3D:
				continue
			var dist: float = origin.distance_to((node as Node3D).global_position)
			if dist > FRAG_RADIUS:
				continue
			var falloff := 1.0 - dist / FRAG_RADIUS
			var dmg := FRAG_DAMAGE * falloff * falloff
			if node.has_method("take_hit"):
				node.take_hit(dmg, thrower)
			elif node.has_method("receive_damage"):
				node.receive_damage(dmg, thrower, false)

	# Destroy nearby barrels / destructibles.
	for node in get_tree().get_nodes_in_group("destructible"):
		if node is Node3D and origin.distance_to((node as Node3D).global_position) <= FRAG_RADIUS:
			_spawn_burst((node as Node3D).global_position, Color(0.6, 0.35, 0.15), 18, 3.5)
			node.queue_free()

	queue_free()


func _explode_flash() -> void:
	var origin := global_position
	_spawn_burst(origin, Color(1, 1, 1), 30, 4.0)
	AudioManager.play_sfx_3d("grenade_explosion", origin, -4.0)
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node3D and origin.distance_to((node as Node3D).global_position) <= FLASH_RADIUS:
			# Ear-ring flashbang sound plays 2D (in the player's head).
			AudioManager.play_sfx("flashbang", -3.0)
			if node.has_method("apply_flash"):
				node.apply_flash(2.5)
	queue_free()


## Shakes any nearby player's camera, scaled by distance.
func _shake_nearby(at: Vector3, radius: float, strength: float) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node3D and node.has_method("add_shake"):
			var dist: float = at.distance_to((node as Node3D).global_position)
			if dist < radius:
				node.add_shake(strength * (1.0 - dist / radius))


## Layered explosion: fireball + smoke + debris + shockwave ring + flash.
func _spawn_burst(at: Vector3, color: Color, amount: int, velocity: float) -> void:
	var scene := get_tree().current_scene
	# Fireball — fast, bright, short-lived.
	_emit(scene, at, amount, 0.45, velocity, velocity * 1.6,
		color, Vector3(0, 2, 0), 0.2, 0.5, false)
	# Smoke — slow, rising, gray, lingers.
	_emit(scene, at + Vector3(0, 0.2, 0), int(amount * 0.6), 1.6, velocity * 0.2, velocity * 0.5,
		Color(0.2, 0.2, 0.22), Vector3(0, 1.5, 0), 0.4, 0.9, true)
	# Debris — dark chunks thrown out with gravity.
	if not is_flash:
		_emit(scene, at, int(amount * 0.4), 1.0, velocity * 0.6, velocity * 1.2,
			Color(0.15, 0.13, 0.1), Vector3(0, -9, 0), 0.06, 0.14, false)

	# Bright flash light.
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 10.0
	light.omni_range = 12.0
	scene.add_child(light)
	light.global_position = at + Vector3(0, 0.5, 0)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.4)
	lt.tween_callback(light.queue_free)

	# Expanding shockwave ring.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.1
	torus.outer_radius = 0.25
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.6)
	ring_mat.emission_enabled = true
	ring_mat.emission = color
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = ring_mat
	ring.mesh = torus
	scene.add_child(ring)
	ring.global_position = at + Vector3(0, 0.15, 0)
	var rt := ring.create_tween()
	rt.parallel().tween_property(ring, "scale", Vector3.ONE * (velocity * 1.6), 0.35)
	rt.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.35)
	rt.tween_callback(ring.queue_free)


func _emit(parent: Node, at: Vector3, amount: int, life: float, vmin: float, vmax: float,
		color: Color, gravity: Vector3, smin: float, smax: float, fade: bool) -> void:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = gravity
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.color = color
	if fade:
		p.scale_amount_curve = _grow_curve()
	parent.add_child(p)
	p.global_position = at
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)


func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(1, 1.0))
	return c
