class_name AbilityData
extends CardData
## A one-shot, sorcery-speed spell effect (§5). Resolves once via
## EffectResolver.resolve_effects(effects, "on_cast", ctx), then goes to
## the graveyard.

@export var effects: Array[Dictionary] = []

func _init() -> void:
	card_type = CardTypes.ABILITY
