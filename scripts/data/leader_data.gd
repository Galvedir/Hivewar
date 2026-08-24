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
## X-cost Ultimate (§ user request — Ashen Cricket): when true, the player
## chooses how much Larva to spend (at least 1, up to their current total)
## instead of paying the fixed ultimate_cost; the amount actually spent is
## passed through as ctx.larva_spent for effects like
## buff_friendly_per_larva_spent to scale by.
@export var ultimate_variable_cost: bool = false

func _init() -> void:
	card_type = CardTypes.LEADER
	is_legendary = true
