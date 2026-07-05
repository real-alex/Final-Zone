class_name WeaponData
extends Resource
## Stats for one weapon. New weapons are new .tres files, no code changes.

@export var display_name := "M4A1"
@export_enum("AR", "SMG", "DMR", "SNIPER", "SHOTGUN", "PISTOL") var category := 0
@export_enum("AUTO", "SEMI") var fire_mode := 0

@export_group("Viewmodel")
## GLB scene holding the gun (may contain many guns/parts).
@export_file("*.glb") var model_path := "res://Assets/Weapons/m4_carbine_with_attachment_set.glb"
## Branch inside the GLB that is this gun. Empty keeps everything.
@export var body_part := ""
## Extra branches kept as-placed (e.g. the seated magazine).
@export var keep_parts := PackedStringArray()
## Cosmetic scope branch mounted on the rail. Empty mounts nothing.
@export var scope_part := ""
## Builds the working red dot on the rail (ADS aligns through it).
@export var build_optic := true
## Normalized gun length in meters; bigger for sniper rifles.
@export var view_length := 0.85
## Set true if the model points backwards after auto-fit.
@export var flip_forward := false
## Pellets per trigger pull (shotguns fire several).
@export var pellets := 1

@export_group("Damage")
@export var damage := 25.0
@export var headshot_multiplier := 2.0
@export var max_range := 250.0

@export_group("Handling")
@export var fire_rate_rpm := 750.0
@export var magazine_size := 30
@export var reserve_ammo := 120
@export var reload_time := 2.2

@export_group("Accuracy")
@export var hip_spread_deg := 2.2
@export var ads_spread_deg := 0.12
@export var move_spread_add_deg := 1.4
@export var recoil_pitch_deg := 0.55
@export var recoil_yaw_deg := 0.3

@export_group("ADS")
## CoD/BattleBit-style aim down sights: time to fully raise the weapon.
@export var ads_time := 0.2
@export var ads_fov := 60.0

@export_group("Audio")
@export var fire_sound := "gunshot"
@export var reload_sound := "reload"

@export_group("Blueprint")
## Epic-blueprint flair: tracer color + a colored kill burst.
@export var tracer_color := Color(1.0, 0.85, 0.4)
@export var is_blueprint := false


## Set by with_attachments when a suppressor is fitted (quieter shots).
var suppressed := false


func get_fire_interval() -> float:
	return 60.0 / maxf(fire_rate_rpm, 1.0)


func get_fire_mode_name() -> String:
	return "AUTO" if fire_mode == 0 else "SEMI"


## Returns a copy with the given attachments' stat effects applied.
## Attachment names: suppressor, foregrip, laser, extended_mag.
func with_attachments(attachments: PackedStringArray) -> WeaponData:
	var modified: WeaponData = duplicate()
	if attachments.has("suppressor"):
		modified.suppressed = true
		modified.damage *= 0.92
		modified.recoil_pitch_deg *= 0.8
		modified.recoil_yaw_deg *= 0.8
		modified.ads_spread_deg *= 0.9
	if attachments.has("foregrip"):
		modified.recoil_pitch_deg *= 0.72
		modified.recoil_yaw_deg *= 0.72
		modified.ads_time *= 1.08
	if attachments.has("laser"):
		modified.hip_spread_deg *= 0.7
		modified.move_spread_add_deg *= 0.75
	if attachments.has("extended_mag"):
		modified.magazine_size = int(ceilf(magazine_size * 1.5))
		modified.reserve_ammo = int(ceilf(reserve_ammo * 1.25))
		modified.reload_time *= 1.15
		modified.ads_time *= 1.05
	return modified
