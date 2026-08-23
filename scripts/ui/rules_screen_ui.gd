class_name RulesScreenUI
extends Control
## Rules/keyword reference screen (§ user request): a plain-text summary of
## the core rules plus every keyword's effect, reachable from both the main
## menu and the Deck Builder. Static content — no live game state — so it's
## just one big scrollable RichTextLabel rather than a card-widget grid.

signal closed

const RULES_TEXT := """
[b]The Basics[/b]
Each player commands a Leader (sets starting health, grants a Hero Power and a once-per-game Ultimate) and a deck of 40-60 cards. You start with 1 Larva (your resource); your maximum grows by 1 each turn you take, capped at 10, and refills fully each turn. Unspent Larva does not carry over. All cards are played at sorcery speed — only on your own turn.

[b]Kingdoms[/b]
Every card belongs to one or two Kingdoms, or none (Colorless). Your Leader's Kingdom(s) never restrict what you can put in your deck, but a card that shares none of your Leader's Kingdoms costs +2 Larva to play. Colorless cards and cards matching at least one of your Leader's Kingdoms cost their printed amount.

[b]Combat[/b]
A creature can't attack the turn it enters play, unless it has Swift. Each attack targets either the enemy Leader or a specific enemy creature directly — no permission needed for creature-vs-creature attacks. If the defender controls a Guard creature, the Leader can't be targeted at all (unless the attacker has Pierce) — you must attack a Guard instead. If there's no Guard, the defender may optionally intercept a Leader-targeted attack with one creature (Flying attackers can only be intercepted by Flying or Reach creatures). A creature that has attacked this turn is Exhausted and can't be chosen as an optional blocker until its controller's next turn — though it can still be forced to fight as someone's Guard.

[b]Legend Rule[/b]
You may run up to 4 copies of a Legendary card, but only one copy of a given Legendary name may be in play on your side at a time — playing a second prompts you to choose which one to keep.

[b]Decking Out[/b]
If you ever try to draw from an empty deck, you lose instantly.
"""

const KEYWORDS_TEXT := """
[b]Guard[/b] — While you control a Guard creature, your Leader can't be attacked directly; attackers must target a Guard instead (your choice which, if you have several), unless the attacker has Pierce.

[b]Flying[/b] — Can attack ground or flying targets freely. A ground creature without Reach can't choose a Flying creature as its direct target, nor block one.

[b]Reach[/b] — A ground creature with Reach can block Flying attackers and be targeted by them, without being Flying itself.

[b]Poison[/b] — Combat damage from this creature also applies a stacking Poison counter. At the end of each turn, poisoned creatures take damage equal to their counters. Leaders are immune to Poison.

[b]Venomstrike[/b] — Kills any creature it damages in combat outright, regardless of remaining health — unless that creature has Chitin.

[b]Chitin[/b] — Immune to Poison and Venomstrike entirely.

[b]Lifesteal[/b] — Damage this creature deals also heals its controller's Leader by the same amount.

[b]Swift[/b] — Can attack the turn it's played, ignoring summoning sickness.

[b]Stealth[/b] — Can't be targeted, attacked, or blocked until something with Keen Sight is involved.

[b]Keen Sight[/b] — Can target, attack, and block Stealth creatures as if they weren't Stealthed.

[b]Decay[/b] — Triggers an effect when this creature dies.

[b]Pierce[/b] — Ignores Guard, attacking the Leader (or anything else) directly even when a Guard is in play. Can't be intercepted by an optional block.

[b]Trample[/b] — Excess combat damage beyond what's needed to kill its target carries through to the Leader (or the next Guard, if any).

[b]Ambush[/b] — Printed as a two-sided card: a weak, generic face-down side that's what gets played and what the opponent sees, and a true face-up side that's revealed later. How it flips varies by card: on attacking, for a Larva cost paid any time on your turn, or automatically under a stated condition (like at the start of your next turn).

[b]Exhausted[/b] — A creature that attacked this turn. Can't be chosen as an optional blocker, but can still be forced to fight as a Guard.
"""

func _ready() -> void:
	LayoutUtil.fill_parent(self)
	_build_ui()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	LayoutUtil.fill_parent(root)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< Back"
	back_btn.pressed.connect(func() -> void: closed.emit())
	top.add_child(back_btn)
	var title := Label.new()
	title.text = "Rules & Keywords"
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(900, 0)
	content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	var rules_label := RichTextLabel.new()
	rules_label.bbcode_enabled = true
	rules_label.fit_content = true
	rules_label.scroll_active = false
	rules_label.text = RULES_TEXT.strip_edges()
	content.add_child(rules_label)

	var keywords_title := Label.new()
	keywords_title.text = "Keywords"
	keywords_title.add_theme_font_size_override("font_size", 20)
	content.add_child(keywords_title)

	var keywords_label := RichTextLabel.new()
	keywords_label.bbcode_enabled = true
	keywords_label.fit_content = true
	keywords_label.scroll_active = false
	keywords_label.text = KEYWORDS_TEXT.strip_edges()
	content.add_child(keywords_label)
