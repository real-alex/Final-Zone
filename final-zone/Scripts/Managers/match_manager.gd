extends Node
## Score keeping and win condition for a deathmatch round.
## Respawning is handled by the match scene; this node only tracks state.
## Autoload: MatchManager

signal score_changed(player_kills: int, bot_kills: int)
signal kill_occurred(killer_name: String, victim_name: String, headshot: bool)
signal match_ended(player_won: bool)

const KILLS_TO_WIN := 10
const RESPAWN_DELAY := 3.0

var player_kills := 0
var bot_kills := 0
var match_active := false


func start_match() -> void:
	player_kills = 0
	bot_kills = 0
	match_active = true
	GameManager.state = GameManager.GameState.PLAYING
	score_changed.emit(player_kills, bot_kills)


func register_kill(killer_name: String, victim_name: String, by_player: bool, headshot: bool = false) -> void:
	if not match_active:
		return
	if by_player:
		player_kills += 1
	else:
		bot_kills += 1
	score_changed.emit(player_kills, bot_kills)
	kill_occurred.emit(killer_name, victim_name, headshot)

	if player_kills >= KILLS_TO_WIN or bot_kills >= KILLS_TO_WIN:
		end_match(player_kills >= KILLS_TO_WIN)


func end_match(player_won: bool) -> void:
	if not match_active:
		return
	match_active = false
	GameManager.state = GameManager.GameState.MATCH_OVER
	match_ended.emit(player_won)
