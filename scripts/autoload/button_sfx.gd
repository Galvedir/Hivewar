extends Node
## Autoload (§ user request: "every button in the game" should play a click
## sound on press and a hover sound on mouse-enter, unified into ONE sound
## each instead of the main menu's earlier separate click sound). Centralized
## here instead of wiring `.pressed`/`mouse_entered` at every one of the many
## individual button-creation call sites across main_ui.gd, deck_builder_ui.gd,
## collection_ui.gd, rules_screen_ui.gd, and multiplayer_hub_ui.gd — this polls
## the viewport's own hover tracking and listens for the raw mouse-release
## event instead, so it automatically covers every Button (and BaseButton
## subclass — OptionButton, CheckBox, card widgets, etc.) anywhere in the
## scene tree with zero per-button wiring, present or future.
##
## Hover explicitly checks `.disabled` (§ user clarification): "if it is
## disabled then it would not be hovered and therefore no sound." The click
## listener checks it too, defensively, even though a disabled button
## shouldn't be reachable as the click target in the first place.

const CLICK_SFX_PATH := "res://music/button_pressed.mp3"
const HOVER_SFX_PATH := "res://music/button_hover.mp3"

var _click_player: AudioStreamPlayer
var _hover_player: AudioStreamPlayer
var _last_hovered: Control

func _ready() -> void:
	if ResourceLoader.exists(CLICK_SFX_PATH):
		_click_player = AudioStreamPlayer.new()
		_click_player.stream = load(CLICK_SFX_PATH)
		add_child(_click_player)
	if ResourceLoader.exists(HOVER_SFX_PATH):
		_hover_player = AudioStreamPlayer.new()
		_hover_player.stream = load(HOVER_SFX_PATH)
		add_child(_hover_player)

func _input(event: InputEvent) -> void:
	if _click_player == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var hovered := _hovered_button()
		if hovered != null and not hovered.disabled:
			_click_player.play()

func _process(_delta: float) -> void:
	if _hover_player == null:
		return
	var hovered := _hovered_button()
	if hovered != _last_hovered:
		if hovered != null and not hovered.disabled:
			_hover_player.play()
		_last_hovered = hovered

func _hovered_button() -> BaseButton:
	var vp := get_viewport()
	if vp == null:
		return null
	var control := vp.gui_get_hovered_control()
	return control as BaseButton

## Lets the SFX volume slider (Options screen) apply here too, same as
## every other AudioStreamPlayer in the game.
func set_volume_db(db: float) -> void:
	if _click_player != null:
		_click_player.volume_db = db
	if _hover_player != null:
		_hover_player.volume_db = db
