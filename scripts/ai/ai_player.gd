class_name AIPlayer
extends RefCounted
## Heuristic/rules-based bot (§12): weighted evaluation of board state, not
## search-based. Stateless static functions that drive TurnManager through
## the exact same API a human UI uses, so it can be swapped/upgraded later
## (and reused for campaign-mode scripted opponents, per §12) without
## touching the rules engine.

## Runs a full turn for the AI-controlled player at `player_index`, ending
## with TurnManager.end_turn(). Must be awaited by the caller since attacks
## may suspend (they never do for an AI defender, but declare_attack is a
## coroutine either way).
static func take_turn(player_index: int) -> void:
	var player := GameState.players[player_index]
	var opponent := GameState.get_opponent(player_index)

	await _play_cards(player)
	_flip_paid_ambush(player)
	if not player.leader.hero_power_used_this_turn and player.leader.data.hero_power_cost <= player.current_larva:
		TurnManager.use_hero_power(player_index)
	if not player.leader.ultimate_used and player.leader.data.ultimate_cost <= player.current_larva:
		TurnManager.use_ultimate(player_index)

	await _attack_phase(player_index, player, opponent)

	TurnManager.end_turn()

## Greedily plays the single most expensive affordable card each pass until
## nothing more is playable — a simple approximation of "don't waste Larva".
static func _play_cards(player: PlayerState) -> void:
	var played := true
	while played:
		played = false
		var best_index := -1
		var best_cost := -1
		for i in range(player.hand.size()):
			var card: CardInstance = player.hand[i]
			if card.data.card_type == CardTypes.GEAR and player.board.is_empty():
				continue
			var cost := CostCalculator.calculate_cost(card.data, player.leader.data)
			if cost <= player.current_larva and cost > best_cost:
				best_cost = cost
				best_index = i
		if best_index != -1:
			var target_id := -1
			if player.hand[best_index].data.card_type == CardTypes.GEAR:
				target_id = player.board[0].instance_id
			if await TurnManager.play_card(player.player_id, best_index, target_id):
				played = true

static func _flip_paid_ambush(player: PlayerState) -> void:
	for c: CardInstance in player.board:
		if c.is_face_down and c.true_data != null and c.true_data.ambush.get("flip_trigger", "") == "paid":
			var cost := int(c.true_data.ambush.get("flip_cost", 0))
			if cost <= player.current_larva:
				TurnManager.flip_ambush_paid(player.player_id, c.instance_id)

## Favor attacks that trade favorably or go face when safe; hold back the
## single best blocker when this player's own health is low (§12).
static func _attack_phase(player_index: int, player: PlayerState, opponent: PlayerState) -> void:
	var attackers := player.board.filter(func(c: CardInstance) -> bool: return CombatResolver.can_attack(c))
	if player.health <= 10 and attackers.size() > 1:
		attackers.sort_custom(func(a: CardInstance, b: CardInstance) -> bool: return a.current_health() > b.current_health())
		attackers = attackers.slice(1)

	for c: CardInstance in attackers:
		var target = _choose_attack_target(c, opponent)
		if target != null:
			await TurnManager.declare_attack(player_index, c.instance_id, target)

static func _choose_attack_target(attacker: CardInstance, opponent: PlayerState):
	if not CombatResolver.is_legal_leader_target(attacker, opponent):
		var guards := opponent.guards()
		guards.sort_custom(func(a: CardInstance, b: CardInstance) -> bool: return a.current_health() < b.current_health())
		var g: CardInstance = guards[0]
		if attacker.current_attack >= g.current_health() or g.current_attack < attacker.current_health():
			return g
		return null # bad trade forced against Guard — decline to attack
	return "leader"

## Defender-side decision when the AI is being attacked and an optional
## block is available (§7). Blocks favorably when possible, chump-blocks
## only to prevent lethal, otherwise takes the hit. Returns 0 or 1 blockers
## — gang-blocking with multiple creatures (§ user request) is a real
## strategic choice the AI doesn't attempt; only a human defender does it,
## via the UI's multi-select block popup.
static func choose_block(defender: PlayerState, attacker: CardInstance, options: Array[CardInstance]) -> Array[CardInstance]:
	var best: CardInstance = null
	for c: CardInstance in options:
		var trades_favorably := c.current_attack >= attacker.current_health() and c.current_health() > attacker.current_attack
		if trades_favorably and (best == null or c.current_attack > best.current_attack):
			best = c
	if best != null:
		return [best]
	if attacker.current_attack >= defender.health:
		var weakest: CardInstance = options[0]
		for c: CardInstance in options:
			if c.current_health() < weakest.current_health():
				weakest = c
		return [weakest]
	return []
