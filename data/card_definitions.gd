class_name CardDefinitions
extends RefCounted
## Phase 1 card pool (§11): enough unique cards across White/Green/Black/Blue
## to build four ~30-card fixed test decks (deck_definitions.gd) covering a
## spread of Kingdoms and keywords, per the Phase 1 scope note in §11 (this
## intentionally undercuts the 40-60 constructed-deck minimum in §9, which
## applies once the Phase 2 deckbuilder exists). Token creatures summoned by
## other cards' effects are defined here too, even though no deck lists them
## directly — they're only ever reached via CardDatabase.create_instance().

static func get_all() -> Array[Dictionary]:
	return WHITE + GREEN + BLACK + BLUE + TOKENS

const WHITE: Array[Dictionary] = [
	{
		"id": "worker_termite", "name": "Worker Termite", "type": "Creature",
		"cost": 1, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.COMMON,
		"attack": 1, "health": 2, "keywords": [Keywords.GUARD],
		"text": "Guard.",
	},
	{
		"id": "honeybee_sentinel", "name": "Honeybee Sentinel", "type": "Creature",
		"cost": 2, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.COMMON,
		"attack": 2, "health": 3, "keywords": [Keywords.GUARD],
		"text": "Guard.",
	},
	{
		"id": "ladybug_healer", "name": "Ladybug Healer", "type": "Creature",
		"cost": 2, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.COMMON,
		"attack": 1, "health": 2, "keywords": [],
		"effects": [{"trigger": "on_play", "effect_id": "heal_leader", "params": {"amount": 2, "target": "self"}}],
		"text": "On Play: restore 2 health to your Leader.",
	},
	{
		"id": "carpenter_ant_defender", "name": "Carpenter Ant Defender", "type": "Creature",
		"cost": 3, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.UNCOMMON,
		"attack": 3, "health": 4, "keywords": [Keywords.GUARD],
		"text": "Guard.",
	},
	{
		"id": "termite_mound", "name": "Termite Mound", "type": "Creature",
		"cost": 3, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.UNCOMMON,
		"attack": 1, "health": 3, "keywords": [],
		"effects": [{"trigger": "on_play", "effect_id": "summon_token", "params": {"token_id": "termite_worker_token", "count": 2}}],
		"text": "On Play: summon two 1/1 Termite Worker tokens with Guard.",
	},
	{
		"id": "queens_guardian_beetle", "name": "Queen's Guardian Beetle", "type": "Creature",
		"cost": 4, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.RARE,
		"attack": 4, "health": 6, "keywords": [Keywords.GUARD, Keywords.LIFESTEAL],
		"text": "Guard. Lifesteal.",
	},
	{
		"id": "hive_blessing", "name": "Hive Blessing", "type": "Ability",
		"cost": 2, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.COMMON,
		"effects": [{"trigger": "on_cast", "effect_id": "heal_leader", "params": {"amount": 5, "target": "self"}}],
		"text": "Restore 5 health to your Leader.",
	},
	{
		"id": "protective_ward", "name": "Protective Ward", "type": "Gear",
		"cost": 1, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.COMMON,
		"grants_keywords": [Keywords.GUARD],
		"text": "Equipped creature gains Guard.",
	},
	{
		"id": "ladybug_swarm_queen", "name": "Ladybug Swarm Queen", "type": "Creature",
		"cost": 5, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.LEGENDARY,
		"attack": 4, "health": 5, "keywords": [],
		"effects": [{"trigger": "on_play", "effect_id": "summon_token", "params": {"token_id": "ladybug_guard_token", "count": 2}}],
		"text": "On Play: summon two 1/1 Ladybug tokens with Guard.",
	},
	{
		"id": "termite_colony", "name": "Termite Colony", "type": "Hive",
		"cost": 3, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.UNCOMMON,
		"static_modifiers": [{"type": "keyword_stat_bonus", "filter_keyword": Keywords.GUARD, "health": 1}],
		"text": "Your Guard creatures have +0/+1.",
	},
	{
		"id": "wax_moth_larva", "name": "Honeycomb Sentinel", "type": "Creature",
		"cost": 1, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.RARE,
		"attack": 3, "health": 4, "keywords": [Keywords.GUARD, Keywords.LIFESTEAL],
		"ambush": {
			"face_down": {"name": "Unidentified Larva", "attack": 0, "health": 1},
			"flip_trigger": "paid", "flip_cost": 2,
		},
		"text": "Ambush (Pay 2: flip face up). Flips into a 3/4 Guard, Lifesteal.",
	},
	{
		"id": "royal_jelly", "name": "Royal Jelly", "type": "Ability",
		"cost": 3, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.COMMON,
		"effects": [
			{"trigger": "on_cast", "effect_id": "heal_leader", "params": {"amount": 4, "target": "self"}},
			{"trigger": "on_cast", "effect_id": "buff_friendly", "params": {"attack": 1, "health": 1}},
		],
		"text": "Restore 4 health to your Leader. Give a friendly creature +1/+1.",
	},
]

const GREEN: Array[Dictionary] = [
	{
		"id": "roly_poly_grub", "name": "Roly-Poly Grub", "type": "Creature",
		"cost": 1, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.COMMON,
		"attack": 1, "health": 3, "keywords": [],
		"text": "",
	},
	{
		"id": "giant_weta_hatchling", "name": "Giant Weta Hatchling", "type": "Creature",
		"cost": 2, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.COMMON,
		"attack": 3, "health": 2, "keywords": [],
		"text": "",
	},
	{
		"id": "stag_beetle_charger", "name": "Stag Beetle Charger", "type": "Creature",
		"cost": 3, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.UNCOMMON,
		"attack": 4, "health": 4, "keywords": [Keywords.SWIFT],
		"text": "Swift.",
	},
	{
		"id": "molting_grub", "name": "Molting Grub", "type": "Ability",
		"cost": 1, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.COMMON,
		"effects": [{"trigger": "on_cast", "effect_id": "gain_larva", "params": {"amount": 2}}],
		"text": "Gain 2 extra Larva this turn.",
	},
	{
		"id": "rhinoceros_beetle", "name": "Rhinoceros Beetle", "type": "Creature",
		"cost": 4, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.UNCOMMON,
		"attack": 5, "health": 5, "keywords": [Keywords.TRAMPLE],
		"text": "Trample.",
	},
	{
		"id": "pillbug_titan", "name": "Pillbug Titan", "type": "Creature",
		"cost": 5, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.RARE,
		"attack": 6, "health": 7, "keywords": [Keywords.TRAMPLE],
		"text": "Trample.",
	},
	{
		"id": "overgrowth", "name": "Overgrowth", "type": "Ability",
		"cost": 2, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.COMMON,
		"effects": [{"trigger": "on_cast", "effect_id": "buff_friendly", "params": {"attack": 2, "health": 2}}],
		"text": "Give a friendly creature +2/+2.",
	},
	{
		"id": "praying_mantis", "name": "Praying Mantis", "type": "Creature",
		"cost": 3, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.COMMON,
		"attack": 4, "health": 3, "keywords": [Keywords.SWIFT],
		"text": "Swift.",
	},
	{
		"id": "goliath_beetle", "name": "Goliath Beetle", "type": "Creature",
		"cost": 6, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.LEGENDARY,
		"attack": 8, "health": 8, "keywords": [Keywords.TRAMPLE, Keywords.SWIFT],
		"text": "Trample. Swift.",
	},
	{
		"id": "thorned_carapace", "name": "Thorned Carapace", "type": "Gear",
		"cost": 2, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.COMMON,
		"attack_buff": 2, "health_buff": 2,
		"text": "Equipped creature gets +2/+2.",
	},
	{
		"id": "wild_growth_hive", "name": "Wild Growth", "type": "Hive",
		"cost": 3, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.UNCOMMON,
		"static_modifiers": [{"type": "keyword_stat_bonus", "filter_keyword": Keywords.TRAMPLE, "attack": 1}],
		"text": "Your Trample creatures have +1/+0.",
	},
	{
		"id": "chrysalis_titan", "name": "Chrysalis Titan", "type": "Creature",
		"cost": 2, "kingdoms": [Kingdoms.GREEN], "rarity": Rarities.RARE,
		"attack": 6, "health": 6, "keywords": [Keywords.TRAMPLE],
		"ambush": {
			"face_down": {"name": "Dormant Grub", "attack": 0, "health": 2},
			"flip_trigger": "conditional", "flip_condition": {"type": "start_of_next_turn"},
		},
		"text": "Ambush (flips at the start of your next turn). Flips into a 6/6 Trample.",
	},
]

const BLACK: Array[Dictionary] = [
	{
		"id": "black_widow_stalker", "name": "Black Widow Stalker", "type": "Creature",
		"cost": 2, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.COMMON,
		"attack": 2, "health": 1, "keywords": [Keywords.POISON],
		"text": "Poison.",
	},
	{
		"id": "scorpion_skulker", "name": "Scorpion Skulker", "type": "Creature",
		"cost": 3, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.UNCOMMON,
		"attack": 3, "health": 2, "keywords": [Keywords.POISON, Keywords.PIERCE],
		"text": "Poison. Pierce.",
	},
	{
		"id": "wasp_striker", "name": "Wasp Striker", "type": "Creature",
		"cost": 1, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.COMMON,
		"attack": 1, "health": 1, "keywords": [Keywords.POISON],
		"text": "Poison.",
	},
	{
		"id": "tarantula_ambusher", "name": "Tarantula Ambusher", "type": "Creature",
		"cost": 3, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.COMMON,
		"attack": 3, "health": 3, "keywords": [Keywords.POISON],
		"text": "Poison.",
	},
	{
		"id": "cicada_nymph", "name": "Cicada Brood Riser", "type": "Creature",
		"cost": 2, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.RARE,
		"attack": 4, "health": 3, "keywords": [Keywords.DECAY],
		"ambush": {
			"face_down": {"name": "Buried Nymph", "attack": 0, "health": 2},
			"flip_trigger": "conditional", "flip_condition": {"type": "start_of_next_turn"},
		},
		"effects": [{"trigger": "on_death", "effect_id": "summon_token", "params": {"token_id": "cicada_swarm_token", "count": 2}}],
		"text": "Ambush (flips at the start of your next turn). Decay: summon two 1/1 Cicada Swarm tokens.",
	},
	{
		"id": "venom_lash", "name": "Venom Lash", "type": "Ability",
		"cost": 2, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.COMMON,
		"effects": [{"trigger": "on_cast", "effect_id": "damage_creature", "params": {"amount": 3}}],
		"text": "Deal 3 damage to the strongest enemy creature.",
	},
	{
		"id": "sacrificial_rite", "name": "Sacrificial Rite", "type": "Ability",
		"cost": 1, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.COMMON,
		"effects": [
			{"trigger": "on_cast", "effect_id": "damage_leader", "params": {"amount": 2, "target": "self"}},
			{"trigger": "on_cast", "effect_id": "draw_card", "params": {"count": 2}},
		],
		"text": "Your Leader takes 2 damage. Draw 2 cards.",
	},
	{
		"id": "black_widow_matriarch", "name": "Black Widow Matriarch", "type": "Creature",
		"cost": 5, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.LEGENDARY,
		"attack": 5, "health": 4, "keywords": [Keywords.POISON, Keywords.DECAY],
		"effects": [{"trigger": "on_death", "effect_id": "damage_creature", "params": {"amount": 4}}],
		"text": "Poison. Decay: deal 4 damage to the strongest enemy creature.",
	},
	{
		"id": "chitin_plague", "name": "Chitin Plague", "type": "Hive",
		"cost": 3, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.UNCOMMON,
		"static_modifiers": [{"type": "keyword_stat_bonus", "filter_keyword": Keywords.POISON, "attack": 1}],
		"text": "Your Poison creatures have +1/+0.",
	},
	{
		"id": "stinger_gauntlet", "name": "Stinger Gauntlet", "type": "Gear",
		"cost": 2, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.COMMON,
		"attack_buff": 1, "grants_keywords": [Keywords.PIERCE],
		"text": "Equipped creature gets +1/+0 and Pierce.",
	},
	{
		"id": "grave_wasp", "name": "Grave Wasp", "type": "Creature",
		"cost": 4, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.UNCOMMON,
		"attack": 4, "health": 3, "keywords": [Keywords.PIERCE, Keywords.DECAY],
		"effects": [{"trigger": "on_death", "effect_id": "draw_card", "params": {"count": 1}}],
		"text": "Pierce. Decay: draw a card.",
	},
]

const BLUE: Array[Dictionary] = [
	{
		"id": "house_fly_scout", "name": "House Fly Scout", "type": "Creature",
		"cost": 1, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.COMMON,
		"attack": 1, "health": 1, "keywords": [Keywords.FLYING],
		"text": "Flying.",
	},
	{
		"id": "dragonfly_duelist", "name": "Dragonfly Duelist", "type": "Creature",
		"cost": 2, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.COMMON,
		"attack": 2, "health": 2, "keywords": [Keywords.FLYING],
		"text": "Flying.",
	},
	{
		"id": "gnat_swarm", "name": "Gnat Swarm", "type": "Creature",
		"cost": 1, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.COMMON,
		"attack": 1, "health": 1, "keywords": [Keywords.FLYING, Keywords.STEALTH],
		"text": "Flying. Stealth.",
	},
	{
		"id": "mayfly_seer", "name": "Mayfly Seer", "type": "Ability",
		"cost": 2, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.COMMON,
		"effects": [{"trigger": "on_cast", "effect_id": "draw_card", "params": {"count": 2}}],
		"text": "Draw 2 cards.",
	},
	{
		"id": "butterfly_dancer", "name": "Butterfly Dancer", "type": "Creature",
		"cost": 3, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.UNCOMMON,
		"attack": 2, "health": 3, "keywords": [Keywords.FLYING],
		"effects": [{"trigger": "on_play", "effect_id": "draw_card", "params": {"count": 1}}],
		"text": "Flying. On Play: draw a card.",
	},
	{
		"id": "gust_of_wind", "name": "Gust of Wind", "type": "Ability",
		"cost": 2, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.UNCOMMON,
		"effects": [{"trigger": "on_cast", "effect_id": "bounce_creature", "params": {}}],
		"text": "Return the strongest enemy creature to its owner's hand.",
	},
	{
		"id": "dragonfly_ace", "name": "Dragonfly Ace", "type": "Creature",
		"cost": 5, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.LEGENDARY,
		"attack": 5, "health": 4, "keywords": [Keywords.FLYING, Keywords.SWIFT],
		"text": "Flying. Swift.",
	},
	{
		"id": "spider_silk_net", "name": "Spider Silk Net", "type": "Gear",
		"cost": 1, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.COMMON,
		"grants_keywords": [Keywords.REACH],
		"text": "Equipped creature gains Reach.",
	},
	{
		"id": "cloudveil_hive", "name": "Cloudveil", "type": "Hive",
		"cost": 3, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.UNCOMMON,
		"static_modifiers": [{"type": "keyword_stat_bonus", "filter_keyword": Keywords.FLYING, "attack": 1}],
		"text": "Your Flying creatures have +1/+0.",
	},
	{
		"id": "monarch_caterpillar", "name": "Monarch Butterfly", "type": "Creature",
		"cost": 2, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.RARE,
		"attack": 4, "health": 3, "keywords": [Keywords.FLYING],
		"ambush": {
			"face_down": {"name": "Unidentified Caterpillar", "attack": 1, "health": 2},
			"flip_trigger": "paid", "flip_cost": 2,
		},
		"text": "Ambush (Pay 2: flip face up). Flips into a 4/3 Flying.",
	},
	{
		"id": "moth_of_shadows", "name": "Moth of Shadows", "type": "Creature",
		"cost": 3, "kingdoms": [Kingdoms.BLUE], "rarity": Rarities.COMMON,
		"attack": 3, "health": 2, "keywords": [Keywords.STEALTH],
		"text": "Stealth.",
	},
]

## Token creatures, only ever reached via summon_token effects — never in a deck list.
const TOKENS: Array[Dictionary] = [
	{
		"id": "termite_worker_token", "name": "Termite Worker", "type": "Creature",
		"cost": 1, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.COMMON,
		"attack": 1, "health": 1, "keywords": [Keywords.GUARD],
	},
	{
		"id": "ladybug_guard_token", "name": "Ladybug", "type": "Creature",
		"cost": 1, "kingdoms": [Kingdoms.WHITE], "rarity": Rarities.COMMON,
		"attack": 1, "health": 1, "keywords": [Keywords.GUARD],
	},
	{
		"id": "cicada_swarm_token", "name": "Cicada Swarm", "type": "Creature",
		"cost": 1, "kingdoms": [Kingdoms.BLACK], "rarity": Rarities.COMMON,
		"attack": 1, "health": 1, "keywords": [],
	},
]
