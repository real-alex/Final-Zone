extends Control
## Operator customization: name, helmet/armor toggles, uniform color — with
## a live rotating 3D preview. Persists via CustomizeManager.

signal closed

const ACCENT := Color(1, 0.706, 0)

@onready var name_edit: LineEdit = %NameEdit
@onready var helmet_check: CheckButton = %HelmetCheck
@onready var armor_check: CheckButton = %ArmorCheck
@onready var colors_row: HBoxContainer = %ColorsRow
@onready var preview_container: SubViewportContainer = %PreviewContainer
@onready var back_button: Button = %CustomizeBackButton

var _viewport: SubViewport
var _preview_holder: Node3D
var _preview_rig: Node3D


func _ready() -> void:
	_build_preview()
	_build_color_buttons()
	name_edit.text = CustomizeManager.operator_name
	helmet_check.button_pressed = CustomizeManager.show_helmet
	armor_check.button_pressed = CustomizeManager.show_armor
	name_edit.text_submitted.connect(func(t: String) -> void: CustomizeManager.set_name_text(t))
	name_edit.text_changed.connect(func(t: String) -> void: CustomizeManager.set_name_text(t))
	helmet_check.toggled.connect(func(on: bool) -> void: CustomizeManager.set_helmet(on); _rebuild())
	armor_check.toggled.connect(func(on: bool) -> void: CustomizeManager.set_armor(on); _rebuild())
	back_button.pressed.connect(func() -> void: hide(); closed.emit())
	_rebuild()


func _process(delta: float) -> void:
	if visible and _preview_rig != null:
		_preview_rig.rotate_y(delta * 0.6)


func _build_color_buttons() -> void:
	for preset_name: String in CustomizeManager.UNIFORM_PRESETS:
		var color: Color = CustomizeManager.UNIFORM_PRESETS[preset_name]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(90, 40)
		btn.text = preset_name
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_border_width_all(2)
		sb.border_color = Color(0, 0, 0, 0.5)
		btn.add_theme_stylebox_override("normal", sb)
		btn.pressed.connect(func() -> void: CustomizeManager.set_uniform(color); _rebuild())
		colors_row.add_child(btn)


func _build_preview() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(420, 620)
	preview_container.add_child(_viewport)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 3.0)
	cam.fov = 42.0
	_viewport.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.4
	_viewport.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, 1, 2)
	fill.light_energy = 0.6
	_viewport.add_child(fill)

	_preview_holder = Node3D.new()
	_viewport.add_child(_preview_holder)


func _rebuild() -> void:
	var yaw := 0.5
	if _preview_rig != null:
		yaw = _preview_rig.rotation.y
		_preview_rig.queue_free()
	_preview_rig = SoldierRig.new()
	_preview_rig.set("use_player_customization", true)
	_preview_rig.rotation.y = yaw
	_preview_holder.add_child(_preview_rig)
