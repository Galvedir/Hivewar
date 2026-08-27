class_name CardPreviewOverlay
extends Control
## Shared "hover to inspect" popup (§ user request): base card widgets show
## only artwork plus name/cost/ATK-DEF decorations — no rules text — so
## this is where the full card gets shown on hover: art on top (with the
## same name/cost decorations as the base card, just larger), all of the
## card's rules text on the bottom half, and the ATK/DEF badge repeated in
## its own corner of that RULES area specifically (not the art area).
##
## Root is a plain Control (not PanelContainer/any other Container) on
## purpose: a Container forces every direct Control child to fill its
## whole content rect on layout, which silently overrides a child's own
## anchors/offsets — that bug is exactly why the ATK/DEF badge used to
## render stretched across the art area instead of staying pinned to the
## bottom-right of the rules-text area below it. `_text_area` is a plain
## Control for the same reason, so the badge nested inside it can be
## anchored to just that sub-region instead of the whole card.
##
## One instance is built per screen (Collection, Deck Builder, the match
## view) and reused for every card widget on that screen; `top_level` is
## set so its position is independent of whatever Container it happens to
## be parented under (a GridContainer/ScrollContainer would otherwise fight
## a manually-set global_position every layout pass).

const PREVIEW_SIZE := Vector2(260, 340)
const ART_HEIGHT := 170.0
const GAP := 12.0

var _art: TextureRect
var _art_area: Control
var _name_label: Label
var _cost_circle: Panel
var _cost_label: Label
var _text_area: Control
var _text: RichTextLabel
var _badge: Label

func _ready() -> void:
	custom_minimum_size = PREVIEW_SIZE
	size = PREVIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 100
	visible = false

	var bg := Panel.new()
	LayoutUtil.fill_parent(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_art_area = Control.new()
	_art_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_area.anchor_right = 1.0
	_art_area.offset_bottom = ART_HEIGHT
	add_child(_art_area)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(_art)
	_art_area.add_child(_art)

	# Same name/cost decorations as the base card face (§ user request:
	# "do the same thing with the name and cost for the enlarged cards"),
	# just laid over the bigger art area here.
	_name_label = CardRenderUtil.add_name_label(_art_area, "", 15)
	_cost_label = CardRenderUtil.add_cost_badge(_art_area, 0)
	_cost_circle = _cost_label.get_parent() as Panel

	_text_area = Control.new()
	_text_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_area.anchor_right = 1.0
	_text_area.anchor_bottom = 1.0
	_text_area.offset_top = ART_HEIGHT
	add_child(_text_area)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(_text)
	_text_area.add_child(_text)

	_badge = Label.new()
	_badge.add_theme_color_override("font_color", Color.WHITE)
	_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	_badge.add_theme_constant_override("shadow_offset_x", 1)
	_badge.add_theme_constant_override("shadow_offset_y", 1)
	_badge.add_theme_font_size_override("font_size", 20)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.anchor_left = 1.0
	_badge.anchor_top = 1.0
	_badge.anchor_right = 1.0
	_badge.anchor_bottom = 1.0
	_badge.offset_left = -76
	_badge.offset_top = -30
	_badge.offset_right = -8
	_badge.offset_bottom = -6
	_text_area.add_child(_badge) # anchored within the rules-text area only (§ user request), not the whole card

## Shows the preview near `anchor_rect` (the hovered widget's global rect),
## clamped to stay fully on-screen. `card_data` supplies the name/cost
## decorations directly (Leaders hide the cost circle, same as the base
## card face); `bbcode_text`/`badge_text` are still caller-supplied since
## they differ between printed CardData and a live CardInstance's current
## stats/status.
func show_for(card_data: CardData, tex: Texture2D, cost: int, bbcode_text: String, badge_text: String, anchor_rect: Rect2) -> void:
	_art.texture = tex
	_art.visible = tex != null
	_name_label.text = card_data.card_name
	_cost_circle.visible = card_data.card_type != CardTypes.LEADER
	_cost_label.text = str(cost)
	_text.text = bbcode_text
	_badge.text = badge_text
	_badge.visible = badge_text != ""
	_position_near(anchor_rect)
	move_to_front()
	visible = true

func hide_preview() -> void:
	visible = false

func _position_near(anchor_rect: Rect2) -> void:
	var viewport_size := get_viewport_rect().size
	var x := anchor_rect.position.x + anchor_rect.size.x * 0.5 - PREVIEW_SIZE.x * 0.5
	var y := anchor_rect.position.y - PREVIEW_SIZE.y - GAP
	if y < 0.0:
		y = anchor_rect.position.y + anchor_rect.size.y + GAP
	x = clamp(x, 4.0, viewport_size.x - PREVIEW_SIZE.x - 4.0)
	y = clamp(y, 4.0, viewport_size.y - PREVIEW_SIZE.y - 4.0)
	global_position = Vector2(x, y)
