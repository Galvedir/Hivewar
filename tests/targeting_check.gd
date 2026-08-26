extends Node
## Regression check for player-directed targeting (buff/damage/bounce
## effects and Hero Power/Ultimate should make the human choose a target,
## not auto-pick). Drives the real Main.tscn UI, not TurnManager directly,
## since the targeting flow lives in main_ui.gd.

const MainScene := preload("res://scenes/Main.tscn")

var _failures := 0

func _ready() -> void:
	print("=== Targeting UI check ===")
	var main := MainScene.instantiate()
	add_child(main)
	await main._on_deck_chosen("white_hive_guardians") # human = White (Queen Amara) vs a random AI deck; starting a match now shows a brief loading beat first

	var human: PlayerState = GameState.players[0]
	var ai: PlayerState = GameState.players[1]

	# Get a friendly creature onto the board as the only legal "friendly" target.
	_put_in_hand(human, "worker_termite")
	main._on_hand_card_pressed(_hand_index(human, "worker_termite"))
	_check(human.board.size() == 1, "Worker Termite entered play")
	var termite: CardInstance = human.board[0]

	# Royal Jelly (heal_leader + buff_friendly, on_cast) must prompt for a target.
	_put_in_hand(human, "royal_jelly")
	var idx := _hand_index(human, "royal_jelly")
	main._on_hand_card_pressed(idx)
	_check(main._selected_hand_index == idx, "Playing Royal Jelly enters targeting mode instead of resolving immediately")
	_check(main._pending_target_side == "friendly", "Royal Jelly asks for a friendly target")

	# Clicking an enemy creature (wrong side) must be rejected, not consumed.
	var enemy_inst := CardDatabase.create_instance("black_widow_stalker", 1)
	ai.board.append(enemy_inst)
	main._on_board_creature_pressed(enemy_inst, false)
	_check(main._selected_hand_index == idx, "Clicking the wrong side does not consume the targeting selection")

	var atk_before := termite.current_attack
	var hp_before := termite.max_health
	main._on_board_creature_pressed(termite, true)
	_check(main._selected_hand_index == -1, "Clicking the correct friendly target resolves the card")
	_check(termite.current_attack == atk_before + 1 and termite.max_health == hp_before + 1, "Royal Jelly buffed the chosen creature (+1/+1), not an auto-picked one")

	# Hero Power (Queen Amara: buff_friendly + temp Guard) must also prompt.
	human.current_larva = 10
	main._on_hero_power_pressed()
	_check(main._pending_power_kind == "hero", "Hero Power enters targeting mode")
	main._on_board_creature_pressed(termite, true)
	_check(main._pending_power_kind == "", "Hero Power resolves once a friendly target is clicked")
	_check(termite.has_keyword("Guard"), "Hero Power's temp Guard landed on the chosen creature")

	# Gear must still work (regression) and should now be visible on the creature.
	_put_in_hand(human, "protective_ward")
	var gear_idx := _hand_index(human, "protective_ward")
	main._on_hand_card_pressed(gear_idx)
	_check(main._pending_target_side == "friendly" and main._selected_hand_index == gear_idx, "Gear still enters targeting mode")
	main._on_board_creature_pressed(termite, true)
	_check(not termite.attached_gear.is_empty(), "Gear attaches to the chosen creature")

	# Hive visibility: play a Hive card and confirm it lands in hive_zone (what _render_hive_row reads from).
	_put_in_hand(human, "termite_colony")
	main._on_hand_card_pressed(_hand_index(human, "termite_colony"))
	_check(human.hive_zone.size() == 1 and human.hive_zone[0].display_name() == "Termite Colony", "Hive card enters hive_zone (rendered by _render_hive_row)")

	# Legend Rule: a second copy of a Legendary must prompt the human, not auto-discard.
	_put_in_hand(human, "ladybug_swarm_queen")
	main._on_hand_card_pressed(_hand_index(human, "ladybug_swarm_queen"))
	var first_queens := human.board.filter(func(c: CardInstance) -> bool: return c.data.card_name == "Paper Wasp Queen")
	_check(first_queens.size() == 1, "First Paper Wasp Queen enters play without a Legend Rule prompt")
	var first_queen: CardInstance = first_queens[0]

	_put_in_hand(human, "ladybug_swarm_queen")
	var legend_prompted := [false] # array, not bool — GDScript lambdas capture outer locals by value, not by reference
	TurnManager.legend_rule_decision_requested.connect(func(new_card: CardInstance, existing: Array[CardInstance]) -> void:
		legend_prompted[0] = true
		TurnManager.call_deferred("submit_legend_choice", existing[0])) # choose to keep the one already in play
	var gy_before := human.graveyard.size()
	await main._on_hand_card_pressed(_hand_index(human, "ladybug_swarm_queen"))
	var safety := 0
	while human.graveyard.size() == gy_before and safety < 30:
		await get_tree().process_frame
		safety += 1
	_check(legend_prompted[0], "Playing a second Legendary prompts the human for a choice")
	_check(human.board.has(first_queen), "Choosing to keep the existing copy leaves the original instance in play")
	_check(human.board.filter(func(c: CardInstance) -> bool: return c.data.card_name == "Paper Wasp Queen").size() == 1, "Exactly one Paper Wasp Queen remains in play")
	_check(human.graveyard.size() == gy_before + 1, "The new copy went to the graveyard instead of replacing the kept one")

	# Leaders must be immune to Poison (Poison creature attacking the Leader directly).
	var poison_bug := CardDatabase.create_instance("wasp_striker", 1) # Poison keyword
	ai.board.append(poison_bug)
	poison_bug.summoning_sick = false
	var health_before := human.health
	CombatResolver.resolve_attack(poison_bug, "leader", ai, human)
	_check(human.health == health_before - poison_bug.current_attack, "Poison attacker still deals its normal damage to the Leader")
	EffectResolver.fire_end_of_turn(human, ai)
	_check(human.health == health_before - poison_bug.current_attack, "Leader takes no extra damage from Poison at end of turn (Leaders are immune)")

	# Decking out is an instant loss (§ user request), checked at the turn draw.
	human.deck.clear()
	var human_health_before := human.health
	TurnManager.start_turn(0) # human is player index 0
	_check(GameState.is_over and GameState.winner_id == 1, "Drawing from an empty deck is an instant loss for that player")
	_check(human.health == human_health_before, "Decking out doesn't deal damage — it's a direct loss, not fatigue")

	print("")
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	get_tree().quit()

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] %s" % label)
	else:
		print("  [FAIL] %s" % label)
		_failures += 1

func _put_in_hand(player: PlayerState, card_id: String) -> void:
	player.current_larva = 10
	player.max_larva = 10
	player.hand.append(CardDatabase.create_instance(card_id, player.player_id))

func _hand_index(player: PlayerState, card_id: String) -> int:
	for i in range(player.hand.size()):
		if player.hand[i].data.id == card_id:
			return i
	return -1
