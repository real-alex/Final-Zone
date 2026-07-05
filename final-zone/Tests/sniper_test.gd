extends Node3D
## Renders the sniper scope overlay at full scope over a simple 3D scene
## to verify it is see-through (world visible in the ocular) with a reticle.

const OUT_DIR_SETTING := "FZ_SHOT_DIR"

var _frame := 0
var _overlay: SniperScopeOverlay


func _ready() -> void:
	# Simple 3D scene so we can tell if the ocular is transparent.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.4, 0.55, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.9, 0.9)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1, 4)
	cam.fov = 34.0  # sniper zoom
	add_child(cam)

	for i in 6:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 1.5, 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.3, 0.2)
		box.material = mat
		m.mesh = box
		m.position = Vector3(-3 + i * 1.2, 0.75, -3)
		add_child(m)

	var layer := CanvasLayer.new()
	add_child(layer)
	_overlay = SniperScopeOverlay.new()
	layer.add_child(_overlay)
	_overlay.set_scope_view(1.0, "sniper")


func _process(_delta: float) -> void:
	_frame += 1
	_overlay.set_scope_view(1.0, "sniper")
	if _frame == 20:
		var img := get_viewport().get_texture().get_image()
		var out_dir := OS.get_environment(OUT_DIR_SETTING)
		if out_dir == "":
			out_dir = "user://"
		img.save_png(out_dir.path_join("sniper_scope.png"))
		print("saved sniper_scope.png")
		get_tree().quit()
