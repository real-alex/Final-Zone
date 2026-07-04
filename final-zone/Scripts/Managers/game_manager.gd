extends Node
## Global game state: current mode, selected difficulty, mouse capture.
## Autoload: GameManager

enum GameState { MENU, PLAYING, PAUSED, MATCH_OVER }
enum Difficulty { EASY, MEDIUM, HARD }

## Bot tuning per difficulty. reaction_time in seconds, aim_spread in
## degrees of cone half-angle, damage per bullet.
const DIFFICULTY_PRESETS := {
	Difficulty.EASY: {
		"name": "Easy",
		"reaction_time": 0.8,
		"aim_spread_deg": 6.0,
		"damage": 8.0,
		"fire_interval": 0.28,
		"move_speed": 3.5,
	},
	Difficulty.MEDIUM: {
		"name": "Medium",
		"reaction_time": 0.45,
		"aim_spread_deg": 3.5,
		"damage": 12.0,
		"fire_interval": 0.2,
		"move_speed": 4.2,
	},
	Difficulty.HARD: {
		"name": "Hard",
		"reaction_time": 0.22,
		"aim_spread_deg": 1.8,
		"damage": 16.0,
		"fire_interval": 0.14,
		"move_speed": 5.0,
	},
}

signal state_changed(new_state: GameState)

var state: GameState = GameState.MENU:
	set(value):
		if state == value:
			return
		state = value
		state_changed.emit(state)

var difficulty: Difficulty = Difficulty.MEDIUM


func get_difficulty_preset() -> Dictionary:
	return DIFFICULTY_PRESETS[difficulty]


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_gameplay_active() -> bool:
	return state == GameState.PLAYING
