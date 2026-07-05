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
	# Mount buttons: SIGHT always available; others need their attachment.
	for mount: String in _mount_buttons:
		var mount_button: Button = _mount_buttons[mount]
		var available: bool = mount == "optic" or fitted.has(MOUNT_REQUIRES[mount])
		mount_button.disabled = not available
		if not available and _active_mount == mount:
			_active_mount = "optic"
	for mount: String in _mount_buttons:
		var mount_button: Button = _mount_buttons[mount]
		mount_button.set_pressed_no_signal(_active_mount == mount)
		_style_toggle_button(mount_button, _active_mount == mount)

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
		button.pressed.connect(_on_optic_pressed.bind(optic_name))
		row.add_child(button)
		_optic_buttons[optic_name] = button


func _build_attachment_toggles() -> void:
	var container := primary_slot_button.get_parent()

	var header := Label.new()
	header.text = "ATTACHMENTS"
	header.add_theme_color_override("font_color", ACCENT)
	header.add_theme_font_size_override("font_size", 18)
	container.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	container.add_child(grid)

	for attachment in LoadoutManager.ATTACHMENT_NAMES:
		var attachment_name := String(attachment)
		var toggle := Button.new()
		toggle.toggle_mode = true
		toggle.text = ATTACHMENT_LABELS.get(attachment_name, attachment_name.to_upper())
		toggle.custom_minimum_size = Vector2(136, 36)
		toggle.pressed.connect(_on_attachment_pressed.bind(attachment_name))
		grid.add_child(toggle)
		_attachment_toggles[attachment_name] = toggle


func _on_optic_pressed(optic_name: String) -> void:
	LoadoutManager.set_optic(_shown_path(), optic_name)
	_refresh()


func _on_attachment_pressed(attachment_name: String) -> void:
	LoadoutManager.toggle_attachment(_shown_path(), attachment_name)


func _style_toggle_button(button: Button, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.055, 0.058, 0.065, 0.92)
	normal.border_color = Color(0.16, 0.16, 0.17)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)

	var active := StyleBoxFlat.new()
	active.bg_color = Color(0.18, 0.14, 0.035, 0.98)
	active.border_color = ACCENT
	active.set_border_width_all(2)
	active.set_corner_radius_all(4)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.10, 0.10, 0.105, 0.98)
	hover.border_color = Color(0.36, 0.32, 0.18)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(4)

	button.add_theme_stylebox_override("normal", active if selected else normal)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover", active if selected else hover)
	button.add_theme_color_override("font_color", ACCENT if selected else Color(0.82, 0.82, 0.84))
	button.add_theme_color_override("font_pressed_color", ACCENT)


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


## ---------- optic / barrel alignment (edit gun) ----------

const ALIGN_STEP := 0.004
const TRIM_STEP := 0.5


const MOUNT_LABELS := {
	"optic": "SIGHT",
	"muzzle": "MUZZLE",
	"laser": "LASER",
	"grip": "GRIP",
	"mag": "MAG",
}
## Which attachment must be fitted for a mount to be editable.
const MOUNT_REQUIRES := {
	"muzzle": "suppressor",
	"laser": "laser",
	"grip": "foregrip",
	"mag": "extended_mag",
}

var _active_mount := "optic"
var _mount_buttons: Dictionary = {}


func _build_align_controls() -> void:
	var container := stats_box.get_parent()

	var header := Label.new()
	header.text = "EDIT GUN"
	header.add_theme_color_override("font_color", ACCENT)
	header.add_theme_font_size_override("font_size", 18)
	container.add_child(header)

	var hint := Label.new()
	hint.text = "Tap a part, then nudge it\nuntil it sits right on the gun."
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.add_theme_font_size_override("font_size", 13)
	container.add_child(hint)

	# Mount selector: tap the part you want to move; it glows gold on
	# the 3D preview.
	var mount_row := HBoxContainer.new()
	mount_row.add_theme_constant_override("separation", 6)
	container.add_child(mount_row)
	for mount: String in MOUNT_LABELS:
		var button := Button.new()
		button.toggle_mode = true
		button.text = MOUNT_LABELS[mount]
		button.custom_minimum_size = Vector2(0, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(func() -> void:
			_active_mount = mount
			_refresh())
		mount_row.add_child(button)
		_mount_buttons[mount] = button

	container.add_child(_align_row("MOVE X", Vector3(-ALIGN_STEP, 0, 0), Vector3(ALIGN_STEP, 0, 0)))
	container.add_child(_align_row("MOVE Y", Vector3(0, -ALIGN_STEP, 0), Vector3(0, ALIGN_STEP, 0)))
	container.add_child(_align_row("MOVE Z", Vector3(0, 0, ALIGN_STEP), Vector3(0, 0, -ALIGN_STEP)))
	container.add_child(_trim_row("BARREL PITCH", Vector3(-TRIM_STEP, 0, 0), Vector3(TRIM_STEP, 0, 0)))
	container.add_child(_trim_row("BARREL YAW", Vector3(0, -TRIM_STEP, 0), Vector3(0, TRIM_STEP, 0)))

	var reset := Button.new()
	reset.text = "RESET SELECTED PART"
	reset.pressed.connect(func() -> void:
		LoadoutManager.set_mount_offset(_shown_path(), _active_mount, Vector3.ZERO)
		_refresh())
	container.add_child(reset)

	var reset_all := Button.new()
	reset_all.text = "RESET ALL EDITS"
	reset_all.pressed.connect(func() -> void:
		var path := _shown_path()
		LoadoutManager.set_optic_offset(path, Vector3.ZERO)
		LoadoutManager.set_aim_trim(path, Vector3.ZERO)
		for mount: String in MOUNT_REQUIRES:
			LoadoutManager.set_mount_offset(path, mount, Vector3.ZERO)
		_refresh())
	container.add_child(reset_all)


func _align_row(label_text: String, minus_delta: Vector3, plus_delta: Vector3) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var row_label := Label.new()
	row_label.text = label_text
	row_label.custom_minimum_size = Vector2(90, 0)
	row_label.add_theme_font_size_override("font_size", 14)
	row.add_child(row_label)

	for pair in [["-", minus_delta], ["+", plus_delta]]:
		var button := Button.new()
		button.text = pair[0]
		button.custom_minimum_size = Vector2(56, 0)
		var delta: Vector3 = pair[1]
		button.pressed.connect(func() -> void:
			var path := _shown_path()
			LoadoutManager.set_mount_offset(
				path, _active_mount,
				LoadoutManager.get_mount_offset(path, _active_mount) + delta)
			_refresh())
		row.add_child(button)
	return row


func _trim_row(label_text: String, minus_delta: Vector3, plus_delta: Vector3) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var row_label := Label.new()
	row_label.text = label_text
	row_label.custom_minimum_size = Vector2(100, 0)
	row_label.add_theme_font_size_override("font_size", 14)
	row.add_child(row_label)

	for pair in [["-", minus_delta], ["+", plus_delta]]:
		var button := Button.new()
		button.text = pair[0]
		button.custom_minimum_size = Vector2(56, 0)
		var delta: Vector3 = pair[1]
		button.pressed.connect(func() -> void:
			var path := _shown_path()
			LoadoutManager.set_aim_trim(path, LoadoutManager.get_aim_trim(path) + delta)
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


func _update_preview(weapon: WeaponData, fitted := PackedStringArray()) -> void:
	var previous_yaw := 0.6
	if _preview_rig != null:
		previous_yaw = _preview_rig.rotation.y
		_preview_rig.queue_free()
	_preview_rig = ViewmodelRig.new()
	_preview_rig.category = weapon.category
	_preview_rig.build_optic = weapon.build_optic
	_preview_rig.optic_type = LoadoutManager.get_optic(weapon.resource_path)
	_preview_rig.optic_offset = LoadoutManager.get_optic_offset(weapon.resource_path)
	_preview_rig.aim_trim_deg = LoadoutManager.get_aim_trim(weapon.resource_path)
	_preview_rig.mount_offsets = LoadoutManager.get_mount_offsets(weapon.resource_path)
	_preview_rig.attachments = fitted
	_preview_rig.target_length = weapon.view_length
	_preview_rig.rotation.y = previous_yaw
	_preview_holder.add_child(_preview_rig)
	# The rig animates itself for first-person; the preview only rotates.
	_preview_rig.set_process(false)
	# Glow the selected part after the rig has built its meshes.
	_preview_rig.highlight_mount.call_deferred(_active_mount)
