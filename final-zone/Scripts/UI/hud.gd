class_name HUD
extends CanvasLayer
## In-match HUD: health, stamina, ammo, crosshair, hit marker, score,
## kill feed, damage vignette, respawn countdown.

const KILL_FEED_LIFETIME := 4.0
const KILL_FEED_MAX_ENTRIES := 5

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


func _ready() -> void:
	respawn_label.hide()
	damage_vignette.material.set_shader_parameter("intensity", 0.0)


func set_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = str(int(ceilf(current)))


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
