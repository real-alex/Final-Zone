extends Node3D
## Builds the procedural soldier in T-pose and exports it as a .glb so it
## can be converted to FBX and auto-rigged/animated in Mixamo.
## Run: godot --path . res://Tests/export_character.tscn

const OUT_PATH := "res://character_tpose.glb"


func _ready() -> void:
	var rig := SoldierRig.new()
	rig.tpose = true
	rig.yaw_offset_deg = 0.0
	add_child(rig)
	# Wait a frame so the rig's _ready builds all the meshes.
	await get_tree().process_frame
	await get_tree().process_frame

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(rig, state)
	if err != OK:
		push_error("append_from_scene failed: %d" % err)
		get_tree().quit(1)
		return
	err = doc.write_to_filesystem(state, OUT_PATH)
	if err == OK:
		print("EXPORTED ", ProjectSettings.globalize_path(OUT_PATH))
	else:
		push_error("write failed: %d" % err)
	get_tree().quit()
