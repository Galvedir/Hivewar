class_name PlayerState
extends RefCounted
## Live per-match state for one player/side: Leader, health, Larva, and all
## zones (§2, §9). Pure data — no scene-tree dependency, per §13, so the
## same state can be driven by a human UI, the AI (§12), or a future
## networked opponent (§11 Phase 5) without rewrites.

var player_id: int
var is_ai: bool = false
## § multiplayer plan — true for the OTHER seat in a networked match, from
## whichever client's own local mirror this is. Only ever consulted on the
## HOST's mirror (see turn_manager.gd's declare_attack/_resolve_legend_rule):
## it makes the host auto-resolve the guest's block/Legend Rule decisions
## with the same heuristics AIPlayer already uses, rather than popping up a
## prompt on the host's screen for a choice that isn't the host's to make.
## The guest's own mirror never reaches those branches at all — it only
## ever replays a decision the host already resolved (via each function's
## forced_* param), so is_remote is set there purely for symmetry/possible
## UI use, not because its value changes any decision logic.
var is_remote: bool = false
var leader: LeaderInstance
var health: int = 30

var max_larva: int = 0     # permanent max, capped at 10 (§2)
var current_larva: int = 0 # can exceed max_larva for the turn via temporary bonuses
var temp_larva_bonus: int = 0

var deck: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var board: Array[CardInstance] = []
var hive_zone: Array[CardInstance] = []
var graveyard: Array[CardInstance] = []

func _init(p_id: int, p_leader: LeaderInstance, p_is_ai: bool = false) -> void:
	player_id = p_id
	leader = p_leader
	is_ai = p_is_ai
	health = p_leader.data.starting_health

func has_guard() -> bool:
	for c in board:
		if c.is_alive() and c.has_keyword(Keywords.GUARD):
			return true
	return false

func guards() -> Array[CardInstance]:
	return board.filter(func(c: CardInstance) -> bool: return c.is_alive() and c.has_keyword(Keywords.GUARD))

func draw_card() -> CardInstance:
	if deck.is_empty():
		return null
	var c: CardInstance = deck.pop_front()
	hand.append(c)
	return c

func find_on_board(instance_id: int) -> CardInstance:
	for c in board:
		if c.instance_id == instance_id:
			return c
	return null

## Legend Rule (§4): at most 1 copy of a given Legendary name may be in play
## on this player's side at a time.
func legendary_copies_in_play(card_name: String) -> Array[CardInstance]:
	return board.filter(func(c: CardInstance) -> bool: return c.data.card_name == card_name and c.data.is_legendary)
