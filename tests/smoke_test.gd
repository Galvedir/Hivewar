extends Node
## Headless smoke test (§16 step 10-11): plays several full AI-vs-AI matches
## across all four deck pairings end to end through the same TurnManager API
## a human UI would use, to validate the whole Phase 1 engine loop without
## needing to click through a UI. Run with:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . res://tests/SmokeTest.tscn

func _ready() -> void:
	print("=== Hivewar Phase 1 smoke test ===")
	var pairings := [
		["white_hive_guardians", "black_venom_broodmother"],
		["green_wildgrowth", "blue_skyswarm"],
		["white_hive_guardians", "blue_skyswarm"],
		["black_venom_broodmother", "green_wildgrowth"],
		["red_bloodhunt", "white_hive_guardians"],
		["red_bloodhunt", "hybrid_venomwing"],
		["hybrid_venomwing", "green_wildgrowth"],
	]
	var runs_per_pairing := 3
	var total := 0
	var stalemates := 0

	for pairing: Array in pairings:
		var deck_ids: Array[String] = [pairing[0], pairing[1]]
		for run in range(runs_per_pairing):
			total += 1
			var starting := run % 2
			var result := _play_match(deck_ids, starting)
			print("[%s vs %s | start P%d] %s" % [deck_ids[0], deck_ids[1], starting, result])
			if result.begins_with("STALEMATE"):
				stalemates += 1

	print("")
	print("=== %d/%d matches completed cleanly, %d stalemates ===" % [total - stalemates, total, stalemates])
	get_tree().quit()

func _play_match(deck_ids: Array[String], starting_player: int) -> String:
	TurnManager.start_game(deck_ids, starting_player)
	GameState.players[0].is_ai = true
	GameState.players[1].is_ai = true

	var safety := 0
	while not GameState.is_over and safety < 200:
		AIPlayer.take_turn(GameState.active_player_index)
		safety += 1

	if GameState.is_over:
		return "won by P%d (%s) in %d turns — final health P0:%d P1:%d" % [
			GameState.winner_id, GameState.players[GameState.winner_id].leader.data.card_name,
			GameState.turn_number, GameState.players[0].health, GameState.players[1].health
		]
	return "STALEMATE after %d turns — health P0:%d P1:%d" % [safety, GameState.players[0].health, GameState.players[1].health]
