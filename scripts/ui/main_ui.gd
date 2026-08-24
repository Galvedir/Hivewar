extends Control
## Minimal functional Phase 1 UI (§16 step 8): deck-select screen, then a
## hand/board/Leader match view wired straight to TurnManager — the same
## API AIPlayer drives. Built programmatically (no hand-authored .tscn
## layout) so it's easy to keep in sync with the engine; swap for real
## scenes/art in a later pass without touching TurnManager/GameState.

const HUMAN := 0
const AI := 1

## Effect ids that need a chosen creature target rather than an auto-pick,
## and which side of the board is legal to click for each (§ user request:
## targeted effects should let the player choose, not silently pick for
## them). AIPlayer is unaffected — it never supplies target_instance_id, so
## EffectResolver's auto-pick heuristic still drives the bot.
const TARGETING_EFFECT_SIDES := {
	"buff_friendly": "friendly",
	"damage_creature": "enemy",
	"bounce_creature": "enemy",
	"shuffle_into_library": "enemy",
	"grant_decay_to_enemy": "enemy",
	"destroy_creature": "enemy",
	"heal_creature_full": "friendly",
	"flip_ambush_instant": "friendly",
	"buff_friendly_per_larva_spent": "friendly",
}

var _deck_select: VBoxContainer
var _saved_decks_menu_box: VBoxContainer
var _deck_builder: DeckBuilderUI
var _collection: CollectionUI
var _rules_screen: RulesScreenUI
var _rules_return_target: Control # whichever screen was open before Rules — main menu or Deck Builder
var _match_view: HBoxContainer
var _match_root: VBoxContainer
var _log_display: RichTextLabel
var _opponent_board: HBoxContainer
var _opponent_hive: HBoxContainer
var _opponent_info: Label
var _opponent_discard_btn: Button
var _player_board: HBoxContainer
var _player_hive: HBoxContainer
var _player_hand: HBoxContainer
var _player_info: Label
var _player_discard_btn: Button
var _discard_popup: PanelContainer
var _discard_popup_box: VBoxContainer
var _status_label: Label
var _hero_power_btn: Button
var _ultimate_btn: Button
var _end_turn_btn: Button
var _cancel_btn: Button
var _block_popup: PanelContainer
var _block_popup_box: VBoxContainer
var _attack_confirm_popup: PanelContainer
var _attack_confirm_label: Label
var _x_cost_popup: PanelContainer
var _x_cost_spinbox: SpinBox
var _legend_popup: PanelContainer
var _legend_popup_box: VBoxContainer
var _game_over_popup: PanelContainer
var _game_over_label: Label

var _selected_hand_index := -1
var _selected_attacker_id := -1
var _pending_attack_target = null # null / "leader" / CardInstance — awaiting the attack-confirm popup
var _pending_ultimate_larva_spend := -1 # set while an X-cost Ultimate's amount has been chosen and is awaiting a target (or is ready to fire if untargeted)
var _pending_target_side := "" # "" / "friendly" / "enemy" — set while awaiting a click to target a hand card or Hero Power/Ultimate
var _pending_power_kind := "" # "" / "hero" / "ultimate"
var _busy := false # true while the AI or an awaited attack is resolving

func _ready() -> void:
	LayoutUtil.fill_parent(self)
	_build_deck_select()
	_build_match_view()
	_match_view.visible = false

	_deck_builder = DeckBuilderUI.new()
	_deck_builder.visible = false
	_deck_builder.closed.connect(_on_deck_builder_closed)
	add_child(_deck_builder)

	_collection = CollectionUI.new()
	_collection.visible = false
	_collection.closed.connect(_on_collection_closed)
	add_child(_collection)

	_rules_screen = RulesScreenUI.new()
	_rules_screen.visible = false
	_rules_screen.closed.connect(_on_rules_closed)
	add_child(_rules_screen)
	_deck_builder.open_rules.connect(_on_open_rules.bind(_deck_builder))

	TurnManager.turn_started.connect(_on_turn_started)
	TurnManager.block_decision_requested.connect(_on_block_requested)
	TurnManager.legend_rule_decision_requested.connect(_on_legend_rule_requested)
	GameState.game_ended.connect(_on_game_ended)
	GameLog.entry_added.connect(_on_log_entry)

	_show_splash_screen()

## --- Deck select ------------------------------------------------------------

const LOGO_PATH := "res://art/branding/logo.png"
const SPLASH_PATH := "res://art/branding/title_screen.png"
const SPLASH_DURATION := 2.5

## A brief title-screen splash (§ user request) shown once at boot, layered
## on top of the deck-select menu that's already built underneath it, before
## the game becomes interactive. Dismisses itself after SPLASH_DURATION
## seconds, or immediately on click/tap. Skipped entirely if the art asset
## isn't present yet, matching _make_title's fallback-safe pattern for
## optional branding assets — a missing splash image should never block
## reaching the menu.
func _show_splash_screen() -> void:
	if not ResourceLoader.exists(SPLASH_PATH):
		return
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	LayoutUtil.fill_parent(overlay)
	add_child(overlay)

	var image := TextureRect.new()
	image.texture = load(SPLASH_PATH)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(image)
	overlay.add_child(image)

	var dismiss := func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			dismiss.call()
	)
	get_tree().create_timer(SPLASH_DURATION).timeout.connect(dismiss)

## The main-menu title: the LARVA wordmark logo if it's present, else a
## plain-text fallback so a missing asset never breaks the menu.
func _make_title() -> Control:
	if ResourceLoader.exists(LOGO_PATH):
		var logo := TextureRect.new()
		logo.texture = load(LOGO_PATH)
		# TextureRect defaults to EXPAND_KEEP_SIZE (renders at the texture's
		# native pixel size, ignoring any box it's given) — IGNORE_SIZE is
		# what actually makes it respect custom_minimum_size, with
		# STRETCH_KEEP_ASPECT_CENTERED then preserving the image's aspect
		# ratio within that box instead of distorting it.
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(420, 180)
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return logo
	var title := Label.new()
	title.text = "LARVA"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title

func _build_deck_select() -> void:
	_deck_select = VBoxContainer.new()
	LayoutUtil.fill_parent(_deck_select)
	add_child(_deck_select)

	_deck_select.add_child(_make_title())

	var menu_row := HBoxContainer.new()
	menu_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_deck_select.add_child(menu_row)
	var builder_btn := Button.new()
	builder_btn.text = "Deck Builder"
	builder_btn.pressed.connect(_on_open_deck_builder)
	menu_row.add_child(builder_btn)
	var collection_btn := Button.new()
	collection_btn.text = "Collection"
	collection_btn.pressed.connect(_on_open_collection)
	menu_row.add_child(collection_btn)
	var rules_btn := Button.new()
	rules_btn.text = "Rules & Keywords"
	rules_btn.pressed.connect(_on_open_rules.bind(_deck_select))
	menu_row.add_child(rules_btn)

	# The 18 fixed decks (one per Leader) plus any saved decks easily
	# overflow the window, so the list itself scrolls — only the title/menu
	# row above stay pinned.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_deck_select.add_child(scroll)

	var list_box := VBoxContainer.new()
	list_box.custom_minimum_size = Vector2(420, 0)
	list_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.add_child(list_box)

	var fixed_title := Label.new()
	fixed_title.text = "Fixed Test Decks"
	fixed_title.add_theme_font_size_override("font_size", 16)
	list_box.add_child(fixed_title)
	for deck_id in DeckDefinitions.all_deck_ids():
		var deck: Dictionary = DeckDefinitions.get_deck(deck_id)
		var leader: LeaderData = CardDatabase.get_leader(deck["leader_id"])
		var btn := Button.new()
		btn.text = "%s\n(%s)" % [deck_id.replace("_", " ").capitalize(), leader.card_name]
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_on_deck_chosen.bind(deck_id))
		list_box.add_child(btn)

	var saved_title := Label.new()
	saved_title.text = "Your Decks"
	saved_title.add_theme_font_size_override("font_size", 16)
	list_box.add_child(saved_title)
	_saved_decks_menu_box = VBoxContainer.new()
	list_box.add_child(_saved_decks_menu_box)
	_refresh_saved_decks_menu()

func _refresh_saved_decks_menu() -> void:
	for child in _saved_decks_menu_box.get_children():
		child.queue_free()
	var names := DeckStorage.all_deck_names()
	if names.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(none yet — build one in the Deck Builder)"
		_saved_decks_menu_box.add_child(empty_label)
		return
	for deck_name: String in names:
		var d := DeckStorage.get_deck(deck_name)
		var leader: LeaderData = CardDatabase.get_leader(d.get("leader_id", ""))
		var btn := Button.new()
		btn.text = "%s\n(%s)" % [deck_name, leader.card_name if leader != null else "?"]
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_on_deck_chosen.bind(deck_name))
		_saved_decks_menu_box.add_child(btn)

func _on_open_deck_builder() -> void:
	_deck_select.visible = false
	_deck_builder.refresh_on_show()
	_deck_builder.visible = true

func _on_deck_builder_closed() -> void:
	_deck_builder.visible = false
	_refresh_saved_decks_menu()
	_deck_select.visible = true

func _on_open_collection() -> void:
	_deck_select.visible = false
	_collection.visible = true

func _on_collection_closed() -> void:
	_collection.visible = false
	_deck_select.visible = true

## `from` is whichever screen was open when Rules was requested (the main
## menu or the Deck Builder), so closing Rules returns to the right place.
func _on_open_rules(from: Control) -> void:
	_rules_return_target = from
	from.visible = false
	_rules_screen.visible = true

func _on_rules_closed() -> void:
	_rules_screen.visible = false
	if _rules_return_target != null:
		_rules_return_target.visible = true

func _on_deck_chosen(deck_id: String) -> void:
	var ai_pool := DeckDefinitions.all_deck_ids()
	ai_pool.erase(deck_id)
	var ai_deck_id: String = ai_pool[randi() % ai_pool.size()] if not ai_pool.is_empty() else deck_id

	_deck_select.visible = false
	_match_view.visible = true
	_selected_hand_index = -1
	_selected_attacker_id = -1
	GameLog.clear()
	if _log_display != null:
		_log_display.clear()

	TurnManager.start_game([deck_id, ai_deck_id], HUMAN)
	GameState.players[AI].is_ai = true
	_refresh()

## --- Match view scaffolding --------------------------------------------------

func _build_match_view() -> void:
	_match_root = VBoxContainer.new()
	_match_view = HBoxContainer.new()
	LayoutUtil.fill_parent(_match_view)
	_match_view.add_theme_constant_override("separation", 10)
	add_child(_match_view)

	_match_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_match_root.add_theme_constant_override("separation", 8)
	_match_view.add_child(_match_root)

	var opponent_info_row := HBoxContainer.new()
	_match_root.add_child(opponent_info_row)
	_opponent_info = Label.new()
	_opponent_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opponent_info_row.add_child(_opponent_info)
	_opponent_discard_btn = Button.new()
	_opponent_discard_btn.pressed.connect(_on_opponent_discard_pressed)
	opponent_info_row.add_child(_opponent_discard_btn)
	_opponent_hive = _make_scrolling_row(100)
	_match_root.add_child(_opponent_hive.get_parent())
	_opponent_board = _make_scrolling_row()
	_match_root.add_child(_opponent_board.get_parent())

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_root.add_child(_status_label)

	var mid := HBoxContainer.new()
	_match_root.add_child(mid)
	_hero_power_btn = Button.new()
	_hero_power_btn.pressed.connect(_on_hero_power_pressed)
	mid.add_child(_hero_power_btn)
	_ultimate_btn = Button.new()
	_ultimate_btn.pressed.connect(_on_ultimate_pressed)
	mid.add_child(_ultimate_btn)
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "End Turn"
	_end_turn_btn.pressed.connect(_on_end_turn_pressed)
	mid.add_child(_end_turn_btn)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	mid.add_child(_cancel_btn)

	_player_board = _make_scrolling_row()
	_match_root.add_child(_player_board.get_parent())
	_player_hive = _make_scrolling_row(100)
	_match_root.add_child(_player_hive.get_parent())
	var player_info_row := HBoxContainer.new()
	_match_root.add_child(player_info_row)
	_player_info = Label.new()
	_player_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_info_row.add_child(_player_info)
	_player_discard_btn = Button.new()
	_player_discard_btn.pressed.connect(_on_player_discard_pressed)
	player_info_row.add_child(_player_discard_btn)
	_player_hand = _make_scrolling_row()
	_match_root.add_child(_player_hand.get_parent())

	_build_log_panel()
	_build_block_popup()
	_build_attack_confirm_popup()
	_build_x_cost_popup()
	_build_legend_popup()
	_build_discard_popup()
	_build_game_over_popup()

func _build_log_panel() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	_match_view.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Action Log"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	_log_display = RichTextLabel.new()
	_log_display.bbcode_enabled = true
	_log_display.scroll_following = true
	_log_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_display.custom_minimum_size = Vector2(300, 200)
	box.add_child(_log_display)

func _on_log_entry(text: String, kind: String) -> void:
	if _log_display == null:
		return
	var color := "#dddddd"
	match kind:
		"system":
			color = "#8fa8ff"
		"combat":
			color = "#ff9955"
		"chat":
			color = "#55ddff"
	_log_display.append_text("[color=%s]%s[/color]\n" % [color, text.replace("[", "(").replace("]", ")")])

func _make_scrolling_row(height: int = 200) -> HBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	scroll.add_child(row)
	return row

func _build_block_popup() -> void:
	_block_popup = PanelContainer.new()
	_block_popup.visible = false
	_block_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_block_popup)
	_block_popup_box = VBoxContainer.new()
	_block_popup.add_child(_block_popup_box)

## Brief "Confirm this attack?" step (§ user request) between choosing a
## target and the attack actually resolving — one attack at a time, not a
## bulk declare-then-confirm phase.
func _build_attack_confirm_popup() -> void:
	_attack_confirm_popup = PanelContainer.new()
	_attack_confirm_popup.visible = false
	_attack_confirm_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_attack_confirm_popup)
	var box := VBoxContainer.new()
	_attack_confirm_popup.add_child(box)
	_attack_confirm_label = Label.new()
	box.add_child(_attack_confirm_label)
	var row := HBoxContainer.new()
	box.add_child(row)
	var yes_btn := Button.new()
	yes_btn.text = "Attack"
	yes_btn.pressed.connect(_on_attack_confirm_yes)
	row.add_child(yes_btn)
	var no_btn := Button.new()
	no_btn.text = "Cancel"
	no_btn.pressed.connect(_on_attack_confirm_no)
	row.add_child(no_btn)

## X-cost Ultimate amount picker (§ user request — Ashen Cricket): shown
## before targeting, letting the player choose how much Larva to spend
## (at least the Leader's ultimate_cost, at most their current total).
func _build_x_cost_popup() -> void:
	_x_cost_popup = PanelContainer.new()
	_x_cost_popup.visible = false
	_x_cost_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_x_cost_popup)
	var box := VBoxContainer.new()
	_x_cost_popup.add_child(box)
	var label := Label.new()
	label.text = "Choose how much Larva to spend:"
	box.add_child(label)
	_x_cost_spinbox = SpinBox.new()
	_x_cost_spinbox.step = 1
	box.add_child(_x_cost_spinbox)
	var row := HBoxContainer.new()
	box.add_child(row)
	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.pressed.connect(_on_x_cost_confirm)
	row.add_child(confirm)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_on_x_cost_cancel)
	row.add_child(cancel)

func _build_legend_popup() -> void:
	_legend_popup = PanelContainer.new()
	_legend_popup.visible = false
	_legend_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_legend_popup)
	_legend_popup_box = VBoxContainer.new()
	_legend_popup.add_child(_legend_popup_box)

func _build_discard_popup() -> void:
	_discard_popup = PanelContainer.new()
	_discard_popup.visible = false
	_discard_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_discard_popup)
	var box := VBoxContainer.new()
	_discard_popup.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 420)
	box.add_child(scroll)
	_discard_popup_box = VBoxContainer.new()
	scroll.add_child(_discard_popup_box)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: _discard_popup.visible = false)
	box.add_child(close)

func _on_player_discard_pressed() -> void:
	_show_discard(GameState.players[HUMAN], "Your")

func _on_opponent_discard_pressed() -> void:
	_show_discard(GameState.players[AI], "%s's" % GameState.players[AI].leader.data.card_name)

func _show_discard(player: PlayerState, label: String) -> void:
	for child in _discard_popup_box.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "%s Discard Pile (%d card%s)" % [label, player.graveyard.size(), "" if player.graveyard.size() == 1 else "s"]
	title.add_theme_font_size_override("font_size", 18)
	_discard_popup_box.add_child(title)
	if player.graveyard.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(empty)"
		_discard_popup_box.add_child(empty_label)
	for c: CardInstance in player.graveyard:
		var entry := Label.new()
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD
		var desc := c.display_name()
		if c.data is CreatureData:
			var cd := c.data as CreatureData
			desc += " (%d/%d)" % [cd.attack, cd.health]
		if c.data.text != "":
			desc += " — " + c.data.text
		entry.text = desc
		_discard_popup_box.add_child(entry)
	_discard_popup.visible = true

func _build_game_over_popup() -> void:
	_game_over_popup = PanelContainer.new()
	_game_over_popup.visible = false
	_game_over_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_game_over_popup)
	var box := VBoxContainer.new()
	_game_over_popup.add_child(box)
	_game_over_label = Label.new()
	box.add_child(_game_over_label)
	var again := Button.new()
	again.text = "New Game"
	again.pressed.connect(_on_new_game_pressed)
	box.add_child(again)

func _on_new_game_pressed() -> void:
	_game_over_popup.visible = false
	_match_view.visible = false
	_refresh_saved_decks_menu()
	_deck_select.visible = true

## --- Signal handlers ---------------------------------------------------------

func _on_turn_started(player_id: int) -> void:
	_refresh()
	if GameState.is_over:
		return
	if GameState.players[player_id].is_ai:
		_busy = true
		_refresh()
		await AIPlayer.take_turn(player_id)
		_busy = false
		_refresh()

## Gang-blocking (§ user request): any number of legal blockers can be
## toggled on before confirming, instead of picking exactly one. Each
## option is a toggle button rather than an instant-submit button so
## multiple can be selected before the choice is locked in.
var _pending_block_selection: Array[CardInstance] = []

func _on_block_requested(attacker: CardInstance, legal_blockers: Array[CardInstance]) -> void:
	_pending_block_selection.clear()
	for child in _block_popup_box.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = "%s is attacking your Leader. Choose any number of blockers." % attacker.display_name()
	_block_popup_box.add_child(label)
	for c: CardInstance in legal_blockers:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "Block with %s (%d/%d)" % [c.display_name(), c.current_attack, c.current_health()]
		btn.toggled.connect(_on_block_toggle.bind(c))
		_block_popup_box.add_child(btn)
	var confirm := Button.new()
	confirm.text = "Confirm Block"
	confirm.pressed.connect(_on_block_confirm)
	_block_popup_box.add_child(confirm)
	var skip := Button.new()
	skip.text = "Take the damage"
	skip.pressed.connect(_on_block_skip)
	_block_popup_box.add_child(skip)
	_block_popup.visible = true

func _on_block_toggle(pressed: bool, c: CardInstance) -> void:
	if pressed:
		if not _pending_block_selection.has(c):
			_pending_block_selection.append(c)
	else:
		_pending_block_selection.erase(c)

func _on_block_confirm() -> void:
	_block_popup.visible = false
	TurnManager.submit_block_choices(_pending_block_selection.duplicate())

func _on_block_skip() -> void:
	_block_popup.visible = false
	TurnManager.submit_block_choices([])

func _on_legend_rule_requested(new_card: CardInstance, existing_copies: Array[CardInstance]) -> void:
	for child in _legend_popup_box.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = "Legend Rule: you already control %s. Which copy do you keep?" % new_card.display_name()
	_legend_popup_box.add_child(label)
	var new_btn := Button.new()
	new_btn.text = "Keep the new one (%d/%d)" % [new_card.current_attack, new_card.current_health()]
	new_btn.pressed.connect(_on_legend_choice.bind(new_card))
	_legend_popup_box.add_child(new_btn)
	for c: CardInstance in existing_copies:
		var btn := Button.new()
		btn.text = "Keep the one already in play (%d/%d)" % [c.current_attack, c.current_health()]
		btn.pressed.connect(_on_legend_choice.bind(c))
		_legend_popup_box.add_child(btn)
	_legend_popup.visible = true

func _on_legend_choice(choice: CardInstance) -> void:
	_legend_popup.visible = false
	TurnManager.submit_legend_choice(choice)

func _on_game_ended(winner_id: int) -> void:
	_game_over_label.text = "%s wins!" % GameState.players[winner_id].leader.data.card_name
	_game_over_popup.visible = true
	_refresh()

## --- Player action handlers --------------------------------------------------

func _on_hero_power_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	var player := GameState.players[HUMAN]
	if _begin_targeting_if_needed(player.leader.data.hero_power_effects, "hero"):
		return
	if not TurnManager.use_hero_power(HUMAN):
		_status_label.text = "Can't use Hero Power right now."
	_refresh()

func _on_ultimate_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	var player := GameState.players[HUMAN]
	if player.leader.data.ultimate_variable_cost:
		var min_spend := player.leader.data.ultimate_cost
		_x_cost_spinbox.min_value = min_spend
		_x_cost_spinbox.max_value = max(min_spend, player.current_larva)
		_x_cost_spinbox.value = min_spend
		_x_cost_popup.visible = true
		return
	if _begin_targeting_if_needed(player.leader.data.ultimate_effects, "ultimate"):
		return
	if not TurnManager.use_ultimate(HUMAN):
		_status_label.text = "Can't use Ultimate right now."
	_refresh()

func _on_x_cost_confirm() -> void:
	_x_cost_popup.visible = false
	var player := GameState.players[HUMAN]
	var amount := int(_x_cost_spinbox.value)
	if amount > player.current_larva:
		_status_label.text = "Not enough Larva."
		return
	_pending_ultimate_larva_spend = amount
	if _begin_targeting_if_needed(player.leader.data.ultimate_effects, "ultimate"):
		return
	var ok := TurnManager.use_ultimate(HUMAN, -1, amount)
	_pending_ultimate_larva_spend = -1
	_status_label.text = "" if ok else "Can't use Ultimate right now."
	_refresh()

func _on_x_cost_cancel() -> void:
	_x_cost_popup.visible = false

## If `effects` needs a creature target and a legal one exists, enters
## target-selection mode and returns true (caller should stop here). If a
## target is needed but none exist, returns false so the caller proceeds
## unTargeted (EffectResolver's auto-pick will find nothing and skip it).
func _begin_targeting_if_needed(effects: Array[Dictionary], power_kind: String) -> bool:
	var side := _required_target_side_for_effects(effects)
	if side == "":
		return false
	var pool := GameState.players[HUMAN].board if side == "friendly" else GameState.players[AI].board
	if not pool.any(func(c: CardInstance) -> bool: return c.is_alive()):
		return false
	_pending_power_kind = power_kind
	_pending_target_side = side
	_status_label.text = "Choose %s creature to target." % ("a friendly" if side == "friendly" else "an enemy")
	_refresh()
	return true

func _required_target_side_for_effects(effects: Array[Dictionary]) -> String:
	for e: Dictionary in effects:
		if TARGETING_EFFECT_SIDES.has(e.get("effect_id", "")):
			return TARGETING_EFFECT_SIDES[e.get("effect_id", "")]
	return ""

func _on_end_turn_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	_clear_selection()
	TurnManager.end_turn()

func _on_cancel_pressed() -> void:
	_clear_selection()
	_status_label.text = ""
	_refresh()

func _clear_selection() -> void:
	_selected_hand_index = -1
	_selected_attacker_id = -1
	_pending_target_side = ""
	_pending_power_kind = ""
	_pending_ultimate_larva_spend = -1

func _on_hand_card_pressed(index: int) -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	var player := GameState.players[HUMAN]
	if index < 0 or index >= player.hand.size():
		return
	var card: CardInstance = player.hand[index]

	if card.data.card_type == CardTypes.GEAR:
		if player.board.is_empty():
			_status_label.text = "No friendly creature to equip Gear to."
			return
		_selected_hand_index = index
		_selected_attacker_id = -1
		_pending_target_side = "friendly"
		_status_label.text = "Choose a friendly creature to equip %s to." % card.display_name()
		_refresh()
		return

	var side := _required_target_side(card)
	if side != "":
		var pool := player.board if side == "friendly" else GameState.players[AI].board
		if pool.any(func(c: CardInstance) -> bool: return c.is_alive()):
			_selected_hand_index = index
			_selected_attacker_id = -1
			_pending_target_side = side
			_status_label.text = "Choose %s creature to target with %s." % [("a friendly" if side == "friendly" else "an enemy"), card.display_name()]
			_refresh()
			return

	_busy = true
	_refresh()
	var ok := await TurnManager.play_card(HUMAN, index)
	_busy = false
	if ok:
		_status_label.text = ""
	else:
		_status_label.text = "Can't play that right now (cost or Legend Rule)."
	_clear_selection()
	_refresh()

## Which side of the board (if any) a hand card's on-play/on-cast effects
## need a creature target from.
func _required_target_side(card: CardInstance) -> String:
	var effects: Array[Dictionary] = []
	var trigger := ""
	if card.data is CreatureData:
		var cd := card.data as CreatureData
		# A Morph (Ambush) creature's on_play effects don't fire when played —
		# it enters face-down with blank data, and they fire later at reveal
		# instead (EffectResolver.fire_on_flip), which is never an interactive
		# player action. Prompting for a target here would be immediately
		# discarded and silently replaced by an auto-pick at flip time.
		if cd.is_ambush():
			return ""
		effects = cd.effects
		trigger = "on_play"
	elif card.data is AbilityData:
		effects = (card.data as AbilityData).effects
		trigger = "on_cast"
	else:
		return ""
	for e: Dictionary in effects:
		if e.get("trigger", "") == trigger and TARGETING_EFFECT_SIDES.has(e.get("effect_id", "")):
			return TARGETING_EFFECT_SIDES[e.get("effect_id", "")]
	return ""

func _on_flip_ambush_pressed(instance_id: int) -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	TurnManager.flip_ambush_paid(HUMAN, instance_id)
	_refresh()

func _on_board_creature_pressed(instance: CardInstance, is_friendly: bool) -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	var player := GameState.players[HUMAN]

	if _selected_hand_index != -1 or _pending_power_kind != "":
		var wants_friendly := _pending_target_side == "friendly"
		if is_friendly != wants_friendly:
			_status_label.text = "Choose %s creature." % ("a friendly" if wants_friendly else "an enemy")
			return
		_busy = true
		_refresh()
		var ok := false
		if _pending_power_kind == "hero":
			ok = TurnManager.use_hero_power(HUMAN, instance.instance_id)
		elif _pending_power_kind == "ultimate":
			ok = TurnManager.use_ultimate(HUMAN, instance.instance_id, _pending_ultimate_larva_spend)
		else:
			ok = await TurnManager.play_card(HUMAN, _selected_hand_index, instance.instance_id)
		_busy = false
		_status_label.text = "" if ok else "Couldn't target that."
		_clear_selection()
		_refresh()
		return

	if is_friendly:
		if CombatResolver.can_attack(instance):
			_selected_attacker_id = instance.instance_id
			_status_label.text = "%s selected — choose a target." % instance.display_name()
		else:
			_status_label.text = "%s can't attack right now." % instance.display_name()
		_refresh()
		return

	# Enemy creature clicked — attempt to resolve a declared attack.
	if _selected_attacker_id == -1:
		return
	var attacker := player.find_on_board(_selected_attacker_id)
	if attacker == null or not CombatResolver.is_legal_creature_target(attacker, instance):
		_status_label.text = "Illegal target."
		return
	_show_attack_confirm(instance)

func _on_enemy_leader_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN or _selected_attacker_id == -1:
		return
	var player := GameState.players[HUMAN]
	var attacker := player.find_on_board(_selected_attacker_id)
	if attacker == null or not CombatResolver.is_legal_leader_target(attacker, GameState.players[AI]):
		_status_label.text = "Leader isn't a legal target (Guard in the way? Flying attackers ignore ground-only Guards)."
		return
	_show_attack_confirm("leader")

## Brief "Confirm this attack?" step (§ user request, like Arena) between
## choosing a target and the attack actually resolving.
func _show_attack_confirm(target) -> void:
	_pending_attack_target = target
	if target is String:
		_attack_confirm_label.text = "Attack the enemy Leader?"
	else:
		var t: CardInstance = target
		_attack_confirm_label.text = "Attack %s (%d/%d)?" % [t.display_name(), t.current_attack, t.current_health()]
	_attack_confirm_popup.visible = true

func _on_attack_confirm_yes() -> void:
	_attack_confirm_popup.visible = false
	var target = _pending_attack_target
	_pending_attack_target = null
	_busy = true
	_refresh()
	await TurnManager.declare_attack(HUMAN, _selected_attacker_id, target)
	_selected_attacker_id = -1
	_busy = false
	_refresh()

func _on_attack_confirm_no() -> void:
	_attack_confirm_popup.visible = false
	_pending_attack_target = null
	# The attacker stays selected so the player can pick a different target,
	# or hit Cancel to deselect entirely.
	_refresh()

## --- Rendering -----------------------------------------------------------

func _refresh() -> void:
	if not _match_view.visible:
		return
	var human := GameState.players[HUMAN]
	var ai := GameState.players[AI]

	_opponent_info.text = "%s — Health %d | Larva %d/%d | Hand %d | Deck %d" % [
		ai.leader.data.card_name, ai.health, ai.current_larva, ai.max_larva, ai.hand.size(), ai.deck.size()
	]
	_opponent_discard_btn.text = "Discard (%d)" % ai.graveyard.size()
	_player_info.text = "%s — Health %d | Larva %d/%d | Turn %d (%s) | Deck %d" % [
		human.leader.data.card_name, human.health, human.current_larva, human.max_larva,
		GameState.turn_number, "Your turn" if GameState.active_player_index == HUMAN else "Opponent's turn", human.deck.size()
	]
	_player_discard_btn.text = "Discard (%d)" % human.graveyard.size()

	_render_row(_opponent_board, ai.board, false)
	_render_row(_player_board, human.board, true)
	_render_hive_row(_opponent_hive, ai.hive_zone)
	_render_hive_row(_player_hive, human.hive_zone)
	_render_hand()

	var can_act := GameState.active_player_index == HUMAN and not _busy and not GameState.is_over
	var targeting := _selected_hand_index != -1 or _pending_power_kind != ""
	_hero_power_btn.disabled = not can_act or targeting or human.leader.hero_power_used_this_turn or human.leader.data.hero_power_cost > human.current_larva
	_hero_power_btn.text = "Hero Power (%d): %s" % [human.leader.data.hero_power_cost, human.leader.data.hero_power_text]
	_ultimate_btn.disabled = not can_act or targeting or human.leader.ultimate_used or human.leader.data.ultimate_cost > human.current_larva
	_ultimate_btn.text = "Ultimate (%d): %s" % [human.leader.data.ultimate_cost, human.leader.data.ultimate_text]
	_end_turn_btn.disabled = not can_act or targeting
	_cancel_btn.visible = targeting or _selected_attacker_id != -1

func _render_row(row: HBoxContainer, board: Array[CardInstance], friendly: bool) -> void:
	for child in row.get_children():
		child.queue_free()
	for c: CardInstance in board:
		row.add_child(_make_creature_widget(c, friendly))
	if not friendly:
		var leader_btn := Button.new()
		leader_btn.text = "Attack Leader"
		leader_btn.custom_minimum_size = Vector2(100, 60)
		leader_btn.pressed.connect(_on_enemy_leader_pressed)
		row.add_child(leader_btn)

func _render_hive_row(row: HBoxContainer, hive_zone: Array[CardInstance]) -> void:
	for child in row.get_children():
		child.queue_free()
	for c: CardInstance in hive_zone:
		row.add_child(_make_hive_widget(c))
	row.get_parent().visible = not hive_zone.is_empty()

func _make_hive_widget(c: CardInstance) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 90)
	var lines := [c.display_name()]
	if c.data.text != "":
		lines.append(_wrap_text(c.data.text))
	btn.text = "\n".join(lines)
	btn.modulate = _card_color(c.data)
	return btn

func _render_hand() -> void:
	for child in _player_hand.get_children():
		child.queue_free()
	var human := GameState.players[HUMAN]
	for i in range(human.hand.size()):
		var card: CardInstance = human.hand[i]
		var cost := CostCalculator.calculate_cost(card.data, human.leader.data)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(170, 190)
		var surcharged := not card.data.matches_kingdom(human.leader.data.kingdoms)
		btn.text = _card_text(card, cost, surcharged)
		btn.modulate = _card_color(card.data)
		btn.disabled = _busy or GameState.active_player_index != HUMAN or cost > human.current_larva
		btn.pressed.connect(_on_hand_card_pressed.bind(i))
		_player_hand.add_child(btn)

func _make_creature_widget(c: CardInstance, friendly: bool) -> Control:
	var box := VBoxContainer.new()
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 150)
	btn.modulate = _card_color(c.data) * (Color(0.6, 0.6, 0.6) if c.is_exhausted() else Color.WHITE)
	btn.pressed.connect(_on_board_creature_pressed.bind(c, friendly))
	box.add_child(btn)

	# A plain Button can't mix text colors, so a click-through RichTextLabel
	# is overlaid on top of it to render BBCode — this is what lets
	# temporarily-granted keywords show in a different color from the
	# card's permanent text (§ user request).
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(rtl)
	rtl.text = _creature_bbcode(c)
	btn.add_child(rtl)

	if friendly and c.is_face_down and c.true_data != null and c.true_data.ambush.get("flip_trigger", "") == "paid":
		var cost := int(c.true_data.ambush.get("flip_cost", 0))
		var flip_btn := Button.new()
		flip_btn.text = "Flip (%d)" % cost
		flip_btn.disabled = _busy or GameState.active_player_index != HUMAN or cost > GameState.players[HUMAN].current_larva
		flip_btn.pressed.connect(_on_flip_ambush_pressed.bind(c.instance_id))
		box.add_child(flip_btn)
	return box

const TEMP_KEYWORD_COLOR := "#ffcc33"

func _creature_bbcode(c: CardInstance) -> String:
	var lines: Array[String] = [_bbcode_escape(c.display_name())]
	var cd0 := c.data as CreatureData
	if cd0 != null and cd0.creature_type != "":
		lines.append(cd0.creature_type)
	lines.append("%d/%d" % [c.current_attack, c.current_health()])
	if c.poison_counters > 0:
		lines.append("Poison x%d" % c.poison_counters)
	if c.data.text != "":
		lines.append(_bbcode_escape(_wrap_text(c.data.text)))
	if not c.temp_keywords.is_empty():
		lines.append("[color=%s]%s (until your next turn)[/color]" % [TEMP_KEYWORD_COLOR, _bbcode_escape(", ".join(c.temp_keywords))])
	if not c.attached_gear.is_empty():
		var gear_names := c.attached_gear.map(func(g: CardInstance) -> String: return g.display_name())
		lines.append("Gear: " + _bbcode_escape(", ".join(gear_names)))
	if c.is_exhausted() and c.is_alive():
		lines.append("[color=#999999](Exhausted — can't block)[/color]")
	if not c.is_alive():
		lines.append("(dead)")
	if c.instance_id == _selected_attacker_id:
		lines.append("[SELECTED]")
	return "\n".join(lines)

func _bbcode_escape(text: String) -> String:
	return text.replace("[", "(").replace("]", ")")

func _card_text(c: CardInstance, cost: int, surcharged: bool = false) -> String:
	var cost_line := "Cost %d (+2 off-Kingdom)" % cost if surcharged else "Cost %d" % cost
	var lines := [c.display_name(), cost_line]
	if c.data is CreatureData:
		var cd := c.data as CreatureData
		if cd.creature_type != "":
			lines.append(cd.creature_type)
		lines.append("%d/%d" % [cd.attack, cd.health])
	else:
		lines.append(c.data.card_type)
	if c.data.text != "":
		lines.append(_wrap_text(c.data.text))
	return "\n".join(lines)

## Buttons don't word-wrap their text on their own, so we hand-wrap ability
## text at a rough character width to keep it legible on the card widgets.
func _wrap_text(text: String, width_chars: int = 22) -> String:
	if text == "":
		return ""
	var words := text.split(" ")
	var lines: Array[String] = []
	var current := ""
	for w: String in words:
		if current == "":
			current = w
		elif (current + " " + w).length() <= width_chars:
			current += " " + w
		else:
			lines.append(current)
			current = w
	if current != "":
		lines.append(current)
	return "\n".join(lines)

func _card_color(card_data: CardData) -> Color:
	return CardRenderUtil.card_color(card_data)
