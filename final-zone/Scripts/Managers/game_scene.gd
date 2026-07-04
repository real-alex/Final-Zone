extends Node3D
## Match scene controller: wires player, bot, HUD and MatchManager
## together, handles respawns, pause, and the end screen.
## Root runs in ALWAYS process mode so pause input keeps working;
## gameplay children are PAUSABLE.

const MENU_SCENE := "res://Scenes/Menus/main_menu.tscn"
const GAME_SCENE := "res://Scenes/Main/game.tscn"

@onready var warehouse: Node3D = $Warehouse
@onready var player: Player = $Player
@onready var bot: Bot = $Bot
@onready var hud: HUD = $HUD
@onready var weapon: WeaponController = player.get_node("Head/Recoil/Camera3D/WeaponHolder")
@onready var pause_layer: CanvasLayer = $PauseLayer
@onready var end_layer: CanvasLayer = $EndLayer
@onready var result_label: Label = %ResultLabel
@onready var final_score_label: Label = %FinalScoreLabel

var _paused := false


func _ready() -> void:
	MatchManager.start_match()
	GameManager.capture_mouse()
	pause_layer.hide()
	end_layer.hide()

	# Player -> HUD.
	player.health_changed.connect(hud.set_health)
	player.stamina_changed.connect(hud.set_stamina)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)

	# Weapon -> HUD / score.
	weapon.ammo_changed.connect(hud.set_ammo)
	weapon.hit_confirmed.connect(_on_hit_confirmed)
	weapon.weapon_changed.connect(
		func(weapon_name: String, mode_name: String) -> void:
			hud.set_fire_mode("%s   %s" % [weapon_name, mode_name]))
	hud.set_fire_mode("%s   %s" % [weapon.data.display_name, weapon.data.get_fire_mode_name()])

	# Match state -> HUD.
	MatchManager.score_changed.connect(hud.set_score)
	MatchManager.kill_occurred.connect(hud.add_kill_entry)
	MatchManager.match_ended.connect(_on_match_ended)

	# Bot boots once the navmesh is baked.
	bot.setup(GameManager.get_difficulty_preset(), warehouse.get_patrol_points())
	bot.set_active(false)
	warehouse.navmesh_ready.connect(func() -> void:
		if MatchManager.match_active:
			bot.set_active(true)
	)

	_connect_menu_buttons()


func _connect_menu_buttons() -> void:
	%ResumeButton.pressed.connect(_toggle_pause)
	%PauseMenuButton.pressed.connect(_go_to_menu)
	%PauseQuitButton.pressed.connect(func() -> void: get_tree().quit())
	%RematchButton.pressed.connect(_rematch)
	%EndMenuButton.pressed.connect(_go_to_menu)
	for button: Button in find_children("*", "Button", true, false):
		button.mouse_entered.connect(AudioManager.play_ui.bind("ui_hover", -6.0))
		button.pressed.connect(AudioManager.play_ui.bind("ui_click"))


func _process(_delta: float) -> void:
	if GameManager.is_gameplay_active():
		hud.set_crosshair_spread(8.0 + weapon.get_current_spread_deg() * 6.0)
		hud.set_crosshair_visible(weapon.get_aim_fraction() < 0.35 and player.health.alive)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and MatchManager.match_active:
		_toggle_pause()


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	pause_layer.visible = _paused
	if _paused:
		GameManager.state = GameManager.GameState.PAUSED
		GameManager.release_mouse()
	else:
		GameManager.state = GameManager.GameState.PLAYING
		GameManager.capture_mouse()


func _on_player_damaged(_amount: float, _attacker: Node) -> void:
	hud.flash_damage()


func _on_hit_confirmed(headshot: bool, killed: bool) -> void:
	hud.show_hit_marker(headshot)
	if killed:
		AudioManager.play_sfx_3d("death", bot.global_position, -2.0)
		MatchManager.register_kill("YOU", "BOT", true, headshot)
		_handle_bot_death()


func _on_player_died(_attacker: Node) -> void:
	MatchManager.register_kill("BOT", "YOU", false)
	AudioManager.play_sfx("death", -4.0)
	player.set_active(false)
	if MatchManager.match_active:
		_respawn_player()


func _handle_bot_death() -> void:
	bot.play_death()
	if MatchManager.match_active:
		_respawn_bot()


func _respawn_player() -> void:
	for seconds_left in [3, 2, 1]:
		hud.show_respawn_countdown(seconds_left)
		await get_tree().create_timer(1.0, false).timeout
		if not MatchManager.match_active or not is_inside_tree():
			hud.hide_respawn_countdown()
			return
	hud.hide_respawn_countdown()
	AudioManager.play_ui("respawn", -6.0)
	player.respawn_at(_farthest_spawn(warehouse.get_player_spawns(), bot.global_position))


func _respawn_bot() -> void:
	await get_tree().create_timer(MatchManager.RESPAWN_DELAY, false).timeout
	if not MatchManager.match_active or not is_inside_tree():
		return
	bot.respawn_at(_farthest_spawn(warehouse.get_bot_spawns(), player.global_position))


func _farthest_spawn(spawns: Array[Marker3D], enemy_position: Vector3) -> Transform3D:
	var best: Marker3D = spawns[0]
	var best_distance := -1.0
	for spawn in spawns:
		var distance := spawn.global_position.distance_squared_to(enemy_position)
		if distance > best_distance:
			best_distance = distance
			best = spawn
	return best.global_transform


func _on_match_ended(player_won: bool) -> void:
	GameManager.release_mouse()
	get_tree().paused = true
	result_label.text = "VICTORY" if player_won else "DEFEAT"
	result_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.706, 0.0) if player_won else Color(0.9, 0.22, 0.18)
	)
	final_score_label.text = "YOU  %d  -  %d  BOT" % [MatchManager.player_kills, MatchManager.bot_kills]
	end_layer.show()
	AudioManager.play_ui("victory" if player_won else "defeat")


func _rematch() -> void:
	get_tree().paused = false
	SceneManager.change_scene_with_loading(GAME_SCENE)


func _go_to_menu() -> void:
	get_tree().paused = false
	SceneManager.change_scene(MENU_SCENE)
