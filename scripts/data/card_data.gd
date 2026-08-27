class_name CardData
extends Resource
## Base printed-card definition shared by every card type (§5).
## Instances are built at startup by CardDatabase from data/card_definitions.gd
## and data/leader_definitions.gd — see CardDatabase for the data-driven load path.

@export var id: String = ""
@export var card_name: String = ""
@export var card_type: String = CardTypes.CREATURE
@export var cost: int = 0
@export var kingdoms: Array[String] = []
@export var rarity: String = Rarities.COMMON
@export var text: String = ""
@export var is_legendary: bool = false
## Path to this card's illustration, resolved by CardDatabase at load time
## by matching card_name against whatever art has been dropped into
## art/cards/illustrations/ (or art/leaders/ for LeaderData) — see
## CardDatabase._scan_illustrations. Empty if no art exists for this card
## yet (art is being added incrementally during playtesting).
@export var illustration_path: String = ""

## True if this card is Colorless or shares a Kingdom with leader_kingdoms.
## Used by CostCalculator (§4) — a Hybrid card only needs one match.
func matches_kingdom(leader_kingdoms: Array[String]) -> bool:
	if kingdoms.is_empty():
		return true
	for k in kingdoms:
		if leader_kingdoms.has(k):
			return true
	return false
