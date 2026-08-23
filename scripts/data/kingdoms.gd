class_name Kingdoms
extends RefCounted
## String constants for the six Kingdoms (§3), flavor-named per the user's
## house naming. These are the actual values stored in every card's
## `kingdoms` array and compared throughout matching/filtering/display
## logic, so renaming here is the single source of truth — nothing else
## should hardcode a Kingdom name as a literal string. Colorless is
## represented by an empty kingdoms array on a card, not by this constant,
## except where a definition needs to reference it explicitly (e.g. Leader
## restrictions).

const WHITE := "The Monogyne"
const GREEN := "The Buprestidae"
const BLACK := "The Arachnida"
const BLUE := "The Metamorphae"
const RED := "The Triatoma"
const COLORLESS := "The Insecta"

const ALL: Array[String] = [WHITE, GREEN, BLACK, BLUE, RED]
