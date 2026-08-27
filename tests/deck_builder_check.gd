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

	# Deck Builder/Collection/Rules are opened from the Practice deck-select
	# screen (§ user request: the main menu is now just 5 top-level buttons —
	# Campaign/Practice/Multiplayer/Options/Exit), so simulate having already
	# navigated there, same as a real player would before clicking any of them.
	main._practice_screen.visible = true

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
	main._on_open_rules(main._practice_screen)
	_check(rules.size.x > 100 and rules.size.y > 100, "Rules screen has a real nonzero size when opened (got %s)" % rules.size)
	_check(not main._practice_screen.visible, "Opening Rules hides the screen it was opened from")
	main._on_rules_closed()
	_check(rules.visible == false and main._practice_screen.visible, "Closing Rules (opened from the Practice screen) returns to the Practice screen")

	main._on_open_deck_builder()
	main._on_open_rules(main._deck_builder)
	main._on_rules_closed()
	_check(main._deck_builder.visible and not main._practice_screen.visible, "Closing Rules (opened from the Deck Builder) returns to the Deck Builder, not the Practice screen")
	main._on_deck_builder_closed()

	# --- Practice deck list is actually scrollable (18 fixed decks overflow the window) ---
	# Container layout resolves only after real frame processing, unlike the
	# anchor-preset bug above — this needs `await`, not an immediate check.
	for i in range(5):
		await get_tree().process_frame
	var scroll := _find_scroll_container(main._practice_screen)
	_check(scroll != null, "Practice deck-select screen has a ScrollContainer")
	if scroll != null:
		_check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "Deck list content is taller than its scroll viewport (scrolling is actually needed and works)")

	# --- Validation rejects an incomplete deck -----------------------------
	db._new_deck()
	db._leader_id = "queen_amara"
	db._cards = {"worker_termite": 4}
	var errors := DeckStorage.validate("x", db._leader_id, db._cards)
	_check(not errors.is_empty(), "Validation rejects a 4-card deck (needs 40-60)")

	# --- Deck builder filters are multi-select (§ user request) -------------
	db._new_deck()
	await get_tree().process_frame
	var baseline_count := db._browser_grid.get_child_count()
	var kingdom_options: Array = Kingdoms.ALL + [Kingdoms.COLORLESS]
	db._on_multi_filter_toggled(0, db._kingdom_menu, kingdom_options, db._kingdom_filters, "Kingdom") # White
	await get_tree().process_frame
	var white_count := db._browser_grid.get_child_count()
	db._on_multi_filter_toggled(2, db._kingdom_menu, kingdom_options, db._kingdom_filters, "Kingdom") # Black
	await get_tree().process_frame
	var white_and_black_count := db._browser_grid.get_child_count()
	_check(db._kingdom_filters.size() == 2, "Selecting a second Kingdom filter adds to the selection instead of replacing it")
	_check(white_count > 0 and white_count < baseline_count, "Filtering to one Kingdom narrows the browser below the unfiltered count")
	_check(white_and_black_count > white_count, "Selecting a second Kingdom OR's it in, showing MORE cards than just the first one")
	db._on_multi_filter_toggled(0, db._kingdom_menu, kingdom_options, db._kingdom_filters, "Kingdom")
	db._on_multi_filter_toggled(2, db._kingdom_menu, kingdom_options, db._kingdom_filters, "Kingdom")
	await get_tree().process_frame
	_check(db._kingdom_filters.is_empty() and db._browser_grid.get_child_count() == baseline_count, "Toggling both Kingdom filters back off clears the filter entirely")

	var type_options: Array = [CardTypes.CREATURE, CardTypes.ABILITY, CardTypes.GEAR, CardTypes.HIVE]
	db._on_multi_filter_toggled(2, db._type_menu, type_options, db._type_filters, "Type") # Gear
	await get_tree().process_frame
	var gear_count := db._browser_grid.get_child_count()
	_check(gear_count > 0 and gear_count < baseline_count, "The new card-type filter (§ user request) narrows the browser to just Gear")
	db._on_multi_filter_toggled(2, db._type_menu, type_options, db._type_filters, "Type")
	await get_tree().process_frame

	# --- Browser sort modes (§ user request) ---------------------------------
	db._new_deck()
	db._leader_id = "queen_amara"
	db._on_sort_selected(DeckBuilderUI.SortMode.COST_LOW)
	await get_tree().process_frame
	var costs_low_to_high: Array[int] = []
	for i in range(min(20, db._browser_grid.get_child_count())):
		var btn: Button = db._browser_grid.get_child(i)
		var cost_line: String = btn.text.split("\n")[1]
		costs_low_to_high.append(int(cost_line.replace("Cost ", "").split(" ")[0]))
	var is_ascending := true
	for i in range(1, costs_low_to_high.size()):
		if costs_low_to_high[i] < costs_low_to_high[i - 1]:
			is_ascending = false
	_check(is_ascending, "Sort: Cost (Low-High) orders the browser by ascending Leader-adjusted cost")

	db._on_sort_selected(DeckBuilderUI.SortMode.COST_HIGH)
	await get_tree().process_frame
	var first_high_cost := int(db._browser_grid.get_child(0).text.split("\n")[1].replace("Cost ", "").split(" ")[0])
	var first_low_cost := costs_low_to_high[0]
	_check(first_high_cost >= first_low_cost, "Sort: Cost (High-Low) puts the most expensive card first")

	db._on_sort_selected(DeckBuilderUI.SortMode.TYPE)
	await get_tree().process_frame
	_check(db._browser_grid.get_child_count() > 0, "Sort: Creature Type doesn't drop any cards, just reorders them")
	db._on_sort_selected(DeckBuilderUI.SortMode.NAME)

	# --- "My Deck" view toggle (§ user request) ------------------------------
	db._new_deck()
	await get_tree().process_frame
	var full_pool_count := db._browser_grid.get_child_count()
	db._add_card("worker_termite")
	db._add_card("blood_tick")
	db._on_view_toggle_pressed()
	await get_tree().process_frame
	_check(db._browser_grid.get_child_count() == 2, "\"View: My Deck\" shows exactly the cards in the current build")
	db._remove_card("blood_tick")
	await get_tree().process_frame
	_check(db._browser_grid.get_child_count() == 1, "Removing a card's last copy drops it from the \"My Deck\" view immediately")
	db._on_view_toggle_pressed()
	await get_tree().process_frame
	_check(db._browser_grid.get_child_count() == full_pool_count, "Toggling back off restores the full pool")

	# --- Deck list is ordered by cost ascending (§ user request) -------------
	db._new_deck()
	db._add_card("apex_bloodhunter") # 9 cost
	db._add_card("worker_termite") # 1 cost
	db._add_card("blood_tick") # 1 cost
	await get_tree().process_frame
	var deck_list_costs: Array[int] = []
	for row in db._deck_list_box.get_children():
		var label_text: String = (row.get_child(0) as Label).text
		var cost_str := label_text.substr(label_text.rfind("(") + 1).trim_suffix(")")
		deck_list_costs.append(int(cost_str))
	var deck_list_ascending := true
	for i in range(1, deck_list_costs.size()):
		if deck_list_costs[i] < deck_list_costs[i - 1]:
			deck_list_ascending = false
	_check(deck_list_costs.size() == 3 and deck_list_ascending, "The deck list panel is ordered by Larva cost ascending")

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

	await main._start_match(TEST_DECK_NAME, "green_wildgrowth") # starting a match now shows a brief loading beat (§ user request) first
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
