extends Node
## The player's equipped weapons and the weapon registry. Selections
## persist to user://loadout.cfg and the match reads them at spawn.
## Autoload: LoadoutManager

signal loadout_changed

const SAVE_PATH := "user://loadout.cfg"

## Every selectable weapon. New guns: add the .tres path here.
const WEAPON_PATHS := [
	"res://Resources/Weapons/m4a1.tres",
	"res://Resources/Weapons/g36c.tres",
	"res://Resources/Weapons/kriss_vector.tres",
	"res://Resources/Weapons/cz_scorpion.tres",
	"res://Resources/Weapons/sr25.tres",
	"res://Resources/Weapons/m24.tres",
]

const DEFAULT_PRIMARY := "res://Resources/Weapons/m4a1.tres"
const DEFAULT_SECONDARY := "res://Resources/Weapons/cz_scorpion.tres"

var primary_path := DEFAULT_PRIMARY
var secondary_path := DEFAULT_SECONDARY
## Per-weapon optic mount corrections (weapon path -> Vector3 offset),
## edited in the loadout screen when auto-placement sits wrong.
var _optic_offsets: Dictionary = {}


func _ready() -> void:
	_load()


func get_primary() -> WeaponData:
	return load(primary_path)


func get_secondary() -> WeaponData:
	return load(secondary_path)


func get_all_weapons() -> Array[WeaponData]:
	var weapons: Array[WeaponData] = []
	for path in WEAPON_PATHS:
		weapons.append(load(path))
	return weapons


## Assigns a weapon to a slot; picking the other slot's weapon swaps them.
func assign(slot: int, weapon_path: String) -> void:
	if slot == 0:
		if weapon_path == secondary_path:
			secondary_path = primary_path
		primary_path = weapon_path
	else:
		if weapon_path == primary_path:
			primary_path = secondary_path
		secondary_path = weapon_path
	_save()
	loadout_changed.emit()


const ATTACHMENT_NAMES := ["suppressor", "foregrip", "laser", "extended_mag"]
const OPTIC_TYPES := ["red_dot", "holo", "sniper"]

## Per-weapon fitted attachments (weapon path -> PackedStringArray).
var _attachments: Dictionary = {}
## Per-weapon barrel angle corrections (weapon path -> Vector3 degrees).
var _aim_trims: Dictionary = {}
## Per-weapon optic choice (weapon path -> String).
var _optics: Dictionary = {}


## Snipers default to the magnified scope, everything else to the red dot.
func get_optic(weapon_path: String) -> String:
	if _optics.has(weapon_path):
		return _optics[weapon_path]
	if weapon_path == "":
		return "red_dot"
	var weapon: WeaponData = load(weapon_path)
	return "sniper" if weapon != null and weapon.category == 3 else "red_dot"


func cycle_optic(weapon_path: String) -> void:
	var index := OPTIC_TYPES.find(get_optic(weapon_path))
	_optics[weapon_path] = OPTIC_TYPES[(index + 1) % OPTIC_TYPES.size()]
	_save()
	loadout_changed.emit()


func set_optic(weapon_path: String, optic_type: String) -> void:
	if weapon_path == "":
		return
	if not OPTIC_TYPES.has(optic_type):
		return
	if get_optic(weapon_path) == optic_type:
		return
	_optics[weapon_path] = optic_type
	_save()
	loadout_changed.emit()


func get_aim_trim(weapon_path: String) -> Vector3:
	return _aim_trims.get(weapon_path, Vector3.ZERO)


func set_aim_trim(weapon_path: String, trim_deg: Vector3) -> void:
	if trim_deg == Vector3.ZERO:
		_aim_trims.erase(weapon_path)
	else:
		_aim_trims[weapon_path] = trim_deg
	_save()


func get_attachments(weapon_path: String) -> PackedStringArray:
	return _attachments.get(weapon_path, PackedStringArray())


func toggle_attachment(weapon_path: String, attachment: String) -> void:
	var fitted := get_attachments(weapon_path)
	if fitted.has(attachment):
		fitted.remove_at(fitted.find(attachment))
	else:
		fitted.append(attachment)
	if fitted.is_empty():
		_attachments.erase(weapon_path)
	else:
		_attachments[weapon_path] = fitted
	_save()
	loadout_changed.emit()


func get_optic_offset(weapon_path: String) -> Vector3:
	return _optic_offsets.get(weapon_path, Vector3.ZERO)


func set_optic_offset(weapon_path: String, offset: Vector3) -> void:
	if offset == Vector3.ZERO:
		_optic_offsets.erase(weapon_path)
	else:
		_optic_offsets[weapon_path] = offset
	_save()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var saved_primary: String = config.get_value("loadout", "primary", DEFAULT_PRIMARY)
	var saved_secondary: String = config.get_value("loadout", "secondary", DEFAULT_SECONDARY)
	if WEAPON_PATHS.has(saved_primary):
		primary_path = saved_primary
	if WEAPON_PATHS.has(saved_secondary):
		secondary_path = saved_secondary
	if config.has_section("optic_offsets"):
		for key in config.get_section_keys("optic_offsets"):
			_optic_offsets[key] = config.get_value("optic_offsets", key)
	if config.has_section("attachments"):
		for key in config.get_section_keys("attachments"):
			_attachments[key] = config.get_value("attachments", key)
	if config.has_section("aim_trims"):
		for key in config.get_section_keys("aim_trims"):
			_aim_trims[key] = config.get_value("aim_trims", key)
	if config.has_section("optics"):
		for key in config.get_section_keys("optics"):
			_optics[key] = config.get_value("optics", key)


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("loadout", "primary", primary_path)
	config.set_value("loadout", "secondary", secondary_path)
	for key in _optic_offsets:
		config.set_value("optic_offsets", key, _optic_offsets[key])
	for key in _attachments:
		config.set_value("attachments", key, _attachments[key])
	for key in _aim_trims:
		config.set_value("aim_trims", key, _aim_trims[key])
	for key in _optics:
		config.set_value("optics", key, _optics[key])
	config.save(SAVE_PATH)
