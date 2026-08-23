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
signal legend_rule_decision_requested(new_card: CardInstance, existing_copies: Array[CardInstance])
signal legend_rule_decision_made

var _pending_block_choice: CardInstance = null
var _pending_legend_keep: CardInstance = null

func start_game(deck_ids: Array[String], starting_player_index: int = 0) -> void:
	GameState.setup_game(deck_ids, starting_player_index)
	for player: PlayerState in GameState.players:
		for i in range(3):
			player.draw_card()
	game_started.emit()
	start_turn(GameState.active_player_index)

func _actor(player: PlayerState) -> String:
	return player.leader.data.card_name

func start_turn(player_index: int) -> void:
	var player := GameState.players[player_index]
	var opponent := GameState.get_opponent(player_index)
	player.max_larva = min(player.max_larva + 1, MAX_LARVA_CAP)
	player.current_larva = player.max_larva
	player.temp_larva_bonus = 0
	var drawn := player.draw_card()
	for c: CardInstance in player.board:
		c.summoning_sick = false
		c.has_attacked_this_turn = false
	player.leader.hero_power_used_this_turn = false
	GameState.turn_number += 1
	GameLog.log("— Turn %d: %s's turn (Larva %d/%d, Health %d) —" % [
		GameState.turn_number, _actor(player), player.current_larva, player.max_larva, player.health
	], "system")
	if drawn != null:
		GameLog.log("%s draws %s." % [_actor(player), drawn.display_name()])
	else:
		GameLog.log("%s tries to draw from an empty deck!" % _actor(player))
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
		var discarded: CardInstance = player.hand.pop_back()
		player.graveyard.append(discarded)
		GameLog.log("%s discards %s (hand size limit)." % [_actor(player), discarded.display_name()], "system")
	EffectResolver.fire_end_of_turn(player, opponent)
	turn_ended.emit(player_index)
	if GameState.is_over:
		return
	GameState.active_player_index = 1 - player_index
	start_turn(GameState.active_player_index)

## --- Player actions --------------------------------------------------------

## Legend Rule (§4): if a second copy of a Legendary name would enter play,
## the controller chooses which to keep — a real choice for a human
## (legend_rule_decision_requested), while the AI just keeps the new copy
## (no UI to ask it anything). Returns true if `new_card` should proceed
## onto the board; false if an existing copy was kept instead, in which
## case the caller discards `new_card` without it ever entering play.
func _resolve_legend_rule(player: PlayerState, new_card: CardInstance) -> bool:
	var existing := player.legendary_copies_in_play(new_card.data.card_name)
	if existing.is_empty():
		return true
	var keep := new_card
	if not player.is_ai:
		keep = await _request_human_legend_choice(new_card, existing)
	if keep == new_card:
		for dup: CardInstance in existing:
			player.board.erase(dup)
			player.graveyard.append(dup)
			GameLog.log("%s's existing %s is discarded (Legend Rule)." % [_actor(player), dup.display_name()], "system")
		return true
	GameLog.log("%s keeps their existing %s and discards the new copy (Legend Rule)." % [_actor(player), keep.display_name()], "system")
	return false

func _request_human_legend_choice(new_card: CardInstance, existing: Array[CardInstance]) -> CardInstance:
	legend_rule_decision_requested.emit(new_card, existing)
	await legend_rule_decision_made
	return _pending_legend_keep

## Called by the UI once the human has picked which copy to keep.
func submit_legend_choice(keep: CardInstance) -> void:
	_pending_legend_keep = keep
	legend_rule_decision_made.emit()

## Plays hand[hand_index]. `target_instance_id` is used for Gear's equip
## target and passed through to on_play/on_cast effect resolution for
## cards whose effect needs a target (e.g. a removal Ability). May suspend
## (via await) if playing a Legendary the human already controls a copy of
## — the caller should `await` this.
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
			var cd := card_inst.data as CreatureData
			var proceeds := true
			if card_inst.data.is_legendary:
				proceeds = await _resolve_legend_rule(player, card_inst)
			if not proceeds:
				player.graveyard.append(card_inst)
			else:
				var is_ambush_creature := cd.is_ambush()
				if is_ambush_creature:
					card_inst.enter_play_face_down()
				player.board.append(card_inst)
				EffectResolver.apply_hive_bonuses_on_enter(card_inst, player)
				if is_ambush_creature:
					GameLog.log("%s plays a face-down Ambush creature for %d Larva." % [_actor(player), cost])
				else:
					var kw := (", ".join(cd.keywords)) if not cd.keywords.is_empty() else ""
					GameLog.log("%s plays %s (%d/%d)%s for %d Larva." % [
						_actor(player), card_inst.display_name(), cd.attack, cd.health,
						(" [" + kw + "]") if kw != "" else "", cost
					])
				EffectResolver.fire_on_play(card_inst, player, opponent, target_instance_id)
		CardTypes.ABILITY:
			GameLog.log("%s casts %s for %d Larva." % [_actor(player), card_inst.display_name(), cost])
			EffectResolver.fire_on_cast(card_inst, player, opponent, target_instance_id)
			player.graveyard.append(card_inst)
		CardTypes.GEAR:
			var gear_target := player.find_on_board(target_instance_id)
			GameState.attach_gear(card_inst, gear_target)
			GameLog.log("%s equips %s onto %s for %d Larva." % [_actor(player), card_inst.display_name(), gear_target.display_name(), cost])
		CardTypes.HIVE:
			player.hive_zone.append(card_inst)
			EffectResolver.apply_new_hive_to_board(card_inst, player)
			GameLog.log("%s establishes %s for %d Larva." % [_actor(player), card_inst.display_name(), cost])

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
	GameLog.log("%s uses Hero Power (%d Larva): %s" % [_actor(player), cost, player.leader.data.hero_power_text])
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
	GameLog.log("%s unleashes their Ultimate (%d Larva): %s" % [_actor(player), cost, player.leader.data.ultimate_text], "combat")
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
	GameLog.log("%s pays %d Larva to flip their hidden creature face up — it's %s (%d/%d)!" % [
		_actor(player), cost, c.display_name(), c.current_attack, c.current_health()
	], "combat")
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
