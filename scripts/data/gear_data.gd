class_name GearData
extends CardData
## Equipment that attaches to a friendly creature for a persistent buff
## and/or keyword grant (§5). Stays until the wearer dies unless the card
## says otherwise; attaching new Gear to an already-equipped creature
## discards the old Gear (see GameState.attach_gear).

@export var attack_buff: int = 0
@export var health_buff: int = 0
@export var grants_keywords: Array[String] = []
@export var effects: Array[Dictionary] = []

func _init() -> void:
	card_type = CardTypes.GEAR
