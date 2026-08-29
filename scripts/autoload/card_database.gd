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
var _texture_cache: Dictionary = {} # path -> Texture2D
var _kingdom_frames: Dictionary = {} # Kingdom name -> frame texture path

## Card and Leader art (§ user request) is dropped in as separate flat
## folders and matched to a card purely by name, rather than being wired up
## by id in every card_definitions.gd entry — this lets art get added
## incrementally during playtesting without any code/data changes per card.
const CARD_ILLUSTRATIONS_DIR := "res://art/cards/illustrations/"
const LEADER_ILLUSTRATIONS_DIR := "res://art/leaders/"
const CARD_FRAMES_DIR := "res://art/cards/frames/"

func _ready() -> void:
	var card_art := _scan_illustrations(CARD_ILLUSTRATIONS_DIR)
	var leader_art := _scan_leader_art(LEADER_ILLUSTRATIONS_DIR)
	_kingdom_frames = _scan_kingdom_frames(CARD_FRAMES_DIR)
	_load_cards(card_art)
	_load_leaders(leader_art)

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

func _load_cards(art_map: Dictionary) -> void:
	for def: Dictionary in CardDefinitions.get_all():
		var card: CardData = _build_card(def)
		if card != null:
			card.illustration_path = art_map.get(_normalize_name(card.card_name), "")
			_cards[card.id] = card

func _load_leaders(art_map: Dictionary) -> void:
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
		leader.ultimate_variable_cost = def.get("ultimate_variable_cost", false)
		var art: Dictionary = art_map.get(_normalize_name(leader.card_name), {})
		leader.illustration_path = art.get("portrait", "")
		leader.animation_sprite_path = art.get("animation", "")
		_leaders[leader.id] = leader

func _is_image_file(file_name: String) -> bool:
	if file_name.ends_with(".import"):
		return false
	var ext := file_name.get_extension().to_lower()
	return ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp"

## Lists image files directly in `dir_path` and indexes them by a
## normalized form of their filename (see _normalize_name), so e.g.
## "Azure_Damselfly.png" matches a card named "Azure Damselfly". No-ops
## (returns an empty map) if the folder doesn't exist yet.
func _scan_illustrations(dir_path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_image_file(file_name):
			out[_normalize_name(file_name.get_basename())] = dir_path + file_name
		file_name = dir.get_next()
	dir.list_dir_end()
	return out

## Leader art (§ user request) lives one subfolder per Leader under
## art/leaders/ — e.g. "Hesper_The_Hourglass_Weaver/" — each holding a
## portrait image and optionally a second file with "animation" in its
## name: a 4x4 sprite sheet that plays once over the portrait when that
## Leader's enlarged hover card is shown (see CardPreviewOverlay). The
## subfolder name is matched to a Leader the same fuzzy way filenames are
## elsewhere (see _normalize_name) — e.g. "One_From_The_Square_Mound"
## matches "One, from the Square Mound". A flat image file placed directly
## in art/leaders/ (no subfolder) still works too, for a Leader that
## hasn't been moved into its own folder yet. Returns
## {normalized_leader_name: {"portrait": path, "animation": path_or_empty}}.
func _scan_leader_art(dir_path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				var sub_path := dir_path + entry + "/"
				var found := _scan_leader_folder(sub_path)
				if found.get("portrait", "") != "":
					out[_normalize_name(entry)] = found
		elif _is_image_file(entry):
			out[_normalize_name(entry.get_basename())] = {"portrait": dir_path + entry, "animation": ""}
		entry = dir.get_next()
	dir.list_dir_end()
	return out

## Within one Leader's art subfolder: whichever image file's name contains
## "animation" is the sprite sheet, the other is the static portrait.
func _scan_leader_folder(sub_path: String) -> Dictionary:
	var portrait := ""
	var animation := ""
	var dir := DirAccess.open(sub_path)
	if dir == null:
		return {"portrait": portrait, "animation": animation}
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_image_file(file_name):
			if file_name.to_lower().contains("animation"):
				animation = sub_path + file_name
			else:
				portrait = sub_path + file_name
		file_name = dir.get_next()
	dir.list_dir_end()
	return {"portrait": portrait, "animation": animation}

## Kingdom card-frame backgrounds (§ user request): one image per Kingdom,
## dropped into art/cards/frames/ as e.g. "Monogyne_Card_background.png" —
## matched to a Kingdom by checking whether the filename (normalized the
## same way everything else is) contains that Kingdom's own normalized
## name, so a future frame just needs the Kingdom's name somewhere in its
## filename, no fixed naming convention required. Cards whose Kingdom has
## no matching frame yet fall back to their existing plain-color look.
func _scan_kingdom_frames(dir_path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_image_file(file_name):
			var normalized := _normalize_name(file_name.get_basename())
			for kingdom: String in Kingdoms.ALL + [Kingdoms.COLORLESS]:
				if normalized.contains(_normalize_name(kingdom)):
					out[kingdom] = dir_path + file_name
		file_name = dir.get_next()
	dir.list_dir_end()
	return out

## Lowercases, strips punctuation, and drops filler words so filenames and
## printed card names compare equal despite cosmetic differences (spaces vs
## underscores, a stray comma, an inserted "The").
func _normalize_name(s: String) -> String:
	var cleaned := s.to_lower().replace(",", " ").replace("_", " ").replace("-", " ")
	var out := ""
	for word in cleaned.split(" ", false):
		if word == "the" or word == "a" or word == "an":
			continue
		out += word
	return out

## Loads (and caches) the Texture2D for a card/leader's illustration_path.
## Fails safe to null — same pattern as every other optional art asset in
## this project — if no art has been matched for this card yet, or the
## matched file no longer exists.
func get_illustration_texture(card: CardData) -> Texture2D:
	if card == null:
		return null
	return _load_and_cache(card.illustration_path)

## The card-frame background texture for `card`'s Kingdom. An empty
## kingdoms array means Colorless — same convention CardRenderUtil.
## kingdom_label already uses. For a Hybrid/multi-Kingdom card (Leaders
## especially — § user request: Leader cards should reliably have a full
## art background), every one of its Kingdoms is checked in order rather
## than just the first, so it only comes up empty if NONE of its Kingdoms
## has a frame image yet.
func get_kingdom_frame_texture(card: CardData) -> Texture2D:
	if card == null:
		return null
	if card.kingdoms.is_empty():
		return _load_and_cache(_kingdom_frames.get(Kingdoms.COLORLESS, ""))
	for kingdom: String in card.kingdoms:
		if _kingdom_frames.has(kingdom):
			return _load_and_cache(_kingdom_frames[kingdom])
	return null

func _load_and_cache(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	_texture_cache[path] = tex
	return tex

func _build_card(def: Dictionary) -> CardData:
	var type: String = def.get("type", CardTypes.CREATURE)
	var card: CardData
	match type:
		CardTypes.CREATURE:
			var c := CreatureData.new()
			c.attack = def.get("attack", 0)
			c.health = def.get("health", 1)
			c.creature_type = def.get("creature_type", "")
			c.is_token = def.get("is_token", false)
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
