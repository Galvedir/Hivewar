extends Node
## Autoload: thin wrapper around the GodotSteam `Steam` singleton (§
## multiplayer plan — host-authoritative P2P via Steam). Owns Steamworks
## init, the per-frame callback pump, and the current lobby's lifecycle;
## re-exposes the handful of Steam signals the rest of the game actually
## needs as plain Godot signals with simplified payloads, so nothing else
## in the codebase has to know GodotSteam's raw callback shapes. Fails
## safe everywhere: every public function no-ops (and every signal simply
## never fires) if Steam never initialized, same fail-safe convention as
## every other optional integration in this project (art/audio assets,
## etc.) — this lets the whole game run normally without Steam at all.

signal lobby_created(success: bool, lobby_id: int)
signal lobby_joined(success: bool, lobby_id: int)
signal lobby_left
signal lobby_members_changed
signal invite_received(lobby_id: int, inviter_name: String)
signal p2p_packet_received(sender_id: int, bytes: PackedByteArray)
signal p2p_session_failed(remote_id: int)

const APP_ID := 480 # Valve's public "Spacewar" test app — see project_multiplayer_architecture memory
const P2P_CHANNEL := 0

var is_initialized := false
var current_lobby_id := 0 # 0 = not in a lobby

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		return
	is_initialized = Steam.steamInit()
	if not is_initialized:
		push_warning("SteamManager: Steam.steamInit() failed — Steam client may not be running. Multiplayer will be unavailable this session.")
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_invite.connect(_on_lobby_invite)
	Steam.join_requested.connect(_on_join_requested)
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	Steam.p2p_session_connect_fail.connect(_on_p2p_session_connect_fail)

func _process(_delta: float) -> void:
	if not is_initialized:
		return
	Steam.run_callbacks()
	_poll_p2p_packets()

func get_local_steam_id() -> int:
	return Steam.getSteamID() if is_initialized else 0

func get_local_persona_name() -> String:
	return Steam.getPersonaName() if is_initialized else "Player"

## A remote user's display name — Steam only guarantees this is populated
## for a user the local client has actually seen data for yet (e.g. a
## fellow lobby member), same caveat GodotSteam itself documents.
func get_persona_name(steam_id: int) -> String:
	return Steam.getFriendPersonaName(steam_id) if is_initialized else "Player"

## Creates a friends-only lobby (§ user request: friend-invite-only for
## v1, not public matchmaking) — result arrives via the `lobby_created`
## signal, not a return value, since Steamworks resolves this
## asynchronously.
func create_lobby(max_members: int = 2) -> void:
	if is_initialized:
		Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max_members)

func join_lobby(lobby_id: int) -> void:
	if is_initialized:
		Steam.joinLobby(lobby_id)

func leave_lobby() -> void:
	if not is_initialized or current_lobby_id == 0:
		return
	for member_id in get_lobby_members():
		if member_id != get_local_steam_id():
			Steam.closeP2PSessionWithUser(member_id)
	Steam.leaveLobby(current_lobby_id)
	current_lobby_id = 0
	lobby_left.emit()

## Opens Steam's own friend-picker overlay (§ user request: "connect with
## a friend" — no custom UI needed for who to invite).
func invite_friend_to_lobby() -> void:
	if is_initialized and current_lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(current_lobby_id)

func get_lobby_members() -> Array[int]:
	var out: Array[int] = []
	if not is_initialized or current_lobby_id == 0:
		return out
	var count := Steam.getNumLobbyMembers(current_lobby_id)
	for i in range(count):
		out.append(Steam.getLobbyMemberByIndex(current_lobby_id, i))
	return out

func is_lobby_owner() -> bool:
	return is_initialized and current_lobby_id != 0 and Steam.getLobbyOwner(current_lobby_id) == get_local_steam_id()

## Steam lobby "data" is a small replicated key/value store every member
## can read — used for match setup (chosen decks, ready flags, lobby
## phase) before the P2P connection for the actual match takes over.
func set_lobby_data(key: String, value: String) -> void:
	if is_initialized and current_lobby_id != 0:
		Steam.setLobbyData(current_lobby_id, key, value)

func get_lobby_data(key: String) -> String:
	return Steam.getLobbyData(current_lobby_id, key) if is_initialized and current_lobby_id != 0 else ""

func send_p2p(remote_id: int, bytes: PackedByteArray, reliable: bool = true) -> void:
	if is_initialized:
		Steam.sendP2PPacket(remote_id, bytes, Steam.P2P_SEND_RELIABLE if reliable else Steam.P2P_SEND_UNRELIABLE, P2P_CHANNEL)

func _poll_p2p_packets() -> void:
	while true:
		var size := Steam.getAvailableP2PPacketSize(P2P_CHANNEL)
		if size <= 0:
			return
		var packet: Dictionary = Steam.readP2PPacket(size, P2P_CHANNEL)
		if packet.is_empty():
			return
		p2p_packet_received.emit(int(packet.get("remote_steam_id", 0)), packet.get("data", PackedByteArray()))

func _on_lobby_created(connect: int, lobby_id: int) -> void:
	var success := connect == Steam.RESULT_OK # verified empirically: EResult k_EResultOK = 1, not 0
	if success:
		current_lobby_id = lobby_id
	lobby_created.emit(success, lobby_id)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	var success := response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS
	if success:
		current_lobby_id = lobby_id
		# Every member accepts P2P from every other member up front — this
		# is a 2-player lobby, so there's exactly one peer to accept
		# regardless of who's "host"; the actual host-authoritative game
		# logic is a layer above this connection, not enforced by it.
		for member_id in get_lobby_members():
			if member_id != get_local_steam_id():
				Steam.acceptP2PSessionWithUser(member_id)
	lobby_joined.emit(success, lobby_id)

func _on_lobby_chat_update(lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	if lobby_id == current_lobby_id:
		for member_id in get_lobby_members():
			if member_id != get_local_steam_id():
				Steam.acceptP2PSessionWithUser(member_id)
		lobby_members_changed.emit()

## Fires when a Steam friend invites the local user to a lobby while
## Hivewar is already running (accepting an invite while the game isn't
## running instead launches it fresh with a connect-lobby command line
## argument — not yet handled here, since testing so far only needs the
## game-already-running path).
func _on_lobby_invite(inviter_id: int, lobby_id: int, _game_id: int) -> void:
	invite_received.emit(lobby_id, get_persona_name(inviter_id))

## Fires when the user accepts an invite via Steam's own UI (friends
## list "Join Game") while Hivewar is already running — that acceptance
## already expresses clear intent, so join immediately rather than
## showing a second in-game confirmation.
func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	join_lobby(lobby_id)

func _on_p2p_session_request(remote_steam_id: int) -> void:
	# Only ever accept a session from someone actually in our lobby — a
	# bare P2P session request from an unrelated Steam user is not
	# something Hivewar has any reason to accept.
	if current_lobby_id != 0 and get_lobby_members().has(remote_steam_id):
		Steam.acceptP2PSessionWithUser(remote_steam_id)

func _on_p2p_session_connect_fail(remote_steam_id: int, _session_error: int) -> void:
	p2p_session_failed.emit(remote_steam_id)
