extends Control
## Lobby-style main menu: top nav bar, 3D operator stage with slung rifle,
## difficulty select, settings. Locked buttons are future features.

const GAME_SCENE := "res://Scenes/Main/game.tscn"

@onready var difficulty_panel: PanelContainer = %DifficultyPanel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var character: Node3D = %Character
@onready var menu_camera: Camera3D = %MenuCamera

var _idle_time := 0.0
var _camera_base: Vector3
var _character_base_yaw := 0.0
var _loadout_screen: Control
var _customize_screen: Control
var _keybind_screen: Control


func _ready() -> void:
	GameManager.release_mouse()
	GameManager.state = GameManager.GameState.MENU
	difficulty_panel.hide()
	settings_panel.hide()
	_camera_base = menu_camera.position
	_character_base_yaw = character.rotation.y
	_connect_buttons()
	_load_settings_controls()
	_connect_settings_controls()
	_connect_hover_sounds()
	AudioManager.play_music("menu_music", -10.0)


func _process(delta: float) -> void:
	# Idle life: operator breathing, slow sway, gentle camera drift.
	_idle_time += delta
	character.position.y = sin(_idle_time * 1.3) * 0.008
	character.rotation.y = _character_base_yaw + sin(_idle_time * 0.32) * 0.03
	menu_camera.position.x = _camera_base.x + sin(_idle_time * 0.21) * 0.05
	menu_camera.position.y = _camera_base.y + sin(_idle_time * 0.4) * 0.015


func _connect_buttons() -> void:
	%PlayButton.pressed.connect(_on_play_pressed)
	%BigPlayButton.pressed.connect(_on_play_pressed)
	%LoadoutButton.pressed.connect(_on_loadout_pressed)
	%CustomizeButton.pressed.connect(_on_customize_pressed)
	%SettingsButton.pressed.connect(_on_settings_pressed)
	%KeybindsButton.pressed.connect(_on_keybinds_pressed)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%EasyButton.pressed.connect(_start_match.bind(GameManager.Difficulty.EASY))
	%MediumButton.pressed.connect(_start_match.bind(GameManager.Difficulty.MEDIUM))
	%HardButton.pressed.connect(_start_match.bind(GameManager.Difficulty.HARD))
	%DifficultyBackButton.pressed.connect(func() -> void: difficulty_panel.hide())
	%SettingsBackButton.pressed.connect(func() -> void: settings_panel.hide())


func _connect_hover_sounds() -> void:
	for button: Button in find_children("*", "Button", true, false):
		button.mouse_entered.connect(AudioManager.play_ui.bind("ui_hover", -6.0))
		button.pressed.connect(AudioManager.play_ui.bind("ui_click"))


func _load_settings_controls() -> void:
	%SensitivitySlider.value = SettingsManager.get_value("controls", "mouse_sensitivity")
	%AdsSensSlider.value = SettingsManager.get_value("controls", "ads_sensitivity_mult")
	%MasterSlider.value = SettingsManager.get_value("audio", "master_volume")
	%MusicSlider.value = SettingsManager.get_value("audio", "music_volume")
	%SfxSlider.value = SettingsManager.get_value("audio", "sfx_volume")
	%UiSlider.value = SettingsManager.get_value("audio", "ui_volume")
	%FullscreenCheck.button_pressed = SettingsManager.get_value("video", "fullscreen")
	%VsyncCheck.button_pressed = SettingsManager.get_value("video", "vsync")
	%AdsToggleCheck.button_pressed = SettingsManager.get_value("controls", "ads_toggle")
	%CrouchToggleCheck.button_pressed = SettingsManager.get_value("controls", "crouch_toggle")


func _connect_settings_controls() -> void:
	%SensitivitySlider.value_changed.connect(
		func(v: float) -> void: SettingsManager.set_value("controls", "mouse_sensitivity", v))
	%AdsSensSlider.value_changed.connect(
		func(v: float) -> void: SettingsManager.set_value("controls", "ads_sensitivity_mult", v))
	%MasterSlider.value_changed.connect(
		func(v: float) -> void: SettingsManager.set_value("audio", "master_volume", v))
	%MusicSlider.value_changed.connect(
		func(v: float) -> void: SettingsManager.set_value("audio", "music_volume", v))
	%SfxSlider.value_changed.connect(
		func(v: float) -> void: SettingsManager.set_value("audio", "sfx_volume", v))
	%UiSlider.value_changed.connect(
		func(v: float) -> void: SettingsManager.set_value("audio", "ui_volume", v))
	%FullscreenCheck.toggled.connect(
		func(on: bool) -> void: SettingsManager.set_value("video", "fullscreen", on))
	%VsyncCheck.toggled.connect(
		func(on: bool) -> void: SettingsManager.set_value("video", "vsync", on))
	%AdsToggleCheck.toggled.connect(
		func(on: bool) -> void: SettingsManager.set_value("controls", "ads_toggle", on))
	%CrouchToggleCheck.toggled.connect(
		func(on: bool) -> void: SettingsManager.set_value("controls", "crouch_toggle", on))


func _on_play_pressed() -> void:
	settings_panel.hide()
	if _loadout_screen != null:
		_loadout_screen.hide()
	if _customize_screen != null:
		_customize_screen.hide()
	difficulty_panel.show()


func _on_settings_pressed() -> void:
	difficulty_panel.hide()
	if _loadout_screen != null:
		_loadout_screen.hide()
	if _customize_screen != null:
		_customize_screen.hide()
	settings_panel.show()


func _on_loadout_pressed() -> void:
	difficulty_panel.hide()
	settings_panel.hide()
	if _customize_screen != null:
		_customize_screen.hide()
	# Instanced lazily: embedding it in the scene file breaks threaded
	# loading of the menu (nested scene sharing the parent's resources).
	if _loadout_screen == null:
		var loadout_scene: PackedScene = load("res://Scenes/Menus/loadout_screen.tscn")
		_loadout_screen = loadout_scene.instantiate()
		add_child(_loadout_screen)
		for button: Button in _loadout_screen.find_children("*", "Button", true, false):
			button.mouse_entered.connect(AudioManager.play_ui.bind("ui_hover", -6.0))
			button.pressed.connect(AudioManager.play_ui.bind("ui_click"))
	_loadout_screen.show()


func _on_keybinds_pressed() -> void:
	if _keybind_screen == null:
		_keybind_screen = KeybindScreen.new()
		add_child(_keybind_screen)
	_keybind_screen.show()


func _on_customize_pressed() -> void:
	difficulty_panel.hide()
	settings_panel.hide()
	if _loadout_screen != null:
		_loadout_screen.hide()
	if _customize_screen == null:
		var scene: PackedScene = load("res://Scenes/Menus/customize_screen.tscn")
		_customize_screen = scene.instantiate()
		add_child(_customize_screen)
		for button: Button in _customize_screen.find_children("*", "Button", true, false):
			button.mouse_entered.connect(AudioManager.play_ui.bind("ui_hover", -6.0))
			button.pressed.connect(AudioManager.play_ui.bind("ui_click"))
	_customize_screen.show()


func _start_match(difficulty: GameManager.Difficulty) -> void:
	GameManager.difficulty = difficulty
	AudioManager.stop_music()
	SceneManager.change_scene_with_loading(GAME_SCENE)
