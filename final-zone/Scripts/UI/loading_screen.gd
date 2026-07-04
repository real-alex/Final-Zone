class_name LoadingScreen
extends Control
## Match loading screen: full-art background (drops in automatically when
## Assets/UI/loading_screen.png exists), real threaded-load progress bar,
## and rotating gameplay tips. The bottom band covers any loader baked
## into the artwork.

const ART_PATHS := [
	"res://Assets/UI/loading_screen.png",
	"res://Assets/UI/loading_screen.jpg",
	"res://Assets/UI/loading_screen.jpeg",
]
const MIN_TIME := 2.4
const TIP_INTERVAL := 3.0

const TIPS := [
	"Communicate with your team. Teamwork is the key to victory.",
	"Headshots deal double damage. Aim high.",
	"Aim down sights for pinpoint accuracy.",
	"Sprinting drains stamina — manage it between fights.",
	"Crouching steadies your aim and shrinks your profile.",
	"Reload behind cover, never in the open.",
	"Watch the kill feed to track the fight.",
	"Moving while shooting widens your spread.",
	"Use the catwalk for sightlines — but watch your back.",
]

## Rendered once off-screen while loading so their shaders compile before
## gameplay — first-draw compilation is the main mid-game hitch on ANGLE.
const WARMUP_SCENES := [
	"res://Assets/Characters/newcharater/Characterpack/black-squad-soldier-character.fbx",
	"res://Assets/Weapons/m4_carbine_with_attachment_set.glb",
	"res://Scenes/Weapons/impact_effect.tscn",
]

## Set by SceneManager before this screen is shown.
static var next_scene := "res://Scenes/Main/game.tscn"

@onready var art_rect: TextureRect = %ArtRect
@onready var fallback_root: Control = %FallbackRoot
@onready var progress_bar: ProgressBar = %LoadProgressBar
@onready var percent_label: Label = %PercentLabel
@onready var tip_label: Label = %TipLabel

var _elapsed := 0.0
var _tip_elapsed := 0.0
var _tip_index := 0
var _visual_progress := 0.0
var _finishing := false
var _load_started := false
var _use_threaded := true


func _ready() -> void:
	GameManager.release_mouse()
	art_rect.hide()
	for art_path: String in ART_PATHS:
		if ResourceLoader.exists(art_path):
			art_rect.texture = load(art_path)
			art_rect.show()
			fallback_root.hide()
			break
	_tip_index = randi() % TIPS.size()
	tip_label.text = TIPS[_tip_index]
	# Deferred one frame: requesting during _ready races the engine's
	# scene-change internals and the threaded parse fails.
	_start_load.call_deferred()


func _start_load() -> void:
	# The menu loads on the main thread: threaded loading of that scene
	# races engine internals and fails intermittently. The heavy game
	# scene threads reliably and is where streaming actually matters.
	_use_threaded = not next_scene.ends_with("main_menu.tscn")
	if _use_threaded:
		ResourceLoader.load_threaded_request(next_scene)
	_load_started = true


func _process(delta: float) -> void:
	if _finishing or not _load_started:
		return
	_elapsed += delta
	_cycle_tips(delta)

	var real_progress := 0.0
	var loaded := true
	if _use_threaded:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(next_scene, progress)
		real_progress = progress[0] if not progress.is_empty() else 0.0
		loaded = status == ResourceLoader.THREAD_LOAD_LOADED
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_finishing = true
			get_tree().change_scene_to_file(next_scene)
			return

	# The bar chases whichever is further: real load progress or the
	# minimum-time pacing, and only completes when the scene is ready.
	var pace := clampf(_elapsed / MIN_TIME, 0.0, 1.0)
	var target := maxf(real_progress, pace)
	if not loaded:
		target = minf(target, 0.96)
	_visual_progress = minf(_visual_progress + delta * 1.2, target)
	progress_bar.value = _visual_progress * 100.0
	percent_label.text = "%d%%" % int(_visual_progress * 100.0)

	if loaded and _elapsed >= MIN_TIME and _visual_progress >= 0.999:
		_finish()


func _cycle_tips(delta: float) -> void:
	_tip_elapsed += delta
	if _tip_elapsed < TIP_INTERVAL:
		return
	_tip_elapsed = 0.0
	_tip_index = (_tip_index + 1) % TIPS.size()
	var tween := create_tween()
	tween.tween_property(tip_label, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void: tip_label.text = TIPS[_tip_index])
	tween.tween_property(tip_label, "modulate:a", 1.0, 0.25)


func _finish() -> void:
	_finishing = true
	var packed: PackedScene
	if _use_threaded:
		packed = ResourceLoader.load_threaded_get(next_scene)
	else:
		packed = load(next_scene)
	await _warm_up_shaders()
	await SceneManager.fade_out()
	get_tree().change_scene_to_packed(packed)
	SceneManager.fade_in()


## Draws the heavy assets into a small hidden viewport for a few frames.
func _warm_up_shaders() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 1.0, 5.0)

	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-45, 30, 0)
	viewport.add_child(light)

	for scene_path: String in WARMUP_SCENES:
		if not ResourceLoader.exists(scene_path):
			continue
		var packed_asset: PackedScene = load(scene_path)
		var instance := packed_asset.instantiate()
		viewport.add_child(instance)
		if instance.has_method("restart"):
			instance.restart()

	for i in 4:
		await get_tree().process_frame
	viewport.queue_free()
