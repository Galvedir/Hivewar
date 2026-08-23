class_name LeaderData
extends CardData
## One per deck, set aside pregame (§4). starting_health defaults to the
## PROPOSED 30 from the spec; individual Leaders may override it.

@export var starting_health: int = 30
@export var hero_power_cost: int = 2
@export var hero_power_text: String = ""
@export var hero_power_effects: Array[Dictionary] = []
@export var ultimate_cost: int = 6
@export var ultimate_text: String = ""
@export var ultimate_effects: Array[Dictionary] = []

func _init() -> void:
	card_type = CardTypes.LEADER
	is_legendary = true
