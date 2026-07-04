extends Node
## Scene transitions with a fade-to-black overlay.
## Autoload: SceneManager

signal scene_changed(scene_path: String)

const FADE_TIME := 0.35

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _is_transitioning := false


func _ready() -> void:
	# Fades must run even if the tree was paused when leaving a scene.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.05, 0.05, 0.05, 1.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate.a = 0.0
	_fade_layer.add_child(_fade_rect)


func change_scene(scene_path: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	await fade_out()
	get_tree().change_scene_to_file(scene_path)
	await fade_in()
	_is_transitioning = false
	scene_changed.emit(scene_path)


## Shows the loading screen (art, progress bar, tips) while the target
## scene loads on a background thread.
func change_scene_with_loading(scene_path: String) -> void:
	LoadingScreen.next_scene = scene_path
	change_scene("res://Scenes/UI/loading_screen.tscn")


func fade_out() -> Signal:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_TIME)
	return tween.finished


func fade_in() -> Signal:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_TIME)
	return tween.finished
