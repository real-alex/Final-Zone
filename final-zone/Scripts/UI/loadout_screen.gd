extends Control
## Loadout screen: assign any registry weapon to the primary or secondary
## slot, with a rotating 3D preview and stat bars. Selections persist via
## LoadoutManager.

signal closed

const CATEGORY_NAMES := ["ASSAULT RIFLE", "SMG", "DMR", "SNIPER", "SHOTGUN", "PISTOL"]
const ACCENT := Color(1, 0.706, 0)
const STATS := ["DAMAGE", "FIRE RATE", "ACCURACY", "MOBILITY", "CONTROL"]

@onready var primary_slot_button: Button = %PrimarySlotButton
@onready var secondary_slot_button: Button = %SecondarySlotButton
@onready var preview_container: SubViewportContainer = %PreviewContainer
@onready var weapon_name_label: Label = %WeaponNameLabel
@onready var category_label: Label = %CategoryLabel
@onready var stats_box: VBoxContainer = %StatsBox
@onready var cards_row: HBoxContainer = %CardsRow
@onready var back_button: Button = %LoadoutBackButton

var _active_slot := 0
var _stat_bars: Array[ProgressBar] = []
var _card_buttons: Array[Button] = []
var _viewport: SubViewport
var _preview_holder: Node3D
var _preview_rig: ViewmodelRig


const ATTACHMENT_LABELS := {
	"suppressor": "SUPPRESSOR",
	"foregrip": "FOREGRIP",
	"laser": "LASER",
	"extended_mag": "EXTENDED MAG",
}
const OPTIC_LABELS := {
	"red_dot": "RED DOT",
	"holo": "HOLO",
	"sniper": "SNIPER",
}

var _attachment_toggles: Dictionary = {}
var _optic_buttons: Dictionary = {}


func _ready() -> void:
	_build_preview_viewport()
	_build_stat_bars()
	_build_optic_buttons()
	_build_align_controls()
	_build_attachment_toggles()
	_build_cards()
	primary_slot_button.pressed.connect(_select_slot.bind(0))
	secondary_slot_button.pressed.connect(_select_slot.bind(1))
	back_button.pressed.connect(func() -> void:
		hide()
		closed.emit())
	LoadoutManager.loadout_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if visible and _preview_rig != null:
		_preview_rig.rotate_y(delta * 0.7)


func _select_slot(slot: int) -> void:
	_active_slot = slot
	_refresh()


func _on_card_pressed(weapon_path: String) -> void:
	LoadoutManager.assign(_active_slot, weapon_path)


func _refresh() -> void:
	var primary := LoadoutManager.get_primary()
	var secondary := LoadoutManager.get_secondary()
	primary_slot_button.text = "PRIMARY   -   %s" % primary.display_name
	secondary_slot_button.text = "SECONDARY   -   %s" % secondary.display_name
	primary_slot_button.button_pressed = _active_slot == 0
	secondary_slot_button.button_pressed = _active_slot == 1

	var shown := primary if _active_slot == 0 else secondary
	var fitted := LoadoutManager.get_attachments(_shown_path())
	var optic_type := LoadoutManager.get_optic(_shown_path())
	weapon_name_label.text = shown.display_name
	category_label.text = CATEGORY_NAMES[shown.category]
	for attachment_name: String in _attachment_toggles:
		var attachment_button: Button = _attachment_toggles[attachment_name]
		var attachment_selected := fitted.has(attachment_name)
		attachment_button.set_pressed_no_signal(attachment_selected)
		_style_toggle_button(attachment_button, attachment_selected)
	for optic_name: String in _optic_buttons:
		var optic_button: Button = _optic_buttons[optic_name]
		var optic_selected := optic_type == optic_name
		optic_button.set_pressed_no_signal(optic_selected)
		_style_toggle_button(optic_button, optic_selected)
	_update_stat_bars(shown.with_attachments(fitted))
	_update_preview(shown, fitted)
	_update_card_highlights()


func _build_optic_buttons() -> void:
	var container := primary_slot_button.get_parent()

	var header := Label.new()
	header.text = "OPTIC"
	header.add_theme_color_override("font_color", ACCENT)
	header.add_theme_font_size_override("font_size", 18)
	container.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	container.add_child(row)

	for optic in LoadoutManager.OPTIC_TYPES:
		var optic_name := String(optic)
		var button := Button.new()
		button.toggle_mode = true
		button.text = OPTIC_LABELS.get(optic_name, optic_name.to_upper())
		button.custom_minimum_size = Vector2(92, 34)
		button.pressed.connect(func() -> void:
			LoadoutManager.set_optic(_shown_path(), optic_name))
		row.add_child(button)
		_optic_buttons[optic_name] = button


func _build_attachment_toggles() -> void:
	var container := primary_slot_button.get_parent()

	var header := Label.new()
	header.text = "ATTACHMENTS"
	header.add_theme_color_override("font_color", ACCENT)
	header.add_theme_font_size_override("font_size", 18)
	container.add_child(header)

	for attachment_name: String in ATTACHMENT_LABELS:
		var row := HBoxContainer.new()
		container.add_child(row)

		var row_label := Label.new()
		row_label.text = ATTACHMENT_LABELS[attachment_name]
		row_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_label.add_theme_font_size_override("font_size", 15)
		row.add_child(row_label)

		var toggle := CheckButton.new()
		toggle.toggled.connect(func(_on: bool) -> void:
			LoadoutManager.toggle_attachment(_shown_path(), attachment_name))
		row.add_child(toggle)
		_attachment_toggles[attachment_name] = toggle


func _update_card_highlights() -> void:
	var primary_path := LoadoutManager.primary_path
	var secondary_path := LoadoutManager.secondary_path
	for i in _card_buttons.size():
		var path: String = LoadoutManager.WEAPON_PATHS[i]
		var suffix := ""
		if path == primary_path:
			suffix = "  [1]"
		elif path == secondary_path:
			suffix = "  [2]"
		var weapon: WeaponData = load(path)
		_card_buttons[i].text = "%s\n%s%s" % [
			weapon.display_name, CATEGORY_NAMES[weapon.category], suffix]


## ---------- stats ----------

func _stat_values(weapon: WeaponData) -> Array[float]:
	return [
		clampf(weapon.damage / 60.0, 0.05, 1.0),
		clampf(weapon.fire_rate_rpm / 1000.0, 0.05, 1.0),
		clampf(1.0 - weapon.ads_spread_deg / 0.4, 0.05, 1.0),
		clampf(1.0 - (weapon.view_length - 0.5) / 0.65, 0.05, 1.0),
		clampf(1.0 - weapon.recoil_pitch_deg / 3.0, 0.05, 1.0),
	]


func _build_stat_bars() -> void:
	for stat_name in STATS:
		var row_label := Label.new()
		row_label.text = stat_name
		row_label.add_theme_font_size_override("font_size", 14)
		stats_box.add_child(row_label)

		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		stats_box.add_child(bar)
		_stat_bars.append(bar)


func _update_stat_bars(weapon: WeaponData) -> void:
	var values := _stat_values(weapon)
	for i in _stat_bars.size():
		_stat_bars[i].value = values[i]


## ---------- optic alignment (edit gun) ----------

const ALIGN_STEP := 0.004


func _build_align_controls() -> void:
	var container := stats_box.get_parent()

	var header := Label.new()
	header.text = "EDIT GUN — OPTIC"
	header.add_theme_color_override("font_color", ACCENT)
	header.add_theme_font_size_override("font_size", 18)
	container.add_child(header)

	var hint := Label.new()
	hint.text = "Nudge the sight if it doesn't\nsit right on this weapon."
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.add_theme_font_size_override("font_size", 13)
	container.add_child(hint)

	container.add_child(_align_row("HEIGHT", Vector3(0, -ALIGN_STEP, 0), Vector3(0, ALIGN_STEP, 0)))
	container.add_child(_align_row("DEPTH", Vector3(0, 0, ALIGN_STEP), Vector3(0, 0, -ALIGN_STEP)))

	var reset := Button.new()
	reset.text = "RESET ALIGNMENT"
	reset.pressed.connect(func() -> void:
		LoadoutManager.set_optic_offset(_shown_path(), Vector3.ZERO)
		_refresh())
	container.add_child(reset)


func _align_row(label_text: String, minus_delta: Vector3, plus_delta: Vector3) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var row_label := Label.new()
	row_label.text = label_text
	row_label.custom_minimum_size = Vector2(90, 0)
	row_label.add_theme_font_size_override("font_size", 14)
	row.add_child(row_label)

	for pair in [["–", minus_delta], ["+", plus_delta]]:
		var button := Button.new()
		button.text = pair[0]
		button.custom_minimum_size = Vector2(56, 0)
		var delta: Vector3 = pair[1]
		button.pressed.connect(func() -> void:
			var path := _shown_path()
			LoadoutManager.set_optic_offset(path, LoadoutManager.get_optic_offset(path) + delta)
			_refresh())
		row.add_child(button)
	return row


func _shown_path() -> String:
	return LoadoutManager.primary_path if _active_slot == 0 else LoadoutManager.secondary_path


## ---------- weapon cards ----------

func _build_cards() -> void:
	for path in LoadoutManager.WEAPON_PATHS:
		var card := Button.new()
		card.custom_minimum_size = Vector2(170, 74)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(_on_card_pressed.bind(path))
		cards_row.add_child(card)
		_card_buttons.append(card)


## ---------- 3D preview ----------

func _build_preview_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(640, 330)
	preview_container.add_child(_viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.06, 1.15)
	camera.fov = 40.0
	_viewport.add_child(camera)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35, 40, 0)
	key_light.light_energy = 1.4
	_viewport.add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-1, -0.4, 1)
	fill_light.light_energy = 0.7
	fill_light.light_color = Color(0.7, 0.8, 1.0)
	_viewport.add_child(fill_light)

	_preview_holder = Node3D.new()
	_viewport.add_child(_preview_holder)


func _update_preview(weapon: WeaponData, fitted := PackedStringArray(