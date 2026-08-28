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
var temp_keywords: Array[String] = [] # granted "until end of next turn"; cleared by TurnManager at the start of the owner's following turn
var poison_counters: int = 0
var summoning_sick: bool = true
var has_attacked_this_turn: bool = false # also means "exhausted" — see is_exhausted()
var temp_attack_bonus: int = 0 # tracks the portion of current_attack from an "until end of next turn" buff, so it can be cleanly reverted
var temp_health_bonus: int = 0
var is_face_down: bool = false
var turns_in_play: int = 0
var attached_gear: Array[CardInstance] = []
var granted_effects: Array[Dictionary] = [] # extra {trigger, effect_id, params, beneficiary_owner_id} entries attached at runtime (e.g. Botfly's granted Decay), resolved alongside this creature's own printed effects
var colony_bonus: int = 0 # currently-applied total health bonus from Colony sources (§ Colony keyword); tracked so EffectResolver.refresh_colony_bonuses can cleanly strip and recompute it

## A card is its true self while in deck/hand — it's only "face-down" as a
## board state once played (§8; see enter_play_face_down). Cost, name, and
## text must all read correctly while sitting in the owner's hand.
func _init(card_data: CardData, p_owner_id: int) -> void:
	instance_id = _next_id
	_next_id += 1
	data = card_data
	owner_id = p_owner_id
	if card_data is CreatureData:
		var cd: CreatureData = card_data
		current_attack = cd.attack
		max_health = cd.health
		runtime_keywords = cd.keywords.duplicate()
		summoning_sick = not has_keyword(Keywords.SWIFT)
		if cd.is_ambush():
			true_data = cd

## Called by TurnManager when an Ambush creature is played from hand (§8) —
## swaps the visible face to the generic face-down side. Must not run any
## earlier than this, or the card would show 0 cost / no text in hand.
func enter_play_face_down() -> void:
	if true_data == null:
		return
	is_face_down = true
	var fd: Dictionary = true_data.ambush.get("face_down", {})
	var face_down := CreatureData.new()
	face_down.id = true_data.id + "_facedown"
	face_down.card_name = fd.get("name", "Unidentified Larva")
	face_down.attack = fd.get("attack", 0)
	face_down.health = fd.get("health", 1)
	face_down.kingdoms = []
	# A face-down side can carry its own keywords (§ user request — e.g.
	# Milkweed Monarch's face-down Caterpillar has Poison) — printed on
	# face_down.keywords like any other creature, and reflected in prose
	# via face_down.text using the same period-joined convention every
	# other card's keyword line already uses.
	var fd_keywords: Array[String] = []
	for kw in fd.get("keywords", []):
		fd_keywords.append(kw)
	face_down.keywords = fd_keywords
	if not fd_keywords.is_empty():
		face_down.text = ". ".join(fd_keywords) + "."
	data = face_down
	current_attack = face_down.attack
	max_health = face_down.health
	runtime_keywords = fd_keywords.duplicate()
	summoning_sick = true
	colony_bonus = 0 # stat baseline is being reset wholesale; a refresh right after will recompute cleanly

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
	colony_bonus = 0 # stat baseline is being reset wholesale; a refresh right after will recompute cleanly

func current_health() -> int:
	return max_health - damage_marked

func is_alive() -> bool:
	return current_health() > 0

func has_keyword(kw: String) -> bool:
	return runtime_keywords.has(kw) or temp_keywords.has(kw)

## Exhaustion (§ user request): a creature that has attacked this turn
## can't be chosen as an optional blocker until its controller's next turn
## clears has_attacked_this_turn. Named separately from that field for
## clarity at call sites even though it's the same underlying state.
func is_exhausted() -> bool:
	return has_attacked_this_turn

## Adds a stat bonus that expires at the end of the owner's next turn (e.g.
## "+2/+0 until end of next turn"). The bonus amount is tracked so
## clear_temp_buffs() can revert exactly this much regardless of other
## permanent changes in between — addition/subtraction commute, so order
## never matters.
func add_temp_buff(attack_bonus: int, health_bonus: int) -> void:
	current_attack += attack_bonus
	max_health += health_bonus
	temp_attack_bonus += attack_bonus
	temp_health_bonus += health_bonus

func clear_temp_buffs() -> void:
	if temp_attack_bonus != 0 or temp_health_bonus != 0:
		current_attack -= temp_attack_bonus
		max_health -= temp_health_bonus
		temp_attack_bonus = 0
		temp_health_bonus = 0

func display_name() -> String:
	return data.card_name

func creature_data() -> CreatureData:
	return data as CreatureData
