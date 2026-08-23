class_name CreatureData
extends CardData
## A creature card (§5). `effects` is a list of triggered-ability
## descriptors: [{trigger, effect_id, params}], consumed by EffectResolver.
## `ambush` is non-empty only for Ambush/Metamorphosis cards (§8):
## {
##   "face_down": {"name": String, "attack": int, "health": int},
##   "flip_trigger": "on_attack" | "paid" | "conditional",
##   "flip_cost": int,                       # only used when flip_trigger == "paid"
##   "flip_condition": {"type": String, ...}, # only used when flip_trigger == "conditional"
## }

@export var attack: int = 0
@export var health: int = 1
@export var keywords: Array[String] = []
@export var effects: Array[Dictionary] = []
@export var ambush: Dictionary = {}

func _init() -> void:
	card_type = CardTypes.CREATURE

func has_keyword(kw: String) -> bool:
	return keywords.has(kw)

func is_ambush() -> bool:
	return not ambush.is_empty()
