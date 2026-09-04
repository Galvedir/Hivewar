class_name CollectionUI
extends Control
## Collection screen (§11 Phase 2): a read-only, filterable browse of every
## card in the game. No unlock economy exists yet (Phase 3), so "owned"
## currently just means "exists" — this screen is where Phase 3's unlock
## state will eventually gate which cards render as owned vs locked.

signal closed

## Collection screen music (§ user request): Music 1 plays once, then
## Music 2 takes over and loops forever — and only while this screen is
## the active one (main_ui.gd pauses the ambient menu track for the
## duration; see _on_open_collection/_on_collection_closed).
const MUSIC_1_PATH := "res://music/collection_menu_music_1.mp3"
const MUSIC_2_PATH := "res://music/collection_menu_music_2.mp3"

var _kingdom_filter := "ALL"
var _rarity_filter := "ALL"
var _search_filter := ""

var _kingdom_option: OptionButton
var _rarity_option: OptionButton
var _search_edit: LineEdit
var _grid: GridContainer
var _count_label: Label
var _overlay: CardPreviewOverlay
var _music_player: AudioStreamPlayer

func _ready() -> void:
	LayoutUtil.fill_parent(self)
	_build_ui()
	_refresh()

func _build_ui() -> void:
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

	var title := Label.new()
	title.text = "Collection"
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(title)

	var filters := HBoxContainer.new()
	root.add_child(filters)
	_kingdom_option = OptionButton.new()
	_kingdom_option.add_item("All Kingdoms")
	for k in Kingdoms.ALL + [Kingdoms.COLORLESS]:
		_kingdom_option.add_item(k)
	_kingdom_option.item_selected.connect(_on_kingdom_filter_selected)
	filters.add_child(_kingdom_option)

	_rarity_option = OptionButton.new()
	_rarity_option.add_item("All Rarities")
	for r in [Rarities.COMMON, Rarities.UNCOMMON, Rarities.RARE, Rarities.LEGENDARY]:
		_rarity_option.add_item(r)
	_rarity_option.item_selected.connect(_on_rarity_filter_selected)
	filters.add_child(_rarity_option)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search name..."
	_search_edit.custom_minimum_size = Vector2(180, 0)
	_search_edit.text_changed.connect(_on_search_changed)
	filters.add_child(_search_edit)

	_count_label = Label.new()
	filters.add_child(_count_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)

	# Added directly to self (a plain Control, not a Container) rather than
	# under `root`/`scroll`/`_grid` — a Container would otherwise fight the
	# overlay's manually-set global_position every layout pass.
	_overlay = CardPreviewOverlay.new()
	add_child(_overlay)

	_music_player = AudioStreamPlayer.new()
	_music_player.finished.connect(_on_music_1_finished)
	add_child(_music_player)

## Starts this screen's music (§ user request): Music 1 once, then Music 2
## looping — called by main_ui.gd when this screen becomes the active one.
## No-ops (fails safe, same pattern as every other optional art/audio
## asset) if Music 1 isn't present yet.
func start_music() -> void:
	if not ResourceLoader.exists(MUSIC_1_PATH):
		return
	var stream: AudioStream = load(MUSIC_1_PATH)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	_music_player.stream = stream
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()

## Music 1 finishing (a one-shot, non-looping stream) is what hands off to
## Music 2 — a plain AudioStreamPlayer never re-emits `finished` for a
## stream with loop enabled, so this can't re-trigger once Music 2 starts.
func _on_music_1_finished() -> void:
	if not ResourceLoader.exists(MUSIC_2_PATH):
		return
	var stream: AudioStream = load(MUSIC_2_PATH)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music_player.stream = stream
	_music_player.play()

## § user request: filters shouldn't carry over between visits — back to
## defaults (and the widgets reset to match) every time you leave.
func _reset_filters() -> void:
	_kingdom_filter = "ALL"
	_rarity_filter = "ALL"
	_search_filter = ""
	_kingdom_option.selected = 0
	_rarity_option.selected = 0
	_search_edit.text = ""
	_refresh()

func _on_kingdom_filter_selected(index: int) -> void:
	_kingdom_filter = "ALL" if index == 0 else _kingdom_option.get_item_text(index)
	_refresh()

func _on_rarity_filter_selected(index: int) -> void:
	_rarity_filter = "ALL" if index == 0 else _rarity_option.get_item_text(index)
	_refresh()

func _on_search_changed(text: String) -> void:
	_search_filter = text.to_lower()
	_refresh()

func _refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var shown := 0
	# Leaders are browsable here too (§ user request) — they're printed
	# CardData just like everything else (Legendary rarity, own kingdoms),
	# so they fold into the same filtered/sorted/searched grid for free.
	var all_cards: Array = CardDatabase.all_cards() + CardDatabase.all_leaders()
	all_cards.sort_custom(func(a: CardData, b: CardData) -> bool: return a.card_name < b.card_name)
	for card: CardData in all_cards:
		if _kingdom_filter != "ALL":
			if _kingdom_filter == Kingdoms.COLORLESS:
				if not card.kingdoms.is_empty():
					continue
			elif not card.kingdoms.has(_kingdom_filter):
				continue
		if _rarity_filter != "ALL" and card.rarity != _rarity_filter:
			continue
		if _search_filter != "" and not card.card_name.to_lower().contains(_search_filter):
			continue
		shown += 1
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 160)
		var tex := CardRenderUtil.style_card_face(btn, card, card.cost)
		btn.focus_mode = Control.FOCUS_NONE # read-only browse — no pressed handler, just not focus-tabbable
		var badge_text := ""
		if card is CreatureData:
			var cd := card as CreatureData
			badge_text = "%d/%d" % [cd.attack, cd.health]
			CardRenderUtil.add_corner_badge(btn, badge_text)
		CardRenderUtil.wire_hover_preview(btn, _overlay, card, tex, card.cost, CardRenderUtil.card_full_text(card), badge_text)
		_grid.add_child(btn)
	_count_label.text = "%d cards" % shown
