class_name ButtonStyleUtil
extends RefCounted
## Shared helper for applying real per-state art to a Button (§ user
## request — the main menu, general nav chrome, deck builder, and match HUD
## button sets all follow the same enabled/hover/pressed/disabled folder
## convention, and now span several separate UI scripts). Fails safe per
## state: no enabled art at all leaves the button as Godot's plain default
## (falls back to `fallback_text`); a missing pressed texture reuses hover
## (looks like "still hovered, now pushed in" without needing a dedicated
## asset — used by main_menu/ and deck_builder/, neither of which has a
## pressed/ folder yet); a missing disabled texture falls back to the
## enabled art darkened.

const GENERAL_BUTTON_ART_DIR := "res://art/ui/buttons/general/"
const GENERAL_BUTTON_WIDTH := 130.0

const MATCH_BUTTON_ART_DIR := "res://art/ui/buttons/match/"
const MATCH_BUTTON_WIDTH := 160.0

const DECK_BUILDER_BUTTON_ART_DIR := "res://art/ui/buttons/deck_builder/"
const DECK_BUILDER_BUTTON_WIDTH := 160.0

static func style_art_button(btn: Button, base_dir: String, art_name: String, target_width: float, fallback_text: String) -> void:
	var enabled_path := base_dir + "enabled/" + art_name + ".png"
	if not ResourceLoader.exists(enabled_path):
		btn.text = fallback_text # asset missing — keep the plain labeled button rather than going blank
		return
	var enabled_tex: Texture2D = load(enabled_path)
	btn.text = "" # the art already has the label baked in
	btn.custom_minimum_size = Vector2(target_width, target_width * enabled_tex.get_height() / enabled_tex.get_width())
	# Without this, a VBoxContainer/HBoxContainer parent stretches the button
	# to fill its own width/height (Godot's default FILL size flags), which
	# distorts a fixed-aspect-ratio texture — this pins the button to exactly
	# its art's own size regardless of which container it ends up in.
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var enabled_style := _stylebox(enabled_tex)
	btn.add_theme_stylebox_override("normal", enabled_style)
	btn.add_theme_stylebox_override("focus", enabled_style)

	var hover_path := base_dir + "hover/" + art_name + ".png"
	var hover_tex: Texture2D = load(hover_path) if ResourceLoader.exists(hover_path) else enabled_tex
	var hover_style := _stylebox(hover_tex)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_path := base_dir + "pressed/" + art_name + ".png"
	var pressed_tex: Texture2D = load(pressed_path) if ResourceLoader.exists(pressed_path) else hover_tex
	btn.add_theme_stylebox_override("pressed", _stylebox(pressed_tex))

	var disabled_path := base_dir + "disabled/" + art_name + ".png"
	if ResourceLoader.exists(disabled_path):
		btn.add_theme_stylebox_override("disabled", _stylebox(load(disabled_path)))
	else:
		var placeholder_disabled := _stylebox(enabled_tex)
		placeholder_disabled.modulate_color = Color(0.45, 0.45, 0.45)
		btn.add_theme_stylebox_override("disabled", placeholder_disabled)

static func _stylebox(tex: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = tex
	return style
