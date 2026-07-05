extends Node
## Loads, applies and persists user settings (controls, audio, video).
## Autoload: SettingsManager

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"

const DEFAULTS := {
	"controls": {
		"mouse_sensitivity": 0.25,
		"ads_sensitivity_mult": 0.6,
		"ads_toggle": false,       ## false = hold to aim, true = toggle
		"crouch_toggle": false,    ## false = hold to crouch, true = toggle
	},
	"audio": {
		"master_volume": 0.8,
		"music_volume": 0.6,
		"sfx_volume": 0.8,
		"ui_volume": 0.7,
	},
	"video": {
		"fullscreen": true,
		"vsync": true,
	},
}

var _data: Dictionary = {}


## Actions the player can rebind in the keybinding screen.
const REBINDABLE := [
	"move_forward", "move_back", "move_left", "move_right", "jump", "sprint",
	"crouch", "reload", "grenade", "flashbang", "medkit", "weapon_1", "weapon_2",
]

var _keybinds: Dictionary = {}   ## action -> physical keycode


func _ready() -> void:
	load_settings()
	# Keybinds live in their own section, managed separately from the
	# value-based settings so save_settings() doesn't clobber them.
	if _data.has("keybinds"):
		_keybinds = _data["keybinds"].duplicate()
		_data.erase("keybinds")
	apply_all()
	_apply_keybinds()


## Rebinds an action to a physical key and persists it.
func rebind(action: String, physical_keycode: int) -> void:
	_keybinds[action] = physical_keycode
	_apply_one_bind(action, physical_keycode)
	_save_keybinds()


func get_bind_label(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string((event as InputEventKey).physical_keycode)
	return "--"


func _apply_keybinds() -> void:
	for action: String in _keybinds:
		_apply_one_bind(action, _keybinds[action])


func _apply_one_bind(action: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	# Replace only keyboard events (keep any mouse bindings intact).
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var new_event := InputEventKey.new()
	new_event.physical_keycode = physical_keycode
	InputMap.action_add_event(action, new_event)


func _save_keybinds() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	for action: String in _keybinds:
		config.set_value("keybinds", action, _keybinds[action])
	config.save(SETTINGS_PATH)


func get_value(section: String, key: String) -> Variant:
	if _data.has(section) and _data[section].has(key):
		return _data[section][key]
	return DEFAULTS[section][key]


func set_value(section: String, key: String, value: Variant) -> void:
	if not _data.has(section):
		_data[section] = {}
	_data[section][key] = value
	apply_all()
	save_settings()
	settings_changed.emit()


func load_settings() -> void:
	_data = DEFAULTS.duplicate(true)
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for section in config.get_sections():
		if not _data.has(section):
			_data[section] = {}
		for key in config.get_section_keys(section):
			_data[section][key] = config.get_value(section, key)


func save_settings() -> void:
	var config := ConfigFile.new()
	for section in _data.keys():
		for key in _data[section].keys():
			config.set_value(section, key, _data[section][key])
	config.save(SETTINGS_PATH)


func apply_all() -> void:
	_apply_bus_volume("Master", get_value("audio", "master_volume"))
	_apply_bus_volume("Music", get_value("audio", "music_volume"))
	_apply_bus_volume("SFX", get_value("audio", "sfx_volume"))
	_apply_bus_volume("UI", get_value("audio", "ui_volume"))

	var fullscreen: bool = get_value("video", "fullscreen")
	var current_mode := DisplayServer.window_get_mode()
	if fullscreen and current_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	var vsync: bool = get_value("video", "vsync")
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus == -1:
		return
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(bus, linear <= 0.001)
