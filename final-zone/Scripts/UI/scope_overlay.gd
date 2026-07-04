class_name SniperScopeOverlay
extends Control

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
	var radius := minf(size.x, size.y) * lerpf(0.29, 0.38, alpha)
	var black := Color(0.0, 0.0, 0.0, 0.88 * alpha)
	var line := Color(0.02, 0.02, 0.02, 0.95 * alpha)
	var glow := Color(0.85, 0.95, 1.0, 0.18 * alpha)

	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, center.y - radius)), black)
	draw_rect(Rect2(Vector2(0, center.y + radius), Vector2(size.x, size.y - center.y - radius)), black)
	draw_rect(Rect2(Vector2.ZERO, Vector2(center.x - radius, size.y)), black)
	draw_rect(Rect2(Vector2(center.x + radius, 0), Vector2(size.x - center.x - radius, size.y)), black)

	draw_arc(center, radius, 0.0, TAU, 96, line, 6.0, true)
	draw_arc(center, radius - 5.0, 0.0, TAU, 96, glow, 2.0, true)
	draw_line(center + Vector2(-radius * 0.55, 0), center + Vector2(-12, 0), line, 2.0, true)
	draw_line(center + Vector2(12, 0), center + Vector2(radius * 0.55, 0), line, 2.0, true)
	draw_line(center + Vector2(0, -radius * 0.55), center + Vector2(0, -12), line, 2.0, true)
	draw_line(center + Vector2(0, 12), center + Vector2(0, radius * 0.55), line, 2.0, true)
	draw_circle(center, 2.5, Color(0.05, 0.05, 0.05, 0.9 * alpha))
