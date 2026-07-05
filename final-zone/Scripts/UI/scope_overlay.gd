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
	# Fall back to the viewport size if our own size hasn't been laid out
	# yet, so the scope always covers the screen.
	var view_size := size
	if view_size.x < 10.0 or view_size.y < 10.0:
		view_size = get_viewport_rect().size
	var center := view_size * 0.5
	# Big ocular so the magnified world fills most of the screen — the
	# glass is SEE-THROUGH; the FOV zoom does the magnifying.
	var radius := minf(view_size.x, view_size.y) * lerpf(0.34, 0.46, alpha)
	var black := Color(0.0, 0.0, 0.0, alpha)
	var reticle := Color(0.04, 0.05, 0.06, 0.95 * alpha)

	# Black eyepiece surround OUTSIDE the ocular only (four rects). Inside
	# the circle nothing is drawn opaque, so the zoomed scene shows through.
	draw_rect(Rect2(Vector2.ZERO, Vector2(view_size.x, center.y - radius)), black)
	draw_rect(Rect2(Vector2(0, center.y + radius), Vector2(view_size.x, view_size.y - center.y - radius)), black)
	draw_rect(Rect2(Vector2.ZERO, Vector2(center.x - radius, view_size.y)), black)
	draw_rect(Rect2(Vector2(center.x + radius, 0), Vector2(view_size.x - center.x - radius, view_size.y)), black)

	# Faint blue glass sheen + a thin soft edge shadow, so the view stays clear.
	draw_arc(center, radius * 0.5, 0.0, TAU, 96, Color(0.55, 0.7, 1.0, 0.04 * alpha), radius * 0.6, true)
	draw_arc(center, radius * 0.955, 0.0, TAU, 128, Color(0, 0, 0, 0.4 * alpha), radius * 0.07, true)
	# Scope tube rim + inner highlight.
	draw_arc(center, radius, 0.0, TAU, 128, Color(0.02, 0.02, 0.02, alpha), 6.0, true)
	draw_arc(center, radius - 5.0, 0.0, TAU, 128, Color(0.6, 0.65, 0.7, 0.18 * alpha), 1.5, true)

	# Fine mil-dot crosshair (thin so it doesn't block the target).
	for axis in [Vector2(1, 0), Vector2(0, 1)]:
		draw_line(center + axis * 8.0, center + axis * radius, reticle, 1.2, true)
		draw_line(center - axis * 8.0, center - axis * radius, reticle, 1.2, true)
		for step in [0.22, 0.40, 0.58, 0.76]:
			draw_circle(center + axis * radius * step, 1.6, reticle)
			draw_circle(center - axis * radius * step, 1.6, reticle)

	draw_circle(center, 1.4, Color(0.7, 0.08, 0.05, alpha))
