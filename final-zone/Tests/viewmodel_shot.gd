extends Node3D
## Dev tool: photographs the first-person viewmodel at hip and at ADS,
## using the same holder offsets as the real player, then quits.
## Run: godot --path . res://Tests/viewmodel_shot.tscn

const OUT_DIR_SETTING := "FZ_SHOT_DIR"
const HIP_POSITION := Vector3(0.24, -0.22, -0.45)
const EYE_RELIEF := 0.24

@onready var holder: Node3D = $Camera3D/WeaponHolder
@onready var rig: ViewmodelRig = $Camera3D/WeaponHolder/Viewmodel

var _frame := 0
var _out_dir := "user://"


func _ready() -> void:
	var env_dir := OS.get_environment(OUT_DIR_SETTING)
	if env_dir != "":
		_out_dir = env_dir
	holder.position = HIP_POSITION
	# FZ_WEAPON_RES swaps the default M4 for any WeaponData resource.
	var res_path := OS.get_environment("FZ_WEAPON_RES")
	if res_path != "":
		rig.free()
		var data: WeaponData = load(res_path)
		rig = ViewmodelRig.new()
		rig.body_part = data.body_part
		rig.keep_parts = data.keep_parts
		rig.scope_part = data.scope_part
		rig.build_optic = data.build_optic
		rig.target_length = data.view_length
		rig.flip_forward = data.flip_forward
		rig.add_child(load(data.model_path).instantiate())
		holder.add_child(rig)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 15:
		_save("vm_hip.png")
		if rig.scope_center != Vector3.ZERO:
			holder.position = Vector3(
				-rig.scope_center.x,
				-rig.scope_center.y,
				-EYE_RELIEF - rig.scope_center.z
			)
		print("scope_center=", rig.scope_center)
	elif _frame == 25:
		_save("vm_ads.png")
		get_tree().quit()


func _save(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out_dir.path_join(file_name))
	print("saved ", file_name)
