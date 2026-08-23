# Art Directory

Placeholder art directory structure (§14) for Hivewar. Everything in the game today is programmatically-drawn Control nodes with flat Kingdom-tinted colors — no textures are wired in yet. Drop files in following the naming conventions below, and a future pass can load them by convention (`card.id` / `leader.id` / keyword name → filename) instead of needing a manual mapping table per asset.

## Layout

```
art/
  cards/
    frames/         Per-Kingdom card frame/border art
    illustrations/  Per-card artwork
    icons/          Small keyword icons (shown next to ability text)
  leaders/           Leader portraits
  ui/
    buttons/         Button backgrounds / 9-patch textures
    panels/          Panel backgrounds, borders, popups
    backgrounds/      Screen backgrounds (menu, match table, etc.)
  fonts/             Custom fonts, if any
```

## Naming conventions

**Card illustrations** (`art/cards/illustrations/`) — name each file after the card's `id` from `data/card_definitions.gd`, e.g.:
- `worker_termite.png`
- `queens_guardian_beetle.png`
- `black_widow_matriarch.png`

**Card frames** (`art/cards/frames/`) — one per Kingdom, matching `scripts/data/kingdoms.gd`:
- `white.png`, `green.png`, `black.png`, `blue.png`, `red.png`, `colorless.png`

Ambush cards (§8) additionally need a distinct face-down frame/back, since the UI must show it's an unrevealed card:
- `ambush_facedown.png`

**Leader portraits** (`art/leaders/`) — name each file after the Leader's `id` from `data/leader_definitions.gd`, e.g.:
- `queen_amara.png`
- `karneth_bloodfang.png`

There are 18 Leaders total across White/Green/Black/Blue/Red (3 each) plus 3 dual-Kingdom Leaders — see `data/leader_definitions.gd` for the full list of ids.

**Keyword icons** (`art/cards/icons/`) — name each file after the keyword, lowercase with underscores for the one two-word keyword, matching `scripts/data/keywords.gd`:
- `guard.png`, `flying.png`, `reach.png`, `poison.png`, `chitin.png`, `lifesteal.png`, `swift.png`, `stealth.png`, `keen_sight.png`, `decay.png`, `swarm.png`, `pierce.png`, `trample.png`, `ambush.png`

**UI chrome** (`art/ui/`) — no fixed naming convention yet since nothing references these by id; use descriptive names (`button_primary.png`, `panel_dark.png`, `background_menu.png`, etc.) and a future pass will wire them into `scripts/ui/*.gd` by hand.

## What's not art-driven yet

Card/Leader/keyword *text* (name, cost, stats, rules text) always comes from `data/card_definitions.gd` and `data/leader_definitions.gd` — art only supplies the visual frame/illustration/icon around it. Missing files should fail gracefully (fall back to the current flat-color placeholder) rather than error, once a loader is wired in.
