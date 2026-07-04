class_name HitMarker
extends Control
## X-shaped hit confirmation. White for body hits, red for headshots.

const INNER := 5.0
const OUTER := 13.0
const THICKNESS := 2.0

var _color := Color.WHITE
var _tween: Tween


func _ready() -> void:
	modulate.a = 0.0


func _draw() -> void:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			draw_line(
				Vector2(INNER * sx, INNER * sy),
				Vector2(OUTER * sx, OUTER * sy),
				_color, THICKNESS
			)


func flash(headshot: bool = false) -> void:
	_color = Color(1.0, 0.25, 0.2) if headshot else Color.WHITE
	queue_redraw()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.3).set_delay(0.05)
