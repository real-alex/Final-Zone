extends Node
## Bisect tool: threaded-loads each resource and reports success/failure.

const PATHS := [
	"res://Assets/UI/final_zone_theme.tres",
	"res://Scripts/UI/main_menu.gd",
	"res://Assets/UI/fz_emblem.svg",
	"res://Scripts/Shared/soldier_rig.gd",
	"res://Scripts/Weapons/viewmodel_rig.gd",
	"res://Assets/Weapons/m4_carbine_with_attachment_set.glb",
	"res://Scripts/UI/menu_stage.gd",
	"res://Scenes/Menus/main_menu.tscn",
]

var _index := 0
var _requested := false


func _process(_delta: float) -> void:
	if _index >= PATHS.size():
		get_tree().quit()
		return
	var path: String = PATHS[_index]
	if not _requested:
		ResourceLoader.load_threaded_request(path)
		_requested = true
		return
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	print("RESULT %s -> %s" % [path, "OK" if status == ResourceLoader.THREAD_LOAD_LOADED else "FAILED(%d)" % status])
	_index += 1
	_requested = false
