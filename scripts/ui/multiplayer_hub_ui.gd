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
## Deck selection and match start aren't built yet — once both players
## are in the lobby this just shows their names with a "coming soon" note
## (see project_multiplayer_architecture memory for the full remaining
## plan: deck pick, ready-up, the network protocol, match-screen changes).

signal closed

var _status_label: Label
var _host_btn: Button
var _invite_btn: Button
var _cancel_btn: Button
var _join_id_edit: LineEdit
var _join_btn: Button
var _lobby_box: VBoxContainer
var _lobby_members_label: Label
var _invite_popup: PanelContainer
var _invite_popup_label: Label
var _pending_invite_lobby_id := 0

func _ready() -> void:
	LayoutUtil.fill_parent(self)
	_build_ui()
	SteamManager.lobby_created.connect(_on_lobby_created)
	SteamManager.lobby_joined.connect(_on_lobby_joined)
	SteamManager.lobby_members_changed.connect(_refresh_lobby_state)
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

	_build_invite_popup()
	_refresh_lobby_state()

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
	_refresh_lobby_state()

func _on_lobby_joined(success: bool, _lobby_id: int) -> void:
	if not success:
		_status_label.text = "Couldn't join that lobby (it may be full, gone, or private)."
		return
	_refresh_lobby_state()

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
		if _status_label.text.begins_with("Lobby") or _status_label.text.begins_with("Waiting") or _status_label.text == "":
			_status_label.text = "Host a game and invite a friend, or join one they've hosted."
		return
	var members := SteamManager.get_lobby_members()
	var names := []
	for member_id in members:
		var name := SteamManager.get_persona_name(member_id)
		names.append(name + (" (you)" if member_id == SteamManager.get_local_steam_id() else ""))
	_lobby_members_label.text = "Lobby %d — %s" % [lobby_id, ", ".join(names)]
	if members.size() >= 2:
		_status_label.text = "Both players connected! Deck selection isn't built yet — coming soon."
	else:
		_status_label.text = "Waiting for a friend to join — click Invite Friend, or share this Lobby ID: %d" % lobby_id
