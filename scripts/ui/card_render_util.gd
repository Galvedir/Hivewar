class_name CardRenderUtil
extends RefCounted
## Shared card-widget rendering helpers used everywhere a card is shown
## (Collection, Deck Builder browser, and every match-view widget — hand,
## board creatures, hive). § user request: the base widget shows only its
## artwork plus an ATK/DEF corner badge (creatures only) and no text at
## all; hovering reveals a CardPreviewOverlay with the art on top and all
## of the card's text below, with the badge repeated in its own corner and
## nowhere else. Live in-play stats (buffs/damage) aren't known here — the
## caller supplies the ATK/DEF text and hover body text so this stays
## usable for both printed CardData (Collection/Deck Builder/hand) and
## live CardInstance state (board creatures).

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
## at a rough character width to stay legible.
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

## Fills `btn` edge-to-edge with `card_data`'s illustration and clears its
## text (§ user request — the base card view is art-only). Falls back to a
## flat kingdom-colored background when no art has been matched yet, so
## the card stays visually distinct until real art is dropped in. Returns
## the resolved texture (or null) for the caller to pass along to
## wire_hover_preview.
static func apply_full_bleed_art(btn: Button, card_data: CardData) -> Texture2D:
	btn.text = ""
	var tex := CardDatabase.get_illustration_texture(card_data)
	if tex != null:
		var art := TextureRect.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		LayoutUtil.fill_parent(art)
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		btn.add_child(art)
	else:
		btn.modulate = card_color(card_data)
	return tex

## Adds a bottom-right ATK/DEF badge as a child of `widget` (§ user
## request — creature stats show only here on the base card view, and
## again only in this same corner on the enlarged hover view).
static func add_corner_badge(widget: Control, text: String) -> void:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	badge.add_theme_constant_override("shadow_offset_x", 1)
	badge.add_theme_constant_override("shadow_offset_y", 1)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.anchor_left = 1.0
	badge.anchor_top = 1.0
	badge.anchor_right = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -44
	badge.offset_top = -20
	badge.offset_right = -4
	badge.offset_bottom = -2
	widget.add_child(badge)

## Wires the shared hover-to-enlarge behavior onto `widget`. No-ops if
## `overlay` is null (e.g. a widget rendered somewhere with no preview
## overlay built for it).
static func wire_hover_preview(widget: Control, overlay: CardPreviewOverlay, tex: Texture2D, bbcode_text: String, badge_text: String) -> void:
	if overlay == null:
		return
	widget.mouse_entered.connect(func() -> void: overlay.show_for(tex, bbcode_text, badge_text, widget.get_global_rect()))
	widget.mouse_exited.connect(overlay.hide_preview)

## Full card text for the enlarged hover view — everything except ATK/DEF,
## which is shown only via the corner badge. `show_cost` is false for
## already-in-play Hive cards, matching their previous no-cost display.
static func card_full_text(card_data: CardData, cost: int = 0, surcharged: bool = false, show_cost: bool = true) -> String:
	var lines: Array[String] = [card_data.card_name]
	if show_cost and card_data.card_type != CardTypes.LEADER:
		lines.append("Cost %d (+2 off-Kingdom)" % cost if surcharged else "Cost %d" % cost)
	lines.append(kingdom_label(card_data))
	if card_data is CreatureData:
		var cd := card_data as CreatureData
		if cd.creature_type != "":
			lines.append(cd.creature_type)
	elif card_data.card_type != CardTypes.LEADER:
		lines.append(card_data.card_type)
	if card_data is LeaderData:
		var ld := card_data as LeaderData
		lines.append("Hero Power (%d): %s" % [ld.hero_power_cost, wrap_text(ld.hero_power_text, 34)])
		lines.append("Ultimate (%d): %s" % [ld.ultimate_cost, wrap_text(ld.ultimate_text, 34)])
	elif card_data.text != "":
		lines.append(wrap_text(card_data.text, 34))
	return "\n".join(lines)
