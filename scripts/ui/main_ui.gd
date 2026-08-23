extends Control
## Minimal functional Phase 1 UI (§16 step 8): deck-select screen, then a
## hand/board/Leader match view wired straight to TurnManager — the same
## API AIPlayer drives. Built programmatically (no hand-authored .tscn
## layout) so it's easy to keep in sync with the engine; swap for real
## scenes/art in a later pass without touching TurnManager/GameState.

const KINGDOM_COLORS := {
	"White": Color(0.85, 0.78, 0.55),
	"Green": Color(0.25, 0.55, 0.30),
	"Black": Color(0.30, 0.20, 0.35),
	"Blue": Color(0.30, 0.55, 0.85),
	"Red": Color(0.80, 0.25, 0.25),
}
const COLORLESS_COLOR := Color(0.55, 0.55, 0.50)
const HUMAN := 0
const AI := 1

var _deck_select: VBoxContainer
var _match_view: HBoxContainer
var _match_root: VBoxContainer
var _log_display: RichTextLabel
var _opponent_board: HBoxContainer
var _opponent_info: Label
var _player_board: HBoxContainer
var _player_hand: HBoxContainer
var _player_info: Label
var _status_label: Label
var _hero_power_btn: Button
var _ultimate_btn: Button
var _end_turn_btn: Button
var _block_popup: PanelContainer
var _block_popup_box: VBoxContainer
var _game_over_popup: PanelContainer
var _game_over_label: Label

var _selected_hand_index := -1
var _selected_attacker_id := -1
var _busy := false # true while the AI or an awaited attack is resolving

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_deck_select()
	_build_match_view()
	_match_view.visible = false
	TurnManager.turn_started.connect(_on_turn_started)
	TurnManager.block_decision_requested.connect(_on_block_requested)
	GameState.game_ended.connect(_on_game_ended)
	GameLog.entry_added.connect(_on_log_entry)

## --- Deck select ------------------------------------------------------------

func _build_deck_select() -> void:
	_deck_select = VBoxContainer.new()
	_deck_select.set_anchors_preset(Control.PRESET_CENTER)
	_deck_select.custom_minimum_size = Vector2(420, 0)
	add_child(_deck_select)

	var title := Label.new()
	title.text = "Hivewar — choose your deck"
	title.add_theme_font_size_override("font_size", 28)
	_deck_select.add_child(title)

	for deck_id in DeckDefinitions.all_deck_ids():
		var deck: Dictionary = DeckDefinitions.get_deck(deck_id)
		var leader: LeaderData = CardDatabase.get_leader(deck["leader_id"])
		var btn := Button.new()
		btn.text = "%s\n(%s)" % [deck_id.replace("_", " ").capitalize(), leader.card_name]
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_on_deck_chosen.bind(deck_id))
		_deck_select.add_child(btn)

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
	_match_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_match_view.add_theme_constant_override("separation", 10)
	add_child(_match_view)

	_match_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_match_root.add_theme_constant_override("separation", 8)
	_match_view.add_child(_match_root)

	_opponent_info = Label.new()
	_match_root.add_child(_opponent_info)
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

	_player_board = _make_scrolling_row()
	_match_root.add_child(_player_board.get_parent())
	_player_info = Label.new()
	_match_root.add_child(_player_info)
	_player_hand = _make_scrolling_row()
	_match_root.add_child(_player_hand.get_parent())

	_build_log_panel()
	_build_block_popup()
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

func _make_scrolling_row() -> HBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
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

func _on_block_requested(attacker: CardInstance, legal_blockers: Array[CardInstance]) -> void:
	for child in _block_popup_box.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = "%s is attacking your Leader. Block?" % attacker.display_name()
	_block_popup_box.add_child(label)
	for c: CardInstance in legal_blockers:
		var btn := Button.new()
		btn.text = "Block with %s (%d/%d)" % [c.display_name(), c.current_attack, c.current_health()]
		btn.pressed.connect(_on_block_choice.bind(c))
		_block_popup_box.add_child(btn)
	var skip := Button.new()
	skip.text = "Take the damage"
	skip.pressed.connect(_on_block_choice.bind(null))
	_block_popup_box.add_child(skip)
	_block_popup.visible = true

func _on_block_choice(choice) -> void:
	_block_popup.visible = false
	TurnManager.submit_block_choice(choice)

func _on_game_ended(winner_id: int) -> void:
	_game_over_label.text = "%s wins!" % GameState.players[winner_id].leader.data.card_name
	_game_over_popup.visible = true
	_refresh()

## --- Player action handlers --------------------------------------------------

func _on_hero_power_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	if not TurnManager.use_hero_power(HUMAN):
		_status_label.text = "Can't use Hero Power right now."
	_refresh()

func _on_ultimate_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	if not TurnManager.use_ultimate(HUMAN):
		_status_label.text = "Can't use Ultimate right now."
	_refresh()

func _on_end_turn_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	_selected_hand_index = -1
	_selected_attacker_id = -1
	TurnManager.end_turn()

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
		_status_label.text = "Choose a friendly creature to equip %s to." % card.display_name()
		_refresh()
		return
	if TurnManager.play_card(HUMAN, index):
		_status_label.text = ""
	else:
		_status_label.text = "Can't play that right now (cost or Legend Rule)."
	_selected_hand_index = -1
	_refresh()

func _on_flip_ambush_pressed(instance_id: int) -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	TurnManager.flip_ambush_paid(HUMAN, instance_id)
	_refresh()

func _on_board_creature_pressed(instance: CardInstance, is_friendly: bool) -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	var player := GameState.players[HUMAN]

	if _selected_hand_index != -1:
		if is_friendly:
			if TurnManager.play_card(HUMAN, _selected_hand_index, instance.instance_id):
				_status_label.text = ""
			else:
				_status_label.text = "Couldn't equip Gear there."
		_selected_hand_index = -1
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
	_busy = true
	_refresh()
	await TurnManager.declare_attack(HUMAN, _selected_attacker_id, instance)
	_selected_attacker_id = -1
	_busy = false
	_refresh()

func _on_enemy_leader_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN or _selected_attacker_id == -1:
		return
	var player := GameState.players[HUMAN]
	var attacker := player.find_on_board(_selected_attacker_id)
	if attacker == null or not CombatResolver.is_legal_leader_target(attacker, GameState.players[AI]):
		_status_label.text = "Leader isn't a legal target (Guard in the way?)."
		return
	_busy = true
	_refresh()
	await TurnManager.declare_attack(HUMAN, _selected_attacker_id, "leader")
	_selected_attacker_id = -1
	_busy = false
	_refresh()

## --- Rendering -----------------------------------------------------------

func _refresh() -> void:
	if not _match_view.visible:
		return
	var human := GameState.players[HUMAN]
	var ai := GameState.players[AI]

	_opponent_info.text = "%s — Health %d | Larva %d/%d | Hand %d" % [
		ai.leader.data.card_name, ai.health, ai.current_larva, ai.max_larva, ai.hand.size()
	]
	_player_info.text = "%s — Health %d | Larva %d/%d | Turn %d (%s)" % [
		human.leader.data.card_name, human.health, human.current_larva, human.max_larva,
		GameState.turn_number, "Your turn" if GameState.active_player_index == HUMAN else "Opponent's turn"
	]

	_render_row(_opponent_board, ai.board, false)
	_render_row(_player_board, human.board, true)
	_render_hand()

	var can_act := GameState.active_player_index == HUMAN and not _busy and not GameState.is_over
	_hero_power_btn.disabled = not can_act or human.leader.hero_power_used_this_turn or human.leader.data.hero_power_cost > human.current_larva
	_hero_power_btn.text = "Hero Power (%d): %s" % [human.leader.data.hero_power_cost, human.leader.data.hero_power_text]
	_ultimate_btn.disabled = not can_act or human.leader.ultimate_used or human.leader.data.ultimate_cost > human.current_larva
	_ultimate_btn.text = "Ultimate (%d): %s" % [human.leader.data.ultimate_cost, human.leader.data.ultimate_text]
	_end_turn_btn.disabled = not can_act

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

func _render_hand() -> void:
	for child in _player_hand.get_children():
		child.queue_free()
	var human := GameState.players[HUMAN]
	for i in range(human.hand.size()):
		var card: CardInstance = human.hand[i]
		var cost := CostCalculator.calculate_cost(card.data, human.leader.data)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(170, 190)
		btn.text = _card_text(card, cost)
		btn.modulate = _card_color(card.data)
		btn.disabled = _busy or GameState.active_player_index != HUMAN or cost > human.current_larva
		btn.pressed.connect(_on_hand_card_pressed.bind(i))
		_player_hand.add_child(btn)

func _make_creature_widget(c: CardInstance, friendly: bool) -> Control:
	var box := VBoxContainer.new()
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 150)
	btn.text = _creature_text(c)
	btn.modulate = _card_color(c.data)
	if c.instance_id == _selected_attacker_id:
		btn.text += "\n[SELECTED]"
	btn.pressed.connect(_on_board_creature_pressed.bind(c, friendly))
	box.add_child(btn)
	if friendly and c.is_face_down and c.true_data != null and c.true_data.ambush.get("flip_trigger", "") == "paid":
		var cost := int(c.true_data.ambush.get("flip_cost", 0))
		var flip_btn := Button.new()
		flip_btn.text = "Flip (%d)" % cost
		flip_btn.disabled = _busy or GameState.active_player_index != HUMAN or cost > GameState.players[HUMAN].current_larva
		flip_btn.pressed.connect(_on_flip_ambush_pressed.bind(c.instance_id))
		box.add_child(flip_btn)
	return box

func _creature_text(c: CardInstance) -> String:
	var lines := [c.display_name(), "%d/%d" % [c.current_attack, c.current_health()]]
	if c.poison_counters > 0:
		lines.append("Poison x%d" % c.poison_counters)
	if c.data.text != "":
		lines.append(_wrap_text(c.data.text))
	if not c.is_alive():
		lines.append("(dead)")
	return "\n".join(lines)

func _card_text(c: CardInstance, cost: int) -> String:
	var lines := [c.display_name(), "Cost %d" % cost]
	if c.data is CreatureData:
		var cd := c.data as CreatureData
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
	if card_data.kingdoms.is_empty():
		return COLORLESS_COLOR
	return KINGDOM_COLORS.get(card_data.kingdoms[0], COLORLESS_COLOR)
