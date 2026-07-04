class_name HealthComponent
extends Node
## Reusable health for player and bots. Owners react through signals.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, attacker: Node, headshot: bool)
signal died(attacker: Node)

@export var max_health := 100.0

var current_health: float
var alive := true


func _ready() -> void:
	reset()


func reset() -> void:
	current_health = max_health
	alive = true
	health_changed.emit(current_health, max_health)


func take_damage(amount: float, attacker: Node = null, headshot: bool = false) -> void:
	if not alive:
		return
	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)
	damaged.emit(amount, attacker, headshot)
	if current_health <= 0.0:
		alive = false
		died.emit(attacker)


func heal(amount: float) -> void:
	if not alive:
		return
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)
