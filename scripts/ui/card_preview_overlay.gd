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
const LEADER_ANIM_FPS := 8.0
const TEXT_BOX_MARGIN := 8.0 # gap between the rules-text area's own edges and the black box (§ user request — a clear border so the background shows through, instead of the box filling the whole bottom portion)
const TEXT_INNER_PADDING := 4.0 # gap between the black box's edges and the text itself, so words don't sit flush against it
const TEXT_MAX_FONT_SIZE := 13
const TEXT_MIN_FONT_SIZE := 8

var _frame_rect: TextureRect
var _art: TextureRect
var _art_area: Control
var _anim_rect: TextureRect
var _anim_atlas: AtlasTexture
var _anim_timer: Timer
var _anim_frame := 0
var _anim_cols := 4 # this Leader's own grid size (not every animation is 4x4 — see CardDatabase._parse_anim_grid), set fresh each _start_leader_animation
var _anim_rows := 4
var _anim_texture_cache: Dictionary = {} # path -> Texture2D
var _name_label: Label
var _cost_circle: Panel
var _cost_label: Label
var _text_area: Control
var _text_box: Control
var _text: RichTextLabel
var _badge_box: Panel
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

	# Kingdom card-frame background (§ user request): spans the whole card,
	# behind both the art area and the rules-text area below it — visible
	# in the rules-text area always (nothing else is drawn there but the
	# text itself), and in the art area only where/if the portrait doesn't
	# fully cover it. Hidden entirely for a Kingdom with no frame image yet.
	_frame_rect = TextureRect.new()
	_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_frame_rect.visible = false
	LayoutUtil.fill_parent(_frame_rect)
	add_child(_frame_rect)

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

	# Leader animation (§ user request): a 4x4 sprite sheet that plays once
	# over the portrait then disappears — same play-once pattern as the
	# main menu's original animated overlay. Sits above the static portrait
	# but below the name/cost decorations, so those stay legible throughout.
	_anim_rect = TextureRect.new()
	_anim_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_anim_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_anim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anim_rect.visible = false
	LayoutUtil.fill_parent(_anim_rect)
	_art_area.add_child(_anim_rect)

	_anim_timer = Timer.new()
	_anim_timer.wait_time = 1.0 / LEADER_ANIM_FPS
	_anim_timer.timeout.connect(_on_anim_tick)
	add_child(_anim_timer)

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

	# The black box itself (§ user request): inset from _text_area's own
	# edges by TEXT_BOX_MARGIN on every side, so a thin strip of whatever's
	# behind (the Kingdom frame/portrait) shows through around it as a
	# clear border, instead of the box filling the whole bottom portion
	# edge to edge. Clips to its own (smaller) bounds so text can't spill
	# past it — combined with the font-size auto-fit in show_for, this is
	# what keeps "make sure it all fits in the box" true even for an
	# unusually verbose card, since the popup can't actually be scrolled by
	# the user (it hides the instant the mouse leaves the small base widget
	# that triggered it, long before it could ever reach this popup).
	_text_box = Control.new()
	_text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_box.anchor_right = 1.0
	_text_box.anchor_bottom = 1.0
	_text_box.offset_left = TEXT_BOX_MARGIN
	_text_box.offset_top = TEXT_BOX_MARGIN
	_text_box.offset_right = -TEXT_BOX_MARGIN
	_text_box.offset_bottom = -TEXT_BOX_MARGIN
	_text_box.clip_contents = true
	_text_area.add_child(_text_box)

	# Mostly-transparent black panel behind the rules text (§ user request),
	# so white text stays legible regardless of what the Kingdom frame or
	# portrait looks like behind it. A plain ColorRect filling the box,
	# added before _text so it draws behind it.
	var text_bg := ColorRect.new()
	text_bg.color = CardRenderUtil.DARK_BOX_COLOR
	text_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(text_bg)
	_text_box.add_child(text_bg)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.add_theme_color_override("default_color", Color.WHITE)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.anchor_right = 1.0
	_text.anchor_bottom = 1.0
	_text.offset_left = TEXT_INNER_PADDING
	_text.offset_top = TEXT_INNER_PADDING
	_text.offset_right = -TEXT_INNER_PADDING
	_text.offset_bottom = -TEXT_INNER_PADDING
	_text_box.add_child(_text)

	# ATK/DEF badge (§ user request): its own mostly-transparent black box,
	# on top of the rules-text panel, anchored within the rules-text area
	# only (not the whole card). Hidden entirely — box included — whenever
	# badge_text is empty (Ability/Gear/Hive cards; see show_for).
	_badge_box = Panel.new()
	_badge_box.add_theme_stylebox_override("panel", CardRenderUtil.make_dark_box_style())
	_badge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_box.anchor_left = 1.0
	_badge_box.anchor_top = 1.0
	_badge_box.anchor_right = 1.0
	_badge_box.anchor_bottom = 1.0
	_badge_box.offset_left = -76
	_badge_box.offset_top = -30
	_badge_box.offset_right = -8
	_badge_box.offset_bottom = -6
	_text_area.add_child(_badge_box)

	_badge = Label.new()
	_badge.add_theme_color_override("font_color", Color.WHITE)
	_badge.add_theme_font_size_override("font_size", 20)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(_badge)
	_badge_box.add_child(_badge)

## Shrinks the rules-text font just enough for a verbose card's text to
## actually fit within the box (§ user request), rather than leaning on
## clip_contents to silently cut it off. format_rules_text/card_full_text
## already hard-wrap every clause at a fixed character width, so the
## number of newline-separated lines is fixed regardless of font size —
## only the vertical space each line needs changes — so just counting
## them is enough to pick a size that fits without ever having to render
## the text first to measure it.
func _fit_font_size(bbcode_text: String) -> int:
	var line_count := bbcode_text.count("\n") + 1
	var box_height: float = (PREVIEW_SIZE.y - ART_HEIGHT) - 2.0 * TEXT_BOX_MARGIN - 2.0 * TEXT_INNER_PADDING
	for size in range(TEXT_MAX_FONT_SIZE, TEXT_MIN_FONT_SIZE - 1, -1):
		if line_count * size * 1.25 <= box_height:
			return size
	return TEXT_MIN_FONT_SIZE

## Shows the preview near `anchor_rect` (the hovered widget's global rect),
## clamped to stay fully on-screen. `card_data` supplies the name/cost
## decorations directly (Leaders hide the cost circle, same as the base
## card face); `bbcode_text`/`badge_text` are still caller-supplied since
## they differ between printed CardData and a live CardInstance's current
## stats/status.
func show_for(card_data: CardData, tex: Texture2D, cost: int, bbcode_text: String, badge_text: String, anchor_rect: Rect2) -> void:
	# Leaders skip the Kingdom-frame background entirely (§ user request —
	# "Leaders should use the full card art, not the background art"): a
	# Leader without a personal portrait just shows no art here rather than
	# borrowing the shared, non-Leader-specific Kingdom background.
	var frame_tex: Texture2D = null
	if not (card_data is LeaderData):
		frame_tex = CardDatabase.get_kingdom_frame_texture(card_data)
	_frame_rect.texture = frame_tex
	_frame_rect.visible = frame_tex != null
	_art.texture = tex
	_art.visible = tex != null
	_name_label.text = card_data.card_name
	_cost_circle.visible = true
	_cost_label.text = str(CardRenderUtil.badge_value(card_data, cost))
	_text.add_theme_font_size_override("normal_font_size", _fit_font_size(bbcode_text))
	_text.text = bbcode_text
	_badge.text = badge_text
	_badge_box.visible = badge_text != ""
	_start_leader_animation(card_data)
	_position_near(anchor_rect)
	move_to_front()
	visible = true

func hide_preview() -> void:
	visible = false
	_anim_timer.stop()

## Plays a Leader's sprite-sheet animation once over its portrait (§ user
## request), then hides itself when the last frame's played — the same
## play-once-and-disappear pattern the main menu's overlay originally
## used. Grid size comes from the Leader's own animation_cols/
## animation_rows (not every sheet is 4x4 — see CardDatabase.
## _parse_anim_grid). Resets/no-ops (clearing any previous animation) for
## anything that isn't a Leader with an animation sprite matched to it.
func _start_leader_animation(card_data: CardData) -> void:
	_anim_timer.stop()
	_anim_rect.visible = false
	if not (card_data is LeaderData):
		return
	var leader := card_data as LeaderData
	var path: String = leader.animation_sprite_path
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_anim_cols = leader.animation_cols
	_anim_rows = leader.animation_rows
	var sheet := _load_anim_texture(path)
	var frame_w := sheet.get_width() / _anim_cols
	var frame_h := sheet.get_height() / _anim_rows
	_anim_atlas = AtlasTexture.new()
	_anim_atlas.atlas = sheet
	_anim_atlas.region = Rect2(0, 0, frame_w, frame_h)
	_anim_rect.texture = _anim_atlas
	_anim_frame = 0
	_anim_rect.visible = true
	_anim_timer.start()

func _load_anim_texture(path: String) -> Texture2D:
	if not _anim_texture_cache.has(path):
		_anim_texture_cache[path] = load(path)
	return _anim_texture_cache[path]

func _on_anim_tick() -> void:
	var total_frames := _anim_cols * _anim_rows
	_anim_frame += 1
	if _anim_frame >= total_frames:
		_anim_timer.stop()
		_anim_rect.visible = false
		return
	var frame_w := _anim_atlas.atlas.get_width() / _anim_cols
	var frame_h := _anim_atlas.atlas.get_height() / _anim_rows
	var col := _anim_frame % _anim_cols
	var row := _anim_frame / _anim_cols
	_anim_atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)

func _position_near(anchor_rect: Rect2) -> void:
	var viewport_size := get_viewport_rect().size
	var x := anchor_rect.position.x + anchor_rect.size.x * 0.5 - PREVIEW_SIZE.x * 0.5
	var y := anchor_rect.position.y - PREVIEW_SIZE.y - GAP
	if y < 0.0:
		y = anchor_rect.position.y + anchor_rect.size.y + GAP
	x = clamp(x, 4.0, viewport_size.x - PREVIEW_SIZE.x - 4.0)
	y = clamp(y, 4.0, viewport_size.y - PREVIEW_SIZE.y - 4.0)
	global_position = Vector2(x, y)
