class_name DeckBuilderUI
extends Control
## Deckbuilder screen (§11 Phase 2): browse the full card pool, filter by
## Kingdom/rarity/name, pick a Leader, and build/save/edit/delete decks
## obeying §9 (40-60 cards, max 4 copies per name). No unlock economy yet
## (Phase 3), so the whole CardDatabase pool is always available to build with.

signal closed

const HERO_POWER_COLOR := "#8fd0ff"
const ULTIMATE_COLOR := "#ffcc33"

var _leader_id := ""
var _cards := {} # card_id (String) -> count (int)
var _editing_name := "" # name of the saved deck being edited, "" if unsaved/new

var _kingdom_filter := "ALL"
var _rarity_filter := "ALL"
var _search_filter := ""

var _leader_option: OptionButton
var _leader_info_label: RichTextLabel
var _name_edit: LineEdit
var _kingdom_option: OptionButton
var _rarity_option: OptionButton
var _browser_grid: GridContainer
var _deck_list_box: VBoxContainer
var _deck_size_label: Label
var _status_label: Label
var _saved_decks_box: VBoxContainer

func _ready() -> void:
	LayoutUtil.fill_parent(self)
	_build_ui()
	_new_deck()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	LayoutUtil.fill_parent(root)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< Back to Menu"
	back_btn.pressed.connect(func() -> void: closed.emit())
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
	_kingdom_option = OptionButton.new()
	_kingdom_option.add_item("All Kingdoms")
	for k in ["White", "Green", "Black", "Blue", "Red", "Colorless"]:
		_kingdom_option.add_item(k)
	_kingdom_option.item_selected.connect(_on_kingdom_filter_selected)
	filters.add_child(_kingdom_option)

	_rarity_option = OptionButton.new()
	_rarity_option.add_item("All Rarities")
	for r in [Rarities.COMMON, Rarities.UNCOMMON, Rarities.RARE, Rarities.LEGENDARY]:
		_rarity_option.add_item(r)
	_rarity_option.item_selected.connect(_on_rarity_filter_selected)
	filters.add_child(_rarity_option)

	var search_edit := LineEdit.new()
	search_edit.placeholder_text = "Search name..."
	search_edit.custom_minimum_size = Vector2(180, 0)
	search_edit.text_changed.connect(_on_search_changed)
	filters.add_child(search_edit)

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
	_refresh()

func _on_leader_selected(index: int) -> void:
	var leaders := CardDatabase.all_leaders()
	_leader_id = leaders[index - 1].id if index > 0 else ""
	_refresh_leader_info()
	_refresh_browser() # costs are Leader-relative (§4), so the browser needs to re-render
	_refresh_deck_list()

func _on_kingdom_filter_selected(index: int) -> void:
	_kingdom_filter = "ALL" if index == 0 else _kingdom_option.get_item_text(index)
	_refresh_browser()

func _on_rarity_filter_selected(index: int) -> void:
	_rarity_filter = "ALL" if index == 0 else _rarity_option.get_item_text(index)
	_refresh_browser()

func _on_search_changed(text: String) -> void:
	_search_filter = text.to_lower()
	_refresh_browser()

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
	_refresh_deck_list()

func _remove_card(card_id: String) -> void:
	var count := int(_cards.get(card_id, 0))
	if count <= 1:
		_cards.erase(card_id)
	else:
		_cards[card_id] = count - 1
	_refresh_deck_list()

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
	for card: CardData in CardDatabase.all_cards():
		if _kingdom_filter != "ALL":
			if _kingdom_filter == "Colorless":
				if not card.kingdoms.is_empty():
					continue
			elif not card.kingdoms.has(_kingdom_filter):
				continue
		if _rarity_filter != "ALL" and card.rarity != _rarity_filter:
			continue
		if _search_filter != "" and not card.card_name.to_lower().contains(_search_filter):
			continue
		var cost := CostCalculator.calculate_cost(card, leader_data) if leader_data != null else card.cost
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 170)
		btn.text = CardRenderUtil.card_summary(card, cost)
		btn.modulate = CardRenderUtil.card_color(card)
		btn.pressed.connect(_add_card.bind(card.id))
		_browser_grid.add_child(btn)

func _refresh_deck_list() -> void:
	for child in _deck_list_box.get_children():
		child.queue_free()
	var total := 0
	var ids: Array = _cards.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return CardDatabase.get_card(a).card_name < CardDatabase.get_card(b).card_name)
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
