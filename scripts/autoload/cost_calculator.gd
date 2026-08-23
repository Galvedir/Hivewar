class_name CostCalculator
extends RefCounted
## Kingdom Cost Matching (§4): printed cost, plus a +2 Larva surcharge if
## none of the card's Kingdoms match the active Leader's Kingdoms. Stateless,
## so this is a plain utility class rather than an autoload — call it
## directly wherever a card's actual Larva cost needs to be known
## (hand UI, AI evaluation, TurnManager.play_card).

const OFF_KINGDOM_SURCHARGE := 2

static func calculate_cost(card_data: CardData, leader_data: LeaderData) -> int:
	if card_data.matches_kingdom(leader_data.kingdoms):
		return card_data.cost
	return card_data.cost + OFF_KINGDOM_SURCHARGE
