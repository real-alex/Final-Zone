extends Control
## AlexionStudios boot splash. Fades in, holds, fades out, then loads the
## main menu. Any key/click skips it.

const MAIN_MENU_SCENE := "res://Scenes/Menus/main_menu.tscn"

var _skipped := false


func _ready() -> void:
	GameManager.release_mouse()
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.9)
	tween.tween_interval(1.6)
	tween.tween_property(self, "modulate:a", 0.0, 0.7)
	await tween.finished
	_go_to_menu()


func _input(event: InputEvent) -> void:
	if _skipped:
		return
	if event is InputEventKey and event.pressed:
		_go_to_menu()
	elif event is InputEventMouseButton and event.pressed:
		_go_to_menu()


func _go_to_menu() -> void:
	if _skipped:
		return
	_skipped = true
	SceneManager.change_scene_with_loading(MAIN_MENU_SCENE)
