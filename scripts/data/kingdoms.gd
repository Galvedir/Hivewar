class_name Kingdoms
extends RefCounted
## String constants for the six Kingdoms (§3). Colorless is represented by
## an empty kingdoms array on a card, not by this constant, except where a
## definition needs to reference it explicitly (e.g. Leader restrictions).

const WHITE := "White"
const GREEN := "Green"
const BLACK := "Black"
const BLUE := "Blue"
const RED := "Red"
const COLORLESS := "Colorless"

const ALL: Array[String] = [WHITE, GREEN, BLACK, BLUE, RED]
