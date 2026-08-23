extends Node
## Drives the real Main.tscn UI programmatically (no real input events
## available headless) to validate the signal-wired path a human player
## actually uses — distinct from tests/smoke_test.gd, which calls
## AIPlayer.take_turn() directly and never exercises TurnManager's
## turn_started signal -> UI -> AIPlayer wiring.

const MainScene := preload("res://scenes/Main.tscn")

func _ready() -> void:
	print("=== LARVA UI-drive test ===")
	var main := MainScene.instantiate()
	add_child(main)
	# Blue has zero Guard creatures, guaranteeing the optional block-prompt
	# path (§7) triggers whenever the AI attacks the human's Leader — this
	# exercises TurnManager.block_decision_requested / submit_block_choice,
	# which the other automated tests never touch (AI-vs-AI never blocks
	# optionally; it only ever hits the forced-Guard or Pierce paths).
	TurnManager.block_decision_requested.connect(func(attacker: CardInstance, options: Array[CardInstance]) -> void:
		print("  [block prompt] %s attacking Leader, %d option(s) — declining" % [attacker.display_name(), options.size()])
		# call_deferred simulates a real player's click landing on a later
		# frame (after _request_human_block's `await` has started listening),
		# not synchronously inside this same emit() call.
		TurnManager.call_deferred("submit_block_choice", null))
	main._on_deck_chosen("blue_skyswarm")

	var safety := 0
	while not GameState.is_over and safety < 100:
		if GameState.active_player_index == 0 and not GameState.players[0].is_ai:
			var human := GameState.players[0]
			var tries := 0
			while tries < 6 and not human.hand.is_empty():
				main._on_hand_card_pressed(0)
				tries += 1
			for c: CardInstance in human.board.duplicate():
				if CombatResolver.can_attack(c):
					main._on_board_creature_pressed(c, true)
					await main._on_enemy_leader_pressed()
			main._on_end_turn_pressed()
		else:
			# It's the AI's turn (or its coroutine is suspended waiting on a
			# deferred block response) — yield to the engine so frame
			# processing/deferred calls can actually run, instead of
			# busy-spinning the safety counter with nothing happening.
			await get_tree().process_frame
		safety += 1

	print("")
	if GameState.is_over:
		print("UI-drive test: GAME OVER after %d turns — winner P%d, final health P0:%d P1:%d" % [
			GameState.turn_number, GameState.winner_id, GameState.players[0].health, GameState.players[1].health
		])
	else:
		print("UI-drive test: SAFETY CAP after %d loop iterations — health P0:%d P1:%d" % [
			safety, GameState.players[0].health, GameState.players[1].health
		])
	get_tree().quit()
