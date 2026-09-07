class_name DeckBuilderUI
extends Control
## Deckbuilder screen (§11 Phase 2): browse the full card pool, filter by
## Kingdom/rarity/name, pick a Leader, and build/save/edit/delete decks
## obeying §9 (40-60 cards, max 4 copies per name). No unlock economy yet
## (Phase 3), so the whole CardDatabase pool is always available to build with.

signal closed
signal open_rules

const HERO_POWER_COLOR := "#8fd0ff"
const ULTIMATE_COLOR := "#ffcc33"

## Deck Builder screen music+background (§ user request, superseding the
## earlier "alternate 1/2 forever" scheme): three phases in strict
## sequence — Song 1 once, then Song 2 once, then Song 3 looping forever —
## each with its own background image, and a 4-second/36-frame (6x6)
## sprite-sheet animation transitioning INTO each phase (played before that
## phase's background/song ever appear, including the very first one when
## the screen opens). Only plays while this screen is the active one
## (main_ui.gd pauses the ambient menu track for the duration, same pattern
## as Collection's).
const SONG_1_PATH := "res://music/deckbuilder/song_1.mp3"
const SONG_2_PATH := "res://music/deckbuilder/song_2.mp3"
const SONG_3_PATH := "res://music/deckbuilder/song_3.mp3"
const BACKGROUND_1_PATH := "res://art/ui/backgrounds/deckbuilder/background_1.png"
const BACKGROUND_2_PATH := "res://art/ui/backgrounds/deckbuilder/background_2.png"
const BACKGROUND_3_PATH := "res://art/ui/backgrounds/deckbuilder/background_3.png"
const TRANSITION_1_PATH := "res://art/ui/backgrounds/deckbuilder/transition_1.png"
const TRANSITION_2_PATH := "res://art/ui/backgrounds/deckbuilder/transition_2.png"
const TRANSITION_3_PATH := "res://art/ui/backgrounds/deckbuilder/transition_3.png"
const TRANSITION_COLS := 6
const TRANSITION_ROWS := 6
const TRANSITION_FPS := 9.0 # 36 frames / 4 seconds
## § user request: a distinct SFX for adding a card to the build.
const ADD_CARD_SFX_PATH := "res://music/add_card_to_deck.mp3"

var _leader_id := ""
var _cards := {} # card_id (String) -> count (int)
var _editing_name := "" # name of the saved deck being edited, "" if unsaved/new

## Multi-select filters (§ user request): empty means "no restriction on
## this dimension", not "match nothing" — same convention across all three.
var _kingdom_filters: Array[String] = []
var _rarity_filters: Array[String] = []
var _type_filters: Array[String] = []
var _search_filter := ""

## Browser sort order (§ user request) and the "My Deck" view toggle, which
## swaps the browser's source pool from the full card database to just the
## cards already in `_cards`, so the player can see full card widgets for
## their current build instead of only the plain-text list on the right.
enum SortMode { NAME, TYPE, COST_LOW, COST_HIGH }
var _sort_mode: int = SortMode.NAME
var _view_deck_only := false

var _leader_option: OptionButton
var _leader_info_label: RichTextLabel
var _name_edit: LineEdit
var _kingdom_menu: MenuButton
var _rarity_menu: MenuButton
var _type_menu: MenuButton
var _sort_option: OptionButton
var _view_toggle_btn: Button
var _search_edit: LineEdit
var _browser_grid: GridContainer
var _deck_list_box: VBoxContainer
var _deck_size_label: Label
var _status_label: Label
var _saved_decks_box: VBoxContainer
var _overlay: CardPreviewOverlay
var _music_player: AudioStreamPlayer
var _music_volume_db := 0.0 # kept in sync by main_ui.gd's _apply_audio_settings, same as the ambient track
var _song_on_finished: Callable # advances to the next phase — see _play_song/_on_music_finished
var _sfx_player: AudioStreamPlayer
var _sfx_volume_db := 0.0 # kept in sync by main_ui.gd's _apply_audio_settings

var _bg_rect: TextureRect
var _transition_rect: TextureRect
var _transition_atlas: AtlasTexture
var _transition_timer: Timer
var _transition_frame := 0
var _transition_on_complete: Callable

func _ready() -> void:
	LayoutUtil.fill_parent(self)
	_build_ui()
	_new_deck()

func _build_ui() -> void:
	# Background image, added first so it renders behind the actual screen
	# content below (same pattern as CollectionUI's own BG_PATH) — self is
	# a plain Control, not a layout container, so the two coexist as
	# separate full-rect layers instead of both being forced into a single
	# vertical stack. Texture swaps between the three phase backgrounds as
	# start_music progresses (see _show_phase_1/2/3); starts with no
	# texture until start_music actually kicks off phase 1.
	_bg_rect = TextureRect.new()
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(_bg_rect)
	add_child(_bg_rect)

	var root := VBoxContainer.new()
	LayoutUtil.fill_parent(root)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< Back to Menu"
	back_btn.pressed.connect(func() -> void:
		_overlay.hide_preview()
		_reset_filters() # § user request: filters shouldn't persist once you navigate away
		stop_music()
		closed.emit())
	top.add_child(back_btn)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Deck name"
	_name_edit.custom_minimum_size = Vector2(220, 0)
	top.add_child(_name_edit)

	_leader_option = OptionButton.new()
	_leader_option.add_item("Choose a Leader...")
	for leader: LeaderData in CardDatabase.all_leaders():
		_leader_option.add_item("%s (%s)" % [leader.card_name, CardRenderUtil.kingdom_label(leader)])
	_leader_option.item_selected.connect(_on_leader_selected)
	top.add_child(_leader_option)

	var new_btn := Button.new()
	new_btn.text = "New Deck"
	new_btn.pressed.connect(_new_deck)
	top.add_child(new_btn)

	var save_btn := Button.new()
	save_btn.text = "Save Deck"
	save_btn.pressed.connect(_on_save_pressed)
	top.add_child(save_btn)

	var rules_btn := Button.new()
	rules_btn.text = "Rules & Keywords"
	rules_btn.pressed.connect(func() -> void: open_rules.emit())
	top.add_child(rules_btn)

	_leader_info_label = RichTextLabel.new()
	_leader_info_label.bbcode_enabled = true
	_leader_info_label.fit_content = true
	_leader_info_label.scroll_active = false
	_leader_info_label.custom_minimum_size = Vector2(0, 70)
	root.add_child(_leader_info_label)

	_status_label = Label.new()
	root.add_child(_status_label)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	root.add_child(split)

	var browser_col := VBoxContainer.new()
	browser_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(browser_col)

	var filters := HBoxContainer.new()
	browser_col.add_child(filters)
	_kingdom_menu = _build_multi_filter_menu("Kingdom", Kingdoms.ALL + [Kingdoms.COLORLESS], _kingdom_filters)
	filters.add_child(_kingdom_menu)

	_rarity_menu = _build_multi_filter_menu("Rarity", [Rarities.COMMON, Rarities.UNCOMMON, Rarities.RARE, Rarities.LEGENDARY], _rarity_filters)
	filters.add_child(_rarity_menu)

	_type_menu = _build_multi_filter_menu("Type", [CardTypes.CREATURE, CardTypes.ABILITY, CardTypes.GEAR, CardTypes.HIVE], _type_filters)
	filters.add_child(_type_menu)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search name..."
	_search_edit.custom_minimum_size = Vector2(180, 0)
	_search_edit.text_changed.connect(_on_search_changed)
	filters.add_child(_search_edit)

	_sort_option = OptionButton.new()
	_sort_option.add_item("Sort: Name")
	_sort_option.add_item("Sort: Creature Type")
	_sort_option.add_item("Sort: Cost (Low-High)")
	_sort_option.add_item("Sort: Cost (High-Low)")
	_sort_option.item_selected.connect(_on_sort_selected)
	filters.add_child(_sort_option)

	_view_toggle_btn = Button.new()
	_view_toggle_btn.text = "View: All Cards"
	_view_toggle_btn.pressed.connect(_on_view_toggle_pressed)
	filters.add_child(_view_toggle_btn)

	var browser_scroll := ScrollContainer.new()
	browser_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser_col.add_child(browser_scroll)
	_browser_grid = GridContainer.new()
	_browser_grid.columns = 4
	_browser_grid.add_theme_constant_override("h_separation", 6)
	_browser_grid.add_theme_constant_override("v_separation", 6)
	browser_scroll.add_child(_browser_grid)

	var deck_col := VBoxContainer.new()
	deck_col.custom_minimum_size = Vector2(360, 0)
	split.add_child(deck_col)

	_deck_size_label = Label.new()
	deck_col.add_child(_deck_size_label)
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_col.add_child(deck_scroll)
	_deck_list_box = VBoxContainer.new()
	deck_scroll.add_child(_deck_list_box)

	var saved_title := Label.new()
	saved_title.text = "Saved Decks"
	saved_title.add_theme_font_size_override("font_size", 16)
	deck_col.add_child(saved_title)
	var saved_scroll := ScrollContainer.new()
	saved_scroll.custom_minimum_size = Vector2(0, 160)
	deck_col.add_child(saved_scroll)
	_saved_decks_box = VBoxContainer.new()
	saved_scroll.add_child(_saved_decks_box)

	# Added directly to self (a plain Control, not a Container) so its
	# manually-set global_position isn't fought by a Container layout pass.
	_overlay = CardPreviewOverlay.new()
	add_child(_overlay)

	_music_player = AudioStreamPlayer.new()
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)

	# The phase-transition overlay (§ TRANSITION_1_PATH's own comment):
	# added last, and stretched over the full screen, so it draws on top of
	# both the background and every real UI control above while a
	# transition is playing — same fill_parent + last-added-wins draw order
	# pattern as _overlay. Starts hidden; _play_transition shows it.
	_transition_rect = TextureRect.new()
	_transition_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_transition_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_transition_rect.visible = false
	LayoutUtil.fill_parent(_transition_rect)
	add_child(_transition_rect)

	_transition_timer = Timer.new()
	_transition_timer.wait_time = 1.0 / TRANSITION_FPS
	_transition_timer.timeout.connect(_on_transition_tick)
	add_child(_transition_timer)

## Starts this screen's music+background sequence (§ SONG_1_PATH's own
## comment) — called by main_ui.gd when this screen becomes the active
## one. Always (re)starts from phase 1, so leaving and reopening the
## screen replays the whole sequence rather than resuming mid-way.
func start_music() -> void:
	_show_phase_1()

func _show_phase_1() -> void:
	_play_transition(TRANSITION_1_PATH, func() -> void:
		_set_background(BACKGROUND_1_PATH)
		_play_song(SONG_1_PATH, false, _show_phase_2))

func _show_phase_2() -> void:
	_play_transition(TRANSITION_2_PATH, func() -> void:
		_set_background(BACKGROUND_2_PATH)
		_play_song(SONG_2_PATH, false, _show_phase_3))

func _show_phase_3() -> void:
	_play_transition(TRANSITION_3_PATH, func() -> void:
		_set_background(BACKGROUND_3_PATH)
		_play_song(SONG_3_PATH, true, Callable()))

func _set_background(path: String) -> void:
	_bg_rect.texture = load(path) if ResourceLoader.exists(path) else null

## Plays `path` once (`loop` false) or forever (`loop` true), then calls
## `on_finished` — but only for a non-looping stream: a plain
## AudioStreamPlayer never re-emits `finished` for a stream with loop
## enabled (see _on_music_finished), so Song 3 looping forever is exactly
## "the sequence just stops advancing here" with no special-casing needed.
## Fails safe straight to `on_finished` if the asset isn't present, so a
## missing track doesn't stall the whole sequence.
func _play_song(path: String, loop: bool, on_finished: Callable) -> void:
	if not ResourceLoader.exists(path):
		if on_finished.is_valid():
			on_finished.call()
		return
	_song_on_finished = on_finished
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	_music_player.volume_db = _music_volume_db
	_music_player.stream = stream
	_music_player.play()

func _on_music_finished() -> void:
	var cb := _song_on_finished
	_song_on_finished = Callable()
	if cb.is_valid():
		cb.call()

## Plays a 6x6/36-frame transition sprite sheet once (§ user request: "use
## the animation sprites as transitions... each sprite is 4 seconds long
## and 36 frames"), then calls `on_complete`. Fails safe straight to
## `on_complete` if the asset isn't present, so a missing transition
## doesn't stall the sequence either.
func _play_transition(path: String, on_complete: Callable) -> void:
	if not ResourceLoader.exists(path):
		on_complete.call()
		return
	var sheet: Texture2D = load(path)
	var frame_w := sheet.get_width() / TRANSITION_COLS
	var frame_h := sheet.get_height() / TRANSITION_ROWS
	_transition_atlas = AtlasTexture.new()
	_transition_atlas.atlas = sheet
	_transition_atlas.region = Rect2(0, 0, frame_w, frame_h)
	_transition_rect.texture = _transition_atlas
	_transition_rect.visible = true
	_transition_frame = 0
	_transition_on_complete = on_complete
	_transition_timer.start()

func _on_transition_tick() -> void:
	var total := TRANSITION_COLS * TRANSITION_ROWS
	_transition_frame += 1
	if _transition_frame >= total:
		_transition_timer.stop()
		_transition_rect.visible = false
		var cb := _transition_on_complete
		_transition_on_complete = Callable()
		if cb.is_valid():
			cb.call()
		return
	var frame_w := _transition_atlas.atlas.get_width() / TRANSITION_COLS
	var frame_h := _transition_atlas.atlas.get_height() / TRANSITION_ROWS
	var col := _transition_frame % TRANSITION_COLS
	var row := _transition_frame / TRANSITION_COLS
	_transition_atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)

## Stops the music sequence and any in-flight transition, and clears the
## background — called when leaving the screen, so a later start_music
## (re-entering) always begins fresh from phase 1's own transition rather
## than however things looked at the moment of leaving.
func stop_music() -> void:
	_music_player.stop()
	_song_on_finished = Callable()
	_transition_timer.stop()
	_transition_rect.visible = false
	_transition_on_complete = Callable()
	_bg_rect.texture = null

## Keeps this screen's music in sync with the Options screen's Music Volume
## slider, same pattern as CollectionUI.set_music_volume_db.
func set_music_volume_db(db: float) -> void:
	_music_volume_db = db
	_music_player.volume_db = db

## Keeps _add_card's SFX in sync with the Options screen's SFX Volume slider.
func set_sfx_volume_db(db: float) -> void:
	_sfx_volume_db = db

## § user request: a distinct sound when a card is added to the build.
func _play_add_card_sfx() -> void:
	if not ResourceLoader.exists(ADD_CARD_SFX_PATH):
		return
	_sfx_player.stream = load(ADD_CARD_SFX_PATH)
	_sfx_player.volume_db = _sfx_volume_db
	_sfx_player.play()

## Builds a dropdown that lets the player check any number of `options`
## (§ user request — deck-builder filters used to be single-select only).
## `target` is the Array this menu's checked state stays in sync with;
## the label updates to reflect how many are currently selected.
func _build_multi_filter_menu(label: String, options: Array, target: Array) -> MenuButton:
	var menu_btn := MenuButton.new()
	menu_btn.text = label
	var popup := menu_btn.get_popup()
	popup.hide_on_checkable_item_selection = false
	for i in range(options.size()):
		popup.add_check_item(str(options[i]), i)
	popup.id_pressed.connect(_on_multi_filter_toggled.bind(menu_btn, options, target, label))
	return menu_btn

func _on_multi_filter_toggled(id: int, menu_btn: MenuButton, options: Array, target: Array, label: String) -> void:
	var popup := menu_btn.get_popup()
	var value = options[id]
	var was_checked := popup.is_item_checked(id)
	popup.set_item_checked(id, not was_checked)
	if was_checked:
		target.erase(value)
	else:
		target.append(value)
	menu_btn.text = label if target.is_empty() else "%s (%d)" % [label, target.size()]
	_refresh_browser()

func _reset_multi_filter(menu_btn: MenuButton, options: Array, target: Array, label: String) -> void:
	var popup := menu_btn.get_popup()
	for i in range(options.size()):
		popup.set_item_checked(i, false)
	target.clear() # same Array object _on_multi_filter_toggled's bound closure holds — clearing in place keeps that binding valid
	menu_btn.text = label

## § user request: filters shouldn't carry over between visits — back to
## defaults (and every widget reset to match) every time you leave.
func _reset_filters() -> void:
	_reset_multi_filter(_kingdom_menu, Kingdoms.ALL + [Kingdoms.COLORLESS], _kingdom_filters, "Kingdom")
	_reset_multi_filter(_rarity_menu, [Rarities.COMMON, Rarities.UNCOMMON, Rarities.RARE, Rarities.LEGENDARY], _rarity_filters, "Rarity")
	_reset_multi_filter(_type_menu, [CardTypes.CREATURE, CardTypes.ABILITY, CardTypes.GEAR, CardTypes.HIVE], _type_filters, "Type")
	_search_filter = ""
	_search_edit.text = ""
	_sort_mode = SortMode.NAME
	_sort_option.selected = 0
	_view_deck_only = false
	_view_toggle_btn.text = "View: All Cards"
	_refresh_browser()

## Called by the host whenever this screen becomes visible, in case saved
## decks changed elsewhere (e.g. deleted from the Play menu).
func refresh_on_show() -> void:
	_refresh_saved_decks()

func _new_deck() -> void:
	_editing_name = ""
	_leader_id = ""
	_cards = {}
	_name_edit.text = ""
	_leader_option.selected = 0
	_status_label.text = ""
	if _view_deck_only:
		_on_view_toggle_pressed() # an empty deck has nothing to show in "My Deck" view — fall back to the full pool
	_refresh()

func _on_leader_selected(index: int) -> void:
	var leaders := CardDatabase.all_leaders()
	_leader_id = leaders[index - 1].id if index > 0 else ""
	_refresh_leader_info()
	_refresh_browser() # costs are Leader-relative (§4), so the browser needs to re-render
	_refresh_deck_list()

func _on_search_changed(text: String) -> void:
	_search_filter = text.to_lower()
	_refresh_browser()

func _on_sort_selected(index: int) -> void:
	_sort_mode = index
	_refresh_browser()

## Toggles the browser between the full card pool and just the cards
## already in the current build (§ user request), so the player can see
## full card widgets for their deck instead of only the plain-text list.
func _on_view_toggle_pressed() -> void:
	_view_deck_only = not _view_deck_only
	_view_toggle_btn.text = "View: My Deck" if _view_deck_only else "View: All Cards"
	_refresh_browser()

## Sort key for "Sort: Creature Type" — creatures group by their printed
## type; non-creature cards group by card type (Ability/Gear/Hive) instead,
## since they have no creature_type of their own.
func _sort_type_key(card: CardData) -> String:
	return (card as CreatureData).creature_type if card is CreatureData else card.card_type

func _on_save_pressed() -> void:
	var deck_name := _name_edit.text.strip_edges()
	var errors := DeckStorage.validate(deck_name, _leader_id, _cards)
	if not errors.is_empty():
		_status_label.text = "Cannot save — " + "; ".join(errors)
		return
	if _editing_name != "" and _editing_name != deck_name:
		DeckStorage.delete_deck(_editing_name)
	DeckStorage.save_deck(deck_name, _leader_id, _cards)
	_editing_name = deck_name
	_status_label.text = "Saved '%s'." % deck_name
	_refresh_saved_decks()

func _load_deck(deck_name: String) -> void:
	var d := DeckStorage.get_deck(deck_name)
	if d.is_empty():
		return
	_editing_name = deck_name
	_leader_id = d["leader_id"]
	_cards = (d["cards"] as Dictionary).duplicate()
	_name_edit.text = deck_name
	_status_label.text = ""
	var leaders := CardDatabase.all_leaders()
	_leader_option.selected = 0
	for i in range(leaders.size()):
		if leaders[i].id == _leader_id:
			_leader_option.selected = i + 1
			break
	_refresh()

func _delete_deck(deck_name: String) -> void:
	DeckStorage.delete_deck(deck_name)
	if _editing_name == deck_name:
		_new_deck()
	else:
		_refresh_saved_decks()

func _add_card(card_id: String) -> void:
	var count := int(_cards.get(card_id, 0))
	if count >= DeckStorage.MAX_COPIES:
		_status_label.text = "Already at the %d-copy limit." % DeckStorage.MAX_COPIES
		return
	_cards[card_id] = count + 1
	_play_add_card_sfx()
	_refresh_deck_list()
	if _view_deck_only:
		_refresh_browser() # a brand-new card in the deck needs to appear in the "My Deck" view

func _remove_card(card_id: String) -> void:
	var count := int(_cards.get(card_id, 0))
	if count <= 1:
		_cards.erase(card_id)
	else:
		_cards[card_id] = count - 1
	_refresh_deck_list()
	if _view_deck_only:
		_refresh_browser() # dropping a card's last copy needs to remove it from the "My Deck" view

## --- Rendering --------------------------------------------------------------

func _refresh_leader_info() -> void:
	if _leader_id == "":
		_leader_info_label.text = "[i]No Leader chosen yet.[/i]"
		return
	var leader: LeaderData = CardDatabase.get_leader(_leader_id)
	if leader == null:
		_leader_info_label.text = "[i]Unknown Leader.[/i]"
		return
	_leader_info_label.text = "[b]%s[/b]  (%s, %d health)\n[color=%s]Hero Power (%d): %s[/color]\n[color=%s]Ultimate (%d): %s[/color]" % [
		leader.card_name, CardRenderUtil.kingdom_label(leader), leader.starting_health,
		HERO_POWER_COLOR, leader.hero_power_cost, leader.hero_power_text,
		ULTIMATE_COLOR, leader.ultimate_cost, leader.ultimate_text,
	]

func _refresh() -> void:
	_refresh_leader_info()
	_refresh_browser()
	_refresh_deck_list()
	_refresh_saved_decks()

func _refresh_browser() -> void:
	for child in _browser_grid.get_children():
		child.queue_free()
	var leader_data: LeaderData = CardDatabase.get_leader(_leader_id) if _leader_id != "" else null

	var pool: Array = []
	if _view_deck_only:
		for card_id: String in _cards.keys():
			var owned := CardDatabase.get_card(card_id)
			if owned != null:
				pool.append(owned)
	else:
		pool = CardDatabase.all_cards()

	var candidates: Array[CardData] = []
	for card: CardData in pool:
		if not _kingdom_filters.is_empty():
			var matches_kingdom := false
			for kf: String in _kingdom_filters:
				if kf == Kingdoms.COLORLESS:
					matches_kingdom = matches_kingdom or card.kingdoms.is_empty()
				else:
					matches_kingdom = matches_kingdom or card.kingdoms.has(kf)
			if not matches_kingdom:
				continue
		if not _rarity_filters.is_empty() and not _rarity_filters.has(card.rarity):
			continue
		if not _type_filters.is_empty() and not _type_filters.has(card.card_type):
			continue
		if _search_filter != "" and not card.card_name.to_lower().contains(_search_filter):
			continue
		candidates.append(card)

	# Sort (§ user request): cost sorts use the Leader-adjusted cost — the
	# same number actually shown on the card — with name as a tiebreaker so
	# equal-cost/type cards land in a stable, predictable order.
	match _sort_mode:
		SortMode.TYPE:
			candidates.sort_custom(func(a: CardData, b: CardData) -> bool:
				var ta := _sort_type_key(a)
				var tb := _sort_type_key(b)
				return a.card_name < b.card_name if ta == tb else ta < tb)
		SortMode.COST_LOW, SortMode.COST_HIGH:
			candidates.sort_custom(func(a: CardData, b: CardData) -> bool:
				var ca := CostCalculator.calculate_cost(a, leader_data) if leader_data != null else a.cost
				var cb := CostCalculator.calculate_cost(b, leader_data) if leader_data != null else b.cost
				if ca == cb:
					return a.card_name < b.card_name
				return ca < cb if _sort_mode == SortMode.COST_LOW else ca > cb)
		_:
			candidates.sort_custom(func(a: CardData, b: CardData) -> bool: return a.card_name < b.card_name)

	for card: CardData in candidates:
		var cost := CostCalculator.calculate_cost(card, leader_data) if leader_data != null else card.cost
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 170)
		var tex := CardRenderUtil.style_card_face(btn, card, cost)
		btn.set_meta("cost", cost) # cost is shown as a badge now, not text — automated checks read it here instead
		var badge_text := ""
		if card is CreatureData:
			var cd := card as CreatureData
			badge_text = "%d/%d" % [cd.attack, cd.health]
			CardRenderUtil.add_corner_badge(btn, badge_text)
		CardRenderUtil.wire_hover_preview(btn, _overlay, card, tex, cost, CardRenderUtil.card_full_text(card), badge_text)
		btn.pressed.connect(_add_card.bind(card.id))
		_browser_grid.add_child(btn)

func _refresh_deck_list() -> void:
	for child in _deck_list_box.get_children():
		child.queue_free()
	var total := 0
	var ids: Array = _cards.keys()
	# Cost ascending (§ user request), name as a tiebreaker for equal-cost cards.
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := CardDatabase.get_card(a)
		var cb := CardDatabase.get_card(b)
		if ca.cost != cb.cost:
			return ca.cost < cb.cost
		return ca.card_name < cb.card_name)
	for card_id: String in ids:
		var count := int(_cards[card_id])
		total += count
		var card := CardDatabase.get_card(card_id)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%dx %s (%d)" % [count, card.card_name, card.cost]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var minus := Button.new()
		minus.text = "-"
		minus.pressed.connect(_remove_card.bind(card_id))
		row.add_child(minus)
		var plus := Button.new()
		plus.text = "+"
		plus.disabled = count >= DeckStorage.MAX_COPIES
		plus.pressed.connect(_add_card.bind(card_id))
		row.add_child(plus)
		_deck_list_box.add_child(row)

	var in_range := total >= DeckStorage.MIN_DECK_SIZE and total <= DeckStorage.MAX_DECK_SIZE
	_deck_size_label.text = "Deck: %d/%d-%d cards" % [total, DeckStorage.MIN_DECK_SIZE, DeckStorage.MAX_DECK_SIZE]
	_deck_size_label.modulate = Color(0.5, 1.0, 0.5) if in_range else Color(1.0, 0.6, 0.5)

func _refresh_saved_decks() -> void:
	for child in _saved_decks_box.get_children():
		child.queue_free()
	for deck_name: String in DeckStorage.all_deck_names():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = deck_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var load_btn := Button.new()
		load_btn.text = "Edit"
		load_btn.pressed.connect(_load_deck.bind(deck_name))
		row.add_child(load_btn)
		var del_btn := Button.new()
		del_btn.text = "Delete"
		del_btn.pressed.connect(_delete_deck.bind(deck_name))
		row.add_child(del_btn)
		_saved_decks_box.add_child(row)
