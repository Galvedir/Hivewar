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
		"marshal_kesk_bulwark":
			return {"leader_id": "marshal_kesk", "cards": MARSHAL_KESK_BULWARK}
		"sister_wren_reclamation":
			return {"leader_id": "sister_wren", "cards": SISTER_WREN_RECLAMATION}
		"bram_deep_roots":
			return {"leader_id": "bram_undergrowth", "cards": BRAM_DEEP_ROOTS}
		"vera_titans_reach":
			return {"leader_id": "vera_stagmaw", "cards": VERA_TITANS_REACH}
		"grix_creeping_rot":
			return {"leader_id": "grix_the_hollow", "cards": GRIX_CREEPING_ROT}
		"nyxa_grave_ledger":
			return {"leader_id": "nyxa_cobweb", "cards": NYXA_GRAVE_LEDGER}
		"captain_vell_vanguard":
			return {"leader_id": "captain_vell", "cards": CAPTAIN_VELL_VANGUARD}
		"mira_tideglass_veil":
			return {"leader_id": "mira_duskwing", "cards": MIRA_TIDEGLASS_VEIL}
		"skarr_swift_talon":
			return {"leader_id": "skarr_wing_reaver", "cards": SKARR_SWIFT_TALON}
		"vex_feral_instinct":
			return {"leader_id": "vex_the_ravenous", "cards": VEX_FERAL_INSTINCT}
		"thessaly_skybound_accord":
			return {"leader_id": "thessaly_ironwing", "cards": THESSALY_SKYBOUND_ACCORD}
		"korrath_withering_bloom":
			return {"leader_id": "korrath_deathvine", "cards": KORRATH_WITHERING_BLOOM}
		_:
			push_error("DeckDefinitions: unknown deck id '%s'" % deck_id)
			return {}

## One fixed test deck per Leader (18 total), collectively using every card
## in the pool at least once (§ user request).
static func all_deck_ids() -> Array[String]:
	return [
		"white_hive_guardians", "green_wildgrowth", "black_venom_broodmother", "blue_skyswarm",
		"red_bloodhunt", "hybrid_venomwing", "marshal_kesk_bulwark", "sister_wren_reclamation",
		"bram_deep_roots", "vera_titans_reach", "grix_creeping_rot", "nyxa_grave_ledger",
		"captain_vell_vanguard", "mira_tideglass_veil", "skarr_swift_talon", "vex_feral_instinct",
		"thessaly_skybound_accord", "korrath_withering_bloom",
	]

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

const MARSHAL_KESK_BULWARK := {
	"meadow_honeybee": 4, "worker_ant_line": 3, "ladybug_sentry": 3, "pollen_moth": 3,
	"termite_engineer": 3, "shield_beetle": 3, "hive_healer_bee": 3, "ant_phalanx": 2,
	"lifebloom_ladybug": 2, "worker_termite": 3, "honeybee_sentinel": 3, "carpenter_ant_defender": 2,
	"queens_guardian_beetle": 2, "common_cricket": 2, "silverfish_scuttler": 2,
} # 40 cards

const SISTER_WREN_RECLAMATION := {
	"elder_termite_queen": 3, "sanctuary_moth": 4, "radiant_hive_guardian": 1, "mending_wax": 4,
	"fortify": 4, "colony_call": 3, "polished_shell": 2, "royal_sash": 2, "sanctum_of_the_hive": 2,
	"ladybug_healer": 3, "termite_mound": 3, "protective_ward": 2, "ladybug_swarm_queen": 1,
	"royal_jelly": 2, "feeders_bounty": 2, "sharpened_mandibles": 2,
} # 40 cards

const BRAM_DEEP_ROOTS := {
	"sapling_weevil": 4, "burrow_grub": 4, "thornback_beetle": 4, "meadow_cricket": 4,
	"bramble_mantis": 3, "ironhide_pillbug": 2, "verdant_locust_swarm": 3, "deep_root_grub": 2,
	"trampling_stagbeetle": 2, "roly_poly_grub": 3, "giant_weta_hatchling": 3, "stag_beetle_charger": 2,
	"chitin_plating": 2, "reinforced_exoskeleton": 2,
} # 40 cards

const VERA_TITANS_REACH := {
	"weta_colossus": 4, "ancient_carapace": 4, "titan_weta_matriarch": 1, "sudden_growth": 4,
	"deep_roots": 4, "natures_bounty": 4, "bark_shield": 3, "serrated_claws": 2, "overgrown_thicket": 2,
	"rhinoceros_beetle": 3, "pillbug_titan": 2, "praying_mantis": 3, "giant_millipede": 2, "locust_plague": 2,
} # 40 cards

const GRIX_CREEPING_ROT := {
	"venomous_recluse": 4, "grave_beetle": 3, "pit_viper_centipede": 3, "carrion_fly": 3,
	"widow_hatchling": 3, "bone_wasp": 4, "plague_scorpion": 3, "toxic_swarm_locust": 3,
	"black_widow_stalker": 3, "wasp_striker": 3, "tarantula_ambusher": 2, "common_roach": 4,
	"adaptive_strike": 2, "garden_earwig": 2,
} # 42 cards

const NYXA_GRAVE_LEDGER := {
	"necrotic_beetle": 4, "venom_drenched_tarantula": 4, "widow_matriarchs_brood": 4, "scorpion_king": 1,
	"blood_pact": 4, "venom_burst": 4, "grim_harvest": 4, "plague_pit": 3, "scorpion_skulker": 3,
	"grave_wasp": 3, "sacrificial_rite": 2, "field_grasshopper": 2, "armored_beetle_grub": 2,
} # 40 cards

const CAPTAIN_VELL_VANGUARD := {
	"pond_skimmer": 3, "mayfly_drifter": 3, "whisper_gnat": 3, "swift_dragonlet": 3,
	"glassy_wing_moth": 3, "fog_moth": 4, "azure_damselfly": 4, "veil_moth": 2,
	"current_rider_dragonfly": 3, "cloudmind_butterfly": 2, "house_fly_scout": 3, "dragonfly_duelist": 3,
	"silverfish_scuttler": 2, "wandering_silverfish": 2,
} # 40 cards

const MIRA_TIDEGLASS_VEIL := {
	"tempest_dragonfly": 4, "monarch_ascendant": 4, "skywhisper_matriarch": 1, "gale_step": 3,
	"tidal_insight": 3, "windswept_veil": 4, "storm_surge": 3, "gossamer_wings": 3, "veil_of_mist": 2,
	"gnat_swarm": 3, "mayfly_seer": 3, "moth_of_shadows": 3, "locust_swarm": 2, "feeder_drone": 2,
} # 40 cards

const SKARR_SWIFT_TALON := {
	"deer_fly_harasser": 4, "bed_bug_swarm": 4, "midge_cloud": 4, "robber_fly": 4,
	"warble_berserker": 4, "stinkbug_brawler": 4, "vampire_moth": 3, "hornet_queen_scourge": 1,
	"mosquito_swarm": 3, "flea_biter": 3, "assassin_bug": 2, "common_cricket": 2, "universal_ration": 2,
} # 40 cards

const VEX_FERAL_INSTINCT := {
	"reckless_bite": 4, "swarm_tactics": 4, "bloodlust": 4, "feeding_strike": 4, "thousand_stings": 4,
	"reckless_gambit": 3, "blood_vial": 2, "bloodhunt_frenzy": 2, "chigger_pest": 3, "blood_tick": 3,
	"horsefly_raider": 3, "silverfish_scuttler": 2, "house_centipede": 2,
} # 40 cards

const THESSALY_SKYBOUND_ACCORD := {
	"armored_hornet": 4, "skyguard_dragonfly": 4, "thorned_guardian_beetle": 4, "hive_wraith": 4,
	"galeforce_hornet": 4, "twilight_swarm_queen": 1, "worker_termite": 4, "house_fly_scout": 4,
	"ladybug_healer": 4, "dragonfly_duelist": 3, "common_cricket": 3, "swarm_engine": 1,
} # 40 cards

const KORRATH_WITHERING_BLOOM := {
	"rampaging_locust_swarm": 4, "shadow_widow": 4, "venom_wing_moth": 4, "bloodroot_mantis": 4,
	"verdant_widow": 4, "black_widow_stalker": 4, "roly_poly_grub": 4, "scorpion_skulker": 4,
	"giant_weta_hatchling": 4, "giant_millipede": 2, "iron_carapace_roach": 2,
} # 40 cards
