class_name HUD
extends CanvasLayer
## In-match HUD: health, stamina, ammo, crosshair, hit marker, score,
## kill feed, damage vignette, respawn countdown.

const KILL_FEED_LIFETIME := 4.0
const KILL_FEED_MAX_ENTRIES := 5

@onready var root: Control = $Root
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var ammo_label: Label = %AmmoLabel
@onready var fire_mode_label: Label = %FireModeLabel
@onready var score_label: Label = %ScoreLabel
@onready var kill_feed: VBoxContainer = %KillFeed
@onready var respawn_label: Label = %RespawnLabel
@onready var crosshair: DynamicCrosshair = %Crosshair
@onready var hit_marker: HitMarker = %HitMarker
@onready var damage_vignette: ColorRect = %DamageVignette

var _vignette_tween: Tween
var _scope_overlay: SniperScopeOverlay
var _flash_rect: ColorRect
var _flash_tween: Tween
var _low_hp_rect: ColorRect
var _killcam_label: Label


func _ready() -> void:
	respawn_label.hide()
	damage_vignette.material.set_shader_parameter("intensity", 0.0)
	# Sniper scope picture, drawn on top of the HUD when a magnified optic
	# is scoped in. Built in code so it always covers the full screen.
	_scope_overlay = SniperScopeOverlay.new()
	root.add_child(_scope_overlay)

	# Full-screen white flash for flashbangs.
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash_rect)

	# Low-health desaturating gray wash (intensifies as HP drops).
	_low_hp_rect = ColorRect.new()
	_low_hp_rect.color = Color(0.5, 0.5, 0.52, 0.0)
	_low_hp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_low_hp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_low_hp_rect)
	root.move_child(_low_hp_rect, 0)  # behind other HUD, over the world


## Kill cam banner ("KILLED BY ...") shown during the death cinematic.
func show_killcam_banner(text: String) -> void:
	if _killcam_label == null:
		_killcam_label = Label.new()
		_killcam_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_killcam_label.position = Vector2(0, 60)
		_killcam_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_killcam_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_killcam_label.add_theme_font_size_override("font_size", 30)
		_killcam_label.add_theme_color_override("font_color", Color(0.9, 0.22, 0.18))
		root.add_child(_killcam_label)
	_killcam_label.text = text
	_killcam_label.show()


func hide_killcam_banner() -> void:
	if _killcam_label != null:
		_killcam_label.hide()


## Flashbang blind: snap to white, then fade over `duration`.
func flash_blind(duration: float) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color.a = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_interval(duration * 0.3)
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, duration * 0.7)


## Called each frame with the weapon's scope fraction and optic type.
## Shows the sniper ocular + reticle and hides the crosshair when scoped.
func set_scope_view(fraction: float, optic_type: String) -> void:
	_scope_overlay.set_scope_view(fraction, optic_type)


func set_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = str(int(ceilf(current)))
	# Below 40% HP the screen washes gray, heavier the closer to death.
	var hp_fraction := current / maxf(maximum, 1.0)
	if _low_hp_rect != null:
		var wash := clampf((0.4 - hp_fraction) / 0.4, 0.0, 1.0) * 0.4
		_low_hp_rect.color.a = wash


func set_stamina(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current


func set_ammo(magazine: int, reserve: int) -> void:
	ammo_label.text = "%d / %d" % [magazine, reserve]


func set_fire_mode(mode_name: String) -> void:
	fire_mode_label.text = mode_name


func set_score(player_kills: int, bot_kills: int) -> void:
	score_label.text = "YOU  %d  -  %d  BOT" % [player_kills, bot_kills]


func set_crosshair_spread(pixels: float) -> void:
	crosshair.spread = pixels


func set_crosshair_visible(shown: bool) -> void:
	crosshair.visible = shown


func show_hit_marker(headshot: bool = false) -> void:
	hit_marker.flash(headshot)
	AudioManager.play_ui("headshot" if headshot else "hit_marker", -4.0)


func flash_damage(intensity: float = 0.6) -> void:
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	damage_vignette.material.set_shader_parameter("intensity", intensity)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(
		func(v: float) -> void: damage_vignette.material.set_shader_parameter("intensity", v),
		intensity, 0.0, 0.8
	)


func add_kill_entry(killer_name: String, victim_name: String, headshot: bool) -> void:
	var entry := Label.new()
	var suffix := "  [HEADSHOT]" if headshot else ""
	entry.text = "%s  >  %s%s" % [killer_name, victim_name, suffix]
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	entry.add_theme_font_size_override("font_size", 16)
	var accent := Color(1.0, 0.706, 0.0) if killer_name == "YOU" else Color(0.9, 0.25, 0.2)
	entry.add_theme_color_override("font_color", accent)
	kill_feed.add_child(entry)

	while kill_feed.get_child_count() > KILL_FEED_MAX_ENTRIES:
		var oldest := kill_feed.get_child(0)
		kill_feed.remove_child(oldest)
		oldest.queue_free()

	var tween := entry.create_tween()
	tween.tween_interval(KILL_FEED_LIFETIME)
	tween.tween_property(entry, "modulate:a", 0.0, 0.6)
	tween.tween_callback(entry.queue_free)


func show_respawn_countdown(seconds_left: int) -> void:
	respawn_label.text = "RESPAWNING IN %d" % maxi(seconds_left, 1)
	respawn_label.show()


func hide_respawn_countdown() -> void:
	respawn_label.hide()
