extends Node
## The player's operator identity + appearance. Persists to disk and is
## applied to the player/lobby character. Autoload: CustomizeManager

signal customize_changed

const SAVE_PATH := "user://customize.cfg"

## Preset uniform colors the customize screen offers.
const UNIFORM_PRESETS := {
	"OLIVE": Color(0.30, 0.33, 0.22),
	"COYOTE": Color(0.45, 0.38, 0.26),
	"BLACK": Color(0.09, 0.09, 0.10),
	"NAVY": Color(0.14, 0.20, 0.30),
	"WOODLAND": Color(0.22, 0.26, 0.17),
}

var operator_name := "OPERATOR"
var show_helmet := true
var show_armor := true
var uniform_color := Color(0.30, 0.33, 0.22)


func _ready() -> void:
	_load()


## Applies the saved look to a SoldierRig (call before it enters the tree).
func apply_to(rig: Node) -> void:
	rig.set("show_helmet", show_helmet)
	rig.set("show_armor", show_armor)
	rig.set("uniform_color", uniform_color)


func set_name_text(text: String) -> void:
	operator_name = text.strip_edges().to_upper()
	if operator_name == "":
		operator_name = "OPERATOR"
	_save()
	customize_changed.emit()


func set_helmet(on: bool) -> void:
	show_helmet = on
	_save()
	customize_changed.emit()


func set_armor(on: bool) -> void:
	show_armor = on
	_save()
	customize_changed.emit()


func set_uniform(color: Color) -> void:
	uniform_color = color
	_save()
	customize_changed.emit()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	operator_name = config.get_value("operator", "name", "OPERATOR")
	show_helmet = config.get_value("operator", "helmet", true)
	show_armor = config.get_value("operator", "armor", true)
	uniform_color = config.get_value("operator", "uniform", uniform_color)


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("operator", "name", operator_name)
	config.set_value("operator", "helmet", show_helmet)
	config.set_value("operator", "armor", show_armor)
	config.set_value("operator", "uniform", uniform_color)
	config.save(SAVE_PATH)
