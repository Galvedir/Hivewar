class_name CardInstance
extends RefCounted
## A live copy of a card in a match: printed CardData plus all the runtime
## state that changes during play (damage, keywords granted, Ambush face,
## Poison counters, etc). GameState/CombatResolver/EffectResolver operate on
## these, never on CardData directly, so printed cards stay immutable.

static var _next_id := 1

var instance_id: int
var data: CardData          # the currently-visible face (face-down data while an Ambush creature is hidden)
var true_data: CreatureData # the real card behind an Ambush creature; null for everything else
var owner_id: int = -1      # index into GameState.players — not a direct reference, to avoid ref cycles

# Creature-only runtime state (meaningless unless `data is CreatureData`)
var current_attack: int = 0
var max_health: int = 0
var damage_marked: int = 0
var runtime_keywords: Array[String] = []
var temp_keywords: Array[String] = [] # granted "this turn" only; cleared by TurnManager at end of turn
var poison_counters: int = 0
var summoning_sick: bool = true
var has_attacked_this_turn: bool = false
var is_face_down: bool = false
var turns_in_play: int = 0
var attached_gear: Array[CardInstance] = []

func _init(card_data: CardData, p_owner_id: int) -> void:
	instance_id = _next_id
	_next_id += 1
	data = card_data
	owner_id = p_owner_id
	if card_data is CreatureData:
		var cd: CreatureData = card_data
		if cd.is_ambush():
			_setup_ambush(cd)
		else:
			current_attack = cd.attack
			max_health = cd.health
			runtime_keywords = cd.keywords.duplicate()
			summoning_sick = not has_keyword(Keywords.SWIFT)

func _setup_ambush(cd: CreatureData) -> void:
	true_data = cd
	is_face_down = true
	var fd: Dictionary = cd.ambush.get("face_down", {})
	var face_down := CreatureData.new()
	face_down.id = cd.id + "_facedown"
	face_down.card_name = fd.get("name", "Unidentified Larva")
	face_down.attack = fd.get("attack", 0)
	face_down.health = fd.get("health", 1)
	face_down.kingdoms = []
	data = face_down
	current_attack = face_down.attack
	max_health = face_down.health
	runtime_keywords = []
	summoning_sick = true

## Flips a face-down Ambush creature to its true face (§8). Combat stats and
## keywords are replaced wholesale; damage already marked carries through.
func flip_face_up() -> void:
	if not is_face_down or true_data == null:
		return
	is_face_down = false
	data = true_data
	current_attack = true_data.attack
	max_health = true_data.health
	runtime_keywords = true_data.keywords.duplicate()

func current_health() -> int:
	return max_health - damage_marked

func is_alive() -> bool:
	return current_health() > 0

func has_keyword(kw: String) -> bool:
	return runtime_keywords.has(kw) or temp_keywords.has(kw)

func display_name() -> String:
	return data.card_name

func creature_data() -> CreatureData:
	return data as CreatureData
