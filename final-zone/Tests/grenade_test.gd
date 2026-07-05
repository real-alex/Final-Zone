extends Node3D
var _min_y := 99.0
var _g: Node3D
func _ready() -> void:
	# floor at y=0
	var floor := StaticBody3D.new(); floor.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(20,0.4,20)
	cs.shape = bs; floor.add_child(cs); floor.position = Vector3(0,-0.2,0); add_child(floor)
	var g: Node3D = load("res://Scenes/Weapons/grenade.tscn").instantiate()
	add_child(g); g.global_position = Vector3(0, 3, 0); g.linear_velocity = Vector3(4, 2, 0)
	_g = g
func _physics_process(_d: float) -> void:
	if is_instance_valid(_g):
		_min_y = min(_min_y, _g.global_position.y)
func _process(_d: float) -> void:
	if Engine.get_process_frames() == 200:
		print("MIN_Y=%.3f grenade_still_exists=%s" % [_min_y, is_instance_valid(_g)])
		get_tree().quit()
