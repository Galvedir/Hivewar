class_name MultiplayerHubUI
extends Control
## Multiplayer entry screen (§ multiplayer plan — host-authoritative P2P
## via Steam, friend-invite-only for v1): reachable from the Main Menu's
## Multiplayer button. Handles hosting a lobby, inviting a friend via
## Steam's own overlay, and both accepting an incoming Steam invite and a
## manual "join by lobby ID" fallback (useful for testing before the
## invite flow is fully polished, since Steam's invite popup only reaches
## the local player while this screen is actually open — see
## _on_invite_received's own comment).
##
## Deck selection and ready-up (§ user spec: "go to a lobby where you both
## choose decks... from your created decks in the deckbuilder or choose
## from a premade deck") work once both players are in the lobby, synced
## via each player's own Steam lobby MEMBER data (a player can only write
## their own entry, so "reading the opponent's" is how each side sees the
## other's live pick/ready state). Match start itself is deliberately a
## stub for now — see _on_start_match_pressed's own comment — since it
## depends on the network action protocol and match-screen seat
## generalization, both still to be built (see
## project_multiplayer_architecture memory for the full remaining plan).

signal closed

const MEMBER_KEY_DECK := "deck_ref"
const MEMBER_KEY_READY := "ready"

var _status_label: Label
var _host_btn: Button
var _invite_btn: Button
var _cancel_btn: Button
var _join_id_edit: LineEdit
var _join_btn: Button
var _lobby_box: VBoxContainer
var _lobby_members_label: Label
var _my_deck_option: OptionButton
var _deck_refs: Array[String] = [] # parallel to _my_deck_option's items
var _ready_btn: Button
var _opponent_status_label: Label
var _start_match_btn: Button
var _my_ready := false
var _invite_popup: PanelContainer
var _invite_popup_label: Label
var _pending_invite_lobby_id := 0

func _ready() -> void:
	LayoutUtil.fill_parent(self)
	_build_ui()
	SteamManager.lobby_created.connect(_on_lobby_created)
	SteamManager.lobby_joined.connect(_on_lobby_joined)
	SteamManager.lobby_members_changed.connect(_refresh_lobby_state)
	SteamManager.lobby_data_changed.connect(_refresh_lobby_state)
	SteamManager.lobby_left.connect(_refresh_lobby_state)
	SteamManager.invite_received.connect(_on_invite_received)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	LayoutUtil.fill_parent(root)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< Back to Menu"
	back_btn.pressed.connect(func() -> void:
		if SteamManager.current_lobby_id != 0:
			SteamManager.leave_lobby()
		closed.emit())
	top.add_child(back_btn)

	var title := Label.new()
	title.text = "Multiplayer"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status_label)

	_host_btn = Button.new()
	_host_btn.text = "Host a Game"
	_host_btn.pressed.connect(_on_host_pressed)
	root.add_child(_host_btn)

	var join_row := HBoxContainer.new()
	root.add_child(join_row)
	var join_label := Label.new()
	join_label.text = "Join by Lobby ID:"
	join_row.add_child(join_label)
	_join_id_edit = LineEdit.new()
	_join_id_edit.custom_minimum_size = Vector2(220, 0)
	_join_id_edit.placeholder_text = "Lobby ID"
	join_row.add_child(_join_id_edit)
	_join_btn = Button.new()
	_join_btn.text = "Join"
	_join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(_join_btn)

	_lobby_box = VBoxContainer.new()
	_lobby_box.visible = false
	root.add_child(_lobby_box)
	_lobby_members_label = Label.new()
	_lobby_members_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lobby_box.add_child(_lobby_members_label)
	var lobby_btn_row := HBoxContainer.new()
	_lobby_box.add_child(lobby_btn_row)
	_invite_btn = Button.new()
	_invite_btn.text = "Invite Friend"
	_invite_btn.pressed.connect(func() -> void: SteamManager.invite_friend_to_lobby())
	lobby_btn_row.add_child(_invite_btn)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Leave Lobby"
	_cancel_btn.pressed.connect(func() -> void: SteamManager.leave_lobby())
	lobby_btn_row.add_child(_cancel_btn)

	var my_row := HBoxContainer.new()
	_lobby_box.add_child(my_row)
	var my_label := Label.new()
	my_label.text = "Your deck:"
	my_row.add_child(my_label)
	_my_deck_option = OptionButton.new()
	_my_deck_option.custom_minimum_size = Vector2(260, 0)
	_my_deck_option.item_selected.connect(_on_my_deck_selected)
	my_row.add_child(_my_deck_option)
	_ready_btn = Button.new()
	_ready_btn.text = "Ready Up"
	_ready_btn.pressed.connect(_on_ready_pressed)
	my_row.add_child(_ready_btn)

	_opponent_status_label = Label.new()
	_opponent_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lobby_box.add_child(_opponent_status_label)

	_start_match_btn = Button.new()
	_start_match_btn.text = "Start Match"
	_start_match_btn.visible = false
	_start_match_btn.pressed.connect(_on_start_match_pressed)
	_lobby_box.add_child(_start_match_btn)

	_build_invite_popup()
	_build_deck_options()
	_refresh_lobby_state()

## Every premade test deck plus every deck the player has saved in the
## Deck Builder (§ user spec: "choose decks from your created decks in the
## deckbuilder or choose from a premade deck") — the same two pools
## Practice mode's deck list draws from, and the same deck_ref shape
## GameState.setup_game already resolves (a DeckDefinitions id OR a
## DeckStorage save name), so starting the eventual match needs no new
## resolution logic.
func _build_deck_options() -> void:
	_deck_refs.clear()
	_my_deck_option.clear()
	for deck_id in DeckDefinitions.all_deck_ids():
		var deck: Dictionary = DeckDefinitions.get_deck(deck_id)
		var leader: LeaderData = CardDatabase.get_leader(deck["leader_id"])
		_my_deck_option.add_item("%s (%s)" % [deck_id.replace("_", " ").capitalize(), leader.card_name])
		_deck_refs.append(deck_id)
	for deck_name in DeckStorage.all_deck_names():
		_my_deck_option.add_item(deck_name)
		_deck_refs.append(deck_name)

func _deck_display_name(deck_ref: String) -> String:
	if DeckDefinitions.all_deck_ids().has(deck_ref):
		return deck_ref.replace("_", " ").capitalize()
	return deck_ref

func _build_invite_popup() -> void:
	_invite_popup = PanelContainer.new()
	_invite_popup.visible = false
	_invite_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_invite_popup)
	var box := VBoxContainer.new()
	_invite_popup.add_child(box)
	_invite_popup_label = Label.new()
	box.add_child(_invite_popup_label)
	var row := HBoxContainer.new()
	box.add_child(row)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(func() -> void:
		_invite_popup.visible = false
		SteamManager.join_lobby(_pending_invite_lobby_id))
	row.add_child(join_btn)
	var decline_btn := Button.new()
	decline_btn.text = "Decline"
	decline_btn.pressed.connect(func() -> void: _invite_popup.visible = false)
	row.add_child(decline_btn)

## Called every time this screen becomes the active one (§ main_ui.gd's
## _on_open_multiplayer) — refreshes in case Steam state changed while
## this screen was hidden (e.g. the player left a lobby from elsewhere).
func refresh_on_show() -> void:
	_refresh_lobby_state()

func _on_host_pressed() -> void:
	if not SteamManager.is_initialized:
		_status_label.text = "Steam isn't available — make sure the Steam client is running and you're logged in."
		return
	_status_label.text = "Creating lobby..."
	_host_btn.disabled = true
	SteamManager.create_lobby(2)

func _on_join_pressed() -> void:
	var text := _join_id_edit.text.strip_edges()
	if text.is_empty() or not text.is_valid_int():
		_status_label.text = "Enter a valid Lobby ID to join."
		return
	_status_label.text = "Joining lobby..."
	SteamManager.join_lobby(text.to_int())

func _on_lobby_created(success: bool, _lobby_id: int) -> void:
	_host_btn.disabled = false
	if not success:
		_status_label.text = "Couldn't create a lobby — try again."
		return
	_my_ready = false
	_my_deck_option.selected = -1
	_refresh_lobby_state()

func _on_lobby_joined(success: bool, _lobby_id: int) -> void:
	if not success:
		_status_label.text = "Couldn't join that lobby (it may be full, gone, or private)."
		return
	_my_ready = false
	_my_deck_option.selected = -1
	_refresh_lobby_state()

func _on_my_deck_selected(index: int) -> void:
	if index < 0 or index >= _deck_refs.size():
		return
	SteamManager.set_my_lobby_member_data(MEMBER_KEY_DECK, _deck_refs[index])
	_refresh_lobby_state()

func _on_ready_pressed() -> void:
	if _my_deck_option.selected < 0:
		_status_label.text = "Choose a deck first."
		return
	_my_ready = not _my_ready
	SteamManager.set_my_lobby_member_data(MEMBER_KEY_READY, "1" if _my_ready else "0")
	_refresh_lobby_state()

## Match start needs the network action protocol and the match screen's
## hardcoded HUMAN/AI seat assumption generalized to "which seat am I" —
## neither exists yet (see project_multiplayer_architecture memory), so
## this is deliberately just a status message rather than a broken match.
func _on_start_match_pressed() -> void:
	_status_label.text = "Match networking isn't built yet — that's the next step!"

## Steam's own invite popup only reaches the local player while Hivewar is
## already running and this screen is the active one — accepting an
## invite that launches the game fresh, or one that arrives while this
## screen isn't open, isn't handled yet (see this class's own header
## comment).
func _on_invite_received(lobby_id: int, inviter_name: String) -> void:
	_pending_invite_lobby_id = lobby_id
	_invite_popup_label.text = "%s invited you to a game. Join?" % inviter_name
	_invite_popup.visible = true

func _refresh_lobby_state() -> void:
	var lobby_id := SteamManager.current_lobby_id
	_lobby_box.visible = lobby_id != 0
	_host_btn.visible = lobby_id == 0
	_join_id_edit.editable = lobby_id == 0
	_join_btn.disabled = lobby_id != 0
	if lobby_id == 0:
		_my_ready = false
		_status_label.text = "Host a game and invite a friend, or join one they've hosted."
		return

	_lobby_members_label.text = "Lobby %d" % lobby_id
	_ready_btn.text = "Unready" if _my_ready else "Ready Up"
	_ready_btn.disabled = _my_deck_option.selected < 0

	var local_id := SteamManager.get_local_steam_id()
	var opponent_id := 0
	for member_id in SteamManager.get_lobby_members():
		if member_id != local_id:
			opponent_id = member_id
			break

	if opponent_id == 0:
		_opponent_status_label.text = ""
		_start_match_btn.visible = false
		_status_label.text = "Waiting for a friend to join — click Invite Friend, or share this Lobby ID: %d" % lobby_id
		return

	var opponent_deck := SteamManager.get_lobby_member_data(opponent_id, MEMBER_KEY_DECK)
	var opponent_ready := SteamManager.get_lobby_member_data(opponent_id, MEMBER_KEY_READY) == "1"
	_opponent_status_label.text = "%s — Deck: %s — %s" % [
		SteamManager.get_persona_name(opponent_id),
		_deck_display_name(opponent_deck) if opponent_deck != "" else "(choosing...)",
		"Ready!" if opponent_ready else "Not ready",
	]

	var both_ready := _my_ready and opponent_ready
	_start_match_btn.visible = both_ready and SteamManager.is_lobby_owner()
	if both_ready and SteamManager.is_lobby_owner():
		_status_label.text = "Both players ready!"
	elif both_ready:
		_status_label.text = "Both players ready — waiting for the host to start."
	else:
		_status_label.text = "Choose your deck and hit Ready."
