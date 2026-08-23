class_name HiveData
extends CardData
## A persistent, global, ongoing effect controlled by its owner (§5) —
## Magic's "enchantment" equivalent. `static_modifiers` describes continuous
## board-wide effects evaluated by EffectResolver.get_static_stat_bonus(), e.g.
## {"type": "keyword_stat_bonus", "filter_keyword": "Flying", "attack": 1}
## grants +1/+0 to every friendly creature with Flying. `effects` covers any
## triggered behavior the Hive card also has.

@export var static_modifiers: Array[Dictionary] = []
@export var effects: Array[Dictionary] = []

func _init() -> void:
	card_type = CardTypes.HIVE
