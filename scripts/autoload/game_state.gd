extends Node
## Autoload: single source of truth for match state (§13). Pure data plus
## small zone-manipulation helpers — no scene-tree/UI dependency, so the
## same state can be driven by a human UI, the AI (§12), or a future
## networked opponent (§11 Phase 5) without rewrites.

signal creature_died(instance: CardInstance, owner_id: int)
signal game_ended(winner_id: int)
signal player_health_changed(player_id: int)

var players: Array[PlayerState] = []
var active_player_index: int = 0
var turn_number: int = 0
var is_over: bool = false
var winner_id: int = -1

func setup_game(deck_ids: Array[String], starting_player_index: int = 0) -> void:
	players.clear()
	for i in range(2):
		var deck_def: Dictionary = DeckDefinitions.get_deck(deck_ids[i])
		var leader := LeaderInstance.new(CardDatabase.get_leader(deck_def["leader_id"]))
		var player := PlayerState.new(i, leader, false)
		var card_ids: Array[String] = DeckDefinitions.expand(deck_def["cards"])
		card_ids.shuffle()
		for cid in card_ids:
			player.deck.append(CardDatabase.create_instance(cid, i))
		players.append(player)
	active_player_index = starting_player_index
	turn_number = 0
	is_over = false
	winner_id = -1

func get_player(id: int) -> PlayerState:
	return players[id]

func get_active_player() -> PlayerState:
	return players[active_player_index]

func get_opponent(player_id: int) -> PlayerState:
	return players[1 - player_id]

func damage_player(player_id: int, amount: int) -> void:
	if amount <= 0 or is_over:
		return
	var p := players[player_id]
	p.health -= amount
	player_health_changed.emit(player_id)
	if p.health <= 0:
		_end_game(1 - player_id)

func heal_player(player_id: int, amount: int) -> void:
	if amount <= 0 or is_over:
		return
	players[player_id].health += amount
	player_health_changed.emit(player_id)

func _end_game(winner: int) -> void:
	if is_over:
		return
	is_over = true
	winner_id = winner
	game_ended.emit(winner)

## Moves any dead creatures (current_health() <= 0) from board to graveyard,
## firing Decay (on_death) for each. Safe to call redundantly.
func cleanup_dead(player_id: int) -> void:
	var p := players[player_id]
	var i := 0
	while i < p.board.size():
		var c: CardInstance = p.board[i]
		if not c.is_alive():
			p.board.remove_at(i)
			p.graveyard.append(c)
			creature_died.emit(c, player_id)
			EffectResolver.fire_on_death(c, p, get_opponent(player_id))
		else:
			i += 1

## Attaches Gear to a friendly creature, discarding any Gear already on it (§5).
func attach_gear(gear_instance: CardInstance, target: CardInstance) -> void:
	for g in target.attached_gear.duplicate():
		_unequip_gear(g, target)
	target.attached_gear.append(gear_instance)
	var gd := gear_instance.data as GearData
	target.current_attack += gd.attack_buff
	target.max_health += gd.health_buff
	for kw: String in gd.grants_keywords:
		if not target.runtime_keywords.has(kw):
			target.runtime_keywords.append(kw)

func _unequip_gear(gear_instance: CardInstance, target: CardInstance) -> void:
	var gd := gear_instance.data as GearData
	target.current_attack -= gd.attack_buff
	target.max_health -= gd.health_buff
	for kw: String in gd.grants_keywords:
		target.runtime_keywords.erase(kw)
	target.attached_gear.erase(gear_instance)
	players[gear_instance.owner_id].graveyard.append(gear_instance)
