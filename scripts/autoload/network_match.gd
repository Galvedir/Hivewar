extends Node
## Autoload: host-authoritative network dispatch layer for a live networked
## match (§ multiplayer plan). Both host and guest run a real local
## GameState/TurnManager mirror (see project_multiplayer_architecture
## memory): the HOST is the only side that ever calls TurnManager mutators
## on its own initiative — either its own local UI input on its own turn,
## or a validated action_request from the guest on the guest's turn. The
## GUEST never calls TurnManager proactively; it only ever replays the
## exact action the host already resolved, via a received action_applied
## message, using each function's forced_* parameter (see turn_manager.gd)
## so its mirror can never diverge from what the host actually decided —
## whether that was a real human choice on the host's screen, or the
## host's own AIPlayer-heuristic default for the guest's own decisions
## (block/Legend Rule prompts aren't round-tripped over the network in v1,
## see the memory file for that scope call).
##
## main_ui.gd calls the `local_*` functions below instead of TurnManager
## directly whenever `is_active` is true, for every action a human can
## take; it never needs to know host vs guest itself, `local_*` handles
## that branch internally. Remote actions arrive as `remote_action_applied`
## events shaped exactly like AIPlayer.take_turn()'s replay log, so
## main_ui's existing `_ai_replay_queue`/`_process` pacing pump can consume
## them completely unchanged.

## Fired once both sides have agreed to start and the seat data (leader +
## exact shuffled card order for both seats) is known — deliberately does
## NOT itself call TurnManager.start_networked_game, so main_ui.gd can show/
## lay out the match view first (see _start_match's own comment about the
## Leader panel starting tiny if GameState setup and its resulting
## turn_started/_refresh calls happen before the view has ever been laid
## out) and only then start the real game.
signal match_ready(seats: Array[Dictionary], starting_player_index: int)
## One entry, shaped exactly like an AIPlayer.take_turn() replay-log entry
## ({"kind": ..., ...}) — main_ui.gd appends these straight onto its
## existing _ai_replay_queue as they arrive, one at a time.
signal remote_action_applied(action: Dictionary)
## A hard Steam-level P2P failure (distinct from the heartbeat/silence
## timeout below) — Steam itself reports the session as gone.
signal opponent_disconnected
## § disconnect policy (project_multiplayer_architecture memory, finalized
## 2026-09-11): 3:00 of silence from the opponent — connection looks
## unstable, but not yet treated as a disconnect.
signal connection_warning
## 4:00 of silence — the final 60 seconds before auto-forfeit; fires every
## frame with the whole seconds remaining so the UI can show a hard-to-
## miss countdown.
signal connection_countdown(seconds_left: int)
## Silence ended before reaching the 5:00 mark — clear whatever warning/
## countdown UI is showing.
signal connection_restored
## 5:00 of total silence — this client independently declares itself the
## winner by default and the match is over; main_ui.gd tears down and
## returns to the Main Menu. Symmetric and independent on both sides (see
## the memory file): if the failure is a genuine two-way network
## partition, both clients reach this on their own, each believing it won
## — there's no central arbiter to resolve that, by design.
signal opponent_timed_out
## True while a guest-side action_request is in flight, waiting for the
## host's echo — main_ui.gd shows a "Waiting for host..." status during
## this window (never fires at all on the host, who applies everything
## synchronously/awaits its own popups directly).
signal guest_request_pending(pending: bool)

var is_active := false
var is_host := false
var local_seat := 0
var remote_seat := 1
var remote_steam_id := 0

signal _local_request_completed(msg: Dictionary)

## § disconnect policy — heartbeat every 1 minute; escalating feedback as
## silence approaches the 5-minute total-timeout mark. `_silence_timer` is
## "time since I last heard ANYTHING from my peer" (reset by every packet
## received, not just heartbeats — a real game action counts too, so
## these only matter during long gaps like the opponent thinking through
## a big turn, or truly having disconnected). `_heartbeat_timer` is
## unrelated to my own silence reading; it's purely so the OTHER side
## keeps hearing from ME during those same long gaps.
const HEARTBEAT_INTERVAL := 60.0
const WARNING_THRESHOLD := 180.0    # 3:00
const COUNTDOWN_THRESHOLD := 240.0  # 4:00
const DISCONNECT_THRESHOLD := 300.0 # 5:00

var _heartbeat_timer := 0.0
var _silence_timer := 0.0
var _warned := false
var _countdown_active := false

func _ready() -> void:
	SteamManager.p2p_packet_received.connect(_on_p2p_packet_received)
	SteamManager.p2p_session_failed.connect(_on_p2p_session_failed)

func _process(delta: float) -> void:
	if not is_active:
		return
	_heartbeat_timer += delta
	if _heartbeat_timer >= HEARTBEAT_INTERVAL:
		_heartbeat_timer = 0.0
		_send_to_remote({"type": "heartbeat"})

	_silence_timer += delta
	if _silence_timer >= DISCONNECT_THRESHOLD:
		_on_silence_timeout()
	elif _silence_timer >= COUNTDOWN_THRESHOLD:
		_countdown_active = true
		connection_countdown.emit(int(ceil(DISCONNECT_THRESHOLD - _silence_timer)))
	elif _silence_timer >= WARNING_THRESHOLD and not _warned:
		_warned = true
		connection_warning.emit()

func _on_silence_timeout() -> void:
	if not is_active:
		return
	end_match()
	opponent_timed_out.emit()

func _reset_connection_timers() -> void:
	_heartbeat_timer = 0.0
	_silence_timer = 0.0
	_warned = false
	_countdown_active = false

## --- Match start ------------------------------------------------------------

## Called on the lobby owner's client once both players are ready.
## `local_deck_def`/`remote_deck_def` are each a resolved
## `{"leader_id", "cards"}` deck definition — NOT a name/ref string.
## MultiplayerHubUI resolves both locally (each player's own choice,
## premade or custom, is always resolvable on their own machine) and
## sends the actual definition over Steam lobby member data, rather than
## a ref the OTHER machine has no way to look up if it's a custom Deck
## Builder save (§ bugfix — see MultiplayerHubUI._on_my_deck_selected's
## own comment; this used to silently blow up whenever either player
## picked a custom deck, matching the "Start Match button doesn't do
## anything" report). Shuffles both decks once, locally, then sends the
## exact resulting card order to the guest so both mirrors start byte-
## identical (see GameState.setup_networked_game) — the guest never
## shuffles anything itself.
func start_as_host(local_deck_def: Dictionary, remote_deck_def: Dictionary, remote_id: int) -> void:
	is_active = true
	is_host = true
	local_seat = 0
	remote_seat = 1
	remote_steam_id = remote_id
	_reset_connection_timers()
	var host_cfg := _build_seat_config(local_deck_def)
	var guest_cfg := _build_seat_config(remote_deck_def)
	_send_to_remote({
		"type": "match_start", "starting_player_index": 0,
		"host_deck": host_cfg, "guest_deck": guest_cfg,
	})
	match_ready.emit([host_cfg, guest_cfg], 0)

## Called by main_ui.gd right after actually starting the game (once the
## match view is visible and laid out) — marks which seat is the remote
## one for turn_manager.gd's auto-resolve heuristics (see PlayerState.is_remote).
func mark_remote_seat() -> void:
	GameState.players[remote_seat].is_remote = true

func end_match() -> void:
	is_active = false
	is_host = false
	remote_steam_id = 0
	_reset_connection_timers()

func _build_seat_config(deck_def: Dictionary) -> Dictionary:
	var card_ids: Array[String] = DeckDefinitions.expand(deck_def["cards"])
	card_ids.shuffle()
	return {"leader_id": deck_def["leader_id"], "card_order": card_ids}

## --- Local-player action entry points (called by main_ui.gd) ---------------

func local_play_card(hand_index: int, target_instance_id: int = -1) -> bool:
	if is_host:
		return await _host_apply_play_card(local_seat, hand_index, target_instance_id)
	return await _guest_request_and_wait("play_card", {"hand_index": hand_index, "target_instance_id": target_instance_id})

func local_hero_power(target_instance_id: int = -1) -> bool:
	if is_host:
		return _host_apply_hero_power(local_seat, target_instance_id)
	return await _guest_request_and_wait("hero_power", {"target_instance_id": target_instance_id})

func local_ultimate(target_instance_id: int = -1, larva_to_spend: int = -1) -> bool:
	if is_host:
		return _host_apply_ultimate(local_seat, target_instance_id, larva_to_spend)
	return await _guest_request_and_wait("ultimate", {"target_instance_id": target_instance_id, "larva_to_spend": larva_to_spend})

func local_flip_ambush(board_instance_id: int) -> bool:
	if is_host:
		return _host_apply_flip_ambush(local_seat, board_instance_id)
	return await _guest_request_and_wait("flip_ambush", {"board_instance_id": board_instance_id})

func local_attack(attacker_instance_id: int, target) -> void:
	var target_payload = target if target is String else target.instance_id
	if is_host:
		await _host_apply_attack(local_seat, attacker_instance_id, target)
	else:
		await _guest_request_and_wait("attack", {"attacker_instance_id": attacker_instance_id, "target": target_payload})

func local_end_turn() -> void:
	if is_host:
		_host_apply_end_turn(local_seat)
	else:
		await _guest_request_and_wait("end_turn", {})

func local_concede() -> void:
	if is_host:
		_host_apply_concede(local_seat)
	else:
		await _guest_request_and_wait("concede", {})

## --- Guest side: request + wait for the host's echo -------------------------

func _guest_request_and_wait(kind: String, params: Dictionary) -> bool:
	var payload := params.duplicate()
	payload["type"] = "action_request"
	payload["kind"] = kind
	_send_to_remote(payload)
	guest_request_pending.emit(true)
	var msg: Dictionary = await _local_request_completed
	guest_request_pending.emit(false)
	return msg.get("ok", true)

## --- Host side: apply via the real TurnManager, then broadcast the result --

func _host_apply_play_card(player_index: int, hand_index: int, target_instance_id: int) -> bool:
	var player := GameState.players[player_index]
	var played_instance_id := -1
	if hand_index >= 0 and hand_index < player.hand.size():
		played_instance_id = player.hand[hand_index].instance_id
	var ok: bool = await TurnManager.play_card(player_index, hand_index, target_instance_id)
	_send_to_remote({
		"type": "action_applied", "kind": "play_card", "actor_seat": player_index, "ok": ok,
		"hand_index": hand_index, "target_instance_id": target_instance_id,
		"instance_id": played_instance_id, "legend_keep_id": TurnManager.last_legend_keep_id,
	})
	return ok

func _host_apply_hero_power(player_index: int, target_instance_id: int) -> bool:
	var ok: bool = TurnManager.use_hero_power(player_index, target_instance_id)
	_send_to_remote({
		"type": "action_applied", "kind": "hero_power", "actor_seat": player_index, "ok": ok,
		"target_instance_id": target_instance_id,
	})
	return ok

func _host_apply_ultimate(player_index: int, target_instance_id: int, larva_to_spend: int) -> bool:
	var ok: bool = TurnManager.use_ultimate(player_index, target_instance_id, larva_to_spend)
	_send_to_remote({
		"type": "action_applied", "kind": "ultimate", "actor_seat": player_index, "ok": ok,
		"target_instance_id": target_instance_id, "larva_to_spend": larva_to_spend,
	})
	return ok

func _host_apply_flip_ambush(player_index: int, board_instance_id: int) -> bool:
	var ok: bool = TurnManager.flip_ambush_paid(player_index, board_instance_id)
	_send_to_remote({
		"type": "action_applied", "kind": "flip_ambush", "actor_seat": player_index, "ok": ok,
		"board_instance_id": board_instance_id,
	})
	return ok

func _host_apply_attack(player_index: int, attacker_instance_id: int, target) -> void:
	await TurnManager.declare_attack(player_index, attacker_instance_id, target)
	var target_payload = target if target is String else target.instance_id
	_send_to_remote({
		"type": "action_applied", "kind": "attack", "actor_seat": player_index, "ok": true,
		"attacker_instance_id": attacker_instance_id, "target": target_payload,
		"block_choice_ids": TurnManager.last_block_choice_ids,
	})

func _host_apply_end_turn(player_index: int) -> void:
	TurnManager.end_turn()
	_send_to_remote({"type": "action_applied", "kind": "end_turn", "actor_seat": player_index, "ok": true})

func _host_apply_concede(player_index: int) -> void:
	TurnManager.concede(player_index)
	_send_to_remote({"type": "action_applied", "kind": "concede", "actor_seat": player_index, "ok": true})

## --- Host side: validated requests from the guest ---------------------------

func _handle_action_request(msg: Dictionary) -> void:
	# Only ever act on a request for whoever's turn it actually is — a
	# stray/out-of-turn request (buggy timing, or a modified guest client)
	# is silently dropped rather than trusted.
	if GameState.active_player_index != remote_seat:
		return
	var kind: String = msg.get("kind", "")
	match kind:
		"play_card":
			await _host_apply_play_card(remote_seat, msg.get("hand_index", -1), msg.get("target_instance_id", -1))
		"attack":
			var target = msg["target"] if msg["target"] is String else _find_any_instance(int(msg["target"]))
			await _host_apply_attack(remote_seat, msg.get("attacker_instance_id", -1), target)
		"hero_power":
			_host_apply_hero_power(remote_seat, msg.get("target_instance_id", -1))
		"ultimate":
			_host_apply_ultimate(remote_seat, msg.get("target_instance_id", -1), msg.get("larva_to_spend", -1))
		"flip_ambush":
			_host_apply_flip_ambush(remote_seat, msg.get("board_instance_id", -1))
		"end_turn":
			_host_apply_end_turn(remote_seat)
		"concede":
			_host_apply_concede(remote_seat)

## --- Guest side: apply whatever the host resolved ---------------------------

func _handle_action_applied(msg: Dictionary) -> void:
	var kind: String = msg.get("kind", "")
	var actor_seat: int = msg.get("actor_seat", remote_seat)
	var ok: bool = msg.get("ok", true)
	var is_own_request := actor_seat == local_seat
	if ok:
		match kind:
			"play_card":
				await TurnManager.play_card(actor_seat, msg.get("hand_index", -1), msg.get("target_instance_id", -1), msg.get("legend_keep_id", -1))
			"flip_ambush":
				TurnManager.flip_ambush_paid(actor_seat, msg.get("board_instance_id", -1))
			"hero_power":
				TurnManager.use_hero_power(actor_seat, msg.get("target_instance_id", -1))
			"ultimate":
				TurnManager.use_ultimate(actor_seat, msg.get("target_instance_id", -1), msg.get("larva_to_spend", -1))
			"attack":
				var target = msg["target"] if msg["target"] is String else _find_any_instance(int(msg["target"]))
				await TurnManager.declare_attack(actor_seat, msg.get("attacker_instance_id", -1), target, msg.get("block_choice_ids", []))
			"end_turn":
				TurnManager.end_turn()
			"concede":
				TurnManager.concede(actor_seat)
	if is_own_request:
		_local_request_completed.emit(msg)
	elif ok:
		var replay_action := _to_replay_action(kind, msg)
		if not replay_action.is_empty():
			remote_action_applied.emit(replay_action)

## Shapes a resolved action_applied message exactly like an
## AIPlayer.take_turn() replay-log entry, so main_ui's existing
## _apply_ai_action_visual needs zero changes to animate it.
func _to_replay_action(kind: String, msg: Dictionary) -> Dictionary:
	match kind:
		"play_card":
			return {"kind": "play_card", "instance_id": msg.get("instance_id", -1)}
		"flip_ambush":
			return {"kind": "flip_ambush", "instance_id": msg.get("board_instance_id", -1)}
		"hero_power":
			return {"kind": "hero_power"}
		"ultimate":
			return {"kind": "ultimate"}
		"attack":
			return {"kind": "attack", "attacker_id": msg.get("attacker_instance_id", -1)}
	return {}

func _find_any_instance(instance_id: int) -> CardInstance:
	for p: PlayerState in GameState.players:
		var c := p.find_on_board(instance_id)
		if c != null:
			return c
	return null

## --- Wire transport ----------------------------------------------------------

func _send_to_remote(msg: Dictionary) -> void:
	SteamManager.send_p2p(remote_steam_id, var_to_bytes(msg))

func _on_p2p_packet_received(sender_id: int, bytes: PackedByteArray) -> void:
	var msg = bytes_to_var(bytes)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	var msg_type: String = msg.get("type", "")
	# "match_start" self-configures the guest side right here instead of
	# requiring a separate prior start_as_guest() call — a guest has no
	# other reliable moment to arm is_active/local_seat/remote_steam_id
	# before this packet can arrive, so treating receipt of a well-formed
	# match_start as sufficient proof (from a real lobby member; Steam P2P
	# sessions are only ever accepted from the current lobby, see
	# SteamManager._on_p2p_session_request) sidesteps that ordering
	# entirely.
	if msg_type == "match_start":
		is_active = true
		is_host = false
		local_seat = 1
		remote_seat = 0
		remote_steam_id = sender_id
		_reset_connection_timers()
		var seats: Array[Dictionary] = [msg["host_deck"], msg["guest_deck"]]
		match_ready.emit(seats, msg.get("starting_player_index", 0))
		return
	if not is_active or sender_id != remote_steam_id:
		return
	# Any packet at all from the opponent counts as proof of life, not just
	# heartbeats — see _process's own comment on _silence_timer.
	if _warned or _countdown_active:
		_warned = false
		_countdown_active = false
		connection_restored.emit()
	_silence_timer = 0.0
	match msg_type:
		"action_request":
			if is_host:
				_handle_action_request(msg)
		"action_applied":
			if not is_host:
				_handle_action_applied(msg)

func _on_p2p_session_failed(remote_id: int, _error_code: int) -> void:
	if is_active and remote_id == remote_steam_id:
		opponent_disconnected.emit()
