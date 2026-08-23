extends Node
## Regression check for the new mechanics added on top of the existing
## engine: Venomstrike, exhaustion/blocking, temporary stat buffs,
## buff_all_matching, token_stat_bonus, scry, return_from_graveyard, and
## shuffle_into_library. None of the existing card pool exercised these
## before this test existed, so the other suites passing doesn't cover them.

var _failures := 0

func _ready() -> void:
	print("=== New mechanics check ===")
	TurnManager.start_game(["white_hive_guardians", "black_venom_broodmother"], 0)
	var p0 := GameState.players[0]
	var p1 := GameState.players[1]

	# --- Venomstrike kills outright, Chitin grants immunity --------------------
	var venom_striker := CardDatabase.create_instance("worker_termite", 0)
	venom_striker.runtime_keywords.append(Keywords.VENOMSTRIKE)
	venom_striker.summoning_sick = false
	p0.board.append(venom_striker)
	var weak_target := CardDatabase.create_instance("wasp_striker", 1) # 1/1
	p1.board.append(weak_target)
	CombatResolver.resolve_attack(venom_striker, weak_target, p0, p1, null)
	_check(not weak_target.is_alive(), "Venomstrike kills a creature outright even with 1 attack vs more health")

	# Tough enough that 1 attack damage alone would never kill it — isolates
	# whether Chitin blocked the Venomstrike insta-kill specifically.
	var chitin_target := CardDatabase.create_instance("queens_guardian_beetle", 1) # 4/6
	chitin_target.runtime_keywords.append(Keywords.CHITIN)
	p1.board.append(chitin_target)
	venom_striker.has_attacked_this_turn = false
	CombatResolver.resolve_attack(venom_striker, chitin_target, p0, p1, null)
	_check(chitin_target.is_alive(), "Chitin grants immunity to Venomstrike (creature survives combat damage)")

	# --- Exhaustion: an attacked creature can't be chosen as an optional blocker ---
	var blocker := CardDatabase.create_instance("worker_termite", 1)
	blocker.summoning_sick = false
	p1.board.append(blocker)
	var attacker2 := CardDatabase.create_instance("wasp_striker", 0)
	attacker2.summoning_sick = false
	p0.board.append(attacker2)
	_check(CombatResolver.legal_block_options(attacker2, p1).has(blocker), "A fresh (non-exhausted) creature is a legal blocker")
	blocker.has_attacked_this_turn = true
	_check(not CombatResolver.legal_block_options(attacker2, p1).has(blocker), "An exhausted creature (attacked this turn) is not a legal blocker")
	_check(blocker.is_exhausted(), "is_exhausted() reflects has_attacked_this_turn")

	# --- Temporary stat buffs revert at end of turn, permanent ones don't ------
	var buffed := CardDatabase.create_instance("worker_termite", 0)
	p0.board.append(buffed)
	var base_atk := buffed.current_attack
	var base_hp := buffed.max_health
	buffed.add_temp_buff(3, 0)
	buffed.current_attack += 1 # a permanent change happening in between, to prove commutativity
	_check(buffed.current_attack == base_atk + 4, "Temp buff and permanent buff both apply immediately")
	buffed.clear_temp_buffs()
	_check(buffed.current_attack == base_atk + 1, "clear_temp_buffs reverts exactly the temp portion, leaving the permanent +1")
	_check(buffed.max_health == base_hp, "clear_temp_buffs with 0 temp health bonus leaves max_health untouched")

	# --- buff_all_matching (Nyxa's ultimate pattern) ----------------------------
	var spider1 := CardDatabase.create_instance("black_widow_stalker", 1)
	var spider2 := CardDatabase.create_instance("tarantula_ambusher", 1)
	var non_spider := CardDatabase.create_instance("roly_poly_grub", 1) # vanilla, no innate keywords — a clean control
	p1.board.append(spider1)
	p1.board.append(spider2)
	p1.board.append(non_spider)
	var s1_atk := spider1.current_attack
	var ns_atk := non_spider.current_attack
	EffectResolver.resolve_effect_list(
		[{"effect_id": "buff_all_matching", "params": {"attack": 1, "health": 1, "keyword": Keywords.VENOMSTRIKE, "filter_creature_type": "Spider"}}],
		p1, p0
	)
	_check(spider1.current_attack == s1_atk + 1 and spider1.has_keyword(Keywords.VENOMSTRIKE), "buff_all_matching buffs a matching creature (Spider) and grants the keyword")
	_check(spider2.has_keyword(Keywords.VENOMSTRIKE), "buff_all_matching affects every matching creature, not just one")
	_check(non_spider.current_attack == ns_atk and not non_spider.has_keyword(Keywords.VENOMSTRIKE), "buff_all_matching does not affect non-matching creatures")

	# --- token_stat_bonus Hive modifier -----------------------------------------
	var hive_inst := CardDatabase.create_instance("termite_colony", 0) # reuse an existing Hive card's shape via a synthetic modifier
	p0.hive_zone.append(hive_inst)
	var token_hive_mod := {"type": "token_stat_bonus", "attack": 1, "health": 1}
	var real_token := CardDatabase.create_instance("termite_worker_token", 0)
	var real_creature := CardDatabase.create_instance("worker_termite", 0)
	EffectResolver.call("_apply_modifier", real_token, token_hive_mod)
	EffectResolver.call("_apply_modifier", real_creature, token_hive_mod)
	_check(real_token.current_attack == 2 and real_token.max_health == 2, "token_stat_bonus buffs a token creature (1/1 -> 2/2)")
	_check(real_creature.current_attack == 1 and real_creature.max_health == 2, "token_stat_bonus does not affect a non-token creature")

	# --- return_from_graveyard, shuffle_into_library, scry ----------------------
	var died := CardDatabase.create_instance("worker_termite", 0)
	p0.graveyard.append(died)
	var hand_before := p0.hand.size()
	EffectResolver.resolve_effect_list([{"effect_id": "return_from_graveyard", "params": {}}], p0, p1)
	_check(p0.hand.size() == hand_before + 1 and not p0.graveyard.has(died), "return_from_graveyard moves a creature card from graveyard to hand")

	# p1.board already has several creatures from earlier steps (auto-pick
	# targets the strongest, so check board *count* rather than tracking one
	# specific instance that might not be the one picked).
	var deck_size_before := p1.deck.size()
	var board_size_before := p1.board.size()
	EffectResolver.resolve_effect_list([{"effect_id": "shuffle_into_library", "params": {}}], p0, p1)
	_check(p1.deck.size() == deck_size_before + 1, "shuffle_into_library adds a card back into the target's deck")
	_check(p1.board.size() == board_size_before - 1, "shuffle_into_library removes the targeted creature from the board")

	var scry_deck_size := p0.deck.size()
	EffectResolver.resolve_effect_list([{"effect_id": "scry", "params": {}}], p0, p1)
	_check(p0.deck.size() == scry_deck_size, "scry never changes deck size, only order")

	# --- Colony keyword: dynamic aura, stacks, and un-applies on leaving -------
	p0.board.clear()
	var colony_ant := CardDatabase.create_instance("worker_ant_line", 0)
	colony_ant.runtime_keywords.append(Keywords.COLONY)
	p0.board.append(colony_ant)
	var ant_mate := CardDatabase.create_instance("ant_phalanx", 0) # different Ant card, same creature_type, no printed Colony of its own
	var non_ant := CardDatabase.create_instance("honeybee_sentinel", 0)
	var ant_base_hp := ant_mate.max_health
	var non_ant_base_hp := non_ant.max_health
	p0.board.append(ant_mate)
	p0.board.append(non_ant)
	EffectResolver.refresh_colony_bonuses(p0)
	_check(ant_mate.max_health == ant_base_hp + 1, "Colony grants +0/+1 to another creature sharing its creature_type")
	_check(non_ant.max_health == non_ant_base_hp, "Colony does not affect a creature of a different creature_type")
	_check(colony_ant.max_health == CardDatabase.create_instance("worker_ant_line", 0).max_health, "The Colony source itself gets no bonus from its own aura (no second Ant source)")

	var second_colony_ant := CardDatabase.create_instance("worker_ant_line", 0)
	second_colony_ant.runtime_keywords.append(Keywords.COLONY)
	p0.board.append(second_colony_ant)
	EffectResolver.refresh_colony_bonuses(p0)
	_check(ant_mate.max_health == ant_base_hp + 2, "A second Colony source of the same type stacks the bonus")
	_check(colony_ant.max_health == CardDatabase.create_instance("worker_ant_line", 0).max_health + 1, "A Colony creature also receives the bonus from another Colony source of its own type")

	p0.board.erase(colony_ant)
	p0.graveyard.append(colony_ant)
	EffectResolver.refresh_colony_bonuses(p0)
	_check(ant_mate.max_health == ant_base_hp + 1, "When one Colony source leaves the field, exactly its bonus leaves with it")

	# --- Botfly: on_play grants an enemy creature a Decay that benefits the CASTER ---
	p1.board.clear()
	var botfly_victim := CardDatabase.create_instance("worker_termite", 1)
	p1.board.append(botfly_victim)
	var p0_board_before := p0.board.size()
	EffectResolver.resolve_effect_list([{"effect_id": "grant_decay_to_enemy", "params": {"token_id": "termite_worker_token", "count": 1}}], p0, p1)
	_check(botfly_victim.has_keyword(Keywords.DECAY), "grant_decay_to_enemy grants the Decay keyword to the targeted enemy creature")
	_check(not botfly_victim.granted_effects.is_empty(), "grant_decay_to_enemy attaches a granted on_death effect to the target")
	GameState.damage_creature(botfly_victim, 999, "test")
	GameState.cleanup_dead(1)
	_check(p0.board.size() == p0_board_before + 1, "When the afflicted enemy creature dies, the token spawns for the GRANTER (not the victim's own controller)")

	# --- "Until end of next turn" effects survive the opponent's whole turn ----
	# (§ user request): a same-turn expiry made e.g. temporary Guard pointless,
	# since it wore off before the opponent's turn — the only turn Guard could
	# actually matter on — ever arrived. GameState.active_player_index is still
	# 0 (P0's turn) at this point since no earlier section in this file has
	# called TurnManager.end_turn().
	var temp_guard_target := CardDatabase.create_instance("worker_ant_line", 0) # vanilla, no innate Guard
	p0.board.append(temp_guard_target)
	EffectResolver.resolve_effect_list(
		[{"effect_id": "buff_friendly", "params": {"attack": 0, "health": 0, "temp_keyword": Keywords.GUARD}}],
		p0, p1, temp_guard_target.instance_id
	)
	_check(temp_guard_target.has_keyword(Keywords.GUARD), "A temp_keyword grant applies immediately")
	TurnManager.end_turn() # ends P0's turn, starts P1's turn
	_check(temp_guard_target.has_keyword(Keywords.GUARD), "Temp keyword survives past the end of the granting player's own turn (this is the actual fix)")
	TurnManager.end_turn() # ends P1's turn, starts P0's turn again
	_check(not temp_guard_target.has_keyword(Keywords.GUARD), "Temp keyword clears at the start of the granting player's NEXT turn, after the opponent's full turn has passed")

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
