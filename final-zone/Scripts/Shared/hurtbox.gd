class_name Hurtbox
extends Area3D
## Damage receiver area. Forwards weapon hits to the scene root (the bot
## or player), marking head hits for the damage multiplier.

@export var is_head := false


func take_hit(damage: float, attacker: Node, headshot_multiplier: float = 1.0) -> Dictionary:
	var target := owner
	if target == null or not target.has_method("receive_damage"):
		return {"killed": false, "headshot": false, "damage": 0.0}
	var final_damage := damage * (headshot_multiplier if is_head else 1.0)
	var result: Dictionary = target.receive_damage(final_damage, attacker, is_head)
	result["damage"] = final_damage
	return result
