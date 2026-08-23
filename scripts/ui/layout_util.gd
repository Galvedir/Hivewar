class_name LayoutUtil
extends RefCounted
## Control.set_anchors_preset(PRESET_FULL_RECT) defaults to
## resize_mode = PRESET_MODE_MINSIZE, which sizes the control to its own
## minimum size rather than stretching it to the parent's rect — a control
## with no inherent minimum size (or one that only coincidentally looks
## full-size because its content happens to be that big) ends up stuck at
## a near-zero size. Setting all four anchors and all four offsets
## explicitly is the only way to guarantee true edge-to-edge stretching
## that also tracks the parent's size if it changes later (e.g. window
## resize).

static func fill_parent(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
