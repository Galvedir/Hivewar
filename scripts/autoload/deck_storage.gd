extends Node
## Autoload: persists player-built decks to disk (§13) as user://decks.json
## — an array of {name, leader_id, cards: {card_id: count}} dictionaries.
## No unlock economy exists yet (Phase 3), so every card in CardDatabase is
## eligible for any deck; validate() only enforces §9's construction rules
## (40-60 cards, max 4 copies per name, a Leader chosen).

const SAVE_PATH := "user://decks.json"
const MIN_DECK_SIZE := 40
const MAX_DECK_SIZE := 60
const MAX_COPIES := 4

var decks: Array[Dictionary] = [] # [{name: String, leader_id: String, cards: Dictionary}]

func _ready() -> void:
	load_decks()

func load_decks() -> void:
	decks.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Array:
		for d in parsed:
			if d is Dictionary and d.has("name") and d.has("leader_id") and d.has("cards"):
				decks.append(_normalize(d))

func save_decks() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("DeckStorage: could not open %s for writing" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(decks, "\t"))
	f.close()

## JSON round-trips ints as floats; normalize card counts back to int so
## downstream code (DeckDefinitions.expand-style logic) doesn't have to care.
func _normalize(d: Dictionary) -> Dictionary:
	var cards: Dictionary = {}
	for card_id in (d["cards"] as Dictionary).keys():
		cards[card_id] = int(d["cards"][card_id])
	return {"name": String(d["name"]), "leader_id": String(d["leader_id"]), "cards": cards}

func get_deck(deck_name: String) -> Dictionary:
	for d: Dictionary in decks:
		if d["name"] == deck_name:
			return d
	return {}

func has_deck(deck_name: String) -> bool:
	return not get_deck(deck_name).is_empty()

func all_deck_names() -> Array[String]:
	var names: Array[String] = []
	for d: Dictionary in decks:
		names.append(d["name"])
	return names

## Saves (creating or overwriting by name) a deck. Does not validate —
## callers should check validate() first and decide how to surface errors.
func save_deck(deck_name: String, leader_id: String, cards: Dictionary) -> void:
	var entry := {"name": deck_name, "leader_id": leader_id, "cards": cards}
	for i in range(decks.size()):
		if decks[i]["name"] == deck_name:
			decks[i] = entry
			save_decks()
			return
	decks.append(entry)
	save_decks()

func delete_deck(deck_name: String) -> void:
	decks = decks.filter(func(d: Dictionary) -> bool: return d["name"] != deck_name)
	save_decks()

## §9 deck construction rules. Returns a list of human-readable problems;
## empty means the deck is legal to save/play.
func validate(deck_name: String, leader_id: String, cards: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if deck_name.strip_edges() == "":
		errors.append("Give the deck a name.")
	if leader_id == "" or CardDatabase.get_leader(leader_id) == null:
		errors.append("Choose a Leader.")
	var total := 0
	for card_id in cards.keys():
		var count := int(cards[card_id])
		total += count
		if count > MAX_COPIES:
			var cd := CardDatabase.get_card(card_id)
			errors.append("%s has %d copies (max %d)." % [cd.card_name if cd != null else card_id, count, MAX_COPIES])
	if total < MIN_DECK_SIZE or total > MAX_DECK_SIZE:
		errors.append("Deck has %d cards — must be %d-%d." % [total, MIN_DECK_SIZE, MAX_DECK_SIZE])
	return errors

## Flat Array[String] of card ids, one per copy — same shape DeckDefinitions.expand() produces.
static func expand(cards: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for card_id: String in cards.keys():
		for i in range(int(cards[card_id])):
			out.append(card_id)
	return out
