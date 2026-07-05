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
var _death_layer: CanvasLayer
var _death_count: Label
var _respawn_button: Button
var _death_loadout: Control


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
	player.flashed.connect(hud.flash_blind)

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
		var scope_fraction := weapon.get_scope_view_fraction()
		hud.set_scope_view(scope_fraction, weapon.get_optic_type())
		# Hide the crosshair when aiming or fully inside the sniper scope.
		hud.set_crosshair_visible(
			weapon.get_aim_fraction() < 0.35 and scope_fraction < 0.2 and player.health.alive)


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
		if weapon.data.is_blueprint:
			_blueprint_kill_effect(bot.global_position + Vector3(0, 1.0, 0), weapon.data.tracer_color)
		MatchManager.register_kill("YOU", "BOT", true, headshot)
		_handle_bot_death()


## Colored spark burst on an epic-blueprint kill.
func _blueprint_kill_effect(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 30
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -4, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	p.color = color
	add_child(p)
	p.global_position = at
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 5.0
	light.omni_range = 5.0
	add_child(light)
	light.global_position = at
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.4).finished.connect(light.queue_free)
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _on_player_died(_attacker: Node) -> void:
	MatchManager.register_kill("BOT", "YOU", false)
	AudioManager.play_sfx("death", -4.0)
	player.set_active(false)
	if MatchManager.match_active:
		await _play_kill_cam()
		if MatchManager.match_active and is_inside_tree():
			_show_death_screen()


## Brief cinematic showing the killer before the respawn screen.
func _play_kill_cam() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var focus := bot.global_position + Vector3(0, 1.2, 0)
	cam.global_position = focus + Vector3(1.6, 1.0, 1.6)
	cam.look_at(focus, Vector3.UP)
	cam.current = true
	hud.show_killcam_banner("KILLED BY %s" % bot.display_name)
	var elapsed := 0.0
	while elapsed < 2.2 and MatchManager.match_active and is_inside_tree():
		# Slow orbit around the killer.
		var t := elapsed
		cam.global_position = focus + Vector3(cos(t) * 2.2, 1.0, sin(t) * 2.2)
		cam.look_at(focus, Vector3.UP)
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	hud.hide_killcam_banner()
	cam.queue_free()
	if player.camera != null:
		player.camera.current = true


## CoD-style respawn screen: eliminated banner, countdown, then a RESPAWN
## button and an EDIT LOADOUT button (so you can switch kit before respawn).
func _show_death_screen() -> void:
	if _death_layer == null:
		_build_death_screen()
	GameManager.release_mouse()
	_death_layer.show()
	_respawn_button.disabled = true
	for seconds_left in [5, 4, 3, 2, 1]:
		_death_count.text = "RESPAWN IN %d" % seconds_left
		await get_tree().create_timer(1.0, false).timeout
		if not MatchManager.match_active or not is_inside_tree():
			_death_layer.hide()
			return
	_death_count.text = "READY"
	_respawn_button.disabled = false


func _do_respawn() -> void:
	_death_layer.hide()
	GameManager.capture_mouse()
	AudioManager.play_ui("respawn", -6.0)
	player.respawn_at(_farthest_spawn(warehouse.get_player_spawns(), bot.global_position))


func _open_loadout_from_death() -> void:
	if _death_loadout == null:
		_death_loadout = load("res://Scenes/Menus/loadout_screen.tscn").instantiate()
		_death_layer.add_child(_death_loadout)
		_death_loadout.closed.connect(func() -> void: _death_loadout.hide())
	_death_loadout.show()


func _build_death_screen() -> void:
	_death_layer = CanvasLayer.new()
	_death_layer.layer = 12
	add_child(_death_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = load("res://Assets/UI/final_zone_theme.tres")
	_death_layer.add_child(root)
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.05, 0.02, 0.02, 0.72)
	root.add_child(overlay)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(vbox)
	var title := Label.new()
	title.text = "YOU WERE ELIMINATED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.9, 0.22, 0.18))
	vbox.add_child(title)
	_death_count = Label.new()
	_death_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_count.add_theme_font_size_override("font_size", 24)
	_death_count.add_theme_color_override("font_color", Color(1, 0.706, 0))
	vbox.add_child(_death_count)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	_respawn_button = Button.new()
	_respawn_button.text = "RESPAWN"
	_respawn_button.custom_minimum_size = Vector2(200, 50)
	_respawn_button.pressed.connect(_do_respawn)
	row.add_child(_respawn_button)
	var loadout_btn := Button.new()
	loadout_btn.text = "EDIT LOADOUT"
	loadout_btn.custom_minimum_size = Vector2(200, 50)
	loadout_btn.pressed.connect(_open_loadout_from_death)
	row.add_child(loadout_btn)


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
