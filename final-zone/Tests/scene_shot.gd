extends Node
## Dev tool: instances the scene from FZ_SHOT_SCENE, waits a few frames,
## saves a screenshot to FZ_SHOT_DIR, and quits.
## Run: godot --path . res://Tests/scene_shot.tscn

var _frame := 0
var _shot_frame := 45


func _ready() -> void:
	var target := OS.get_environment("FZ_SHOT_SCENE")
	if target == "":
		push_error("FZ_SHOT_SCENE not set")
		get_tree().quit(1)
		return
	var frames_env := OS.get_environment("FZ_SHOT_FRAMES")
	if frames_env.is_valid_int():
		_shot_frame = frames_env.to_int()
	var packed: PackedScene = load(target)
	add_child(packed.instantiate())


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == _shot_frame:
		var out_dir := OS.get_environment("FZ_SHOT_DIR")
		if out_dir == "":
			out_dir = "user://"
		var image := get_viewport().get_texture().get_image()
		image.save_png(out_dir.path_join("scene_shot.png"))
		print("saved scene_shot.png")
		get_tree().quit()
