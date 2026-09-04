class_name CardRenderUtil
extends RefCounted
## Shared card-widget rendering helpers used everywhere a card is shown
## (Collection, Deck Builder browser, and every match-view widget — hand,
## board creatures, hive). § user request: the base widget shows only its
## artwork, its name (top-left) and Larva cost (top-right, in a circular
## badge — a placeholder for real card-frame art later), and an ATK/DEF
## corner badge (creatures only) — no rules text. Hovering reveals a
## CardPreviewOverlay with the same name/cost decorations over its (larger)
## art, and all of the card's rules text below with the ATK/DEF badge
## repeated in its own corner there too. Live in-play stats (buffs/damage)
## aren't known here — the caller supplies the ATK/DEF text and hover body
## text so this stays usable for both printed CardData (Collection/Deck
## Builder/hand) and live CardInstance state (board creatures).

const KINGDOM_COLORS := {
	Kingdoms.WHITE: Color(0.85, 0.78, 0.55),
	Kingdoms.GREEN: Color(0.25, 0.55, 0.30),
	Kingdoms.BLACK: Color(0.30, 0.20, 0.35),
	Kingdoms.BLUE: Color(0.30, 0.55, 0.85),
	Kingdoms.RED: Color(0.80, 0.25, 0.25),
}
const COLORLESS_COLOR := Color(0.55, 0.55, 0.50)
const CARD_BACK_PATH := "res://art/cards/card_back.png"

const NAME_BAR_HEIGHT := 22.0
const COST_BADGE_SIZE := 26.0
const DARK_BOX_COLOR := Color(0, 0, 0, 0.62) # mostly-transparent black (§ user request), shared by the rules-text panel and both ATK/DEF badge boxes
const GLOW_COLOR := Color(1.0, 0.85, 0.25, 0.95)

static func make_dark_box_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = DARK_BOX_COLOR
	style.set_corner_radius_all(3)
	return style

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
## text (§ user request — the base card view is art-only). Falls back to
## the card's Kingdom frame background (§ user request — one shared
## background image per Kingdom, e.g. Monogyne) when no illustration has
## been matched yet, or to a flat kingdom-colored tint if that Kingdom has
## no frame image either. Leaders are excluded from the Kingdom-frame
## fallback (§ user request — "Leaders should use the full card art, not
## the background art... full art card, not full background art"): a
## Leader without a personal portrait yet just gets the flat tint instead
## of borrowing a shared, non-Leader-specific background. Returns the
## resolved illustration texture (or null — note this is independent of
## whether a frame image is now showing) for the caller to pass along to
## wire_hover_preview.
static func apply_full_bleed_art(btn: Button, card_data: CardData) -> Texture2D:
	btn.text = ""
	var tex := CardDatabase.get_illustration_texture(card_data)
	if tex != null:
		_add_full_rect_texture(btn, tex)
	else:
		var frame_tex: Texture2D = null
		if not (card_data is LeaderData):
			frame_tex = CardDatabase.get_kingdom_frame_texture(card_data)
		if frame_tex != null:
			_add_full_rect_texture(btn, frame_tex)
		else:
			btn.modulate = card_color(card_data)
	return tex

static func _add_full_rect_texture(widget: Control, tex: Texture2D) -> void:
	var rect := TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(rect)
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	widget.add_child(rect)

## The number shown in the top-right circle badge: a Leader's starting
## health (§ user request — Leaders aren't cast for Larva, so their
## circle shows life total instead) or the printed/effective Larva cost
## for every other card type.
static func badge_value(card_data: CardData, cost: int) -> int:
	if card_data is LeaderData:
		return (card_data as LeaderData).starting_health
	return cost

## Adds the base card face's name (top-left, ellipsized instead of ever
## overlapping the cost badge) and top-right circle badge (Larva cost, or
## a Leader's starting health — see badge_value; a plain circle for now,
## § user request: "eventually this circle will be replaced with an
## image") on top of `btn`'s art. Combines apply_full_bleed_art with these
## two decorations since every card display needs all three together.
## Returns the resolved art texture (or null) for the caller to pass along
## to wire_hover_preview.
static func style_card_face(btn: Button, card_data: CardData, cost: int) -> Texture2D:
	var tex := apply_full_bleed_art(btn, card_data)
	add_name_label(btn, card_data.card_name)
	add_cost_badge(btn, badge_value(card_data, cost))
	return tex

## Semi-transparent bar across the top (a placeholder "nameplate" until
## real card-frame art exists) holding the printed name. clip_text +
## OVERRUN_TRIM_ELLIPSIS is what turns an overlong name into "Some Long
## Na…" instead of overlapping the cost badge (§ user request) — the
## label's own right edge is anchored to stop short of the badge rather
## than the ellipsis needing any special-casing for it. Exposed (not
## private) so CardPreviewOverlay can build the same decoration over its
## own, larger art region.
static func add_name_label(widget: Control, card_name: String, font_size: int = 13) -> Label:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.55)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_right = 1.0
	bar.offset_bottom = NAME_BAR_HEIGHT
	widget.add_child(bar)

	var label := Label.new()
	label.text = card_name
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", font_size)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_right = 1.0
	label.offset_left = 4.0
	label.offset_right = -(COST_BADGE_SIZE + 8.0) # stop short of the cost badge regardless of the widget's actual width
	label.offset_bottom = NAME_BAR_HEIGHT
	widget.add_child(label)
	return label

static func make_cost_circle_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.92)
	style.border_color = Color(0.85, 0.8, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(COST_BADGE_SIZE / 2.0))
	return style

## Circular Larva-cost badge, top-right — a flat placeholder shape for now
## (§ user request: "eventually this circle will be replaced with an
## image"). Exposed (not private) so CardPreviewOverlay can build the same
## decoration over its own, larger art region.
static func add_cost_badge(widget: Control, cost: int) -> Label:
	var circle := Panel.new()
	circle.add_theme_stylebox_override("panel", make_cost_circle_style())
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.anchor_left = 1.0
	circle.anchor_right = 1.0
	circle.offset_left = -(COST_BADGE_SIZE + 4.0)
	circle.offset_top = 4.0
	circle.offset_right = -4.0
	circle.offset_bottom = 4.0 + COST_BADGE_SIZE
	widget.add_child(circle)

	var label := Label.new()
	label.text = str(cost)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(label)
	circle.add_child(label)
	return label

## Adds a bottom-right ATK/DEF badge — white text on a mostly-transparent
## black box (§ user request) — as a child of `widget`. Only ever called
## for a creature (every call site already skips it entirely for
## Ability/Gear/Hive cards), so no box appears where there's no ATK/DEF to
## show (§ user request).
static func add_corner_badge(widget: Control, text: String) -> void:
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", make_dark_box_style())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 1.0
	box.anchor_top = 1.0
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -44
	box.offset_top = -20
	box.offset_right = -4
	box.offset_bottom = -2
	widget.add_child(box)

	var badge := Label.new()
	badge.text = text
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(badge)
	box.add_child(badge)

## A glowing outline (§ user request: "activate abilities... denote that by
## having a glowing outline of what cards are able to be used") — an
## oversized bordered+soft-shadowed panel behind the widget, rather than any
## bloom/shader effect, to stay consistent with this project's flat,
## StyleBoxFlat-driven visual language (e.g. the gold "selected attacker"
## tint). Caller decides what "usable" means for the widget in question
## (playable hand card, attack-ready creature, legal target, an available
## Hero Power/Ultimate, ...) — this just draws the cue.
static func add_playable_glow(widget: Control) -> void:
	var glow := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = GLOW_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.55)
	style.shadow_size = 6
	glow.add_theme_stylebox_override("panel", style)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.anchor_right = 1.0
	glow.anchor_bottom = 1.0
	glow.offset_left = -4
	glow.offset_top = -4
	glow.offset_right = 4
	glow.offset_bottom = 4
	widget.add_child(glow)

## Wires the shared hover-to-enlarge behavior onto `widget`. No-ops if
## `overlay` is null (e.g. a widget rendered somewhere with no preview
## overlay built for it).
static func wire_hover_preview(widget: Control, overlay: CardPreviewOverlay, card_data: CardData, tex: Texture2D, cost: int, bbcode_text: String, badge_text: String) -> void:
	if overlay == null:
		return
	widget.mouse_entered.connect(func() -> void: overlay.show_for(card_data, tex, cost, bbcode_text, badge_text, widget.get_global_rect()))
	widget.mouse_exited.connect(overlay.hide_preview)

## Face-down card-back visual (§ user request — the battlefield HUD needs a
## deck pile and, later, a fanned opponent hand, both of which show a
## face-down back rather than any real card). Uses real art once it exists
## at CARD_BACK_PATH; until then draws a simple placeholder so a pile still
## reads clearly as "a card" instead of a blank rect — swap-in-place, same
## fail-safe convention as every other optional art asset in this project.
static func build_card_back(size: Vector2) -> Control:
	var back := Panel.new()
	back.custom_minimum_size = size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(CARD_BACK_PATH):
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		back.add_theme_stylebox_override("panel", style)
		_add_full_rect_texture(back, load(CARD_BACK_PATH))
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.12, 0.20)
		style.border_color = Color(0.55, 0.45, 0.75)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		back.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = "LARVA"
		label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.9))
		label.add_theme_font_size_override("font_size", maxi(8, int(size.x * 0.16)))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		LayoutUtil.fill_parent(label)
		back.add_child(label)
	return back

## Deck/discard "pile" visual (§ user request: "a spot that shows the deck,
## the discard pile") — a face-down card-back plus a count badge. Used bare
## for the deck (not interactive) and dropped into a Button for the discard
## pile (kept clickable to open its existing list popup) — the visual
## itself doesn't need to know which case it's in.
static func build_pile_visual(size: Vector2, count: int) -> Control:
	var root := Control.new()
	root.custom_minimum_size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := build_card_back(size)
	LayoutUtil.fill_parent(back)
	root.add_child(back)

	var badge := Panel.new()
	badge.add_theme_stylebox_override("panel", make_dark_box_style())
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.anchor_left = 0.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_top = -18
	root.add_child(badge)

	var label := Label.new()
	label.text = str(count)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(label)
	badge.add_child(label)
	return root

## First line of a card's rules text (§ user request): "{Kingdom} -
## {Creature Type}" for creatures, "{Kingdom} - {Ability/Gear/Hive}"
## otherwise. Leaders skip this entirely — card_full_text shows their Hero
## Power/Ultimate instead, and "Kingdom - Leader" isn't meaningful the same
## way.
static func type_line(card_data: CardData) -> String:
	var kingdom := kingdom_label(card_data)
	if card_data is CreatureData:
		var cd := card_data as CreatureData
		return "%s - %s" % [kingdom, cd.creature_type] if cd.creature_type != "" else "%s - Creature" % kingdom
	return "%s - %s" % [kingdom, card_data.card_type]

## Splits `text` into one line per keyword/ability clause (§ user
## request — "each keyword should be on its own line followed by any
## abilities it has, each ability should also be on its own line"):
## card_definitions.gd already writes keywords first, then any triggered
## abilities, as sentences separated by ". " — this turns each such clause
## into its own line instead of one flowing paragraph, so no per-card text
## rewrites were needed. Long clauses still wrap within their own line.
static func format_rules_text(text: String, width_chars: int = 34) -> String:
	if text == "":
		return ""
	var clauses := text.split(". ")
	var lines: Array[String] = []
	for i in range(clauses.size()):
		var clause: String = clauses[i].strip_edges()
		if clause == "":
			continue
		if i < clauses.size() - 1 or not clause.ends_with("."):
			clause += "." # re-add the period the ". " split consumed (every clause but a bare-period-less last one)
		lines.append(wrap_text(clause, width_chars))
	return "\n".join(lines)

## Rules-text body for the enlarged hover view. Name and cost are shown as
## dedicated overlay decorations instead (matching the base card face), so
## this is everything else: the kingdom/type line, then each keyword/
## ability on its own line, then (for Leaders) Hero Power/Ultimate.
static func card_full_text(card_data: CardData) -> String:
	var lines: Array[String] = []
	if card_data.card_type != CardTypes.LEADER:
		lines.append(type_line(card_data))
	var body := format_rules_text(card_data.text)
	if body != "":
		lines.append(body)
	if card_data is LeaderData:
		var ld := card_data as LeaderData
		lines.append("Hero Power (%d): %s" % [ld.hero_power_cost, format_rules_text(ld.hero_power_text)])
		lines.append("Ultimate (%d): %s" % [ld.ultimate_cost, format_rules_text(ld.ultimate_text)])
	return "\n".join(lines)
