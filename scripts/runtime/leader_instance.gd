class_name LeaderInstance
extends RefCounted
## Live per-match state for a player's Leader: which printed LeaderData they
## chose, plus whether their Hero Power/Ultimate have been used (§4).

var data: LeaderData
var hero_power_used_this_turn: bool = false
var ultimate_used: bool = false

func _init(p_data: LeaderData) -> void:
	data = p_data
