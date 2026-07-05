class_name KeybindScreen
extends Control
## Key rebinding: lists the rebindable actions with their current key; click
## a key to capture a new one. Persists through SettingsManager. Built
## entirely in code so it needs no scene file.

signal closed

const LABELS := {
	"move_forward": "MOVE FORWARD", "move_back": "MOVE BACK",
	"move_left": "MOVE LEFT", "move_right": "MOVE RIGHT",
	"jump": "JUMP", "sprint": "SPRINT", "crouch": "CROUCH",
	"reload": "RELOAD", "grenade": "GRENADE", "flashbang": "FLASHBANG",
	"medkit": "MEDKIT", "weapon_1": "PRIMARY", "weapon_2": "SECONDARY",
}

var _listening := ""
var _buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = load("res://Assets/UI/final_zone_theme.tres")

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.018, 0.018, 0.02, 0.98)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "KEY BINDINGS"
	title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title)
	var hint := Label.new()
	hint.text = "Click a key, then press the new key to bind it."
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	for action: String in SettingsManager.REBINDABLE:
		var label := Label.new()
		label.text = LABELS.get(action, action.to_upper())
		label.custom_minimum_size = Vector2(150, 0)
		label.add_theme_font_size_override("font_size", 15)
		grid.add_child(label)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 34)
		btn.text = SettingsManager.get_bind_label(action)
		btn.pressed.connect(_start_listen.bind(action, btn))
		grid.add_child(btn)
		_buttons[action] = btn

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(200, 44)
	back.pressed.connect(func() -> void: hide(); closed.emit())
	vbox.add_child(back)


func _start_listen(action: String, btn: Button) -> void:
	_listening = action
	btn.text = "PRESS KEY..."


func _input(event: InputEvent) -> void:
	if _listening == "" or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var keycode: int = (event as InputEventKey).physical_keycode
		SettingsManager.rebind(_listening, keycode)
		_buttons[_listening].text = SettingsManager.get_bind_label(_listening)
		_listening = ""
		accept_event()
