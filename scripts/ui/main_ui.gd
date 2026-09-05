extends Control
## Minimal functional Phase 1 UI (§16 step 8): deck-select screen, then a
## hand/board/Leader match view wired straight to TurnManager — the same
## API AIPlayer drives. Built programmatically (no hand-authored .tscn
## layout) so it's easy to keep in sync with the engine; swap for real
## scenes/art in a later pass without touching TurnManager/GameState.

const HUMAN := 0
const AI := 1

## Battlefield layout (§ user request — an exact percentage spec, mirrored
## for the opponent): each side's own area splits vertically into a play
## row (leader/board/hive, TOP_RATIO share) and a HUD row (deck+discard/
## hand/action-buttons, HUD_RATIO share); BoxContainer stretch ratios (not
## fixed pixel sizes — the earlier fixed-size Leader panel is exactly what
## caused the last layout bug: it didn't adapt to the actual window size)
## drive every zone below, so this is genuinely responsive instead of
## calibrated-and-hoped for one particular window size.
const TOP_RATIO := 6.0
const HUD_RATIO := 4.0
## Player HUD row, left to right: deck+discard / hand / action buttons.
const HUD_PILES_RATIO := 2.0
const HUD_HAND_RATIO := 6.0
const HUD_ACTIONS_RATIO := 2.0
## Player play row, left to right: Leader / play area / card preview.
const PLAY_LEADER_RATIO := 2.0
const PLAY_BOARD_RATIO := 6.0
const PLAY_PREVIEW_RATIO := 2.0
## Play area itself, left to right: creatures / Hive (non-creature
## permanents that stick to the field) — hidden entirely, freeing its
## share back to the creature zone, whenever Hive is empty.
const BOARD_CREATURES_RATIO := 8.0
const BOARD_HIVE_RATIO := 2.0
## The opponent's HUD/play rows are mirrored on BOTH axes (§ user request:
## "as though I am sitting across from them") — not just top-to-bottom but
## left-to-right too — and drop the preview/action-button columns entirely
## (§ user request — those only ever matter for the player's own
## interaction, even in future multiplayer), with hand/play area
## absorbing that freed share instead of leaving it blank.
const OPP_HUD_HAND_RATIO := HUD_HAND_RATIO + HUD_ACTIONS_RATIO
const OPP_HUD_PILES_RATIO := HUD_PILES_RATIO
const OPP_PLAY_BOARD_RATIO := PLAY_BOARD_RATIO + PLAY_PREVIEW_RATIO
const OPP_PLAY_LEADER_RATIO := PLAY_LEADER_RATIO

## Creature card sizing (§ user request: "current sizes... seems ok, we can
## start to shrink them if we get too many... so they can all still be
## shown"): natural size used whenever everything fits; shrinks toward the
## floor as more creatures need to fit in the same space, then (below the
## floor) falls back to the board's existing horizontal scrolling instead
## of shrinking further.
const CREATURE_CARD_NATURAL_SIZE := Vector2(150, 150)
const CREATURE_CARD_MIN_SIZE := Vector2(80, 80)
const CREATURE_ROW_SPACING := 6.0

## Fallback sizes used only before the real layout has ever run a pass
## (so an actual Control's .size is still zero) — every zone otherwise
## sizes itself from its own real, already-laid-out dimensions.
const FALLBACK_HAND_ZONE_SIZE := Vector2(900, 190)
const FALLBACK_LEADER_ZONE_SIZE := Vector2(180, 260)
const FALLBACK_PILE_SIZE := Vector2(60, 84)
const HAND_CARD_ASPECT := 0.72 # width = height * this, matching a real card's proportions
const HAND_PLAY_LIFT_THRESHOLD := 90.0 # how far above the hand tray's own top edge a card must be dragged before releasing it counts as playing it instead of reordering — "pick up cards and place them in the play area to play them"

## Larva pips (§ user request): a floating column per side, positioned
## beside that side's Leader/discard pile (see _build_larva_overlay_column
## and _refresh_larva_pips), showing how much Larva is available to spend
## right now — always at least TurnManager.MAX_LARVA_CAP (10) of them shown
## empty, filling in as many as the player currently has available (not the
## printed max — the *available*, i.e. unspent, amount, which drains toward
## empty over the turn as it's spent and refills to the new max at the
## start of the next one), and growing past 10 only if some future effect
## ever pushes max Larva higher than that (nothing does yet). Uses the
## dedicated hive-cell artwork if present, falling back to a plain drawn
## circle (same fail-safe pattern as every other optional art asset in this
## file) if not.
const LARVA_PIP_SIZE := Vector2(96, 96)
## Gap between the pip column and the Leader zone it's positioned beside.
const LARVA_COLUMN_GAP := 8.0
## The column's own BoxContainer separation is computed fresh each refresh
## to exactly fit however many pips there are into that side's available
## height — the vertical span between its Leader zone and discard pile (see
## _refresh_larva_pips) — these just bound how far that computation is
## allowed to go: never spread out further apart than LARVA_PIP_SEPARATION_MAX
## (§ user request: "make them much closer together" — keep them at least
## that close even when there's room to spare) and never overlap tighter
## than LARVA_PIP_SEPARATION_MIN (so a very large pip count still reads as
## separate icons instead of a single blob — real overflow past that floor
## is what clip_contents is for).
const LARVA_PIP_SEPARATION_MAX := -30.0
const LARVA_PIP_SEPARATION_MIN := -72.0
const LARVA_PIP_EMPTY_PATH := "res://art/ui/panels/Empty_Larva.png"
const LARVA_PIP_FILLED_PATH := "res://art/ui/panels/Filled_Larva.png"

## Effect ids that need a chosen creature target rather than an auto-pick,
## and which side of the board is legal to click for each (§ user request:
## targeted effects should let the player choose, not silently pick for
## them). AIPlayer is unaffected — it never supplies target_instance_id, so
## EffectResolver's auto-pick heuristic still drives the bot.
const TARGETING_EFFECT_SIDES := {
	"buff_friendly": "friendly",
	"damage_creature": "enemy",
	"bounce_creature": "enemy",
	"shuffle_into_library": "enemy",
	"grant_decay_to_enemy": "enemy",
	"destroy_creature": "enemy",
	"heal_creature_full": "friendly",
	"flip_ambush_instant": "friendly",
	"buff_friendly_per_larva_spent": "friendly",
	"destroy_face_down_creature": "enemy",
}

## Effects that need more than just "friendly vs enemy" to pick a legal
## target (§ user request — Caterpillar Searcher's "you may destroy target
## face-down creature" only makes sense against a face-down creature; "you
## may" falls out naturally — if the enemy has none, this stays "" for
## every candidate and the whole targeting prompt never engages, same as
## how every other targeted effect here just no-ops with an empty pool).
const TARGETING_EXTRA_FILTER := {
	"destroy_face_down_creature": "face_down",
}

func _passes_extra_filter(effect_id: String, c: CardInstance) -> bool:
	match TARGETING_EXTRA_FILTER.get(effect_id, ""):
		"face_down":
			return c.is_face_down
		_:
			return true

var _main_menu: Control # plain Control wrapper (not a layout container) so a full-screen background image can sit behind the actual VBox content as a separate layer
var _main_menu_status_label: Label
var _practice_screen: Control
var _saved_decks_menu_box: VBoxContainer
var _options_screen: Control
var _deck_builder: DeckBuilderUI
var _collection: CollectionUI
var _rules_screen: RulesScreenUI
var _rules_return_target: Control # whichever screen was open before Rules — main menu, Practice, or Deck Builder
var _deck_builder_return_target: Control # whichever screen was open before Deck Builder — main menu or Practice
var _collection_return_target: Control # whichever screen was open before Collection — main menu or Practice
var _match_view: HBoxContainer
var _match_bg: ColorRect
var _battlefield_root: VBoxContainer
var _log_panel: PanelContainer
var _log_display: RichTextLabel
var _pause_menu: PanelContainer
var _opponent_board: HBoxContainer
var _opponent_hive: HBoxContainer
var _opponent_board_zone: Control # the play-area's own zone Control, read for its real width when sizing creature cards
var _opponent_hand: Control
var _opponent_larva_row: VBoxContainer
var _opponent_leader_btn: Button
var _opponent_leader_view: EnlargedCardView
var _opponent_leader_zone: Control # read for its real position when placing the Larva column beside it — see _refresh_larva_pips
var _opponent_deck_pile: Control
var _opponent_discard_btn: Button
var _player_board: HBoxContainer
var _player_hive: HBoxContainer
var _player_board_zone: Control
var _player_hand: Control
var _player_larva_row: VBoxContainer
var _player_leader_btn: Button
var _player_leader_view: EnlargedCardView
var _player_leader_zone: Control # the button+view's shared parent, read for its real size when fitting the view — see _refresh_leader_panel
var _player_deck_pile: Control
var _player_discard_btn: Button
var _discard_popup: PanelContainer
var _discard_popup_box: VBoxContainer
var _status_label: Label
var _hero_power_btn: Button
var _ultimate_btn: Button
var _end_turn_btn: Button
var _cancel_btn: Button
var _attack_leader_btn: Button
var _block_popup: PanelContainer
var _block_popup_box: VBoxContainer
var _attack_confirm_popup: PanelContainer
var _attack_confirm_label: Label
var _x_cost_popup: PanelContainer
var _x_cost_spinbox: SpinBox
var _legend_popup: PanelContainer
var _legend_popup_box: VBoxContainer
var _game_over_popup: PanelContainer
var _game_over_label: Label
## The card-preview panel (§ user request: "instead of showing it near the
## card you are hovering over") — docked in a fixed region of the player's
## own play row (see PLAY_PREVIEW_RATIO) instead of floating near whatever
## was hovered. Every hoverable card (either side's) routes here now, so
## CardPreviewOverlay's floating-popup behavior is unused in the match view
## (Collection/Deck Builder still use it as before — this is match-view-only).
var _preview_dock: Control
var _preview_view: EnlargedCardView

## § user request: clicking the Leader (when a Hero Power/Ultimate is
## available) opens both as buttons in the action zone (only the actually-
## usable one clickable) plus a Cancel there to back out — see
## _on_leader_clicked/_on_cancel_pressed.
var _leader_menu_open := false
var _selected_hand_index := -1
var _selected_attacker_id := -1
var _pending_attack_target = null # null / "leader" / CardInstance — awaiting the attack-confirm popup
var _pending_ultimate_larva_spend := -1 # set while an X-cost Ultimate's amount has been chosen and is awaiting a target (or is ready to fire if untargeted)
var _pending_target_side := "" # "" / "friendly" / "enemy" — set while awaiting a click to target a hand card or Hero Power/Ultimate
var _pending_target_effect_id := "" # the specific effect_id being targeted, if any extra legality filter applies (see TARGETING_EXTRA_FILTER)
var _pending_power_kind := "" # "" / "hero" / "ultimate"
var _busy := false # true while the AI or an awaited attack is resolving

## Hand drag state (§ user request: "pick up cards and place them in the
## play area to play them" — dragging is the only way to play a card now).
## _hand_display_order is a purely cosmetic ordering of the human's hand,
## independent of PlayerState.hand's actual array order, so a manual
## drag-reorder (§ user request) sticks between refreshes instead of
## resetting to hand[] order every time — see _sync_hand_display_order.
var _hand_display_order: Array[int] = []
var _drag_btn: Control = null
var _drag_instance_id := -1
var _drag_can_play := false
var _drag_grab_offset := Vector2.ZERO

## Progressive-reveal state for an in-progress AI turn replay (§ user
## request — see _process). While active, an opponent board/hive card not
## yet in this set is hidden entirely, so newly-played cards only appear
## once their own replay step reveals them instead of all showing up at once.
var _ai_reveal_active := false
var _ai_reveal_set: Dictionary = {}

## AI-turn replay queue, drained one action per AI_ACTION_PAUSE seconds by
## _process — see its own comment for why this is plain per-frame polling
## instead of a chain of awaits.
var _ai_replay_queue: Array[Dictionary] = []
var _ai_replay_pause_timer := 0.0

var _menu_music_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _menu_anim_rect: TextureRect
var _menu_anim_atlas: AtlasTexture
var _menu_anim_timer: Timer
var _menu_anim_frame := 0

## Options (§ user request): basic sound/graphics settings, persisted to
## user://settings.cfg so they survive a restart.
const SETTINGS_PATH := "user://settings.cfg"
var _music_volume := 1.0 # linear 0.0-1.0
var _sfx_volume := 1.0
var _fullscreen := false
var _music_volume_slider: HSlider
var _sfx_volume_slider: HSlider
var _fullscreen_check: CheckBox

## Practice mode (§ user request): the player picks BOTH decks before a
## match starts, instead of the AI's deck being randomized.
var _practice_your_deck_id := ""
var _practice_opponent_deck_id := ""
var _practice_choosing_side := "your" # "your" / "opponent"
var _practice_your_label: Label
var _practice_opponent_label: Label
var _practice_start_btn: Button
var _practice_choose_your_btn: Button
var _practice_choose_opp_btn: Button

func _ready() -> void:
	LayoutUtil.fill_parent(self)
	_load_settings()
	_build_main_menu()
	_build_practice_screen()
	_build_options_screen()
	_build_match_view()
	_match_view.visible = false
	_match_bg.visible = false

	# § note: the match view no longer uses a floating CardPreviewOverlay —
	# every hoverable card there routes into the docked preview panel
	# instead (see _preview_dock/_preview_view, built in _build_play_row).
	# CardPreviewOverlay itself is still used by Collection/Deck Builder.

	_deck_builder = DeckBuilderUI.new()
	_deck_builder.visible = false
	_deck_builder.closed.connect(_on_deck_builder_closed)
	add_child(_deck_builder)

	_collection = CollectionUI.new()
	_collection.visible = false
	_collection.closed.connect(_on_collection_closed)
	add_child(_collection)

	_rules_screen = RulesScreenUI.new()
	_rules_screen.visible = false
	_rules_screen.closed.connect(_on_rules_closed)
	add_child(_rules_screen)
	_deck_builder.open_rules.connect(_on_open_rules.bind(_deck_builder))

	TurnManager.turn_started.connect(_on_turn_started)
	TurnManager.block_decision_requested.connect(_on_block_requested)
	TurnManager.legend_rule_decision_requested.connect(_on_legend_rule_requested)
	GameState.game_ended.connect(_on_game_ended)
	GameLog.entry_added.connect(_on_log_entry)

	_setup_menu_audio()
	_apply_audio_settings()
	_apply_graphics_settings()
	_show_studio_splash()

## --- Options / settings persistence -----------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_music_volume = cfg.get_value("audio", "music_volume", 1.0)
		_sfx_volume = cfg.get_value("audio", "sfx_volume", 1.0)
		_fullscreen = cfg.get_value("graphics", "fullscreen", false)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", _music_volume)
	cfg.set_value("audio", "sfx_volume", _sfx_volume)
	cfg.set_value("graphics", "fullscreen", _fullscreen)
	cfg.save(SETTINGS_PATH)

func _linear_to_volume_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)

func _apply_audio_settings() -> void:
	if _menu_music_player != null:
		_menu_music_player.volume_db = _linear_to_volume_db(_music_volume)
	if _sfx_player != null:
		_sfx_player.volume_db = _linear_to_volume_db(_sfx_volume)
	# The Collection and Deck Builder screens' music (§ user request — it
	# wasn't respecting the Music Volume slider at all, since neither
	# screen's player ever had its volume_db touched) each use their own
	# AudioStreamPlayer, so they need to be kept in sync here too, same as
	# the ambient track above.
	if _collection != null:
		_collection.set_music_volume_db(_linear_to_volume_db(_music_volume))
	if _deck_builder != null:
		_deck_builder.set_music_volume_db(_linear_to_volume_db(_music_volume))

func _apply_graphics_settings() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _build_options_screen() -> void:
	_options_screen = Control.new()
	LayoutUtil.fill_parent(_options_screen)
	_options_screen.visible = false
	add_child(_options_screen)

	var box := VBoxContainer.new()
	LayoutUtil.fill_parent(box)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	_options_screen.add_child(box)

	var title := Label.new()
	title.text = "Options"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var music_row := HBoxContainer.new()
	music_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(music_row)
	var music_label := Label.new()
	music_label.text = "Music Volume"
	music_label.custom_minimum_size = Vector2(140, 0)
	music_row.add_child(music_label)
	_music_volume_slider = HSlider.new()
	_music_volume_slider.min_value = 0
	_music_volume_slider.max_value = 100
	_music_volume_slider.step = 1
	_music_volume_slider.value = _music_volume * 100.0
	_music_volume_slider.custom_minimum_size = Vector2(220, 0)
	_music_volume_slider.value_changed.connect(_on_music_volume_changed)
	music_row.add_child(_music_volume_slider)

	var sfx_row := HBoxContainer.new()
	sfx_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(sfx_row)
	var sfx_label := Label.new()
	sfx_label.text = "SFX Volume"
	sfx_label.custom_minimum_size = Vector2(140, 0)
	sfx_row.add_child(sfx_label)
	_sfx_volume_slider = HSlider.new()
	_sfx_volume_slider.min_value = 0
	_sfx_volume_slider.max_value = 100
	_sfx_volume_slider.step = 1
	_sfx_volume_slider.value = _sfx_volume * 100.0
	_sfx_volume_slider.custom_minimum_size = Vector2(220, 0)
	_sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	sfx_row.add_child(_sfx_volume_slider)

	var fullscreen_row := HBoxContainer.new()
	fullscreen_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(fullscreen_row)
	_fullscreen_check = CheckBox.new()
	_fullscreen_check.text = "Fullscreen"
	_fullscreen_check.button_pressed = _fullscreen
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	fullscreen_row.add_child(_fullscreen_check)

	var back_btn := Button.new()
	back_btn.text = "< Back"
	back_btn.pressed.connect(_on_options_back_pressed)
	box.add_child(back_btn)

func _on_music_volume_changed(value: float) -> void:
	_music_volume = value / 100.0
	_apply_audio_settings()
	_save_settings()

func _on_sfx_volume_changed(value: float) -> void:
	_sfx_volume = value / 100.0
	_apply_audio_settings()
	_save_settings()

func _on_fullscreen_toggled(pressed: bool) -> void:
	_fullscreen = pressed
	_apply_graphics_settings()
	_save_settings()

func _on_options_pressed() -> void:
	_set_main_menu_visible(false)
	_options_screen.visible = true

func _on_options_back_pressed() -> void:
	_options_screen.visible = false
	_set_main_menu_visible(true)

## --- Main menu ---------------------------------------------------------------

const LOGO_PATH := "res://art/branding/logo.png"
const SPLASH_PATH := "res://art/branding/title_screen.png"
const SPLASH_DURATION := 2.5
const MENU_MUSIC_PATH := "res://music/main_menu_music.mp3"
const BUTTON_CLICK_SFX_PATH := "res://music/button_press.mp3"
const LOADING_SPRITE_PATH := "res://art/branding/loading/loading-sprite.png"
const LOADING_SPRITE_COLS := 4
const LOADING_SPRITE_ROWS := 4
const LOADING_SPRITE_FPS := 8.0
const LOADING_SCREEN_DURATION := 1.0

## Studio/credits splash (§ user request) — a 6x6 sprite sheet, shown once
## at boot BEFORE the title splash, looping a few times to fill a few
## seconds before moving on.
const STUDIO_SPLASH_PATH := "res://art/branding/loading/studio_loading_sprite.png"
const STUDIO_SPLASH_COLS := 6
const STUDIO_SPLASH_ROWS := 6
const STUDIO_SPLASH_FPS := 15.0
const STUDIO_SPLASH_LOOPS := 2

## Main-menu-only audio (§ user request) — no general audio system yet,
## just background music that plays while the deck-select screen is the
## active screen, and a click SFX for its buttons. Both fail safe (no
## AudioStreamPlayer created at all) if the asset isn't present.
func _setup_menu_audio() -> void:
	if ResourceLoader.exists(MENU_MUSIC_PATH):
		_menu_music_player = AudioStreamPlayer.new()
		var stream: AudioStream = load(MENU_MUSIC_PATH)
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		_menu_music_player.stream = stream
		add_child(_menu_music_player)
		_menu_music_player.play()
	if ResourceLoader.exists(BUTTON_CLICK_SFX_PATH):
		_sfx_player = AudioStreamPlayer.new()
		_sfx_player.stream = load(BUTTON_CLICK_SFX_PATH)
		add_child(_sfx_player)

func _play_click_sfx() -> void:
	if _sfx_player != null:
		_sfx_player.play()

## Single source of truth for showing/hiding the top-level main menu —
## just its own visibility plus the bg animation overlay, which only ever
## lives on this screen. Music is no longer tied to this (§ user request:
## the ambient music should keep playing across the main menu, Practice
## deck-select, Deck Builder/Collection/Rules/Options, and the loading
## screen — it only actually stops once a match starts; see
## _stop_ambient_music/_resume_ambient_music).
func _set_main_menu_visible(visible_now: bool) -> void:
	_main_menu.visible = visible_now
	if visible_now:
		_start_menu_anim()
	elif _menu_anim_rect != null:
		_menu_anim_timer.stop()
		_menu_anim_rect.visible = false

func _stop_ambient_music() -> void:
	if _menu_music_player != null and _menu_music_player.playing:
		_menu_music_player.stop()

func _resume_ambient_music() -> void:
	if _menu_music_player != null and not _menu_music_player.playing:
		_menu_music_player.play()

## Restarts the main-menu overlay animation from frame 0 and starts it
## looping (§ user request — trying looping in place of the original
## play-once-then-hide behavior; see _on_menu_anim_tick) — no-ops if the
## asset isn't present.
func _start_menu_anim() -> void:
	if _menu_anim_rect == null:
		return
	_menu_anim_frame = 0
	var frame_w := _menu_anim_atlas.atlas.get_width() / MENU_ANIM_COLS
	var frame_h := _menu_anim_atlas.atlas.get_height() / MENU_ANIM_ROWS
	_menu_anim_atlas.region = Rect2(0, 0, frame_w, frame_h)
	_menu_anim_rect.visible = true
	_menu_anim_timer.start()

func _on_menu_anim_tick() -> void:
	# Looping (§ user request — trying it out in place of the original
	# play-once-then-hide behavior): wraps back to frame 0 instead of
	# stopping and hiding once every frame has played.
	var total_frames := MENU_ANIM_COLS * MENU_ANIM_ROWS
	_menu_anim_frame = (_menu_anim_frame + 1) % total_frames
	var frame_w := _menu_anim_atlas.atlas.get_width() / MENU_ANIM_COLS
	var frame_h := _menu_anim_atlas.atlas.get_height() / MENU_ANIM_ROWS
	var col := _menu_anim_frame % MENU_ANIM_COLS
	var row := _menu_anim_frame / MENU_ANIM_COLS
	_menu_anim_atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)

## Builds a small animated loading-spinner widget from a 4x4 sprite sheet
## (§ user request), cycling all 16 frames on a Timer. Returns null if the
## asset isn't present, same fail-safe pattern as the logo/splash/menu-bg.
func _make_loading_sprite(size: Vector2 = Vector2(80, 80)) -> Control:
	if not ResourceLoader.exists(LOADING_SPRITE_PATH):
		return null
	var sheet: Texture2D = load(LOADING_SPRITE_PATH)
	var frame_w := sheet.get_width() / LOADING_SPRITE_COLS
	var frame_h := sheet.get_height() / LOADING_SPRITE_ROWS
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, frame_w, frame_h)

	var rect := TextureRect.new()
	rect.texture = atlas
	rect.custom_minimum_size = size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame_index := [0] # array wrapper — lambdas capture outer locals by value, not reference
	var frame_timer := Timer.new()
	frame_timer.wait_time = 1.0 / LOADING_SPRITE_FPS
	frame_timer.autostart = true
	frame_timer.timeout.connect(func() -> void:
		var next: int = (int(frame_index[0]) + 1) % (LOADING_SPRITE_COLS * LOADING_SPRITE_ROWS)
		frame_index[0] = next
		var col: int = next % LOADING_SPRITE_COLS
		var row: int = next / LOADING_SPRITE_COLS
		atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h))
	rect.add_child(frame_timer)
	return rect

## Anchors `control` to the bottom-right corner of its parent, `size` big,
## with `margin` px of breathing room from both edges.
func _anchor_bottom_right(control: Control, size: Vector2, margin: float = 16.0) -> void:
	control.anchor_left = 1.0
	control.anchor_top = 1.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = -size.x - margin
	control.offset_top = -size.y - margin
	control.offset_right = -margin
	control.offset_bottom = -margin

## A studio/credits splash (§ user request) shown once at boot, BEFORE the
## title splash — loops its 6x6 animation a few times (STUDIO_SPLASH_LOOPS)
## to fill a few seconds, then hands off to _show_splash_screen. Skipped
## straight to that title splash if the art isn't present yet, same
## fail-safe pattern as every other optional branding asset here.
## Dismissible early by click/tap, matching the title splash right after it.
func _show_studio_splash() -> void:
	if not ResourceLoader.exists(STUDIO_SPLASH_PATH):
		_show_splash_screen()
		return
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	LayoutUtil.fill_parent(overlay)
	add_child(overlay)

	var sheet: Texture2D = load(STUDIO_SPLASH_PATH)
	var frame_w := sheet.get_width() / STUDIO_SPLASH_COLS
	var frame_h := sheet.get_height() / STUDIO_SPLASH_ROWS
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, frame_w, frame_h)

	var rect := TextureRect.new()
	rect.texture = atlas
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# § user request: "take up a pretty good portion of the screen, but
	# also be both vertically and horizontally centered" — an 80%-of-the-
	# viewport centered box (anchors, not a fixed pixel size) so it scales
	# sensibly across window sizes instead of being calibrated to one.
	rect.anchor_left = 0.1
	rect.anchor_top = 0.1
	rect.anchor_right = 0.9
	rect.anchor_bottom = 0.9
	overlay.add_child(rect)

	var total_frames := STUDIO_SPLASH_COLS * STUDIO_SPLASH_ROWS
	var frame_index := [0] # array wrapper — lambdas capture outer locals by value, not reference
	var loops_done := [0]
	var timer := Timer.new()
	timer.wait_time = 1.0 / STUDIO_SPLASH_FPS
	timer.autostart = true
	overlay.add_child(timer)

	var dismiss := func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
		_show_splash_screen()
	timer.timeout.connect(func() -> void:
		var next: int = (int(frame_index[0]) + 1) % total_frames
		if next == 0:
			loops_done[0] = int(loops_done[0]) + 1
			if int(loops_done[0]) >= STUDIO_SPLASH_LOOPS:
				dismiss.call()
				return
		frame_index[0] = next
		var col: int = next % STUDIO_SPLASH_COLS
		var row: int = next / STUDIO_SPLASH_COLS
		atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h))
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			dismiss.call()
	)

## A brief title-screen splash (§ user request) shown once at boot, layered
## on top of the deck-select menu that's already built underneath it, before
## the game becomes interactive. Dismisses itself after SPLASH_DURATION
## seconds, or immediately on click/tap. Skipped entirely if the art asset
## isn't present yet, matching _make_title's fallback-safe pattern for
## optional branding assets — a missing splash image should never block
## reaching the menu.
func _show_splash_screen() -> void:
	if not ResourceLoader.exists(SPLASH_PATH):
		_start_menu_anim() # no splash to wait for — the menu is already visible
		return
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	LayoutUtil.fill_parent(overlay)
	add_child(overlay)

	var image := TextureRect.new()
	image.texture = load(SPLASH_PATH)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LayoutUtil.fill_parent(image)
	overlay.add_child(image)

	var spinner := _make_loading_sprite()
	if spinner != null:
		_anchor_bottom_right(spinner, Vector2(80, 80))
		overlay.add_child(spinner)

	var dismiss := func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
		_start_menu_anim() # the menu is only actually visible from this moment on
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			dismiss.call()
	)
	get_tree().create_timer(SPLASH_DURATION).timeout.connect(dismiss)

## The main-menu title: the LARVA wordmark logo if it's present, else a
## plain-text fallback so a missing asset never breaks the menu.
func _make_title() -> Control:
	if ResourceLoader.exists(LOGO_PATH):
		var logo := TextureRect.new()
		logo.texture = load(LOGO_PATH)
		# TextureRect defaults to EXPAND_KEEP_SIZE (renders at the texture's
		# native pixel size, ignoring any box it's given) — IGNORE_SIZE is
		# what actually makes it respect custom_minimum_size, with
		# STRETCH_KEEP_ASPECT_CENTERED then preserving the image's aspect
		# ratio within that box instead of distorting it.
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(420, 180)
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return logo
	var title := Label.new()
	title.text = "LARVA"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title

const MENU_BG_PATH := "res://art/ui/backgrounds/main_menu_bg.png"
const MENU_ANIM_SPRITE_PATH := "res://art/ui/backgrounds/main_menu_anim_sprite.png"
const MENU_ANIM_COLS := 4
const MENU_ANIM_ROWS := 4
const MENU_ANIM_FPS := 8.0

func _build_main_menu() -> void:
	_main_menu = Control.new()
	LayoutUtil.fill_parent(_main_menu)
	add_child(_main_menu)

	# Background image (§ user request), added first so it renders behind
	# the actual menu content below — a plain Control (not a layout
	# container) is what makes it possible for the two to coexist as
	# separate full-rect layers instead of both being forced into a single
	# vertical stack. Fails safe (no background at all) if the art isn't
	# present, same pattern as the logo/splash.
	if ResourceLoader.exists(MENU_BG_PATH):
		var bg := TextureRect.new()
		bg.texture = load(MENU_BG_PATH)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		LayoutUtil.fill_parent(bg)
		_main_menu.add_child(bg)

	# Animated overlay (§ user request): same full-screen size as the
	# background, sits directly on top of it but still behind the actual
	# menu content (title/buttons/deck list) added below, so it never
	# blocks a click. Loops continuously while the main menu is shown
	# (see _start_menu_anim/_on_menu_anim_tick, called from
	# _set_main_menu_visible) and pauses+hides when the menu isn't. Deliberately
	# NOT started here: the title splash covers the whole screen for
	# SPLASH_DURATION (2.5s) immediately after this runs, so starting the
	# loop this early would just mean a few silent cycles behind the
	# splash before the player ever saw the menu. _show_splash_screen's
	# dismiss callback starts it instead, at the moment the menu actually
	# becomes visible.
	if ResourceLoader.exists(MENU_ANIM_SPRITE_PATH):
		var sheet: Texture2D = load(MENU_ANIM_SPRITE_PATH)
		var frame_w := sheet.get_width() / MENU_ANIM_COLS
		var frame_h := sheet.get_height() / MENU_ANIM_ROWS
		_menu_anim_atlas = AtlasTexture.new()
		_menu_anim_atlas.atlas = sheet
		_menu_anim_atlas.region = Rect2(0, 0, frame_w, frame_h)
		_menu_anim_rect = TextureRect.new()
		_menu_anim_rect.texture = _menu_anim_atlas
		_menu_anim_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_menu_anim_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_menu_anim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu_anim_rect.visible = false
		LayoutUtil.fill_parent(_menu_anim_rect)
		_main_menu.add_child(_menu_anim_rect)

		_menu_anim_timer = Timer.new()
		_menu_anim_timer.wait_time = 1.0 / MENU_ANIM_FPS
		_menu_anim_timer.timeout.connect(_on_menu_anim_tick)
		add_child(_menu_anim_timer)

	var content := VBoxContainer.new()
	LayoutUtil.fill_parent(content)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_menu.add_child(content)

	content.add_child(_make_title())

	var btn_box := VBoxContainer.new()
	btn_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_box.custom_minimum_size = Vector2(260, 0)
	btn_box.add_theme_constant_override("separation", 10)
	content.add_child(btn_box)

	var campaign_btn := Button.new()
	campaign_btn.text = "Campaign"
	campaign_btn.pressed.connect(_on_campaign_pressed)
	campaign_btn.pressed.connect(_play_click_sfx)
	btn_box.add_child(campaign_btn)

	var practice_btn := Button.new()
	practice_btn.text = "Practice"
	practice_btn.pressed.connect(_on_open_practice)
	practice_btn.pressed.connect(_play_click_sfx)
	btn_box.add_child(practice_btn)

	var multiplayer_btn := Button.new()
	multiplayer_btn.text = "Multiplayer"
	multiplayer_btn.pressed.connect(_on_multiplayer_pressed)
	multiplayer_btn.pressed.connect(_play_click_sfx)
	btn_box.add_child(multiplayer_btn)

	var builder_btn := Button.new()
	builder_btn.text = "Deck Builder"
	builder_btn.pressed.connect(_on_open_deck_builder.bind(_main_menu))
	builder_btn.pressed.connect(_play_click_sfx)
	btn_box.add_child(builder_btn)

	var collection_btn := Button.new()
	collection_btn.text = "Collection"
	collection_btn.pressed.connect(_on_open_collection.bind(_main_menu))
	collection_btn.pressed.connect(_play_click_sfx)
	btn_box.add_child(collection_btn)

	var rules_btn := Button.new()
	rules_btn.text = "Rules & Keywords"
	rules_btn.pressed.connect(_on_open_rules.bind(_main_menu))
	rules_btn.pressed.connect(_play_click_sfx)
	btn_box.add_child(rules_btn)

	var options_btn := Button.new()
	options_btn.text = "Options"
	options_btn.pressed.connect(_on_options_pressed)
	options_btn.pressed.connect(_play_click_sfx)
	btn_box.add_child(options_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.pressed.connect(_on_exit_pressed)
	exit_btn.pressed.connect(_play_click_sfx)
	btn_box.add_child(exit_btn)

	_main_menu_status_label = Label.new()
	_main_menu_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_main_menu_status_label)

func _on_campaign_pressed() -> void:
	_main_menu_status_label.text = "Campaign mode isn't available yet."

func _on_multiplayer_pressed() -> void:
	_main_menu_status_label.text = "Multiplayer isn't available yet."

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_open_practice() -> void:
	_set_main_menu_visible(false)
	_refresh_saved_decks_menu()
	_practice_screen.visible = true

## --- Practice mode: deck selection --------------------------------------------

func _build_practice_screen() -> void:
	_practice_screen = Control.new()
	LayoutUtil.fill_parent(_practice_screen)
	_practice_screen.visible = false
	add_child(_practice_screen)

	var content := VBoxContainer.new()
	LayoutUtil.fill_parent(content)
	content.add_theme_constant_override("separation", 6)
	_practice_screen.add_child(content)

	content.add_child(_make_title())

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< Back to Main Menu"
	back_btn.pressed.connect(_on_practice_back_pressed)
	back_btn.pressed.connect(_play_click_sfx)
	top.add_child(back_btn)
	var builder_btn := Button.new()
	builder_btn.text = "Deck Builder"
	builder_btn.pressed.connect(_on_open_deck_builder.bind(_practice_screen))
	builder_btn.pressed.connect(_play_click_sfx)
	top.add_child(builder_btn)
	var collection_btn := Button.new()
	collection_btn.text = "Collection"
	collection_btn.pressed.connect(_on_open_collection.bind(_practice_screen))
	collection_btn.pressed.connect(_play_click_sfx)
	top.add_child(collection_btn)
	var rules_btn := Button.new()
	rules_btn.text = "Rules & Keywords"
	rules_btn.pressed.connect(_on_open_rules.bind(_practice_screen))
	rules_btn.pressed.connect(_play_click_sfx)
	top.add_child(rules_btn)

	var selection_row := HBoxContainer.new()
	selection_row.alignment = BoxContainer.ALIGNMENT_CENTER
	selection_row.add_theme_constant_override("separation", 30)
	content.add_child(selection_row)
	_practice_your_label = Label.new()
	_practice_your_label.text = "Your Deck: (none)"
	selection_row.add_child(_practice_your_label)
	_practice_opponent_label = Label.new()
	_practice_opponent_label.text = "Opponent Deck: (none)"
	selection_row.add_child(_practice_opponent_label)

	var toggle_row := HBoxContainer.new()
	toggle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	toggle_row.add_theme_constant_override("separation", 10)
	content.add_child(toggle_row)
	_practice_choose_your_btn = Button.new()
	_practice_choose_your_btn.toggle_mode = true
	_practice_choose_your_btn.button_pressed = true
	_practice_choose_your_btn.text = "Choosing: Your Deck"
	_practice_choose_your_btn.pressed.connect(_on_practice_choose_side.bind("your"))
	toggle_row.add_child(_practice_choose_your_btn)
	_practice_choose_opp_btn = Button.new()
	_practice_choose_opp_btn.toggle_mode = true
	_practice_choose_opp_btn.text = "Choosing: Opponent Deck"
	_practice_choose_opp_btn.pressed.connect(_on_practice_choose_side.bind("opponent"))
	toggle_row.add_child(_practice_choose_opp_btn)
	var random_btn := Button.new()
	random_btn.text = "Random Opponent"
	random_btn.pressed.connect(_on_practice_random_opponent)
	toggle_row.add_child(random_btn)

	# The 18 fixed decks (one per Leader) plus any saved decks easily
	# overflow the window, so the list itself scrolls — only the header
	# above stays pinned.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	var list_box := VBoxContainer.new()
	list_box.custom_minimum_size = Vector2(420, 0)
	list_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.add_child(list_box)

	var fixed_title := Label.new()
	fixed_title.text = "Fixed Test Decks"
	fixed_title.add_theme_font_size_override("font_size", 16)
	list_box.add_child(fixed_title)
	for deck_id in DeckDefinitions.all_deck_ids():
		var deck: Dictionary = DeckDefinitions.get_deck(deck_id)
		var leader: LeaderData = CardDatabase.get_leader(deck["leader_id"])
		var btn := Button.new()
		btn.text = "%s\n(%s)" % [deck_id.replace("_", " ").capitalize(), leader.card_name]
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_on_practice_deck_picked.bind(deck_id))
		btn.pressed.connect(_play_click_sfx)
		list_box.add_child(btn)

	var saved_title := Label.new()
	saved_title.text = "Your Decks"
	saved_title.add_theme_font_size_override("font_size", 16)
	list_box.add_child(saved_title)
	_saved_decks_menu_box = VBoxContainer.new()
	list_box.add_child(_saved_decks_menu_box)
	_refresh_saved_decks_menu()

	_practice_start_btn = Button.new()
	_practice_start_btn.text = "Start Match"
	_practice_start_btn.disabled = true
	_practice_start_btn.pressed.connect(_on_practice_start_pressed)
	content.add_child(_practice_start_btn)

func _on_practice_back_pressed() -> void:
	_practice_screen.visible = false
	_set_main_menu_visible(true)

func _on_practice_choose_side(side: String) -> void:
	_practice_choosing_side = side
	_practice_choose_your_btn.button_pressed = side == "your"
	_practice_choose_opp_btn.button_pressed = side == "opponent"

func _on_practice_deck_picked(deck_id: String) -> void:
	if _practice_choosing_side == "your":
		_practice_your_deck_id = deck_id
		_practice_your_label.text = "Your Deck: %s" % _practice_display_name(deck_id)
	else:
		_practice_opponent_deck_id = deck_id
		_practice_opponent_label.text = "Opponent Deck: %s" % _practice_display_name(deck_id)
	_practice_start_btn.disabled = _practice_your_deck_id.is_empty() or _practice_opponent_deck_id.is_empty()

func _on_practice_random_opponent() -> void:
	var pool := DeckDefinitions.all_deck_ids()
	if not _practice_your_deck_id.is_empty():
		pool.erase(_practice_your_deck_id)
	if pool.is_empty():
		return
	var chosen: String = pool[randi() % pool.size()]
	_practice_opponent_deck_id = chosen
	_practice_opponent_label.text = "Opponent Deck: %s" % _practice_display_name(chosen)
	_practice_start_btn.disabled = _practice_your_deck_id.is_empty() or _practice_opponent_deck_id.is_empty()

func _practice_display_name(deck_id: String) -> String:
	if DeckDefinitions.all_deck_ids().has(deck_id):
		return deck_id.replace("_", " ").capitalize()
	return deck_id

func _on_practice_start_pressed() -> void:
	await _start_match(_practice_your_deck_id, _practice_opponent_deck_id)

func _refresh_saved_decks_menu() -> void:
	for child in _saved_decks_menu_box.get_children():
		child.queue_free()
	var names := DeckStorage.all_deck_names()
	if names.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(none yet — build one in the Deck Builder)"
		_saved_decks_menu_box.add_child(empty_label)
		return
	for deck_name: String in names:
		var d := DeckStorage.get_deck(deck_name)
		var leader: LeaderData = CardDatabase.get_leader(d.get("leader_id", ""))
		var btn := Button.new()
		btn.text = "%s\n(%s)" % [deck_name, leader.card_name if leader != null else "?"]
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_on_practice_deck_picked.bind(deck_name))
		btn.pressed.connect(_play_click_sfx)
		_saved_decks_menu_box.add_child(btn)

## Shows/hides a top-level screen, special-casing the main menu so its bg
## animation starts/stops correctly (§ user request: Deck Builder,
## Collection, and Rules & Keywords are reachable from BOTH the main menu
## and the Practice screen now, so closing one of them must return to
## whichever of those two actually opened it, not always the same screen).
func _show_screen(s: Control) -> void:
	if s == _main_menu:
		_set_main_menu_visible(true)
	else:
		s.visible = true

func _hide_screen(s: Control) -> void:
	if s == _main_menu:
		_set_main_menu_visible(false)
	else:
		s.visible = false

func _on_open_deck_builder(from: Control) -> void:
	_deck_builder_return_target = from
	_hide_screen(from)
	_deck_builder.refresh_on_show()
	_deck_builder.visible = true
	# § user request: the Deck Builder has its own music, same as the
	# Collection screen — pause the ambient menu track while it's open.
	_stop_ambient_music()
	_deck_builder.start_music()

func _on_deck_builder_closed() -> void:
	_deck_builder.visible = false
	_resume_ambient_music()
	_refresh_saved_decks_menu()
	if _deck_builder_return_target != null:
		_show_screen(_deck_builder_return_target)

func _on_open_collection(from: Control) -> void:
	_collection_return_target = from
	_hide_screen(from)
	_collection.visible = true
	# § user request: the Collection screen has its own music, and no other
	# music should play alongside it — pause the ambient menu track for as
	# long as this screen is open.
	_stop_ambient_music()
	_collection.start_music()

func _on_collection_closed() -> void:
	_collection.visible = false
	_resume_ambient_music()
	if _collection_return_target != null:
		_show_screen(_collection_return_target)

## `from` is whichever screen was open when Rules was requested (the main
## menu, the Practice deck-select screen, or the Deck Builder), so closing
## Rules returns to the right place.
func _on_open_rules(from: Control) -> void:
	_rules_return_target = from
	_hide_screen(from)
	_rules_screen.visible = true

func _on_rules_closed() -> void:
	_rules_screen.visible = false
	if _rules_return_target != null:
		_show_screen(_rules_return_target)

## Brief loading beat (§ user request) shown while a match is being set up
## — currently instant work (deck shuffle, opening hands), so this is a
## deliberate UX pause with the animated sprite in the bottom-right corner,
## same spot as the splash screen's. No-ops instantly if the sprite asset
## isn't present.
func _show_loading_screen() -> void:
	var spinner := _make_loading_sprite()
	if spinner == null:
		return
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	LayoutUtil.fill_parent(overlay)
	add_child(overlay)
	_anchor_bottom_right(spinner, Vector2(80, 80))
	overlay.add_child(spinner)
	await get_tree().create_timer(LOADING_SCREEN_DURATION).timeout
	overlay.queue_free()

## Starts a match with explicitly-chosen decks for both sides (§ user
## request — Practice mode now lets the player pick the AI's deck too,
## instead of it being randomized). Ambient menu music (§ user request)
## keeps playing through the loading screen and only actually stops once
## the match view becomes visible; _on_new_game_pressed resumes it when
## the player returns to the Practice deck-select screen.
func _start_match(your_deck_id: String, opponent_deck_id: String) -> void:
	_practice_screen.visible = false
	_main_menu.visible = false # defensive — normally already hidden by the Practice-screen navigation that got here, but a match should never show the menu bleeding through regardless of how it was reached
	_hide_docked_preview()
	await _show_loading_screen()
	_match_view.visible = true
	_match_bg.visible = true
	# § user bug report — "leader cards start very small during some
	# matches": every zone that sizes itself from its own real,
	# already-laid-out dimensions (the Leader panel, hand cards, piles —
	# see _current_zone_size) falls back to a small placeholder size
	# whenever that real size reads as zero, which it always does right
	# here — _match_view was invisible (and thus never laid out at all)
	# until the line just above, and Container/anchor layout is resolved
	# on the next idle step, not synchronously the instant .visible flips.
	# TurnManager.start_game below fires GameLog entries and (for an AI
	# player) can even resolve a whole turn synchronously, each of which
	# calls _refresh() well before that first real layout pass — so
	# without this wait, the very first several refreshes of a match all
	# compute sizes from zero instead of the real, final layout.
	await get_tree().process_frame
	await get_tree().process_frame
	_stop_ambient_music()
	_selected_hand_index = -1
	_selected_attacker_id = -1
	GameLog.clear()
	if _log_display != null:
		_log_display.clear()

	TurnManager.start_game([your_deck_id, opponent_deck_id], HUMAN)
	GameState.players[AI].is_ai = true
	_refresh()

## --- Match view scaffolding --------------------------------------------------

func _stretch_h(c: Control, ratio: float) -> void:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = ratio

func _stretch_v(c: Control, ratio: float) -> void:
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = ratio

## `.size` before a Control has ever been through a real layout pass reads
## as (0,0) — this is the fallback used everywhere a zone's own current
## size drives how something inside it is sized (piles, hand cards, Leader
## preview scale, creature shrink-to-fit).
func _current_zone_size(zone: Control, fallback: Vector2) -> Vector2:
	var s: Vector2 = zone.size
	return Vector2(s.x if s.x > 1.0 else fallback.x, s.y if s.y > 1.0 else fallback.y)

func _build_match_view() -> void:
	# An opaque battlefield background (§ user bug report — the main menu
	# was visible bleeding through the match view wherever no widget
	# happened to cover that exact pixel, since the layout containers
	# themselves are fully transparent).
	_match_bg = ColorRect.new()
	_match_bg.color = Color(0.08, 0.08, 0.1)
	_match_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_match_bg.visible = false
	LayoutUtil.fill_parent(_match_bg)
	add_child(_match_bg)

	_battlefield_root = VBoxContainer.new()
	_match_view = HBoxContainer.new()
	LayoutUtil.fill_parent(_match_view)
	_match_view.add_theme_constant_override("separation", 10)
	add_child(_match_view)

	_stretch_h(_battlefield_root, 1.0)
	_battlefield_root.add_theme_constant_override("separation", 4)
	_match_view.add_child(_battlefield_root)

	# § user request — an exact percentage spec, mirrored on BOTH axes for
	# the opponent ("as though I am sitting across from them... except I
	# should still be able to read their stuff" — positions mirror, but
	# nothing is actually rendered upside down): reading top to bottom,
	# the opponent's HUD strip sits at the very top edge (mirroring the
	# player's, which sits at the very bottom edge), then the opponent's
	# play row, then the player's play row, then the player's HUD strip —
	# so the two play rows meet in the screen's vertical middle and the two
	# HUD strips sit at the outer top/bottom edges.
	var opponent_hud := HBoxContainer.new()
	opponent_hud.add_theme_constant_override("separation", 8)
	_stretch_v(opponent_hud, HUD_RATIO)
	_battlefield_root.add_child(opponent_hud)
	_build_hud_row(opponent_hud, false)

	var opponent_play := HBoxContainer.new()
	opponent_play.add_theme_constant_override("separation", 8)
	_stretch_v(opponent_play, TOP_RATIO)
	_battlefield_root.add_child(opponent_play)
	_build_play_row(opponent_play, false)

	var player_play := HBoxContainer.new()
	player_play.add_theme_constant_override("separation", 8)
	_stretch_v(player_play, TOP_RATIO)
	_battlefield_root.add_child(player_play)
	_build_play_row(player_play, true)

	var player_hud := HBoxContainer.new()
	player_hud.add_theme_constant_override("separation", 8)
	_stretch_v(player_hud, HUD_RATIO)
	_battlefield_root.add_child(player_hud)
	_build_hud_row(player_hud, true)

	# § user request (follow-up): the Larva pips shouldn't occupy space in
	# the layout grid at all ("should not interact with the areas and take
	# up any space in that grid") — they float on top of everything instead
	# (anchored to _match_bg, a plain Control the VBox/HBox layout
	# containers above can't fight, same reason CardPreviewOverlay-style
	# widgets always parent there instead of into a Container). A further
	# follow-up moved them from a full-width horizontal strip on the
	# play/HUD seam to a vertical column "just to the right of the discard
	# pile, going upwards... do not go into the other player's side" — see
	# _build_larva_overlay_column's own comment.
	_opponent_larva_row = _build_larva_overlay_column(false)
	_player_larva_row = _build_larva_overlay_column(true)

	_build_log_panel()
	_build_pause_menu()
	_build_block_popup()
	_build_attack_confirm_popup()
	_build_x_cost_popup()
	_build_legend_popup()
	_build_discard_popup()
	_build_game_over_popup()

## A floating vertical column of one side's Larva pips (§ user request,
## through several follow-ups — final form: "directly next to the leader
## and discard pile... the opponent's larva column should be on the left
## side of the leader not the right side") — a plain VBoxContainer parented
## into `_match_bg` (a plain Control, not a layout Container, so nothing
## here fights the VBox/HBox layout above — same reason CardPreviewOverlay-
## style widgets elsewhere always parent there too) with no anchors set, so
## its position/size are entirely manual — computed fresh every refresh in
## _refresh_larva_pips from the real, already-laid-out rects of that side's
## Leader zone and discard pile (see its own comment for why), not from any
## ratio math here. `alignment` only needs setting once: END packs the
## pips flush against the BOTTOM of whatever rect gets assigned each
## refresh (the player's discard pile sits below their Leader), BEGIN packs
## them flush against the TOP (the opponent's discard pile sits above
## theirs, mirrored).
func _build_larva_overlay_column(is_player: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.z_index = 100
	col.clip_contents = true
	col.alignment = BoxContainer.ALIGNMENT_END if is_player else BoxContainer.ALIGNMENT_BEGIN
	_match_bg.add_child(col)
	return col

## One side's HUD strip (§ user request), left to right: deck+discard piles
## / hand / action buttons for the player; mirrored on both axes for the
## opponent (hand / deck+discard), with the action-button column dropped
## and its share folded into the hand column instead of left blank (§ user
## request — the opponent never needs it, even in future multiplayer).
func _build_hud_row(row: HBoxContainer, is_player: bool) -> void:
	var piles_zone := _build_piles_zone(is_player)
	var hand_zone := _build_hand_zone(is_player)
	if is_player:
		_stretch_h(piles_zone, HUD_PILES_RATIO)
		row.add_child(piles_zone)
		_stretch_h(hand_zone, HUD_HAND_RATIO)
		row.add_child(hand_zone)
		var actions_zone := _build_action_zone()
		_stretch_h(actions_zone, HUD_ACTIONS_RATIO)
		row.add_child(actions_zone)
	else:
		_stretch_h(hand_zone, OPP_HUD_HAND_RATIO)
		row.add_child(hand_zone)
		_stretch_h(piles_zone, OPP_HUD_PILES_RATIO)
		row.add_child(piles_zone)

## Deck + discard piles (§ user request: "fill the area as much as you
## can") — each pile is an equal EXPAND_FILL share of this zone instead of
## a fixed pixel size, so _refresh_pile can size the pile art from each
## button's own real, already-laid-out dimensions.
func _build_piles_zone(is_player: bool) -> HBoxContainer:
	var zone := HBoxContainer.new()
	zone.add_theme_constant_override("separation", 6)
	var deck_pile := Control.new()
	_stretch_h(deck_pile, 1.0)
	var discard_btn := Button.new()
	_stretch_h(discard_btn, 1.0)
	if is_player:
		_player_deck_pile = deck_pile
		_player_discard_btn = discard_btn
		_player_discard_btn.pressed.connect(_on_player_discard_pressed)
		zone.add_child(deck_pile)
		zone.add_child(discard_btn)
	else:
		_opponent_deck_pile = deck_pile
		_opponent_discard_btn = discard_btn
		_opponent_discard_btn.pressed.connect(_on_opponent_discard_pressed)
		zone.add_child(discard_btn)
		zone.add_child(deck_pile)
	return zone

## The hand zone: a plain Control, not a layout Container — cards are
## free-floating widgets positioned/rotated into a fan by
## _position_hand_slot, and the player's are dragged freely by
## _begin_hand_drag/_input, neither of which a Container would tolerate
## (it would fight both the fan's per-card offsets and a drag's manually-
## set global_position every layout pass — the exact bug
## EnlargedCardView's header comment documents for the same reason).
## clip_contents stays off so a lifted card can rise above the tray's own
## bounds while dragging.
func _build_hand_zone(is_player: bool) -> Control:
	var zone := Control.new()
	if is_player:
		_player_hand = zone
	else:
		_opponent_hand = zone
	return zone

## § user request: End Turn by default; Cancel (plus, for the specific
## action in progress, whichever of Attack Leader or the Leader's Hero
## Power/Ultimate applies) once the player has clicked into something —
## see _refresh's own "action zone" section for the actual state machine.
func _build_action_zone() -> Control:
	var zone := VBoxContainer.new()
	zone.alignment = BoxContainer.ALIGNMENT_CENTER
	zone.add_theme_constant_override("separation", 6)

	_end_turn_btn = Button.new()
	_end_turn_btn.text = "End Turn"
	_end_turn_btn.pressed.connect(_on_end_turn_pressed)
	zone.add_child(_end_turn_btn)

	_attack_leader_btn = Button.new()
	_attack_leader_btn.text = "Attack Leader"
	_attack_leader_btn.visible = false
	_attack_leader_btn.pressed.connect(_on_enemy_leader_pressed)
	zone.add_child(_attack_leader_btn)

	_hero_power_btn = Button.new()
	_hero_power_btn.clip_text = true
	_hero_power_btn.visible = false
	_hero_power_btn.pressed.connect(_on_hero_power_pressed)
	zone.add_child(_hero_power_btn)

	_ultimate_btn = Button.new()
	_ultimate_btn.clip_text = true
	_ultimate_btn.visible = false
	_ultimate_btn.pressed.connect(_on_ultimate_pressed)
	zone.add_child(_ultimate_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	zone.add_child(_cancel_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	zone.add_child(_status_label)

	return zone

## One side's play row (§ user request), left to right: Leader / play area
## (creatures + Hive) / card preview for the player; mirrored on both axes
## for the opponent (play area / Leader), with the preview column dropped
## and its share folded into the play area instead of left blank (§ user
## request).
func _build_play_row(row: HBoxContainer, is_player: bool) -> void:
	var leader_zone := _build_leader_zone(is_player)
	var board_zone := _build_board_zone(is_player)
	if is_player:
		_stretch_h(leader_zone, PLAY_LEADER_RATIO)
		row.add_child(leader_zone)
		_stretch_h(board_zone, PLAY_BOARD_RATIO)
		row.add_child(board_zone)
		var preview_zone := Control.new()
		_preview_dock = preview_zone
		_preview_view = EnlargedCardView.new()
		_preview_view.visible = false
		_preview_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_zone.add_child(_preview_view)
		_stretch_h(preview_zone, PLAY_PREVIEW_RATIO)
		row.add_child(preview_zone)
	else:
		_stretch_h(board_zone, OPP_PLAY_BOARD_RATIO)
		row.add_child(board_zone)
		_stretch_h(leader_zone, OPP_PLAY_LEADER_RATIO)
		row.add_child(leader_zone)

## The always-visible Leader panel (§ user request: "the leader card should
## always be shown... enlarged" — and, per follow-ups, showing its full
## rules text always rather than only on hover "since it's always in that
## state on the field", and — later still — with no separate info line at
## all so the card itself can be bigger: its current health lives directly
## on the card's own life-total badge instead, via _refresh_leader_panel's
## life_override, and larva/hand-size/turn are all visible elsewhere
## already (the new larva pips, the opponent's own visible hand, the
## Action Log)). The same EnlargedCardView the docked hover-preview uses
## (art, name, life badge, and — unlike every other card widget in this
## file — its full rules text box, since a Leader's Hero Power/Ultimate
## wording is exactly the point of always showing it), scaled (see
## _fit_view_to_region) to fit whatever this zone's real proportional size
## turns out to be instead of a fixed pixel size (§ the previous
## fixed-size version is exactly what caused an earlier layout bug). A
## plain flat Button sits underneath it purely for click/hover handling,
## since EnlargedCardView itself ignores mouse input (see its own _ready).
## The player's Leader is also clickable (§ user request): it highlights
## whenever an ability is usable, and opens both as buttons in the action
## zone.
func _build_leader_zone(is_player: bool) -> Control:
	var zone := Control.new()

	var leader_btn := Button.new()
	leader_btn.flat = true
	leader_btn.focus_mode = Control.FOCUS_NONE
	LayoutUtil.fill_parent(leader_btn)
	zone.add_child(leader_btn)

	var leader_view := EnlargedCardView.new()
	leader_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(leader_view)

	if is_player:
		_player_leader_btn = leader_btn
		_player_leader_view = leader_view
		_player_leader_zone = zone
		leader_btn.pressed.connect(_on_leader_clicked)
	else:
		_opponent_leader_btn = leader_btn
		_opponent_leader_view = leader_view
		_opponent_leader_zone = zone
	leader_btn.mouse_entered.connect(_show_leader_preview.bind(is_player))
	leader_btn.mouse_exited.connect(_hide_docked_preview)
	return zone

## The play area (§ user request): creatures front-and-center, Hive (non-
## creature permanents that stick to the field) in its own area — hidden
## entirely, freeing its share back to the creature zone, whenever it's
## empty (see _render_hive_row). Mirrored on both axes for the opponent
## (Hive on the left, creatures on the right) to match the outer mirroring.
func _build_board_zone(is_player: bool) -> Control:
	var zone := HBoxContainer.new()
	zone.add_theme_constant_override("separation", 8)

	var board_scroll := ScrollContainer.new()
	board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	board_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stretch_h(board_scroll, BOARD_CREATURES_RATIO)
	var board_row := HBoxContainer.new()
	board_row.add_theme_constant_override("separation", CREATURE_ROW_SPACING)
	board_scroll.add_child(board_row)

	var hive_scroll := ScrollContainer.new()
	hive_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hive_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stretch_h(hive_scroll, BOARD_HIVE_RATIO)
	var hive_row := HBoxContainer.new()
	hive_row.add_theme_constant_override("separation", 6)
	hive_scroll.add_child(hive_row)

	if is_player:
		_player_board = board_row
		_player_board_zone = board_scroll
		_player_hive = hive_row
		zone.add_child(board_scroll)
		zone.add_child(hive_scroll)
	else:
		_opponent_board = board_row
		_opponent_board_zone = board_scroll
		_opponent_hive = hive_row
		zone.add_child(hive_scroll)
		zone.add_child(board_scroll)
	return zone

func _build_log_panel() -> void:
	_log_panel = PanelContainer.new()
	_log_panel.custom_minimum_size = Vector2(320, 0)
	_match_view.add_child(_log_panel)
	var box := VBoxContainer.new()
	_log_panel.add_child(box)
	var title := Label.new()
	title.text = "Action Log"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	_log_display = RichTextLabel.new()
	_log_display.bbcode_enabled = true
	_log_display.scroll_following = true
	_log_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_display.custom_minimum_size = Vector2(300, 200)
	box.add_child(_log_display)

## § user request: closed, the battlefield takes the whole screen; open, it
## shrinks to make room rather than overlapping — both already fall out of
## _log_panel being a normal HBoxContainer sibling of _battlefield_root
## (a hidden Container child is skipped entirely during layout, so
## _battlefield_root's own EXPAND_FILL reclaims the space for free) —
## toggling .visible here is the only piece actually needed.
func _on_log_toggle_pressed() -> void:
	_log_panel.visible = not _log_panel.visible

## § user request: "Add a small menu when escape is pressed where the
## show/hide log button lives as well as a concede match button" — replaces
## the old standalone corner "Log" button entirely (folded in here instead).
func _build_pause_menu() -> void:
	_pause_menu = PanelContainer.new()
	_pause_menu.visible = false
	_pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	_pause_menu.z_index = 100
	add_child(_pause_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_pause_menu.add_child(box)
	var title := Label.new()
	title.text = "Menu"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var log_btn := Button.new()
	log_btn.text = "Show/Hide Log"
	log_btn.pressed.connect(_on_log_toggle_pressed)
	box.add_child(log_btn)
	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.pressed.connect(_toggle_pause_menu)
	box.add_child(resume_btn)
	var concede_btn := Button.new()
	concede_btn.text = "Concede Match"
	concede_btn.pressed.connect(_on_concede_pressed)
	box.add_child(concede_btn)

func _toggle_pause_menu() -> void:
	_pause_menu.visible = not _pause_menu.visible

## Forfeits the current match (§ user request) — TurnManager.concede ends
## the game the same way a normal loss does, so the existing
## game_ended -> _on_game_ended -> game-over-popup -> _on_new_game_pressed
## chain is what actually returns the player to deck selection; this just
## triggers that chain and closes the menu that opened it.
func _on_concede_pressed() -> void:
	_pause_menu.visible = false
	TurnManager.concede(HUMAN)

## GameLog.entry_added fires for essentially every game action (draws,
## plays, attacks, damage, hero powers, ...), so re-rendering the board
## here (§ user request) keeps it live throughout the AI's whole turn
## instead of only before and after it. Previously the only refreshes
## around an AI turn were _on_turn_started's (before) and the one after
## `await AIPlayer.take_turn(...)` finishes — so a creature the AI played
## AND attacked with in the same turn (e.g. a Swift creature) was
## invisible on the opponent board the entire time, only appearing once
## its whole turn had already ended. _refresh() itself no-ops if the
## match view isn't showing, so this is safe to call this often.
func _on_log_entry(text: String, kind: String) -> void:
	if _log_display == null:
		return
	var color := "#dddddd"
	match kind:
		"system":
			color = "#8fa8ff"
		"combat":
			color = "#ff9955"
		"chat":
			color = "#55ddff"
	_log_display.append_text("[color=%s]%s[/color]\n" % [color, text.replace("[", "(").replace("]", ")")])
	_refresh()


func _build_block_popup() -> void:
	_block_popup = PanelContainer.new()
	_block_popup.visible = false
	_block_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_block_popup)
	_block_popup_box = VBoxContainer.new()
	_block_popup.add_child(_block_popup_box)

## Brief "Confirm this attack?" step (§ user request) between choosing a
## target and the attack actually resolving — one attack at a time, not a
## bulk declare-then-confirm phase.
func _build_attack_confirm_popup() -> void:
	_attack_confirm_popup = PanelContainer.new()
	_attack_confirm_popup.visible = false
	_attack_confirm_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_attack_confirm_popup)
	var box := VBoxContainer.new()
	_attack_confirm_popup.add_child(box)
	_attack_confirm_label = Label.new()
	box.add_child(_attack_confirm_label)
	var row := HBoxContainer.new()
	box.add_child(row)
	var yes_btn := Button.new()
	yes_btn.text = "Attack"
	yes_btn.pressed.connect(_on_attack_confirm_yes)
	row.add_child(yes_btn)
	var no_btn := Button.new()
	no_btn.text = "Cancel"
	no_btn.pressed.connect(_on_attack_confirm_no)
	row.add_child(no_btn)

## X-cost Ultimate amount picker (§ user request — Ashen Cricket): shown
## before targeting, letting the player choose how much Larva to spend
## (at least the Leader's ultimate_cost, at most their current total).
func _build_x_cost_popup() -> void:
	_x_cost_popup = PanelContainer.new()
	_x_cost_popup.visible = false
	_x_cost_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_x_cost_popup)
	var box := VBoxContainer.new()
	_x_cost_popup.add_child(box)
	var label := Label.new()
	label.text = "Choose how much Larva to spend:"
	box.add_child(label)
	_x_cost_spinbox = SpinBox.new()
	_x_cost_spinbox.step = 1
	box.add_child(_x_cost_spinbox)
	var row := HBoxContainer.new()
	box.add_child(row)
	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.pressed.connect(_on_x_cost_confirm)
	row.add_child(confirm)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_on_x_cost_cancel)
	row.add_child(cancel)

func _build_legend_popup() -> void:
	_legend_popup = PanelContainer.new()
	_legend_popup.visible = false
	_legend_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_legend_popup)
	_legend_popup_box = VBoxContainer.new()
	_legend_popup.add_child(_legend_popup_box)

func _build_discard_popup() -> void:
	_discard_popup = PanelContainer.new()
	_discard_popup.visible = false
	_discard_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_discard_popup)
	var box := VBoxContainer.new()
	_discard_popup.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 420)
	box.add_child(scroll)
	_discard_popup_box = VBoxContainer.new()
	scroll.add_child(_discard_popup_box)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: _discard_popup.visible = false)
	box.add_child(close)

func _on_player_discard_pressed() -> void:
	_show_discard(GameState.players[HUMAN], "Your")

func _on_opponent_discard_pressed() -> void:
	_show_discard(GameState.players[AI], "%s's" % GameState.players[AI].leader.data.card_name)

func _show_discard(player: PlayerState, label: String) -> void:
	for child in _discard_popup_box.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "%s Discard Pile (%d card%s)" % [label, player.graveyard.size(), "" if player.graveyard.size() == 1 else "s"]
	title.add_theme_font_size_override("font_size", 18)
	_discard_popup_box.add_child(title)
	if player.graveyard.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(empty)"
		_discard_popup_box.add_child(empty_label)
	for c: CardInstance in player.graveyard:
		var entry := Label.new()
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD
		var desc := c.display_name()
		if c.data is CreatureData:
			var cd := c.data as CreatureData
			desc += " (%d/%d)" % [cd.attack, cd.health]
		if c.data.text != "":
			desc += " — " + c.data.text
		entry.text = desc
		_discard_popup_box.add_child(entry)
	_discard_popup.visible = true

func _build_game_over_popup() -> void:
	_game_over_popup = PanelContainer.new()
	_game_over_popup.visible = false
	_game_over_popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_game_over_popup)
	var box := VBoxContainer.new()
	_game_over_popup.add_child(box)
	_game_over_label = Label.new()
	box.add_child(_game_over_label)
	var again := Button.new()
	again.text = "New Game"
	again.pressed.connect(_on_new_game_pressed)
	box.add_child(again)

func _on_new_game_pressed() -> void:
	_game_over_popup.visible = false
	_pause_menu.visible = false
	_match_view.visible = false
	_match_bg.visible = false
	_hide_docked_preview()
	_resume_ambient_music()
	_refresh_saved_decks_menu()
	_practice_screen.visible = true

## --- Signal handlers ---------------------------------------------------------

func _on_turn_started(player_id: int) -> void:
	_refresh()
	if GameState.is_over:
		return
	if GameState.players[player_id].is_ai:
		_busy = true
		_refresh()
		var ai_player := GameState.players[player_id]
		_ai_reveal_set = {}
		for c: CardInstance in ai_player.board:
			_ai_reveal_set[c.instance_id] = true
		for c: CardInstance in ai_player.hive_zone:
			_ai_reveal_set[c.instance_id] = true
		_ai_reveal_active = true
		# Nothing awaited after this line (see _process's own comment for
		# why the actual pacing/animation happens there instead of here).
		_ai_replay_queue = await AIPlayer.take_turn(player_id)

const AI_ACTION_PAUSE := 0.45

## Drives the AI-turn replay queue (§ user request: "have it take each turn
## action in a way where the player can tell what they are doing before
## moving on to the next action") entirely through per-frame polling
## instead of a chain of awaits (get_tree().process_frame /
## create_timer().timeout / tween.finished, directly or via call_deferred).
## _on_turn_started (a signal callback for TurnManager.turn_started) can be
## reentered synchronously from within its own await on AIPlayer.take_turn
## — that call's tail end_turn() cascades straight into the next
## start_turn/turn_started before this one even returns to its caller — and
## an await-chain-based version of this replay reliably stalled partway
## through real matches even though every isolated repro of that same
## pattern worked fine in isolation. Polling from _process sidesteps the
## question entirely: there is no await anywhere in the replay path itself,
## so there's nothing left for that reentrancy to interact badly with.
func _process(delta: float) -> void:
	if _ai_replay_queue.is_empty():
		return
	if _ai_replay_pause_timer > 0.0:
		_ai_replay_pause_timer -= delta
		return
	var action: Dictionary = _ai_replay_queue.pop_front()
	_apply_ai_action_visual(action)
	_ai_replay_pause_timer = AI_ACTION_PAUSE
	if _ai_replay_queue.is_empty():
		_ai_reveal_active = false
		_busy = false
		_refresh()

## Applies one AI action's visual reveal/animation (§ user request — see
## _process's own comment for why this doesn't await anything). Tweens
## started here are fire-and-forget: each easily finishes well within
## AI_ACTION_PAUSE before the next action's own _refresh would touch the
## same widget anyway. _ai_reveal_set (seeded in _on_turn_started with
## every opponent board/hive card that already existed BEFORE this turn) is
## what makes this look progressive rather than "everything's already
## there, then it pops for flavor": _render_row/_render_hive_row hide any
## opponent card not yet in that set while _ai_reveal_active is true, so a
## card newly played this turn only actually appears once its own
## play_card/flip_ambush step here adds it and re-renders.
func _apply_ai_action_visual(action: Dictionary) -> void:
	var kind: String = action.get("kind", "")
	if kind == "play_card" or kind == "flip_ambush":
		_ai_reveal_set[int(action.get("instance_id", -1))] = true
	_refresh()
	match kind:
		"play_card", "flip_ambush":
			var widget := _find_widget_by_instance(_opponent_board, action.get("instance_id", -1))
			if widget == null:
				widget = _find_widget_by_instance(_opponent_hive, action.get("instance_id", -1))
			if widget != null:
				_start_pop_animation(widget)
		"attack":
			var widget := _find_widget_by_instance(_opponent_board, action.get("attacker_id", -1))
			if widget != null:
				_start_lunge_animation(widget)
		"hero_power", "ultimate":
			_start_pulse_animation(_opponent_leader_view)

func _find_widget_by_instance(container: Node, instance_id: int) -> Control:
	for child in container.get_children():
		if child.has_meta("instance_id") and int(child.get_meta("instance_id")) == instance_id:
			return child
	return null

## A played/flipped card popping into place from nothing, instead of just
## appearing instantly. Fire-and-forget (see _process's own comment) — the
## tween runs independently and finishes well within AI_ACTION_PAUSE.
func _start_pop_animation(widget: Control) -> void:
	widget.pivot_offset = widget.size * 0.5
	widget.scale = Vector2(0.2, 0.2)
	widget.modulate.a = 0.3
	var tween := create_tween()
	tween.tween_property(widget, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(widget, "modulate:a", 1.0, 0.2)

## An attacker lunging toward the shared middle of the board (the opponent's
## row sits above it) and back — reads as "reaching across to attack"
## without needing to track the specific defender's screen position through
## a refresh that may have just removed it.
func _start_lunge_animation(widget: Control) -> void:
	var start := widget.position
	var tween := create_tween()
	tween.tween_property(widget, "position", start + Vector2(0, 24), 0.12)
	tween.tween_property(widget, "position", start, 0.15)

## A brief scale pulse on the Leader panel for Hero Power/Ultimate —
## relative to whatever scale it's already sitting at (the Leader view is
## always fit-scaled to its zone via _fit_view_to_region, so animating to
## an absolute Vector2.ONE would snap it to native 1:1 size instead of back
## to its correct fit).
func _start_pulse_animation(view: Control) -> void:
	if view == null:
		return
	view.pivot_offset = view.size * 0.5
	var base_scale := view.scale
	var tween := create_tween()
	tween.tween_property(view, "scale", base_scale * 1.08, 0.15)
	tween.tween_property(view, "scale", base_scale, 0.15)

## Gang-blocking (§ user request): any number of legal blockers can be
## toggled on before confirming, instead of picking exactly one. Each
## option is a toggle button rather than an instant-submit button so
## multiple can be selected before the choice is locked in.
var _pending_block_selection: Array[CardInstance] = []

func _on_block_requested(attacker: CardInstance, legal_blockers: Array[CardInstance]) -> void:
	_pending_block_selection.clear()
	for child in _block_popup_box.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = "%s (%d/%d) is attacking your Leader. Choose any number of blockers." % [attacker.display_name(), attacker.current_attack, attacker.current_health()]
	_block_popup_box.add_child(label)
	for c: CardInstance in legal_blockers:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "Block with %s (%d/%d)" % [c.display_name(), c.current_attack, c.current_health()]
		btn.toggled.connect(_on_block_toggle.bind(c))
		_block_popup_box.add_child(btn)
	var confirm := Button.new()
	confirm.text = "Confirm Block"
	confirm.pressed.connect(_on_block_confirm)
	_block_popup_box.add_child(confirm)
	var skip := Button.new()
	skip.text = "Take the damage"
	skip.pressed.connect(_on_block_skip)
	_block_popup_box.add_child(skip)
	_block_popup.visible = true

func _on_block_toggle(pressed: bool, c: CardInstance) -> void:
	if pressed:
		if not _pending_block_selection.has(c):
			_pending_block_selection.append(c)
	else:
		_pending_block_selection.erase(c)

func _on_block_confirm() -> void:
	_block_popup.visible = false
	TurnManager.submit_block_choices(_pending_block_selection.duplicate())

func _on_block_skip() -> void:
	_block_popup.visible = false
	TurnManager.submit_block_choices([])

func _on_legend_rule_requested(new_card: CardInstance, existing_copies: Array[CardInstance]) -> void:
	for child in _legend_popup_box.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = "Legend Rule: you already control %s. Which copy do you keep?" % new_card.display_name()
	_legend_popup_box.add_child(label)
	var new_btn := Button.new()
	new_btn.text = "Keep the new one (%d/%d)" % [new_card.current_attack, new_card.current_health()]
	new_btn.pressed.connect(_on_legend_choice.bind(new_card))
	_legend_popup_box.add_child(new_btn)
	for c: CardInstance in existing_copies:
		var btn := Button.new()
		btn.text = "Keep the one already in play (%d/%d)" % [c.current_attack, c.current_health()]
		btn.pressed.connect(_on_legend_choice.bind(c))
		_legend_popup_box.add_child(btn)
	_legend_popup.visible = true

func _on_legend_choice(choice: CardInstance) -> void:
	_legend_popup.visible = false
	TurnManager.submit_legend_choice(choice)

func _on_game_ended(winner_id: int) -> void:
	_game_over_label.text = "%s wins!" % GameState.players[winner_id].leader.data.card_name
	_game_over_popup.visible = true
	_refresh()

## --- Player action handlers --------------------------------------------------

func _on_hero_power_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	var player := GameState.players[HUMAN]
	if _begin_targeting_if_needed(player.leader.data.hero_power_effects, "hero"):
		return
	if not TurnManager.use_hero_power(HUMAN):
		_status_label.text = "Can't use Hero Power right now."
	_refresh()

func _on_ultimate_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	var player := GameState.players[HUMAN]
	if player.leader.data.ultimate_variable_cost:
		var min_spend := player.leader.data.ultimate_cost
		_x_cost_spinbox.min_value = min_spend
		_x_cost_spinbox.max_value = max(min_spend, player.current_larva)
		_x_cost_spinbox.value = min_spend
		_x_cost_popup.visible = true
		return
	if _begin_targeting_if_needed(player.leader.data.ultimate_effects, "ultimate"):
		return
	if not TurnManager.use_ultimate(HUMAN):
		_status_label.text = "Can't use Ultimate right now."
	_refresh()

func _on_x_cost_confirm() -> void:
	_x_cost_popup.visible = false
	var player := GameState.players[HUMAN]
	var amount := int(_x_cost_spinbox.value)
	if amount > player.current_larva:
		_status_label.text = "Not enough Larva."
		return
	_pending_ultimate_larva_spend = amount
	if _begin_targeting_if_needed(player.leader.data.ultimate_effects, "ultimate"):
		return
	var ok := TurnManager.use_ultimate(HUMAN, -1, amount)
	_pending_ultimate_larva_spend = -1
	_status_label.text = "" if ok else "Can't use Ultimate right now."
	_refresh()

func _on_x_cost_cancel() -> void:
	_x_cost_popup.visible = false

## If `effects` needs a creature target and a legal one exists, enters
## target-selection mode and returns true (caller should stop here). If a
## target is needed but none exist, returns false so the caller proceeds
## unTargeted (EffectResolver's auto-pick will find nothing and skip it).
func _begin_targeting_if_needed(effects: Array[Dictionary], power_kind: String) -> bool:
	var side := _required_target_side_for_effects(effects)
	if side == "":
		return false
	var pool := GameState.players[HUMAN].board if side == "friendly" else GameState.players[AI].board
	if not pool.any(func(c: CardInstance) -> bool: return c.is_alive()):
		return false
	_pending_power_kind = power_kind
	_pending_target_side = side
	_status_label.text = "Choose %s creature to target." % ("a friendly" if side == "friendly" else "an enemy")
	_refresh()
	return true

func _required_target_side_for_effects(effects: Array[Dictionary]) -> String:
	for e: Dictionary in effects:
		if TARGETING_EFFECT_SIDES.has(e.get("effect_id", "")):
			return TARGETING_EFFECT_SIDES[e.get("effect_id", "")]
	return ""

func _on_end_turn_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	_clear_selection()
	TurnManager.end_turn()

func _on_cancel_pressed() -> void:
	_clear_selection()
	_status_label.text = ""
	_refresh()

func _clear_selection() -> void:
	_selected_hand_index = -1
	_selected_attacker_id = -1
	_pending_target_side = ""
	_pending_target_effect_id = ""
	_pending_power_kind = ""
	_pending_ultimate_larva_spend = -1
	_leader_menu_open = false

## § user request: clicking the Leader opens Hero Power/Ultimate as buttons
## in the action zone (see _refresh's "action zone" section for which of
## those two actually end up clickable) plus a Cancel there to back out.
## Ignored while another action is already in progress rather than
## interrupting it, since there's no spec for what should happen to that
## other action if the Leader is clicked mid-way through it.
func _on_leader_clicked() -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	if _selected_hand_index != -1 or _pending_power_kind != "" or _selected_attacker_id != -1:
		return
	_leader_menu_open = true
	_refresh()

func _on_hand_card_pressed(index: int) -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	var player := GameState.players[HUMAN]
	if index < 0 or index >= player.hand.size():
		return
	var card: CardInstance = player.hand[index]

	if card.data.card_type == CardTypes.GEAR:
		if player.board.is_empty():
			_status_label.text = "No friendly creature to equip Gear to."
			return
		_selected_hand_index = index
		_selected_attacker_id = -1
		_pending_target_side = "friendly"
		_status_label.text = "Choose a friendly creature to equip %s to." % card.display_name()
		_refresh()
		return

	var side := _required_target_side(card)
	if side != "":
		var effect_id := _required_target_effect_id(card)
		var pool := player.board if side == "friendly" else GameState.players[AI].board
		if pool.any(func(c: CardInstance) -> bool: return c.is_alive() and _passes_extra_filter(effect_id, c)):
			_selected_hand_index = index
			_selected_attacker_id = -1
			_pending_target_side = side
			_pending_target_effect_id = effect_id
			_status_label.text = "Choose %s creature to target with %s." % [("a friendly" if side == "friendly" else "an enemy"), card.display_name()]
			_refresh()
			return

	_busy = true
	_refresh()
	var ok := await TurnManager.play_card(HUMAN, index)
	_busy = false
	if ok:
		_status_label.text = ""
	else:
		_status_label.text = "Can't play that right now (cost or Legend Rule)."
	_clear_selection()
	_refresh()

## Which side of the board (if any) a hand card's on-play/on-cast effects
## need a creature target from.
func _required_target_side(card: CardInstance) -> String:
	var effects: Array[Dictionary] = []
	var trigger := ""
	if card.data is CreatureData:
		var cd := card.data as CreatureData
		# A Morph (Ambush) creature's on_play effects don't fire when played —
		# it enters face-down with blank data, and they fire later at reveal
		# instead (EffectResolver.fire_on_flip), which is never an interactive
		# player action. Prompting for a target here would be immediately
		# discarded and silently replaced by an auto-pick at flip time.
		if cd.is_ambush():
			return ""
		effects = cd.effects
		trigger = "on_play"
	elif card.data is AbilityData:
		effects = (card.data as AbilityData).effects
		trigger = "on_cast"
	else:
		return ""
	for e: Dictionary in effects:
		if e.get("trigger", "") == trigger and TARGETING_EFFECT_SIDES.has(e.get("effect_id", "")):
			return TARGETING_EFFECT_SIDES[e.get("effect_id", "")]
	return ""

## The specific effect_id _required_target_side matched, if any — needed
## separately so extra-filter effects (see TARGETING_EXTRA_FILTER) can be
## validated against, not just their side.
func _required_target_effect_id(card: CardInstance) -> String:
	var effects: Array[Dictionary] = []
	var trigger := ""
	if card.data is CreatureData:
		var cd := card.data as CreatureData
		if cd.is_ambush():
			return ""
		effects = cd.effects
		trigger = "on_play"
	elif card.data is AbilityData:
		effects = (card.data as AbilityData).effects
		trigger = "on_cast"
	else:
		return ""
	for e: Dictionary in effects:
		var effect_id: String = e.get("effect_id", "")
		if e.get("trigger", "") == trigger and TARGETING_EFFECT_SIDES.has(effect_id):
			return effect_id
	return ""

func _on_flip_ambush_pressed(instance_id: int) -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	TurnManager.flip_ambush_paid(HUMAN, instance_id)
	_refresh()

func _on_board_creature_pressed(instance: CardInstance, is_friendly: bool) -> void:
	if _busy or GameState.active_player_index != HUMAN:
		return
	var player := GameState.players[HUMAN]

	if _selected_hand_index != -1 or _pending_power_kind != "":
		var wants_friendly := _pending_target_side == "friendly"
		if is_friendly != wants_friendly:
			_status_label.text = "Choose %s creature." % ("a friendly" if wants_friendly else "an enemy")
			return
		if not _passes_extra_filter(_pending_target_effect_id, instance):
			_status_label.text = "Choose a face-down creature."
			return
		_busy = true
		_refresh()
		var ok := false
		if _pending_power_kind == "hero":
			ok = TurnManager.use_hero_power(HUMAN, instance.instance_id)
		elif _pending_power_kind == "ultimate":
			ok = TurnManager.use_ultimate(HUMAN, instance.instance_id, _pending_ultimate_larva_spend)
		else:
			ok = await TurnManager.play_card(HUMAN, _selected_hand_index, instance.instance_id)
		_busy = false
		_status_label.text = "" if ok else "Couldn't target that."
		_clear_selection()
		_refresh()
		return

	if is_friendly:
		if CombatResolver.can_attack(instance):
			_selected_attacker_id = instance.instance_id
			_status_label.text = "%s selected — choose a target." % instance.display_name()
		else:
			_status_label.text = "%s can't attack right now." % instance.display_name()
		_refresh()
		return

	# Enemy creature clicked — attempt to resolve a declared attack.
	if _selected_attacker_id == -1:
		return
	var attacker := player.find_on_board(_selected_attacker_id)
	if attacker == null or not CombatResolver.is_legal_creature_target(attacker, instance):
		_status_label.text = "Illegal target."
		return
	_show_attack_confirm(instance)

func _on_enemy_leader_pressed() -> void:
	if _busy or GameState.active_player_index != HUMAN or _selected_attacker_id == -1:
		return
	var player := GameState.players[HUMAN]
	var attacker := player.find_on_board(_selected_attacker_id)
	if attacker == null or not CombatResolver.is_legal_leader_target(attacker, GameState.players[AI]):
		_status_label.text = "Leader isn't a legal target (Guard in the way? Flying attackers ignore ground-only Guards)."
		return
	_show_attack_confirm("leader")

## Brief "Confirm this attack?" step (§ user request, like Arena) between
## choosing a target and the attack actually resolving.
func _show_attack_confirm(target) -> void:
	_pending_attack_target = target
	if target is String:
		_attack_confirm_label.text = "Attack the enemy Leader?"
	else:
		var t: CardInstance = target
		_attack_confirm_label.text = "Attack %s (%d/%d)?" % [t.display_name(), t.current_attack, t.current_health()]
	_attack_confirm_popup.visible = true

func _on_attack_confirm_yes() -> void:
	_attack_confirm_popup.visible = false
	var target = _pending_attack_target
	_pending_attack_target = null
	_busy = true
	_refresh()
	await TurnManager.declare_attack(HUMAN, _selected_attacker_id, target)
	_selected_attacker_id = -1
	_busy = false
	_refresh()

func _on_attack_confirm_no() -> void:
	_attack_confirm_popup.visible = false
	_pending_attack_target = null
	# The attacker stays selected so the player can pick a different target,
	# or hit Cancel to deselect entirely.
	_refresh()

## --- Rendering -----------------------------------------------------------

func _refresh() -> void:
	if not _match_view.visible:
		return
	var human := GameState.players[HUMAN]
	var ai := GameState.players[AI]

	# § user request: no separate info line anymore — the Leader's name is
	# already on its own card art, its current health now lives directly on
	# the card's own life-total badge (see _refresh_leader_panel's
	# life_override), and larva/hand-size/turn are all visible elsewhere
	# already (each side's own Larva pip row, the opponent's own visible
	# hand, and the Action Log, respectively).
	_refresh_leader_panel(_opponent_leader_btn, _opponent_leader_view, ai.leader.data, ai.health)
	_refresh_pile(_opponent_deck_pile, ai.deck.size())
	_refresh_pile(_opponent_discard_btn, ai.graveyard.size())

	_refresh_leader_panel(_player_leader_btn, _player_leader_view, human.leader.data, human.health)
	_refresh_pile(_player_deck_pile, human.deck.size())
	_refresh_pile(_player_discard_btn, human.graveyard.size())

	_render_row(_opponent_board, ai.board, false, _opponent_board_zone)
	_render_row(_player_board, human.board, true, _player_board_zone)
	_render_hive_row(_opponent_hive, ai.hive_zone, false)
	_render_hive_row(_player_hive, human.hive_zone, true)
	_render_hand()
	_render_opponent_hand()
	_refresh_larva_pips(_player_larva_row, human.current_larva, human.max_larva, true)
	_refresh_larva_pips(_opponent_larva_row, ai.current_larva, ai.max_larva, false)

	var can_act := GameState.active_player_index == HUMAN and not _busy and not GameState.is_over
	var targeting := _selected_hand_index != -1 or _pending_power_kind != ""
	var hero_usable := can_act and not targeting and not human.leader.hero_power_used_this_turn and human.leader.data.hero_power_cost <= human.current_larva
	var ultimate_usable := can_act and not targeting and not human.leader.ultimate_used and human.leader.data.ultimate_cost <= human.current_larva
	# § "make this more like MTG Arena": short button labels — the full
	# ability wording used to be baked into the button's own text, long
	# enough (especially the Ultimate's) to blow out this column's width
	# and, since the Leader panel used to default to filling whatever width
	# its siblings demanded, stretch it into a giant misshapen box (§ user
	# bug report). The full wording is a tooltip instead now.
	_hero_power_btn.disabled = not hero_usable
	_hero_power_btn.text = "Hero Power (%d)" % human.leader.data.hero_power_cost
	_hero_power_btn.tooltip_text = human.leader.data.hero_power_text
	_ultimate_btn.disabled = not ultimate_usable
	_ultimate_btn.text = "Ultimate (%d)" % human.leader.data.ultimate_cost
	_ultimate_btn.tooltip_text = human.leader.data.ultimate_text

	# § user request: the Leader highlights whenever an ability is
	# available, and clicking it (_on_leader_clicked) opens both as buttons
	# down in the action zone. Glowing _player_leader_view itself (not the
	# zone, and not _player_leader_btn) — the view is fit-scaled to however
	# much of the zone's rectangle its own aspect ratio actually fills (see
	# _fit_view_to_region), so glowing the zone highlighted that whole
	# rectangle, letterbox space and all, rather than just the card (§ user
	# report: "just the leader should highlight, not the entire area"). A
	# glow added as a CHILD of the view inherits the view's own
	# position/scale transform, so it tracks the card's actual on-screen
	# bounds exactly regardless of the fit scale — and it renders on top of
	# the view's own content (bg/art/text) since it's appended after those
	# already-built children, avoiding the button/glow draw-order problem a
	# glow at the button level would hit instead (the opaque EnlargedCardView
	# sits on top of that flat button, hiding anything drawn behind it). The
	# glow panel is tagged so it can be found and cleared before adding a
	# fresh one, since _player_leader_view (unlike most other card widgets)
	# is persistent instead of torn down and rebuilt every refresh.
	for child in _player_leader_view.get_children():
		if child.has_meta("_glow"):
			child.queue_free()
	if (hero_usable or ultimate_usable) and not _leader_menu_open:
		CardRenderUtil.add_playable_glow(_player_leader_view)
		_player_leader_view.get_child(_player_leader_view.get_child_count() - 1).set_meta("_glow", true)

	# --- Action zone (§ user request): End Turn by default; Cancel plus
	# whichever of {Hero Power+Ultimate, Attack Leader} applies to the
	# action actually in progress. Exactly one of these three states is
	# active at a time. ---
	var show_leader_menu := _leader_menu_open and can_act
	var show_attack_leader := not show_leader_menu and not targeting and _selected_attacker_id != -1
	var show_end_turn := not show_leader_menu and not targeting and _selected_attacker_id == -1

	_end_turn_btn.visible = show_end_turn
	_end_turn_btn.disabled = not can_act

	_attack_leader_btn.visible = show_attack_leader
	for child in _attack_leader_btn.get_children():
		child.queue_free()
	if show_attack_leader:
		var attacker := human.find_on_board(_selected_attacker_id)
		_attack_leader_btn.disabled = attacker == null or not CombatResolver.is_legal_leader_target(attacker, ai)
		if not _attack_leader_btn.disabled:
			CardRenderUtil.add_playable_glow(_attack_leader_btn)

	_hero_power_btn.visible = show_leader_menu
	_ultimate_btn.visible = show_leader_menu
	for child in _hero_power_btn.get_children():
		child.queue_free()
	if show_leader_menu and not _hero_power_btn.disabled:
		CardRenderUtil.add_playable_glow(_hero_power_btn)
	for child in _ultimate_btn.get_children():
		child.queue_free()
	if show_leader_menu and not _ultimate_btn.disabled:
		CardRenderUtil.add_playable_glow(_ultimate_btn)

	_cancel_btn.visible = show_leader_menu or targeting or _selected_attacker_id != -1

## Rebuilds a deck/discard pile widget's visual (§ user request: "a spot
## that shows the deck, the discard pile... fill the area as much as you
## can") — `container` is either a plain Control (the deck, not
## interactive) or a Button (the discard pile, kept clickable to open its
## existing list popup); either way this sizes the pile art to the
## container's own real, already-laid-out size (an equal share of the
## piles zone — see _build_piles_zone) instead of a fixed pixel size.
func _refresh_pile(container: Control, count: int) -> void:
	for child in container.get_children():
		child.queue_free()
	var size := _current_zone_size(container, FALLBACK_PILE_SIZE)
	var visual := CardRenderUtil.build_pile_visual(size, count)
	container.add_child(visual)
	LayoutUtil.fill_parent(visual)

## Rebuilds and repositions one side's Larva-pip column (§ LARVA_PIP_SIZE's
## own comment, and § _build_larva_overlay_column's — this now runs for
## both `_player_larva_row` and `_opponent_larva_row`) — `current` of the
## pips are filled (available to spend right now), the rest of the column
## (always at least MAX_LARVA_CAP, more if `max_larva` itself is ever
## pushed higher) are left empty. Every pip ignores the mouse (§ user
## request — the column floats on top of everything else and "should not
## interact with the areas"), same as the column itself.
##
## Position (§ user request: "directly next to the leader and discard
## pile... the opponent's larva column should be on the left side of the
## leader not the right side") is computed fresh every refresh from the
## real, already-laid-out rects of that side's Leader zone and discard
## pile — not from ratio math against the full window, which doesn't
## account for the Action Log panel narrowing the actual battlefield width
## when it's open. The column's vertical span is the union of those two
## rects (Leader zone above discard pile for the player, discard pile above
## Leader zone for the mirrored opponent), which is always entirely within
## that side's own half of the battlefield by construction — no separate
## "don't cross into the other side" check needed. `is_player` decides
## which side of that span the column sits on (right for the player, left
## for the opponent) and which pip ends up nearest the discard pile: pip 0
## is added LAST for the player so it lands flush against the bottom of the
## packed group (ALIGNMENT_END, discard sits below the Leader there), and
## FIRST for the opponent so it lands flush against the top (ALIGNMENT_BEGIN,
## discard sits above the Leader there, mirrored).
func _refresh_larva_pips(row: VBoxContainer, current: int, max_larva: int, is_player: bool) -> void:
	# remove_child (not just queue_free, which only detaches at end of
	# frame) so a pip about to be freed can never still count toward this
	# Container's own minimum-size calculation during a same-frame rebuild
	# — GameLog entries can trigger several refreshes per frame during
	# setup, and a stale pip surviving into that calculation was inflating
	# row's forced minimum size (and clamping the .size set below upward
	# with it) well past what the current pip count actually needs.
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var total := maxi(TurnManager.MAX_LARVA_CAP, max_larva)

	var leader_zone: Control = _player_leader_zone if is_player else _opponent_leader_zone
	var discard_btn: Control = _player_discard_btn if is_player else _opponent_discard_btn
	var leader_rect := leader_zone.get_global_rect()
	var discard_rect := discard_btn.get_global_rect()
	var top_y := minf(leader_rect.position.y, discard_rect.position.y)
	var bottom_y := maxf(leader_rect.position.y + leader_rect.size.y, discard_rect.position.y + discard_rect.size.y)
	var available_height := bottom_y - top_y
	var x := leader_rect.position.x + leader_rect.size.x + LARVA_COLUMN_GAP if is_player \
		else leader_rect.position.x - LARVA_COLUMN_GAP - LARVA_PIP_SIZE.x
	row.position = Vector2(x, top_y)
	row.size = Vector2(LARVA_PIP_SIZE.x, available_height)

	var separation := LARVA_PIP_SEPARATION_MAX
	if total > 1:
		var fit_separation := (available_height - LARVA_PIP_SIZE.y) / float(total - 1) - LARVA_PIP_SIZE.y
		separation = clampf(fit_separation, LARVA_PIP_SEPARATION_MIN, LARVA_PIP_SEPARATION_MAX)
	row.add_theme_constant_override("separation", int(separation))
	var have_art := ResourceLoader.exists(LARVA_PIP_EMPTY_PATH) and ResourceLoader.exists(LARVA_PIP_FILLED_PATH)
	var indices: Array = range(total)
	if is_player:
		indices.reverse()
	for i: int in indices:
		var filled := i < current
		if have_art:
			var pip := TextureRect.new()
			pip.texture = load(LARVA_PIP_FILLED_PATH if filled else LARVA_PIP_EMPTY_PATH)
			pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pip.custom_minimum_size = LARVA_PIP_SIZE
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(pip)
		else:
			var panel := Panel.new()
			panel.custom_minimum_size = LARVA_PIP_SIZE
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var style := StyleBoxFlat.new()
			style.set_corner_radius_all(int(LARVA_PIP_SIZE.x / 2.0))
			style.border_color = Color(0.75, 0.6, 0.95)
			style.set_border_width_all(2)
			style.bg_color = Color(0.6, 0.4, 0.9, 0.95) if filled else Color(0, 0, 0, 0)
			panel.add_theme_stylebox_override("panel", style)
			row.add_child(panel)

## Uniformly scales+centers an EnlargedCardView to fit `region` — shared by
## the docked hover-preview and the always-visible Leader panel (§ user
## request: the Leader should show its full rules text "always... since
## it's always in that state on the field", not just on hover). Uniform
## scale rather than stretching keeps everything inside proportional
## (EnlargedCardView's own internal layout is already anchor/percentage-
## based, so this is the only transform needed to resize it cleanly).
func _fit_view_to_region(view: EnlargedCardView, region: Vector2) -> void:
	var native: Vector2 = EnlargedCardView.SIZE
	var scale_factor: float = clampf(minf(region.x / native.x, region.y / native.y), 0.1, 4.0)
	view.scale = Vector2(scale_factor, scale_factor)
	view.position = (region - native * scale_factor) * 0.5

## Refreshes the always-visible Leader panel's content and fit. `btn`'s own
## size mirrors the zone's (it fills it — see _build_leader_zone), so it
## doubles as the "how much room is there" read — the card view now gets
## the whole thing (§ user request: no more separate info line reserving
## space below it). `current_health` overrides the life-total badge, which
## would otherwise show the Leader's *printed* starting_health like every
## other context that renders a Leader (Collection, the hover preview
## elsewhere) — here specifically it should track the Leader's actual
## current health, going up and down as the match plays out.
func _refresh_leader_panel(btn: Button, view: EnlargedCardView, leader_data: LeaderData, current_health: int) -> void:
	var tex := CardDatabase.get_illustration_texture(leader_data)
	view.set_content(leader_data, tex, 0, CardRenderUtil.card_full_text(leader_data), "", current_health)
	_fit_view_to_region(view, _current_zone_size(btn, FALLBACK_LEADER_ZONE_SIZE))

## Hover handler for a Leader panel, wired once per side in
## _build_leader_zone rather than per-refresh like every other card (the
## Leader panel button is persistent instead of rebuilt each time, and
## _wire_docked_preview's closure would capture stale values if reconnected
## on top of itself every refresh instead of leaving one connection that
## reads the current Leader fresh at hover time). Shows current health too,
## same as the always-visible panel, for consistency.
func _show_leader_preview(is_player: bool) -> void:
	var player := GameState.players[HUMAN] if is_player else GameState.players[AI]
	var data: LeaderData = player.leader.data
	var tex := CardDatabase.get_illustration_texture(data)
	_show_docked_preview(data, tex, 0, CardRenderUtil.card_full_text(data), "", player.health)

## Wires the docked hover-preview (§ user request: "instead of showing it
## near the card you are hovering over") onto a freshly-built card widget —
## same closure-capture pattern CardRenderUtil.wire_hover_preview uses,
## just targeting the docked panel instead of a floating popup. Safe to
## call every refresh since these widgets (unlike the Leader panel) are
## torn down and rebuilt fresh each time.
func _wire_docked_preview(widget: Control, card_data: CardData, tex: Texture2D, cost: int, bbcode_text: String, badge_text: String) -> void:
	widget.mouse_entered.connect(_show_docked_preview.bind(card_data, tex, cost, bbcode_text, badge_text, -1))
	widget.mouse_exited.connect(_hide_docked_preview)

## Shows a card in the docked preview panel, scaled to fill whatever the
## panel's real proportional region turns out to be (§ user request: the
## preview panel "scale[s] to fill the region") rather than staying a fixed
## size. `life_override` (a Leader's current health) defaults to -1 (use
## the card's own printed stat) for every non-Leader caller.
func _show_docked_preview(card_data: CardData, tex: Texture2D, cost: int, bbcode_text: String, badge_text: String, life_override: int = -1) -> void:
	_preview_view.set_content(card_data, tex, cost, bbcode_text, badge_text, life_override)
	_fit_view_to_region(_preview_view, _current_zone_size(_preview_dock, FALLBACK_LEADER_ZONE_SIZE))
	_preview_view.visible = true

func _hide_docked_preview() -> void:
	_preview_view.visible = false
	_preview_view.stop_animation()

## Creature card sizing (§ user request: "current sizes... seems ok, we can
## start to shrink them if we get too many... so they can all still be
## shown"): the natural size as long as everything fits `available_width`
## without it, otherwise shrunk down toward the floor — below the floor,
## the board's existing horizontal scrolling takes over instead of
## shrinking further.
func _creature_card_size(available_width: float, count: int) -> Vector2:
	if count <= 0 or available_width <= 1.0:
		return CREATURE_CARD_NATURAL_SIZE
	var natural_total: float = CREATURE_CARD_NATURAL_SIZE.x * count + CREATURE_ROW_SPACING * maxi(count - 1, 0)
	if natural_total <= available_width:
		return CREATURE_CARD_NATURAL_SIZE
	var fit: float = (available_width - CREATURE_ROW_SPACING * maxi(count - 1, 0)) / count
	var size: float = maxf(fit, CREATURE_CARD_MIN_SIZE.x)
	return Vector2(size, size)

func _render_row(row: HBoxContainer, board: Array[CardInstance], friendly: bool, board_zone: Control) -> void:
	for child in row.get_children():
		child.queue_free()
	var visible_board: Array[CardInstance] = []
	for c: CardInstance in board:
		if not friendly and _ai_reveal_active and not _ai_reveal_set.has(c.instance_id):
			continue # § user request — not revealed by the AI turn replay yet
		visible_board.append(c)
	var card_size := _creature_card_size(board_zone.size.x, visible_board.size())
	for c: CardInstance in visible_board:
		row.add_child(_make_creature_widget(c, friendly, card_size))

## Whether a board creature widget should show the "usable" glow (§ user
## request: "activate abilities, such as clicking on cards that are able to
## be used, and denote that by having a glowing outline") — reuses the same
## legality checks _on_board_creature_pressed itself validates against, so
## the glow can never promise something a click would then reject:
## - mid hand-card/Hero-Power/Ultimate targeting: glows legal targets on
##   the required side (friendly or enemy) that also pass any extra filter
##   (e.g. Caterpillar Searcher only wants face-down creatures).
## - otherwise: a friendly creature glows if it can attack right now; an
##   enemy creature glows only once an attacker is already selected and
##   this one is a legal target for it.
func _creature_usable_glow(c: CardInstance, friendly: bool) -> bool:
	if _busy or GameState.active_player_index != HUMAN or GameState.is_over:
		return false
	if _selected_hand_index != -1 or _pending_power_kind != "":
		if friendly != (_pending_target_side == "friendly"):
			return false
		return c.is_alive() and _passes_extra_filter(_pending_target_effect_id, c)
	if friendly:
		return CombatResolver.can_attack(c)
	if _selected_attacker_id != -1:
		var attacker := GameState.players[HUMAN].find_on_board(_selected_attacker_id)
		return attacker != null and CombatResolver.is_legal_creature_target(attacker, c)
	return false

func _render_hive_row(row: HBoxContainer, hive_zone: Array[CardInstance], friendly: bool) -> void:
	for child in row.get_children():
		child.queue_free()
	for c: CardInstance in hive_zone:
		if not friendly and _ai_reveal_active and not _ai_reveal_set.has(c.instance_id):
			continue # § user request — not revealed by the AI turn replay yet
		row.add_child(_make_hive_widget(c))
	row.get_parent().visible = not hive_zone.is_empty()

func _make_hive_widget(c: CardInstance) -> Control:
	var btn := Button.new()
	btn.set_meta("instance_id", c.instance_id) # § lets _find_widget_by_instance locate this for the AI turn-animation hook
	btn.custom_minimum_size = Vector2(160, 90)
	var tex := CardRenderUtil.style_card_face(btn, c.data, c.data.cost)
	_wire_docked_preview(btn, c.data, tex, c.data.cost, CardRenderUtil.card_full_text(c.data), "")
	return btn

## Player's hand: fanned out along the bottom (§ user request — "should
## feel like moving real cards"), each card a free-floating widget
## positioned/rotated by _position_hand_slot rather than laid out by a
## Container, so it can overlap its neighbors and be dragged freely. Cards
## render in _hand_display_order (cosmetic — see its declaration) instead
## of raw hand[] order. Clicking no longer plays a card at all (§ user
## request: dragging is the only way to play one) — _wire_hand_drag is the
## only interaction wired onto these widgets now; _on_hand_card_pressed is
## still the function that actually plays one, just invoked from a
## completed drag (_finish_hand_drag) instead of a Button's pressed signal.
## Hand card size (§ user request: hand cards "spread... to fill the
## area") — derived from the hand zone's own real, already-laid-out height
## instead of a fixed pixel size, at roughly a real card's aspect ratio.
func _hand_card_size(tray_size: Vector2) -> Vector2:
	var h: float = maxf(tray_size.y - 20.0, 60.0)
	return Vector2(h * HAND_CARD_ASPECT, h)

func _render_hand() -> void:
	for child in _player_hand.get_children():
		child.queue_free()
	var human := GameState.players[HUMAN]
	_sync_hand_display_order(human.hand)
	var n := _hand_display_order.size()
	var tray_size := _current_zone_size(_player_hand, FALLBACK_HAND_ZONE_SIZE)
	var card_size := _hand_card_size(tray_size)
	for slot in range(n):
		var iid: int = _hand_display_order[slot]
		var card := _find_in_hand(human.hand, iid)
		if card == null:
			continue
		var cost := CostCalculator.calculate_cost(card.data, human.leader.data)
		var btn := Button.new()
		btn.custom_minimum_size = card_size
		btn.size = card_size
		btn.pivot_offset = card_size * 0.5
		var tex := CardRenderUtil.style_card_face(btn, card.data, cost)
		var can_play := _can_play_from_hand(card, cost, human)
		if can_play:
			CardRenderUtil.add_playable_glow(btn)
		else:
			btn.modulate *= Color(0.55, 0.55, 0.55)
		var badge_text := ""
		if card.data is CreatureData:
			var cd := card.data as CreatureData
			badge_text = "%d/%d" % [cd.attack, cd.health]
			CardRenderUtil.add_corner_badge(btn, badge_text)
		_wire_docked_preview(btn, card.data, tex, cost, CardRenderUtil.card_full_text(card.data), badge_text)
		_position_hand_slot(btn, slot, n, tray_size, card_size)
		_wire_hand_drag(btn, iid, can_play)
		_player_hand.add_child(btn)

## The opponent's hand (§ user request — mirrored HUD strip): the same fan
## treatment as the player's, but face-down (hidden information) and with
## no interactivity at all — no drag, no hover-preview.
func _render_opponent_hand() -> void:
	for child in _opponent_hand.get_children():
		child.queue_free()
	var n := GameState.players[AI].hand.size()
	var tray_size := _current_zone_size(_opponent_hand, FALLBACK_HAND_ZONE_SIZE)
	var card_size := _hand_card_size(tray_size)
	for slot in range(n):
		var back := CardRenderUtil.build_card_back(card_size)
		back.pivot_offset = card_size * 0.5
		_position_hand_slot(back, slot, n, tray_size, card_size)
		_opponent_hand.add_child(back)

func _find_in_hand(hand: Array[CardInstance], iid: int) -> CardInstance:
	for c: CardInstance in hand:
		if c.instance_id == iid:
			return c
	return null

## Keeps _hand_display_order in sync with the actual hand contents —
## appends newly-drawn cards' instance_ids at the end, drops any that left
## the hand (played/discarded) — without disturbing the relative order of
## cards still present, which is what makes a manual drag-reorder stick
## between refreshes instead of resetting to hand[] order every time.
func _sync_hand_display_order(hand: Array[CardInstance]) -> void:
	var live_ids: Array[int] = []
	for c: CardInstance in hand:
		live_ids.append(c.instance_id)
	_hand_display_order = _hand_display_order.filter(func(iid: int) -> bool: return live_ids.has(iid))
	for iid in live_ids:
		if not _hand_display_order.has(iid):
			_hand_display_order.append(iid)

## Whether a hand card can actually be played right now — the same gate
## _render_hand used to bake into Button.disabled, now also driving the
## glow cue (§ user request: "denote that by having a glowing outline of
## what cards are able to be used") and whether a lifted-out-of-hand drag
## resolves as a play attempt at all (see _finish_hand_drag). Gear needs a
## friendly creature to equip onto, mirroring _on_hand_card_pressed's own
## check — no point glowing a Gear card as playable if it has nowhere to go.
func _can_play_from_hand(card: CardInstance, cost: int, human: PlayerState) -> bool:
	if _busy or GameState.active_player_index != HUMAN or _selected_hand_index != -1 or _pending_power_kind != "":
		return false
	if cost > human.current_larva:
		return false
	if card.data.card_type == CardTypes.GEAR and human.board.is_empty():
		return false
	return true

## Fan slot geometry, shared between rendering (_position_hand_slot) and
## resolving a reorder drop (_reorder_hand_to) so the two can never drift
## out of sync with each other. Takes `card_width` explicitly (rather than
## reading a fixed constant) since hand card size is now derived from the
## tray's own real height (§ user request — see _hand_card_size).
func _hand_slot_layout(n: int, tray_width: float, card_width: float) -> Dictionary:
	var overlap := card_width * 0.55
	var natural_spacing := card_width - overlap
	var total_span := natural_spacing * maxi(n - 1, 0)
	var max_span := tray_width - card_width - 40.0
	var spacing: float = natural_spacing if (n <= 1 or total_span <= max_span) else max_span / maxi(n - 1, 1)
	var start_x: float = (tray_width - (card_width + spacing * maxi(n - 1, 0))) * 0.5
	return {"spacing": spacing, "start_x": start_x}

## A gentle arc (§ user request: cards "fanned out") — the middle of the
## hand sits a little higher than the edges, like a real held hand of cards.
func _hand_slot_rise(offset_from_mid: float, n: int) -> float:
	if n <= 1:
		return 0.0
	var t: float = offset_from_mid / (n * 0.5)
	return (1.0 - t * t) * 18.0

func _hand_slot_position(slot: int, n: int, tray_size: Vector2, card_size: Vector2) -> Vector2:
	var tray_width: float = maxf(tray_size.x, 400.0)
	var layout := _hand_slot_layout(n, tray_width, card_size.x)
	var mid: float = (n - 1) / 2.0
	var offset_from_mid: float = slot - mid
	var x: float = layout["start_x"] + layout["spacing"] * slot
	var y: float = tray_size.y - card_size.y - 10.0 - _hand_slot_rise(offset_from_mid, n)
	return Vector2(x, y)

func _hand_slot_rotation(slot: int, n: int) -> float:
	var mid: float = (n - 1) / 2.0
	return deg_to_rad(clampf((slot - mid) * 4.0, -22.0, 22.0))

func _position_hand_slot(btn: Control, slot: int, n: int, tray_size: Vector2, card_size: Vector2) -> void:
	btn.position = _hand_slot_position(slot, n, tray_size, card_size)
	btn.rotation = _hand_slot_rotation(slot, n)
	btn.z_index = slot

## Wires the free-drag gesture onto a hand card (§ user request: "pick up
## cards and place them in the play area to play them" — this is now the
## ONLY way to play a card; clicking does nothing). Tracking the drag itself
## happens in _input once _drag_btn is set, since gui_input alone would
## stop reporting motion the instant the mouse leaves this widget's own rect.
func _wire_hand_drag(btn: Control, instance_id: int, can_play: bool) -> void:
	btn.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin_hand_drag(btn, instance_id, can_play, event.global_position))

func _begin_hand_drag(btn: Control, instance_id: int, can_play: bool, mouse_global: Vector2) -> void:
	if _busy or _drag_btn != null:
		return
	_hide_docked_preview()
	_drag_btn = btn
	_drag_instance_id = instance_id
	_drag_can_play = can_play
	_drag_grab_offset = mouse_global - btn.global_position
	btn.top_level = true # independent of the hand tray's own transform while it follows the mouse
	btn.z_index = 500
	btn.rotation = 0.0
	btn.scale = Vector2(1.12, 1.12)

## Global input while a hand card is being dragged (§ user request — cards
## should "feel like moving real cards"): follows the mouse until release,
## then _finish_hand_drag decides whether that was a play or a reorder.
## Only main_ui itself needs this (there's exactly one drag at a time), so
## it's cheap to leave this a near-instant no-op the rest of the time.
func _input(event: InputEvent) -> void:
	# § user request: Escape opens a small in-match menu (log toggle +
	# concede) — only meaningful while a match is actually on screen.
	if _match_view.visible and event.is_action_pressed("ui_cancel"):
		_toggle_pause_menu()
		return
	if _drag_btn == null:
		return
	if event is InputEventMouseMotion:
		_drag_btn.global_position = event.global_position - _drag_grab_offset
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_hand_drag(event.global_position)

## Resolves a completed hand-card drag. Lifting the card above the hand
## tray's own top edge by HAND_PLAY_LIFT_THRESHOLD or more plays it
## (reusing _on_hand_card_pressed — the exact same targeting/Gear/Legend
## Rule flow the old click path used, just triggered by a drop instead of a
## press); anything else (not lifted far enough, or the card wasn't
## playable to begin with) is treated as a reorder within the hand instead
## of being discarded outright, so an unaffordable card can still be
## shuffled around. Either way the dragged widget itself is thrown away —
## _refresh() (called either directly or via the tween below) rebuilds every
## hand widget fresh in its resolved position regardless of outcome.
func _finish_hand_drag(mouse_global: Vector2) -> void:
	var btn := _drag_btn
	var instance_id := _drag_instance_id
	var can_play := _drag_can_play
	_drag_btn = null
	_drag_instance_id = -1

	if can_play and not _busy and GameState.active_player_index == HUMAN:
		var tray_top: float = _player_hand.get_global_rect().position.y
		if mouse_global.y < tray_top - HAND_PLAY_LIFT_THRESHOLD:
			var human := GameState.players[HUMAN]
			var idx := -1
			for i in range(human.hand.size()):
				if human.hand[i].instance_id == instance_id:
					idx = i
					break
			if idx != -1:
				_on_hand_card_pressed(idx)
				return

	_reorder_hand_to(instance_id, mouse_global.x)
	var slot := _hand_display_order.find(instance_id)
	var n := _hand_display_order.size()
	if slot != -1 and btn != null and is_instance_valid(btn):
		var tray_size := _current_zone_size(_player_hand, FALLBACK_HAND_ZONE_SIZE)
		var card_size := _hand_card_size(tray_size)
		var target := _player_hand.get_global_rect().position + _hand_slot_position(slot, n, tray_size, card_size)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "global_position", target, 0.15)
		tween.tween_property(btn, "rotation", _hand_slot_rotation(slot, n), 0.15)
		tween.tween_property(btn, "scale", Vector2.ONE, 0.15)
		tween.set_parallel(false)
		tween.tween_callback(_refresh)
	else:
		_refresh()

## Moves the dragged card to whichever fan slot its drop point landed
## closest to (§ user request: hand cards "should be able to be reordered
## simply by dragging them into a different order... should feel like
## moving real cards") — purely a _hand_display_order change, since hand
## order has no gameplay meaning here.
func _reorder_hand_to(instance_id: int, drop_x: float) -> void:
	var n := _hand_display_order.size()
	if n <= 1:
		return
	var tray_rect := _player_hand.get_global_rect()
	var local_x := drop_x - tray_rect.position.x
	var tray_size := _current_zone_size(_player_hand, FALLBACK_HAND_ZONE_SIZE)
	var card_size := _hand_card_size(tray_size)
	# Same width floor _hand_slot_position uses (§ bug caught by a throwaway
	# diagnostic) — without it, the two disagree on every slot's center
	# whenever the tray hasn't been laid out to a real width yet (0), and a
	# drop would never match the slot _position_hand_slot actually drew it at.
	var layout := _hand_slot_layout(n, maxf(tray_rect.size.x, 400.0), card_size.x)
	var spacing: float = layout["spacing"]
	var start_x: float = layout["start_x"]
	var best_slot := 0
	var best_dist := INF
	for slot in range(n):
		var center := start_x + spacing * slot + card_size.x * 0.5
		var dist := absf(local_x - center)
		if dist < best_dist:
			best_dist = dist
			best_slot = slot
	var from_slot := _hand_display_order.find(instance_id)
	if from_slot == -1 or from_slot == best_slot:
		return
	_hand_display_order.remove_at(from_slot)
	_hand_display_order.insert(best_slot, instance_id)

func _make_creature_widget(c: CardInstance, friendly: bool, card_size: Vector2) -> Control:
	var box := VBoxContainer.new()
	box.set_meta("instance_id", c.instance_id) # § lets _find_widget_by_instance locate this for the AI turn-animation hook
	var btn := Button.new()
	btn.custom_minimum_size = card_size
	var tex := CardRenderUtil.style_card_face(btn, c.data, c.data.cost)
	if c.is_exhausted():
		btn.modulate *= Color(0.6, 0.6, 0.6)
	if c.instance_id == _selected_attacker_id:
		btn.modulate *= Color(1.3, 1.3, 0.6) # gold tint — the only "selection" cue left now that the base card has no text (§ user request)
	if _creature_usable_glow(c, friendly):
		CardRenderUtil.add_playable_glow(btn)
	btn.pressed.connect(_on_board_creature_pressed.bind(c, friendly))
	box.add_child(btn)

	var badge_text := ""
	if c.data is CreatureData:
		badge_text = "%d/%d" % [c.current_attack, c.current_health()]
		CardRenderUtil.add_corner_badge(btn, badge_text)
	_wire_docked_preview(btn, c.data, tex, c.data.cost, _creature_bbcode(c), badge_text)

	if friendly and c.is_face_down and c.true_data != null and c.true_data.ambush.get("flip_trigger", "") == "paid":
		var cost := int(c.true_data.ambush.get("flip_cost", 0))
		var flip_btn := Button.new()
		flip_btn.text = "Flip (%d)" % cost
		flip_btn.disabled = _busy or GameState.active_player_index != HUMAN or cost > GameState.players[HUMAN].current_larva
		flip_btn.pressed.connect(_on_flip_ambush_pressed.bind(c.instance_id))
		box.add_child(flip_btn)
	return box

const TEMP_KEYWORD_COLOR := "#ffcc33"

## Hover-preview body text for a live board creature (§ user request: the
## base widget shows only art + name/cost/ATK-DEF decorations — this is
## everything else, shown only on hover). ATK/DEF is deliberately excluded
## here since the corner badge already covers it; name/cost are likewise
## shown only as the overlay's own art-area decorations.
func _creature_bbcode(c: CardInstance) -> String:
	var lines: Array[String] = [_bbcode_escape(CardRenderUtil.type_line(c.data))]
	if c.poison_counters > 0:
		lines.append("Poison x%d" % c.poison_counters)
	if c.data.text != "":
		lines.append(_bbcode_escape(CardRenderUtil.format_rules_text(c.data.text)))
	if not c.temp_keywords.is_empty():
		lines.append("[color=%s]%s (until your next turn)[/color]" % [TEMP_KEYWORD_COLOR, _bbcode_escape(", ".join(c.temp_keywords))])
	if not c.attached_gear.is_empty():
		var gear_names := c.attached_gear.map(func(g: CardInstance) -> String: return g.display_name())
		lines.append("Gear: " + _bbcode_escape(", ".join(gear_names)))
	if c.is_exhausted() and c.is_alive():
		lines.append("[color=#999999](Exhausted — can't block)[/color]")
	if not c.is_alive():
		lines.append("(dead)")
	if c.instance_id == _selected_attacker_id:
		lines.append("[SELECTED]")
	return "\n".join(lines)

func _bbcode_escape(text: String) -> String:
	return text.replace("[", "(").replace("]", ")")
