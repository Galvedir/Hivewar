class_name MultiplayerHubUI
extends Control
## Multiplayer entry screen (§ multiplayer plan — host-authoritative P2P
## via Steam, friend-invite-only for v1): reachable from the Main Menu's
## Multiplayer button. Handles hosting a lobby, inviting a friend via
## Steam's own overlay, and a manual "join by lobby ID" fallback (useful
## for testing). Accepting an INCOMING invite is handled by main_ui.gd
## instead, as a top-level overlay independent of which screen is
## currently showing — see its _on_invite_received's own comment for why
## that couldn't live here.
##
## Deck selection and ready-up (§ user spec: "go to a lobby where you both
## choose decks... from your created decks in the deckbuilder or choose
## from a premade deck") work once both players are in the lobby, synced
## via each player's own Steam lobby MEMBER data (a player can only write
## their own entry, so "reading the opponent's" is how each side sees the
## other's live pick/ready state). Match start itself hands off to
## NetworkMatch (see _on_start_match_pressed) — this screen's own job ends
## there; main_ui.gd owns the actual match view and reacts to
## NetworkMatch.match_ready to swap over to it.

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
var _opponent_id := 0 # the current lobby's other member, kept in sync by _refresh_lobby_state

func _ready() -> void:
	LayoutUtil.fill_parent(self)
	_build_ui()
	SteamManager.lobby_created.connect(_on_lobby_created)
	SteamManager.lobby_joined.connect(_on_lobby_joined)
	SteamManager.lobby_members_changed.connect(_refresh_lobby_state)
	SteamManager.lobby_data_changed.connect(_refresh_lobby_state)
	SteamManager.lobby_left.connect(_refresh_lobby_state)
	SteamManager.p2p_session_failed.connect(_on_p2p_session_failed)

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

## § bugfix — a custom (Deck Builder-saved) deck's name only resolves
## against DeckStorage on the machine that saved it; the opponent's
## DeckStorage has no idea it exists. Sending just the ref string here
## used to leave the HOST unable to resolve the GUEST's custom deck (or
## vice versa) when it came time to actually start the match — silently:
## _build_seat_config would look it up, find nothing, and blow up
## resolving Dictionary["cards"] on an empty result, which aborted
## start_as_host before it ever got to match_ready.emit(), matching the
## user's "Start Match button doesn't do anything" report exactly. Fix:
## resolve the FULL deck definition locally (always possible — a player
## always has their OWN choice available, premade or custom) and send
## that, not just a name that only means something on this machine.
func _on_my_deck_selected(index: int) -> void:
	if index < 0 or index >= _deck_refs.size():
		return
	var ref := _deck_refs[index]
	var deck_def := _resolve_deck_ref(ref)
	var payload := {"ref": ref, "leader_id": deck_def.get("leader_id", ""), "cards": deck_def.get("cards", {})}
	SteamManager.set_my_lobby_member_data(MEMBER_KEY_DECK, JSON.stringify(payload))
	_refresh_lobby_state()

## Same resolution GameState.setup_game/_resolve_deck_ref does — a deck
## ref is checked against the shared premade pool first, then the local
## player's own DeckStorage saves. Only ever called with a ref chosen by
## the LOCAL player, so DeckStorage always actually has it if it's not
## premade.
func _resolve_deck_ref(deck_ref: String) -> Dictionary:
	if DeckDefinitions.all_deck_ids().has(deck_ref):
		return DeckDefinitions.get_deck(deck_ref)
	return DeckStorage.get_deck(deck_ref)

## Parses the {"ref", "leader_id", "cards"} blob written by
## _on_my_deck_selected above out of a lobby member's raw MEMBER_KEY_DECK
## string. Returns {} for "not chosen yet" (empty string) or anything
## malformed.
func _parse_deck_payload(text: String) -> Dictionary:
	if text == "":
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _on_ready_pressed() -> void:
	if _my_deck_option.selected < 0:
		_status_label.text = "Choose a deck first."
		return
	_my_ready = not _my_ready
	SteamManager.set_my_lobby_member_data(MEMBER_KEY_READY, "1" if _my_ready else "0")
	_refresh_lobby_state()

## Only the lobby owner ever sees this button (see _refresh_lobby_state) —
## it shuffles both decks locally and hands off to NetworkMatch, which
## sends the resulting deck data to the guest and fires `match_ready` on
## both clients; main_ui.gd is what actually swaps this screen out for the
## match view once that arrives (see its _on_network_match_ready).
## § bugfix — each early-out used to be a silent no-op with zero visible
## feedback, which is exactly what "the Start Match button doesn't do
## anything" looks like from the outside regardless of the actual cause.
## Every branch now leaves a status message behind.
func _on_start_match_pressed() -> void:
	if not SteamManager.is_lobby_owner():
		return # button isn't even visible to a non-owner; defensive only
	if _opponent_id == 0:
		_status_label.text = "No opponent in the lobby to start a match with."
		return
	if _my_deck_option.selected < 0:
		_status_label.text = "Choose a deck first."
		return
	var my_deck_def := _resolve_deck_ref(_deck_refs[_my_deck_option.selected])
	var opponent_deck_def := _parse_deck_payload(SteamManager.get_lobby_member_data(_opponent_id, MEMBER_KEY_DECK))
	if my_deck_def.is_empty() or opponent_deck_def.is_empty():
		_status_label.text = "Couldn't read a deck — try re-selecting your deck and Ready Up again."
		return
	_status_label.text = "Starting match..."
	NetworkMatch.start_as_host(my_deck_def, opponent_deck_def, _opponent_id)

## § bugfix — this used to only ever be checked once NetworkMatch was
## already mid-match (NetworkMatch._on_p2p_session_failed gates on
## is_active), so a P2P connection failure happening during the LOBBY
## phase — before Start Match is ever pressed, e.g. restrictive NAT/
## firewall on either side preventing a direct connection at all — was
## silently dropped: lobby DATA (deck picks, ready state) still syncs fine
## regardless, since that goes through Steam's central lobby service, not
## a direct P2P link, so nothing in the lobby UI ever hinted at a problem
## until Start Match tried to actually send P2P data and went nowhere.
## This is a real, plausible explanation for "Start Match doesn't do
## anything" persisting even after the deck-resolution bug was fixed.
func _on_p2p_session_failed(remote_id: int, error_code: int) -> void:
	if remote_id != _opponent_id or NetworkMatch.is_active:
		return
	var reason := "timed out" if error_code == Steam.P2P_SESSION_ERROR_TIMEOUT else "failed (error %d)" % error_code
	_status_label.text = "Couldn't establish a direct connection to your opponent (%s) — this can happen with restrictive NAT/firewall settings. Starting a match likely won't work until this is resolved." % reason

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
	_opponent_id = 0
	for member_id in SteamManager.get_lobby_members():
		if member_id != local_id:
			_opponent_id = member_id
			break

	if _opponent_id == 0:
		_opponent_status_label.text = ""
		_start_match_btn.visible = false
		_status_label.text = "Waiting for a friend to join — click Invite Friend, or share this Lobby ID: %d" % lobby_id
		return

	var opponent_deck := _parse_deck_payload(SteamManager.get_lobby_member_data(_opponent_id, MEMBER_KEY_DECK))
	var opponent_ready := SteamManager.get_lobby_member_data(_opponent_id, MEMBER_KEY_READY) == "1"
	_opponent_status_label.text = "%s — Deck: %s — %s" % [
		SteamManager.get_persona_name(_opponent_id),
		_deck_display_name(opponent_deck.get("ref", "")) if not opponent_deck.is_empty() else "(choosing...)",
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
