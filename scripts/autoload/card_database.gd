extends Node
## Autoload: loads and indexes every CardData/LeaderData, built from the
## plain-GDScript tables in data/card_definitions.gd and
## data/leader_definitions.gd (§13). Keeping content in data tables rather
## than hand-authored .tres files is a Phase 1 shortcut — content can be
## migrated to .tres resources in Phase 2 without touching any code that
## calls get_card()/get_leader(), since both return the same CardData/
## LeaderData objects either way.

var _cards: Dictionary = {}   # id -> CardData
var _leaders: Dictionary = {} # id -> LeaderData

func _ready() -> void:
	_load_cards()
	_load_leaders()

func get_card(id: String) -> CardData:
	if not _cards.has(id):
		push_error("CardDatabase: unknown card id '%s'" % id)
		return null
	return _cards[id]

func get_leader(id: String) -> LeaderData:
	if not _leaders.has(id):
		push_error("CardDatabase: unknown leader id '%s'" % id)
		return null
	return _leaders[id]

func all_cards() -> Array:
	return _cards.values()

func all_leaders() -> Array:
	return _leaders.values()

## Builds a fresh CardInstance for a card id, owned by owner_id.
func create_instance(id: String, owner_id: int) -> CardInstance:
	var card_data: CardData = get_card(id)
	if card_data == null:
		return null
	return CardInstance.new(card_data, owner_id)

func _load_cards() -> void:
	for def: Dictionary in CardDefinitions.get_all():
		var card: CardData = _build_card(def)
		if card != null:
			_cards[card.id] = card

func _load_leaders() -> void:
	for def: Dictionary in LeaderDefinitions.get_all():
		var leader := LeaderData.new()
		leader.id = def.get("id", "")
		leader.card_name = def.get("name", "")
		leader.kingdoms = _str_array(def.get("kingdoms", []))
		leader.rarity = Rarities.LEGENDARY
		leader.text = def.get("text", "")
		leader.starting_health = def.get("starting_health", 30)
		leader.hero_power_cost = def.get("hero_power_cost", 2)
		leader.hero_power_text = def.get("hero_power_text", "")
		leader.hero_power_effects = _dict_array(def.get("hero_power_effects", []))
		leader.ultimate_cost = def.get("ultimate_cost", 6)
		leader.ultimate_text = def.get("ultimate_text", "")
		leader.ultimate_effects = _dict_array(def.get("ultimate_effects", []))
		_leaders[leader.id] = leader

func _build_card(def: Dictionary) -> CardData:
	var type: String = def.get("type", CardTypes.CREATURE)
	var card: CardData
	match type:
		CardTypes.CREATURE:
			var c := CreatureData.new()
			c.attack = def.get("attack", 0)
			c.health = def.get("health", 1)
			c.creature_type = def.get("creature_type", "")
			c.keywords = _str_array(def.get("keywords", []))
			c.effects = _dict_array(def.get("effects", []))
			c.ambush = (def.get("ambush", {}) as Dictionary).duplicate(true)
			card = c
		CardTypes.ABILITY:
			var a := AbilityData.new()
			a.effects = _dict_array(def.get("effects", []))
			card = a
		CardTypes.GEAR:
			var g := GearData.new()
			g.attack_buff = def.get("attack_buff", 0)
			g.health_buff = def.get("health_buff", 0)
			g.grants_keywords = _str_array(def.get("grants_keywords", []))
			g.effects = _dict_array(def.get("effects", []))
			card = g
		CardTypes.HIVE:
			var h := HiveData.new()
			h.static_modifiers = _dict_array(def.get("static_modifiers", []))
			h.effects = _dict_array(def.get("effects", []))
			card = h
		_:
			push_error("CardDatabase: unknown card type '%s' for id '%s'" % [type, def.get("id", "?")])
			return null

	card.id = def.get("id", "")
	card.card_name = def.get("name", "")
	card.cost = def.get("cost", 0)
	card.kingdoms = _str_array(def.get("kingdoms", []))
	card.rarity = def.get("rarity", Rarities.COMMON)
	card.text = def.get("text", "")
	card.is_legendary = def.get("is_legendary", card.rarity == Rarities.LEGENDARY)
	return card

## GDScript can't assign a plain untyped Array into an Array[String]/
## Array[Dictionary]-typed property directly; the data tables hand us
## untyped Arrays (they're built from Dictionary literals), so convert here.
func _str_array(src: Array) -> Array[String]:
	var out: Array[String] = []
	for v in src:
		out.append(v)
	return out

func _dict_array(src: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v in src:
		out.append((v as Dictionary).duplicate(true))
	return out
