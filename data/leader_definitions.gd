class_name LeaderDefinitions
extends RefCounted
## One Leader per Phase 1 test deck (§4, §11). starting_health uses the
## PROPOSED 30 from §4. Hero Power/Ultimate effect_ids are resolved by
## EffectResolver the same way card effects are.

static func get_all() -> Array[Dictionary]:
	return [
		{
			"id": "queen_amara", "name": "Queen Amara, the Hive Mother",
			"kingdoms": [Kingdoms.WHITE], "starting_health": 30,
			"text": "Leader of the Hive.",
			"hero_power_cost": 2,
			"hero_power_text": "Give a friendly creature +1/+1 and Guard this turn.",
			"hero_power_effects": [{"effect_id": "buff_friendly", "params": {"attack": 1, "health": 1, "temp_keyword": Keywords.GUARD}}],
			"ultimate_cost": 6,
			"ultimate_text": "Summon three 1/1 Worker Bee tokens with Guard.",
			"ultimate_effects": [{"effect_id": "summon_token", "params": {"token_id": "ladybug_guard_token", "count": 3}}],
		},
		{
			"id": "thornback_grael", "name": "Thornback Grael",
			"kingdoms": [Kingdoms.GREEN], "starting_health": 30,
			"text": "Leader of the Wild.",
			"hero_power_cost": 1,
			"hero_power_text": "Gain 1 extra Larva this turn.",
			"hero_power_effects": [{"effect_id": "gain_larva", "params": {"amount": 1}}],
			"ultimate_cost": 7,
			"ultimate_text": "Give a friendly creature +4/+4 and Trample.",
			"ultimate_effects": [{"effect_id": "buff_friendly", "params": {"attack": 4, "health": 4, "keyword": Keywords.TRAMPLE}}],
		},
		{
			"id": "matriarch_vess", "name": "Matriarch Vess",
			"kingdoms": [Kingdoms.BLACK], "starting_health": 30,
			"text": "Leader of the Venom.",
			"hero_power_cost": 2,
			"hero_power_text": "Deal 1 damage to the strongest enemy creature.",
			"hero_power_effects": [{"effect_id": "damage_creature", "params": {"amount": 1}}],
			"ultimate_cost": 6,
			"ultimate_text": "Deal 6 damage to the strongest enemy creature.",
			"ultimate_effects": [{"effect_id": "damage_creature", "params": {"amount": 6}}],
		},
		{
			"id": "skywhisper_iyra", "name": "Skywhisper Iyra",
			"kingdoms": [Kingdoms.BLUE], "starting_health": 30,
			"text": "Leader of the Swarm Aloft.",
			"hero_power_cost": 1,
			"hero_power_text": "Draw a card.",
			"hero_power_effects": [{"effect_id": "draw_card", "params": {"count": 1}}],
			"ultimate_cost": 5,
			"ultimate_text": "Return the strongest enemy creature to its owner's hand and draw 2 cards.",
			"ultimate_effects": [
				{"effect_id": "bounce_creature", "params": {}},
				{"effect_id": "draw_card", "params": {"count": 2}},
			],
		},
	]
