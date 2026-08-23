extends Node
## Autoload: phase sequencing and the player-facing action API (§13). Both
## the human UI and AIPlayer call these same functions — neither talks to
## GameState/CombatResolver/EffectResolver directly for player actions,
## keeping a single validated entry point per action.

const MAX_LARVA_CAP := 10
const MAX_HAND_SIZE := 10 # PROPOSED — not numerically specified in the spec; standard CCG default.

signal game_started
signal turn_started(player_id: int)
signal turn_ended(player_id: int)
signal attack_resolved(attacker_instance_id: int)
signal block_decision_requested(attacker: CardInstance, legal_blockers: Array[CardInstance])
signal block_decision_made

var _pending_block_choice: CardInstance = null

func start_game(deck_ids: Array[String], starting_player_index: int = 0) -> void:
	GameState.setup_game(deck_ids, starting_player_index)
	for player: PlayerState in GameState.players:
		for i in range(3):
			player.draw_card()
	game_started.emit()
	start_turn(GameState.active_player_index)

func start_turn(player_index: int) -> void:
	var player := GameState.players[player_index]
	var opponent := GameState.get_opponent(player_index)
	player.max_larva = min(player.max_larva + 1, MAX_LARVA_CAP)
	player.current_larva = player.max_larva
	player.temp_larva_bonus = 0
	player.draw_card()
	for c: CardInstance in player.board:
		c.summoning_sick = false
		c.has_attacked_this_turn = false
	player.leader.hero_power_used_this_turn = false
	GameState.turn_number += 1
	EffectResolver.fire_start_of_turn(player, opponent)
	turn_started.emit(player_index)

func end_turn() -> void:
	if GameState.is_over:
		return
	var player_index := GameState.active_player_index
	var player := GameState.players[player_index]
	var opponent := GameState.get_opponent(player_index)
	for c: CardInstance in player.board:
		c.temp_keywords.clear()
	while player.hand.size() > MAX_HAND_SIZE:
		player.graveyard.append(player.hand.pop_back())
	EffectResolver.fire_end_of_turn(player, opponent)
	turn_ended.emit(player_index)
	if GameState.is_over:
		return
	GameState.active_player_index = 1 - player_index
	start_turn(GameState.active_player_index)

## --- Player actions --------------------------------------------------------

## Plays hand[hand_index]. `target_instance_id` is used for Gear's equip
## target and passed through to on_play/on_cast effect resolution for
## cards whose effect needs a target (e.g. a removal Ability).
func play_card(player_index: int, hand_index: int, target_instance_id: int = -1) -> bool:
	if GameState.is_over:
		return false
	var player := GameState.players[player_index]
	var opponent := GameState.get_opponent(player_index)
	if hand_index < 0 or hand_index >= player.hand.size():
		return false
	var card_inst: CardInstance = player.hand[hand_index]
	var cost := CostCalculator.calculate_cost(card_inst.data, player.leader.data)
	if cost > player.current_larva:
		return false

	if card_inst.data.card_type == CardTypes.GEAR:
		var gear_target := player.find_on_board(target_instance_id)
		if gear_target == null:
			return false

	player.hand.remove_at(hand_index)
	player.current_larva -= cost

	match card_inst.data.card_type:
		CardTypes.CREATURE:
			if card_inst.data.is_legendary:
				for dup: CardInstance in player.legendary_copies_in_play(card_inst.data.card_name):
					player.board.erase(dup)
					player.graveyard.append(dup)
			player.board.append(card_inst)
			EffectResolver.apply_hive_bonuses_on_enter(card_inst, player)
			EffectResolver.fire_on_play(card_inst, player, opponent, target_instance_id)
		CardTypes.ABILITY:
			EffectResolver.fire_on_cast(card_inst.data, player, opponent, target_instance_id)
			player.graveyard.append(card_inst)
		CardTypes.GEAR:
			GameState.attach_gear(card_inst, player.find_on_board(target_instance_id))
		CardTypes.HIVE:
			player.hive_zone.append(card_inst)
			EffectResolver.apply_new_hive_to_board(card_inst, player)

	GameState.cleanup_dead(player.player_id)
	GameState.cleanup_dead(opponent.player_id)
	return true

func use_hero_power(player_index: int, target_instance_id: int = -1) -> bool:
	if GameState.is_over:
		return false
	var player := GameState.players[player_index]
	var opponent := GameState.get_opponent(player_index)
	if player.leader.hero_power_used_this_turn:
		return false
	var cost := player.leader.data.hero_power_cost
	if cost > player.current_larva:
		return false
	player.current_larva -= cost
	player.leader.hero_power_used_this_turn = true
	EffectResolver.resolve_effect_list(player.leader.data.hero_power_effects, player, opponent, target_instance_id)
	return true

func use_ultimate(player_index: int, target_instance_id: int = -1) -> bool:
	if GameState.is_over:
		return false
	var player := GameState.players[player_index]
	var opponent := GameState.get_opponent(player_index)
	if player.leader.ultimate_used:
		return false
	var cost := player.leader.data.ultimate_cost
	if cost > player.current_larva:
		return false
	player.current_larva -= cost
	player.leader.ultimate_used = true
	EffectResolver.resolve_effect_list(player.leader.data.ultimate_effects, player, opponent, target_instance_id)
	return true

## Ambush's "paid" flip trigger (§8) — flips a face-down creature the
## controller already has in play, any time during their main phase.
func flip_ambush_paid(player_index: int, board_instance_id: int) -> bool:
	if GameState.is_over:
		return false
	var player := GameState.players[player_index]
	var c := player.find_on_board(board_instance_id)
	if c == null or not c.is_face_down or c.true_data == null:
		return false
	if c.true_data.ambush.get("flip_trigger", "") != "paid":
		return false
	var cost := int(c.true_data.ambush.get("flip_cost", 0))
	if cost > player.current_larva:
		return false
	player.current_larva -= cost
	EffectResolver.flip_paid(c)
	return true

## Declares an attack. `target` is the String "leader", or a CardInstance
## for a direct creature-vs-creature duel (including a Guard the caller
## already chose to redirect to). Suspends (via await) if the defender is
## human and an optional block is available — the caller should `await`
## this too, or listen for `attack_resolved`.
func declare_attack(attacker_player_index: int, attacker_instance_id: int, target) -> void:
	if GameState.is_over:
		return
	var player := GameState.players[attacker_player_index]
	var opponent := GameState.get_opponent(attacker_player_index)
	var attacker := player.find_on_board(attacker_instance_id)
	if attacker == null or not CombatResolver.can_attack(attacker):
		return

	if target is String and target == "leader":
		if not CombatResolver.is_legal_leader_target(attacker, opponent):
			return
		var options := CombatResolver.legal_block_options(attacker, opponent)
		var block_choice: CardInstance = null
		if not options.is_empty():
			if opponent.is_ai:
				block_choice = AIPlayer.choose_block(opponent, attacker, options)
			else:
				block_choice = await _request_human_block(attacker, options)
		CombatResolver.resolve_attack(attacker, "leader", player, opponent, block_choice)
	else:
		var creature_target: CardInstance = target
		if not CombatResolver.is_legal_creature_target(attacker, creature_target):
			return
		CombatResolver.resolve_attack(attacker, creature_target, player, opponent, null)

	attack_resolved.emit(attacker_instance_id)

func _request_human_block(attacker: CardInstance, options: Array[CardInstance]) -> CardInstance:
	block_decision_requested.emit(attacker, options)
	await block_decision_made
	return _pending_block_choice

## Called by the UI once the human defender has chosen (or declined) a block.
func submit_block_choice(choice: CardInstance) -> void:
	_pending_block_choice = choice
	block_decision_made.emit()
