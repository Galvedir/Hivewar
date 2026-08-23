extends Node
## Autoload: a single running feed of everything that happens in a match —
## cards played, targets chosen, attacks declared, damage dealt, deaths,
## Hero Power/Ultimate/Ambush activations, turn changes, and the game's
## outcome. Every other autoload calls log() as actions resolve, so the UI
## can render a live feed without polling state diffs. `kind` is a light
## style hint ("system"/"action"/"combat"/"chat") — "chat" is reserved for
## when this doubles as a real chat feed in a networked future (§11 Phase 5).

signal entry_added(text: String, kind: String)

var entries: Array[Dictionary] = [] # [{text: String, kind: String}]

func log(text: String, kind: String = "action") -> void:
	entries.append({"text": text, "kind": kind})
	entry_added.emit(text, kind)

func clear() -> void:
	entries.clear()
