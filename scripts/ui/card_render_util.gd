class_name CardRenderUtil
extends RefCounted
## Shared card-widget text/color helpers for the deckbuilder and collection
## screens, which render printed CardData directly (no live CardInstance /
## runtime state to reflect, unlike main_ui.gd's in-match widgets).

const KINGDOM_COLORS := {
	Kingdoms.WHITE: Color(0.85, 0.78, 0.55),
	Kingdoms.GREEN: Color(0.25, 0.55, 0.30),
	Kingdoms.BLACK: Color(0.30, 0.20, 0.35),
	Kingdoms.BLUE: Color(0.30, 0.55, 0.85),
	Kingdoms.RED: Color(0.80, 0.25, 0.25),
}
const COLORLESS_COLOR := Color(0.55, 0.55, 0.50)

static func card_color(card_data: CardData) -> Color:
	if card_data.kingdoms.is_empty():
		return COLORLESS_COLOR
	return KINGDOM_COLORS.get(card_data.kingdoms[0], COLORLESS_COLOR)

static func kingdom_label(card_data: CardData) -> String:
	if card_data.kingdoms.is_empty():
		return Kingdoms.COLORLESS
	return "/".join(card_data.kingdoms)

## Buttons don't word-wrap their own text, so ability text is hand-wrapped
## at a rough character width to stay legible on the card widgets.
static func wrap_text(text: String, width_chars: int = 22) -> String:
	if text == "":
		return ""
	var words := text.split(" ")
	var lines: Array[String] = []
	var current := ""
	for w: String in words:
		if current == "":
			current = w
		elif (current + " " + w).length() <= width_chars:
			current += " " + w
		else:
			lines.append(current)
			current = w
	if current != "":
		lines.append(current)
	return "\n".join(lines)

## Multi-line summary for a printed card (not a live instance). `surcharged`
## (§4 Kingdom Cost Matching) marks that `cost` already includes the +2
## off-Kingdom Larva surcharge, so that's visible on the card itself rather
## than something the player has to work out by comparing Kingdoms.
static func card_summary(card_data: CardData, cost: int, surcharged: bool = false) -> String:
	var cost_line := "Cost %d (+2 off-Kingdom)" % cost if surcharged else "Cost %d" % cost
	var lines := [card_data.card_name, cost_line, kingdom_label(card_data)]
	if card_data is CreatureData:
		var cd := card_data as CreatureData
		if cd.creature_type != "":
			lines.append(cd.creature_type)
		lines.append("%d/%d" % [cd.attack, cd.health])
	else:
		lines.append(card_data.card_type)
	if card_data.text != "":
		lines.append(wrap_text(card_data.text))
	return "\n".join(lines)
