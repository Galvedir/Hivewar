extends Node
## Autoload: implements §7 combat rules. Stateless — every function takes
## the state it needs as arguments. Attack orchestration (including the
## async "ask the defender whether to block" step) lives in TurnManager;
## this resolver only validates legality and applies damage once a block
## choice (if any) is already decided.

## Whether `attacker` is currently eligible to attack at all (summoning
## sickness / Swift, already attacked, alive). A face-down Ambush creature
## may only attack if its flip trigger is "on_attack" (§8) — declaring the
## attack is what reveals it; other face-down creatures stay passive.
func can_attack(attacker: CardInstance) -> bool:
	if not attacker.is_alive() or attacker.has_attacked_this_turn:
		return false
	# summoning_sick is set once, at the moment a creature enters play, based
	# on whatever keywords it had printed then — it's never revisited. Swift
	# granted afterward (e.g. equipping Barbed Stinger) must still lift
	# sickness immediately, so re-check has_keyword live rather than trusting
	# the stale flag alone.
	if attacker.summoning_sick and not attacker.has_keyword(Keywords.SWIFT):
		return false
	if not attacker.is_face_down:
		return true
	return attacker.true_data != null and attacker.true_data.ambush.get("flip_trigger", "") == "on_attack"

## Leader is not a legal target while the defender controls a Guard, unless
## the attacker has Pierce (§7).
func is_legal_leader_target(attacker: CardInstance, defender_player: PlayerState) -> bool:
	if attacker.has_keyword(Keywords.PIERCE):
		return true
	return not defender_player.has_guard()

## A ground creature without Reach can't choose an enemy Flyer as its direct
## target; Stealth creatures can't be chosen unless the attacker has Keen
## Sight. Guard overrides both when the attacker is being forced to target
## a Guard creature (call this only for the attacker's freely-chosen target).
func is_legal_creature_target(attacker: CardInstance, target: CardInstance) -> bool:
	if not target.is_alive():
		return false
	if target.has_keyword(Keywords.STEALTH) and not attacker.has_keyword(Keywords.KEEN_SIGHT):
		return false
	if target.has_keyword(Keywords.FLYING) and not (attacker.has_keyword(Keywords.FLYING) or attacker.has_keyword(Keywords.REACH)):
		return false
	return true

## If the defender controls a Guard, an attack on the Leader must be
## redirected to a Guard creature — defender's choice among their Guards.
## Returns null if no redirect is required (no Guard present, or Pierce).
func forced_guard_target(attacker: CardInstance, defender_player: PlayerState) -> Array[CardInstance]:
	if attacker.has_keyword(Keywords.PIERCE):
		return []
	return defender_player.guards()

## Legal optional blockers when the attacker targets the Leader directly and
## the defender has no Guard. Empty if Pierce (unblockable) or the attacker
## isn't targeting the Leader. Exhausted creatures (§ user request — attacked
## this turn) can't be chosen; this is the optional-block path only — a
## Guard's mandatory redirect (forced_guard_target) isn't "blocking" and
## stays available even while exhausted.
func legal_block_options(attacker: CardInstance, defender_player: PlayerState) -> Array[CardInstance]:
	if attacker.has_keyword(Keywords.PIERCE):
		return []
	var flying := attacker.has_keyword(Keywords.FLYING)
	return defender_player.board.filter(func(c: CardInstance) -> bool:
		if not c.is_alive() or c.is_face_down or c.is_exhausted():
			return false
		if flying:
			return c.has_keyword(Keywords.FLYING) or c.has_keyword(Keywords.REACH)
		return true)

## Resolves a fully-decided attack: `target` is either the String "leader"
## or a CardInstance (a direct creature-vs-creature duel, or the Guard
## defender chose to redirect to). `block_choice` is the creature the
## defender opted to intercept with, already validated against
## legal_block_options — pass null for no block / not applicable.
func resolve_attack(attacker: CardInstance, target, attacker_player: PlayerState, defender_player: PlayerState, block_choice: CardInstance = null) -> void:
	if attacker.is_face_down and attacker.true_data != null and attacker.true_data.ambush.get("flip_trigger", "") == "on_attack":
		attacker.flip_face_up()
		GameLog.log("%s's hidden creature reveals itself as it attacks — it's %s (%d/%d)!" % [
			attacker_player.leader.data.card_name, attacker.display_name(), attacker.current_attack, attacker.current_health()
		], "combat")

	attacker.has_attacked_this_turn = true
	EffectResolver.fire_on_attack(attacker, attacker_player, defender_player)

	if block_choice != null:
		GameLog.log("%s attacks %s's Leader with %s (%d/%d) — blocked by %s (%d/%d)!" % [
			attacker_player.leader.data.card_name, defender_player.leader.data.card_name, attacker.display_name(),
			attacker.current_attack, attacker.current_health(), block_choice.display_name(),
			block_choice.current_attack, block_choice.current_health()
		], "combat")
		_fight(attacker, block_choice, attacker_player, defender_player)
	elif target is String:
		GameLog.log("%s attacks %s's Leader with %s (%d/%d)." % [
			attacker_player.leader.data.card_name, defender_player.leader.data.card_name,
			attacker.display_name(), attacker.current_attack, attacker.current_health()
		], "combat")
		_hit_leader(attacker, attacker_player, defender_player, attacker.current_attack)
	else:
		var defender := target as CardInstance
		GameLog.log("%s attacks %s (%d/%d) with %s (%d/%d)." % [
			attacker_player.leader.data.card_name, defender.display_name(), defender.current_attack, defender.current_health(),
			attacker.display_name(), attacker.current_attack, attacker.current_health()
		], "combat")
		_fight(attacker, defender, attacker_player, defender_player)

	GameState.cleanup_dead(attacker_player.player_id)
	GameState.cleanup_dead(defender_player.player_id)

## Poison never applies to Leaders (house rule override of the original
## §6 draft, which had it hitting Leaders too) — it's a creature-only
## damage-over-time tool.
func _hit_leader(attacker: CardInstance, attacker_player: PlayerState, defender_player: PlayerState, amount: int) -> void:
	GameState.damage_player(defender_player.player_id, amount, attacker.display_name())
	if attacker.has_keyword(Keywords.LIFESTEAL):
		GameState.heal_player(attacker_player.player_id, amount, attacker.display_name() + "'s Lifesteal")
	EffectResolver.fire_on_damage_dealt(attacker, defender_player.player_id, amount)

## Creature-vs-creature combat, both directions simultaneously (no first
## strike in v1). Handles Poison, Lifesteal, Chitin, and Trample overflow.
func _fight(attacker: CardInstance, defender: CardInstance, attacker_player: PlayerState, defender_player: PlayerState) -> void:
	var dmg_to_defender: int = attacker.current_attack
	var dmg_to_attacker: int = defender.current_attack

	GameState.damage_creature(defender, dmg_to_defender, attacker.display_name())
	GameState.damage_creature(attacker, dmg_to_attacker, defender.display_name())

	if attacker.has_keyword(Keywords.POISON) and not defender.has_keyword(Keywords.CHITIN):
		defender.poison_counters += 1
		GameLog.log("%s is poisoned by %s (now %d Poison counters)." % [defender.display_name(), attacker.display_name(), defender.poison_counters], "combat")
	if defender.has_keyword(Keywords.POISON) and not attacker.has_keyword(Keywords.CHITIN):
		attacker.poison_counters += 1
		GameLog.log("%s is poisoned by %s (now %d Poison counters)." % [attacker.display_name(), defender.display_name(), attacker.poison_counters], "combat")

	# Venomstrike: kills any creature it damages in combat outright, unless
	# that creature has Chitin (which already grants Poison immunity — reused
	# here rather than adding a second near-identical immunity keyword).
	if attacker.has_keyword(Keywords.VENOMSTRIKE) and not defender.has_keyword(Keywords.CHITIN) and defender.is_alive():
		defender.damage_marked = defender.max_health
		GameLog.log("%s's Venomstrike kills %s instantly!" % [attacker.display_name(), defender.display_name()], "combat")
	if defender.has_keyword(Keywords.VENOMSTRIKE) and not attacker.has_keyword(Keywords.CHITIN) and attacker.is_alive():
		attacker.damage_marked = attacker.max_health
		GameLog.log("%s's Venomstrike kills %s instantly!" % [defender.display_name(), attacker.display_name()], "combat")

	if attacker.has_keyword(Keywords.LIFESTEAL):
		GameState.heal_player(attacker_player.player_id, dmg_to_defender, attacker.display_name() + "'s Lifesteal")
	if defender.has_keyword(Keywords.LIFESTEAL):
		GameState.heal_player(defender_player.player_id, dmg_to_attacker, defender.display_name() + "'s Lifesteal")

	EffectResolver.fire_on_damage_dealt(attacker, defender_player.player_id, dmg_to_defender)
	EffectResolver.fire_on_damage_taken(defender, attacker, dmg_to_defender)
	EffectResolver.fire_on_damage_taken(attacker, defender, dmg_to_attacker)

	if attacker.has_keyword(Keywords.TRAMPLE) and not defender.is_alive():
		var excess: int = dmg_to_defender - defender.max_health
		if excess > 0:
			var guards := defender_player.guards()
			guards.erase(defender)
			if guards.is_empty():
				GameLog.log("%s's excess damage (%d) tramples through to %s's Leader!" % [
					attacker.display_name(), excess, defender_player.leader.data.card_name
				], "combat")
				_hit_leader(attacker, attacker_player, defender_player, excess)
