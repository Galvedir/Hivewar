class_name Keywords
extends RefCounted
## String constants for the v1 keyword list (§6). New keywords should be
## added here plus wired into CombatResolver/EffectResolver as generic
## rules, per the extensibility note at the end of §6.

const GUARD := "Guard"
const FLYING := "Flying"
const REACH := "Reach"
const POISON := "Poison"
const CHITIN := "Chitin"
const LIFESTEAL := "Lifesteal"
const SWIFT := "Swift"
const STEALTH := "Camouflage" # constant name kept as STEALTH for code stability; display string renamed per user request
const KEEN_SIGHT := "Keen Sight"
const DECAY := "Decay"
const SWARM := "Swarm"
const PIERCE := "Pierce"
const TRAMPLE := "Trample"
const AMBUSH := "Morph" # unused as a granted keyword (the real mechanic runs through CreatureData.ambush, not this constant) — kept for completeness; display string renamed per user request
const VENOMSTRIKE := "Venomstrike" # kills any creature it damages in combat, unless that creature has Chitin
const COLONY := "Colony" # other friendly creatures sharing a creature_type with this one get +0/+1 while it's in play; leaves with it
