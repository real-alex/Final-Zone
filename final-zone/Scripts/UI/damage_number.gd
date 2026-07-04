class_name DamageNumber
extends Label3D
## Floating combat damage number: rises, then fades. Gold for headshots.

const RISE_HEIGHT := 0.55
const LIFETIME := 0.7


static func spawn(parent: Node, world_position: Vector3, amount: float, headshot: bool) -> void:
	var number := DamageNumber.new()
	number.text = str(int(roundf(amount)))
	number.modulate = Color(1.0, 0.78, 0.1) if headshot else Color(0.95, 0.95, 0.95)
	number.font_size = 60 if headshot else 44
	number.outline_size = 10
	number.outline_modulate = Color(0, 0, 0, 0.85)
	number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	number.fixed_size = true
	number.pixel_size = 0.0006
	number.no_depth_test = true
	parent.add_child(number)
	number.global_position = world_position + Vector3(
		randf_range(-0.06, 0.06), 0.12, randf_range(-0.06, 0.06)
	)
	number._animate()


func _animate() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y + RISE_HEIGHT, LIFETIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 0.0, LIFETIME * 0.45) \
		.set_delay(LIFETIME * 0.55)
	tween.tween_callback(queue_free)
