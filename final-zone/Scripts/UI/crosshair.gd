class_name DynamicCrosshair
extends Control
## Four-line crosshair with a center dot. Spread widens with weapon
## inaccuracy (hip fire, movement) and collapses when aiming.

const LINE_LENGTH := 8.0
const THICKNESS := 2.0

var spread := 6.0:
	set(value):
		spread = value
		queue_redraw()

var color := Color(0.95, 0.95, 0.95, 0.9)


func _draw() -> void:
	draw_rect(Rect2(-1.0, -1.0, 2.0, 2.0), color)
	draw_rect(Rect2(spread, -THICKNESS * 0.5, LINE_LENGTH, THICKNESS), color)
	draw_rect(Rect2(-spread - LINE_LENGTH, -THICKNESS * 0.5, LINE_LENGTH, THICKNESS), color)
	draw_rect(Rect2(-THICKNESS * 0.5, spread, THICKNESS, LINE_LENGTH), color)
	draw_rect(Rect2(-THICKNESS * 0.5, -spread - LINE_LENGTH, THICKNESS, LINE_LENGTH), color)
