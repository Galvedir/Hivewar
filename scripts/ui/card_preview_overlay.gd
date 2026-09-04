class_name CardPreviewOverlay
extends Control
## Shared "hover to inspect" popup: base card widgets show only artwork plus
## name/cost/ATK-DEF decorations — no rules text — so this is where the
## full card gets shown on hover. The actual card visual (art, name/cost,
## rules-text box, ATK/DEF badge) is EnlargedCardView; this wrapper only
## adds the popup behavior around it — floating position independent of
## layout, shown/hidden on hover, clamped on-screen.
##
## `top_level` is set so this popup's position is independent of whatever
## Container it happens to be parented under (a GridContainer/
## ScrollContainer would otherwise fight a manually-set global_position
## every layout pass). One instance is built per screen (Collection, Deck
## Builder, the match view) and reused for every card widget on that screen.

const GAP := 12.0

var _view: EnlargedCardView

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 100
	visible = false
	_view = EnlargedCardView.new()
	add_child(_view)
	custom_minimum_size = EnlargedCardView.SIZE
	size = EnlargedCardView.SIZE
	LayoutUtil.fill_parent(_view)

## Shows the preview near `anchor_rect` (the hovered widget's global rect),
## clamped to stay fully on-screen.
func show_for(card_data: CardData, tex: Texture2D, cost: int, bbcode_text: String, badge_text: String, anchor_rect: Rect2) -> void:
	_view.set_content(card_data, tex, cost, bbcode_text, badge_text)
	_position_near(anchor_rect)
	move_to_front()
	visible = true

func hide_preview() -> void:
	visible = false
	_view.stop_animation()

func _position_near(anchor_rect: Rect2) -> void:
	var viewport_size := get_viewport_rect().size
	var view_size := EnlargedCardView.SIZE
	var x := anchor_rect.position.x + anchor_rect.size.x * 0.5 - view_size.x * 0.5
	var y := anchor_rect.position.y - view_size.y - GAP
	if y < 0.0:
		y = anchor_rect.position.y + anchor_rect.size.y + GAP
	x = clamp(x, 4.0, viewport_size.x - view_size.x - 4.0)
	y = clamp(y, 4.0, viewport_size.y - view_size.y - 4.0)
	global_position = Vector2(x, y)
