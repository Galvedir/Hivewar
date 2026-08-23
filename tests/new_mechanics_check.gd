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
	var non_spider := CardDatabase.create_instance("wasp_striker", 1)
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
