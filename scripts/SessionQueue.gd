class_name SessionQueue
## SessionQueue.gd
## Hands one queued treatment across a scene reload, so a participant can play
## T1 and then T2 in one sitting without returning to the main menu.
##
## Why a reload at all: CityGrid builds the map exactly once per scene
## (CONNECT_ONE_SHOT on round_started, CityGrid.gd), so resetting in place would
## leave the grid bound to the previous CityNetwork instance and only appear to
## work because the topology happens to be identical. Reloading is the
## lifecycle the rest of the scene already assumes, which leaves the problem of
## carrying the participant's identity across it. That is all this file does.
##
## Static rather than a field on ResearchConfig, which documents itself as
## holding study-design PARAMETERS; this is mutable runtime state, and mixing
## the two would undo the separation that file exists to maintain. Not on
## GameManager either, which owns model state rather than session bookkeeping.
##
## Statics live with the script resource, which stays loaded across a scene
## reload. That is exactly the lifetime needed here and no longer: nothing is
## written to disk, so a queued treatment cannot survive the app closing.

static var _pending: bool = false
static var _treatment: int = 0
static var _num_players: int = 1
static var _participant_ids: Array[String] = []
static var _group_id: String = ""
## The session this one follows on from, so the two folders a single sitting
## produces can be recognised as one sitting rather than inferred from adjacent
## timestamps. T1-then-T2 back to back carries an order and fatigue effect that
## the same two treatments played on separate days does not, and that is a
## difference the analysis has to be able to see.
static var _from_session_id: String = ""


## Queues the treatment to run immediately after the current scene reloads.
static func queue_next(treatment: int, participant_ids: Array, group_id: String,
		num_players: int, from_session_id: String = "") -> void:
	_pending = true
	_treatment = treatment
	_num_players = num_players
	_group_id = group_id
	_from_session_id = from_session_id
	_participant_ids = []
	for id in participant_ids:
		_participant_ids.append(str(id))


static func has_pending() -> bool:
	return _pending


## Reads the queued session AND clears it in the same call, so a queued
## treatment can only ever start once. A reload that happens for any other
## reason afterwards falls through to the main menu as normal, rather than
## silently replaying the treatment that was already played.
static func take() -> Dictionary:
	var out := {
		"treatment": _treatment,
		"num_players": _num_players,
		"participant_ids": _participant_ids.duplicate(),
		"group_id": _group_id,
		"from_session_id": _from_session_id,
	}
	clear()
	return out


static func clear() -> void:
	_pending = false
	_treatment = 0
	_num_players = 1
	_participant_ids = []
	_group_id = ""
	_from_session_id = ""
