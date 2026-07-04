extends Node3D
## One-shot bullet impact sparks; frees itself when done.


func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	queue_free()
