class_name DeckDefinitions
extends RefCounted
## Four hand-authored ~30-card test decks (§11 Phase 1 scope), one per
## represented Kingdom, each paired with its Kingdom's Leader so every card
## in the deck costs its printed Larva total (no off-Kingdom surcharge) --
## see §4. Each entry is {card_id: count}, max 4 copies per name (§9).

static func get_deck(deck_id: String) -> Dictionary:
	match deck_id:
		"white_hive_guardians":
			return {"leader_id": "queen_amara", "cards": WHITE_HIVE_GUARDIANS}
		"green_wildgrowth":
			return {"leader_id": "thornback_grael", "cards": GREEN_WILDGROWTH}
		"black_venom_broodmother":
			return {"leader_id": "matriarch_vess", "cards": BLACK_VENOM_BROODMOTHER}
		"blue_skyswarm":
			return {"leader_id": "skywhisper_iyra", "cards": BLUE_SKYSWARM}
		"red_bloodhunt":
			return {"leader_id": "karneth_bloodfang", "cards": RED_BLOODHUNT}
		"hybrid_venomwing":
			return {"leader_id": "zeth_cindermaw", "cards": HYBRID_VENOMWING}
		_:
			push_error("DeckDefinitions: unknown deck id '%s'" % deck_id)
			return {}

static func all_deck_ids() -> Array[String]:
	return ["white_hive_guardians", "green_wildgrowth", "black_venom_broodmother", "blue_skyswarm", "red_bloodhunt", "hybrid_venomwing"]

## Expands a {card_id: count} deck entry into a flat Array[String] of card ids, one per copy.
static func expand(deck_cards: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for card_id: String in deck_cards.keys():
		for i in range(int(deck_cards[card_id])):
			out.append(card_id)
	return out

const WHITE_HIVE_GUARDIANS := {
	"worker_termite": 4,
	"honeybee_sentinel": 4,
	"ladybug_healer": 3,
	"carpenter_ant_defender": 3,
	"termite_mound": 2,
	"queens_guardian_beetle": 2,
	"hive_blessing": 3,
	"protective_ward": 2,
	"ladybug_swarm_queen": 1,
	"termite_colony": 2,
	"wax_moth_larva": 2,
	"royal_jelly": 2,
} # 30 cards

const GREEN_WILDGROWTH := {
	"roly_poly_grub": 4,
	"giant_weta_hatchling": 4,
	"stag_beetle_charger": 3,
	"molting_grub": 2,
	"rhinoceros_beetle": 3,
	"pillbug_titan": 2,
	"overgrowth": 3,
	"praying_mantis": 3,
	"goliath_beetle": 1,
	"thorned_carapace": 2,
	"wild_growth_hive": 2,
	"chrysalis_titan": 1,
} # 30 cards

const BLACK_VENOM_BROODMOTHER := {
	"black_widow_stalker": 4,
	"scorpion_skulker": 3,
	"wasp_striker": 4,
	"cicada_nymph": 2,
	"venom_lash": 3,
	"sacrificial_rite": 2,
	"black_widow_matriarch": 1,
	"chitin_plague": 2,
	"stinger_gauntlet": 2,
	"grave_wasp": 3,
	"tarantula_ambusher": 4,
} # 30 cards

const BLUE_SKYSWARM := {
	"house_fly_scout": 4,
	"dragonfly_duelist": 4,
	"gnat_swarm": 3,
	"mayfly_seer": 3,
	"butterfly_dancer": 3,
	"gust_of_wind": 3,
	"dragonfly_ace": 1,
	"spider_silk_net": 2,
	"cloudveil_hive": 2,
	"monarch_caterpillar": 2,
	"moth_of_shadows": 3,
} # 30 cards

const RED_BLOODHUNT := {
	"mosquito_swarm": 4,
	"flea_biter": 4,
	"chigger_pest": 3,
	"blood_tick": 3,
	"horsefly_raider": 3,
	"assassin_bug": 2,
	"hornet_skirmisher": 2,
	"botfly_harrier": 2,
	"blood_wasp_swarm": 2,
	"tick_matriarch": 1,
	"chigger_swarm_lord": 1,
	"bloodhunt_alpha": 1,
	"blood_frenzy": 2,
} # 30 cards

const HYBRID_VENOMWING := {
	"venomous_stinger_wasp": 3,
	"wasp_striker": 3,
	"black_widow_stalker": 3,
	"scorpion_skulker": 2,
	"mosquito_swarm": 3,
	"blood_tick": 3,
	"hornet_skirmisher": 2,
	"blood_frenzy": 2,
	"withering_touch": 2,
	"venom_lash": 2,
	"barbed_stinger": 2,
	"venom_fangs": 2,
	"gravehatch_riser": 1,
} # 30 cards
