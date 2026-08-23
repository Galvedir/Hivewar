extends Node
## Regression check for the deckbuilder + custom-deck constructed play
## (§11 Phase 2): drives the real DeckBuilderUI, not DeckStorage directly,
## since building/saving/loading/validating is where user interaction
## actually happens. Cleans up its own test decks from user://decks.json
## afterward so repeated runs don't pollute real save data.

const MainScene := preload("res://scenes/Main.tscn")
const TEST_DECK_NAME := "__QA Test Deck__"
const TEST_DECK_NAME_2 := "__QA Test Deck 2__"

var _failures := 0

func _ready() -> void:
	print("=== Deckbuilder + constructed-play check ===")
	# Start clean in case a prior aborted run left test decks behind.
	DeckStorage.delete_deck(TEST_DECK_NAME)
	DeckStorage.delete_deck(TEST_DECK_NAME_2)

	var main := MainScene.instantiate()
	add_child(main)
	var db: DeckBuilderUI = main._deck_builder

	# --- Screens actually get a nonzero size when shown ------------------------
	# Regression check: set_anchors_preset(PRESET_FULL_RECT) defaults to
	# resize_mode = PRESET_MODE_MINSIZE, which sizes a control to its own
	# minimum size rather than stretching it to fill its parent — a plain
	# Control with no inherent minimum size silently renders at (0,0) with
	# no error. Bit both DeckBuilderUI and CollectionUI this way in practice
	# (fixed via LayoutUtil.fill_parent, which sets anchors+offsets explicitly).
	main._on_open_deck_builder()
	_check(db.size.x > 100 and db.size.y > 100, "Deck Builder screen has a real nonzero size when opened (got %s)" % db.size)
	main._on_deck_builder_closed()
	main._on_open_collection()
	var col: CollectionUI = main._collection
	_check(col.size.x > 100 and col.size.y > 100, "Collection screen has a real nonzero size when opened (got %s)" % col.size)
	main._on_collection_closed()

	# --- Rules screen: real size, and returns to whichever screen opened it ---
	var rules: RulesScreenUI = main._rules_screen
	main._on_open_rules(main._deck_select)
	_check(rules.size.x > 100 and rules.size.y > 100, "Rules screen has a real nonzero size when opened (got %s)" % rules.size)
	_check(not main._deck_select.visible, "Opening Rules hides the screen it was opened from")
	main._on_rules_closed()
	_check(rules.visible == false and main._deck_select.visible, "Closing Rules (opened from the main menu) returns to the main menu")

	main._on_open_deck_builder()
	main._on_open_rules(main._deck_builder)
	main._on_rules_closed()
	_check(main._deck_builder.visible and not main._deck_select.visible, "Closing Rules (opened from the Deck Builder) returns to the Deck Builder, not the main menu")
	main._on_deck_builder_closed()

	# --- Deck-select list is actually scrollable (18 fixed decks overflow the window) ---
	# Container layout resolves only after real frame processing, unlike the
	# anchor-preset bug above — this needs `await`, not an immediate check.
	for i in range(5):
		await get_tree().process_frame
	var scroll := _find_scroll_container(main._deck_select)
	_check(scroll != null, "Deck-select screen has a ScrollContainer")
	if scroll != null:
		_check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "Deck list content is taller than its scroll viewport (scrolling is actually needed and works)")

	# --- Validation rejects an incomplete deck -----------------------------
	db._new_deck()
	db._leader_id = "queen_amara"
	db._cards = {"worker_termite": 4}
	var errors := DeckStorage.validate("x", db._leader_id, db._cards)
	_check(not errors.is_empty(), "Validation rejects a 4-card deck (needs 40-60)")

	# --- Max-copy enforcement ------------------------------------------------
	db._new_deck()
	db._leader_id = "queen_amara"
	for i in range(6):
		db._add_card("worker_termite")
	_check(int(db._cards.get("worker_termite", 0)) == DeckStorage.MAX_COPIES, "Adding a 5th/6th copy caps at the %d-copy limit" % DeckStorage.MAX_COPIES)

	# --- Build a full legal deck and save it ---------------------------------
	db._new_deck()
	db._leader_id = "queen_amara"
	var pool: Array[String] = ["worker_termite", "honeybee_sentinel", "ladybug_healer", "carpenter_ant_defender",
		"termite_mound", "queens_guardian_beetle", "hive_blessing", "protective_ward", "termite_colony",
		"royal_jelly", "meadow_honeybee", "worker_ant_line"]
	for card_id in pool:
		for i in range(4):
			db._add_card(card_id)
	var total_cards := 0
	for c in db._cards.values():
		total_cards += int(c)
	_check(total_cards >= DeckStorage.MIN_DECK_SIZE and total_cards <= DeckStorage.MAX_DECK_SIZE,
		"Built deck lands in the legal 40-60 range (got %d)" % total_cards)

	db._name_edit.text = TEST_DECK_NAME
	db._on_save_pressed()
	_check(DeckStorage.has_deck(TEST_DECK_NAME), "Saving a legal deck persists it to DeckStorage")

	# --- Loading restores state, editing + re-saving under a new name renames it ---
	db._new_deck()
	db._load_deck(TEST_DECK_NAME)
	_check(db._leader_id == "queen_amara" and int(db._cards.get("worker_termite", 0)) == 4, "Loading a saved deck restores its Leader and card counts")
	db._name_edit.text = TEST_DECK_NAME_2
	db._on_save_pressed()
	_check(DeckStorage.has_deck(TEST_DECK_NAME_2) and not DeckStorage.has_deck(TEST_DECK_NAME), "Re-saving a loaded deck under a new name renames it (old name removed)")

	# --- Deletion --------------------------------------------------------------
	DeckStorage.delete_deck(TEST_DECK_NAME_2)
	_check(not DeckStorage.has_deck(TEST_DECK_NAME_2), "Deleting a deck removes it from DeckStorage")

	# --- Constructed play: a custom deck actually plays through TurnManager -----
	var custom_cards := {
		"worker_termite": 4, "honeybee_sentinel": 4, "ladybug_healer": 4, "carpenter_ant_defender": 4,
		"termite_mound": 4, "queens_guardian_beetle": 4, "hive_blessing": 3, "protective_ward": 3,
		"ladybug_swarm_queen": 1, "termite_colony": 3, "wax_moth_larva": 3, "royal_jelly": 3,
	} # sums to 40
	var custom_total := 0
	for c in custom_cards.values():
		custom_total += int(c)
	DeckStorage.save_deck(TEST_DECK_NAME, "queen_amara", custom_cards)
	_check(custom_total >= 40 and custom_total <= 60, "Custom deck for the play test is itself legal (%d cards)" % custom_total)

	main._on_deck_chosen(TEST_DECK_NAME)
	var human := GameState.players[0]
	_check(human.leader.data.id == "queen_amara", "Starting a match with a custom deck by name sets the right Leader")
	_check(human.deck.size() + human.hand.size() == custom_total, "Custom deck's full card count is in play (deck + opening hand)")

	GameState.players[0].is_ai = true
	GameState.players[1].is_ai = true
	var safety := 0
	while not GameState.is_over and safety < 100:
		AIPlayer.take_turn(GameState.active_player_index)
		safety += 1
	_check(GameState.is_over, "A match started from a custom deck plays through to completion")

	DeckStorage.delete_deck(TEST_DECK_NAME)
	DeckStorage.delete_deck(TEST_DECK_NAME_2)

	print("")
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	get_tree().quit()

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] %s" % label)
	else:
		print("  [FAIL] %s" % label)
		_failures += 1

func _find_scroll_container(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var r := _find_scroll_container(c)
		if r != null:
			return r
	return null
