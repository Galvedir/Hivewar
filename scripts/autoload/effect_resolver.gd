extends Node
## Autoload: event-driven trigger dispatch (§13) — no priority/response
## stack, effects resolve immediately in trigger order. Card `effects`
## arrays are lists of {trigger, effect_id, params}; this resolver matches
## the trigger name and executes effect_id against a small, extensible
## effect-id library (_resolve_effect). Also owns Ambush's conditional/timed
## flip checks (§8) and applying Hive static stat bonuses (§5) at the
## moment a qualifying creature or Hive card enters play.

func _ctx(player: PlayerState, opponent: PlayerState, source: CardInstance, target_instance_id: int = -1) -> Dictionary:
	return {"player": player, "opponent": opponent, "source": source, "target_instance_id": target_instance_id}

func _resolve_list(effects: Array[Dictionary], trigger: String, ctx: Dictionary) -> void:
	for e: Dictionary in effects:
		if e.get("trigger", "") == trigger:
			_resolve_effect(e.get("effect_id", ""), e.get("params", {}), ctx)
	GameState.cleanup_dead(ctx["player"].player_id)
	GameState.cleanup_dead(ctx["opponent"].player_id)

## Resolves every entry in `effects` unconditionally (no trigger filter) —
## used for Leader Hero Power / Ultimate effect lists, which only ever
## contain effects meant to fire immediately on activation.
func resolve_effect_list(effects: Array[Dictionary], player: PlayerState, opponent: PlayerState, target_instance_id: int = -1) -> void:
	var ctx := _ctx(player, opponent, null, target_instance_id)
	for e: Dictionary in effects:
		_resolve_effect(e.get("effect_id", ""), e.get("params", {}), ctx)
	GameState.cleanup_dead(player.player_id)
	GameState.cleanup_dead(opponent.player_id)

## --- Public trigger entry points -----------------------------------------

func fire_on_play(instance: CardInstance, player: PlayerState, opponent: PlayerState, target_instance_id: int = -1) -> void:
	var cd := instance.creature_data()
	if cd != null:
		_resolve_list(cd.effects, "on_play", _ctx(player, opponent, instance, target_instance_id))

func fire_on_cast(instance: CardInstance, player: PlayerState, opponent: PlayerState, target_instance_id: int = -1) -> void:
	var ad := instance.data as AbilityData
	if ad != null:
		_resolve_list(ad.effects, "on_cast", _ctx(player, opponent, instance, target_instance_id))

func fire_on_death(instance: CardInstance, player: PlayerState, opponent: PlayerState) -> void:
	var cd := instance.true_data if instance.true_data != null else instance.data
	if cd is CreatureData:
		_resolve_list((cd as CreatureData).effects, "on_death", _ctx(player, opponent, instance))

func fire_on_attack(instance: CardInstance, player: PlayerState, opponent: PlayerState) -> void:
	var cd := instance.creature_data()
	if cd != null:
		_resolve_list(cd.effects, "on_attack", _ctx(player, opponent, instance))

func fire_on_damage_dealt(source: CardInstance, target_player_id: int, amount: int) -> void:
	pass # reserved: no v1 card currently listens on this trigger

func fire_on_damage_taken(instance: CardInstance, source: CardInstance, amount: int) -> void:
	var cd := instance.creature_data()
	if cd == null:
		return
	var player := GameState.get_player(instance.owner_id)
	var opponent := GameState.get_opponent(instance.owner_id)
	_resolve_list(cd.effects, "on_damage_taken", _ctx(player, opponent, instance))
	_check_damage_taken_flip(instance)

## Called by TurnManager at the start of `player`'s turn, after Larva/
## sickness housekeeping. Handles Ambush's "start_of_next_turn" flip and
## fires any card effects registered on that trigger.
func fire_start_of_turn(player: PlayerState, opponent: PlayerState) -> void:
	for c: CardInstance in player.board:
		if c.is_face_down and c.true_data != null:
			var cond: Dictionary = c.true_data.ambush.get("flip_condition", {})
			if c.true_data.ambush.get("flip_trigger", "") == "conditional" and cond.get("type", "") == "start_of_next_turn":
				c.flip_face_up()
				GameLog.log("%s's hidden creature stirs and flips face up — it's %s (%d/%d)!" % [
					player.leader.data.card_name, c.display_name(), c.current_attack, c.current_health()
				], "combat")
	for c: CardInstance in player.board:
		var cd := c.creature_data()
		if cd != null:
			_resolve_list(cd.effects, "start_of_turn", _ctx(player, opponent, c))

## Called by TurnManager while ending `player`'s turn, before the active
## player switches. Resolves Poison damage (§6) then fires end_of_turn
## card effects.
func fire_end_of_turn(player: PlayerState, opponent: PlayerState) -> void:
	for p: PlayerState in [player, opponent]:
		if p.poison_counters > 0:
			GameState.damage_player(p.player_id, p.poison_counters, "Poison")
		for c: CardInstance in p.board:
			if c.is_alive() and c.poison_counters > 0:
				GameState.damage_creature(c, c.poison_counters, "Poison")
	GameState.cleanup_dead(player.player_id)
	GameState.cleanup_dead(opponent.player_id)
	for c: CardInstance in player.board:
		var cd := c.creature_data()
		if cd != null:
			_resolve_list(cd.effects, "end_of_turn", _ctx(player, opponent, c))

func _check_damage_taken_flip(instance: CardInstance) -> void:
	if not instance.is_face_down or instance.true_data == null:
		return
	var ambush: Dictionary = instance.true_data.ambush
	if ambush.get("flip_trigger", "") != "conditional":
		return
	if ambush.get("flip_condition", {}).get("type", "") == "on_damage_taken":
		instance.flip_face_up()
		GameLog.log("The damage exposes a hidden creature — it's %s (%d/%d)!" % [
			instance.display_name(), instance.current_attack, instance.current_health()
		], "combat")

## Manual/paid activation (§8) — called by TurnManager.flip_ambush_paid after
## the Larva cost has already been deducted by the caller.
func flip_paid(instance: CardInstance) -> void:
	instance.flip_face_up()

## --- Hive static stat bonuses (§5) ----------------------------------------

func _apply_modifier(instance: CardInstance, mod: Dictionary) -> void:
	if mod.get("type", "") != "keyword_stat_bonus":
		return
	if instance.is_face_down:
		return
	if instance.has_keyword(mod.get("filter_keyword", "")):
		instance.current_attack += int(mod.get("attack", 0))
		instance.max_health += int(mod.get("health", 0))

## Call whenever a creature enters play (played from hand or summoned), so
## it immediately picks up bonuses from any Hive already in play.
func apply_hive_bonuses_on_enter(instance: CardInstance, player: PlayerState) -> void:
	for hive: CardInstance in player.hive_zone:
		var hd := hive.data as HiveData
		if hd == null:
			continue
		for mod: Dictionary in hd.static_modifiers:
			_apply_modifier(instance, mod)

## Call when a new Hive card enters play, to retroactively buff the board.
func apply_new_hive_to_board(hive_instance: CardInstance, player: PlayerState) -> void:
	var hd := hive_instance.data as HiveData
	if hd == null:
		return
	for mod: Dictionary in hd.static_modifiers:
		for c: CardInstance in player.board:
			_apply_modifier(c, mod)

## --- Effect-id library ------------------------------------------------------
## Small, deliberately generic vocabulary (§13) covering the Phase 1 card
## pool. New effect_ids get added here as new cards need them.

## What to call the thing causing this effect, for the log — the source
## card if there is one (a creature/ability's own trigger), else the
## controller's Leader (a Hero Power/Ultimate has no CardInstance source).
func _source_label(ctx: Dictionary) -> String:
	var source: CardInstance = ctx.get("source")
	if source != null:
		return source.display_name()
	return (ctx["player"] as PlayerState).leader.data.card_name

func _resolve_effect(effect_id: String, params: Dictionary, ctx: Dictionary) -> void:
	var player: PlayerState = ctx["player"]
	var opponent: PlayerState = ctx["opponent"]
	var source_label := _source_label(ctx)
	match effect_id:
		"heal_leader":
			var target := opponent if params.get("target", "self") == "enemy" else player
			GameState.heal_player(target.player_id, int(params.get("amount", 0)), source_label)
		"damage_leader":
			var target := player if params.get("target", "enemy") == "self" else opponent
			GameState.damage_player(target.player_id, int(params.get("amount", 0)), source_label)
		"draw_card":
			for i in range(int(params.get("count", 1))):
				var drawn := player.draw_card()
				if drawn != null:
					GameLog.log("%s draws %s (from %s)." % [player.leader.data.card_name, drawn.display_name(), source_label])
				else:
					GameLog.log("%s tries to draw from an empty deck (from %s)!" % [player.leader.data.card_name, source_label])
		"gain_larva":
			var amount := int(params.get("amount", 0))
			player.current_larva += amount
			player.temp_larva_bonus += amount
			GameLog.log("%s gains %d extra Larva this turn (now %d) from %s." % [player.leader.data.card_name, amount, player.current_larva, source_label])
		"summon_token":
			var token_id: String = params.get("token_id", "")
			var count := int(params.get("count", 1))
			var summoned_name := ""
			for i in range(count):
				var inst := CardDatabase.create_instance(token_id, player.player_id)
				if inst != null:
					summoned_name = inst.display_name()
					player.board.append(inst)
					apply_hive_bonuses_on_enter(inst, player)
			if summoned_name != "":
				GameLog.log("%s summons %d x %s (from %s)." % [player.leader.data.card_name, count, summoned_name, source_label])
		"buff_friendly":
			var target := _pick_target(ctx, player.board, "weakest")
			if target != null:
				var atk := int(params.get("attack", 0))
				var hp := int(params.get("health", 0))
				target.current_attack += atk
				target.max_health += hp
				var extra := ""
				if params.has("keyword") and not target.runtime_keywords.has(params["keyword"]):
					target.runtime_keywords.append(params["keyword"])
					extra += " and %s" % params["keyword"]
				if params.has("temp_keyword") and not target.temp_keywords.has(params["temp_keyword"]):
					target.temp_keywords.append(params["temp_keyword"])
					extra += " and %s this turn" % params["temp_keyword"]
				GameLog.log("%s gets +%d/+%d%s from %s." % [target.display_name(), atk, hp, extra, source_label])
		"damage_creature":
			var target := _pick_target(ctx, opponent.board, "strongest")
			if target != null:
				GameState.damage_creature(target, int(params.get("amount", 0)), source_label)
		"bounce_creature":
			var target := _pick_target(ctx, opponent.board, "strongest")
			if target != null:
				var true_id: String = target.true_data.id if target.true_data != null else target.data.id
				opponent.board.erase(target)
				var fresh := CardDatabase.create_instance(true_id, opponent.player_id)
				if fresh != null:
					opponent.hand.append(fresh)
					GameLog.log("%s returns %s to %s's hand (from %s)." % [
						player.leader.data.card_name, fresh.display_name(), opponent.leader.data.card_name, source_label
					])
		_:
			push_warning("EffectResolver: unknown effect_id '%s'" % effect_id)

## Picks ctx.target_instance_id from `pool` if supplied and alive, else
## falls back to an auto-pick heuristic ("strongest"/"weakest" by attack).
func _pick_target(ctx: Dictionary, pool: Array[CardInstance], prefer: String) -> CardInstance:
	var alive := pool.filter(func(c: CardInstance) -> bool: return c.is_alive())
	if alive.is_empty():
		return null
	var wanted_id: int = ctx.get("target_instance_id", -1)
	if wanted_id != -1:
		for c: CardInstance in alive:
			if c.instance_id == wanted_id:
				return c
	alive.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
		return a.current_attack > b.current_attack if prefer == "strongest" else a.current_attack < b.current_attack)
	return alive[0]
