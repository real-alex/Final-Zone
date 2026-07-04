class_name SniperScopeOverlay
extends Control
## Full-screen sniper scope picture: black surround outside the ocular
## circle, a mil-dot reticle, and a faint lens vignette. Only draws for the
## "sniper" optic; red-dot and holo optics use their 3D reticle instead so
## every optic looks different. Driven each frame by the weapon's scope
## fraction (0 = not scoped, 1 = fully scoped).

var _fraction := 0.0
var _optic_type := "sniper"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	hide()


func set_scope_view(fraction: float, optic_type: String) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	_optic_type = optic_type
	visible = _fraction > 0.01 and _optic_type == "sniper"
	queue_redraw()


func _draw() -> void:
	if _fraction <= 0.01 or _optic_type != "sniper":
		return

	var alpha := ease(_fraction, -2.0)
	var center := size * 0.5
	var radius := minf(size.x, size.y) * lerpf(0.30, 0.40, alpha)
	var black := Color(0.0, 0.0, 0.0, alpha)
	var line := Color(0.02, 0.02, 0.02, 0.96 * alpha)
	var reticle := Color(0.03, 0.03, 0.03, 0.98 * alpha)

	# Black surround outside the ocular circle (four rects around it).
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, center.y - radius)), black)
	draw_rect(Rect2(Vector2(0, center.y + radius), Vector2(size.x, size.y - center.y - radius)), black)
	draw_rect(Rect2(Vector2.ZERO, Vector2(center.x - radius, size.y)), black)
	draw_rect(Rect2(Vector2(center.x + radius, 0), Vector2(size.x - center.x - radius, size.y)), black)

	# Lens vignette: a soft dark ring hugging the inside edge.
	draw_arc(center, radius * 0.985, 0.0, TAU, 128, Color(0, 0, 0, 0.5 * alpha), radius * 0.06, true)
	# Scope tube rim and a faint glint highlight.
	draw_arc(center, radius, 0.0, TAU, 128, line, 5.0, true)
	draw_arc(center, radius - 4.0, 0.0, TAU, 128, Color(0.5, 0.55, 0.6, 0.14 * alpha), 2.0, true)

	# Mil-dot crosshair: thin inner cross, heavy outer posts, center gap.
	var gap := 10.0
	for axis in [Vector2(1, 0), Vector2(0, 1)]:
		draw_line(center + axis * gap, center + axis * radius * 0.62, reticle, 1.5, true)
		draw_line(center - axis * gap, center - axis * radius * 0.62, reticle, 1.5, true)
		draw_line(center + axis * radius * 0.62, center + axis * radius, reticle, 3.5, true)
		draw_line(center - axis * radius * 0.62, center - axis * radius, reticle, 3.5, true)
		for step in [0.20, 0.34, 0.48]:
			draw_circle(center + axis * radius * step, 2.0, reticle)
			draw_circle(center - axis * radius * step, 2.0, reticle)

	# Center aiming dot.
	draw_circle(center, 1.6, Color(0.6, 0.05, 0.03, alpha))
