extends SceneTree
## Headless generator for a complete sample study, written to user://research_sessions/.
##
## Drives the real game through the same GameManager and DataLogger calls that
## scenes/main.gd makes, in the same order, so the output is produced by the
## shipped model and logging paths rather than by a parallel implementation of
## them. Nothing here reimplements routing, costing or metrics.
##
## Run:
##   godot --headless --path <project> --script res://tools/generate_sample_logs.gd
##
## Produces 7 sessions: T1 and T2 for each of three participants, then one T3
## group session with all three. That is the treatment order the study uses, and
## running it in that order is what makes alpha_source read survey / stored /
## default the way a real sitting would.
##
## Three things this deliberately guarantees, because the previous sample data
## missed them: every round is played to completion, each round spends as close
## to the whole budget as the remaining link prices allow, and both surveys are
## answered by every participant.
##
## Timing note: the delays below are REAL, not fabricated. Every timestamp in
## the output is a genuine measurement of this script's own pacing. They are
## compressed far below human speed (a round decides in ~2s, not ~2min), so
## decision_time_s is honest about what happened but is not a model of
## participant deliberation. Do not analyse it as one.

## Paced so the recorded timings are ordered and real rather than all-zero.
const DELAY_MS: int = 120
const CONFIRM_DELAY_MS: int = 400

## A round buys protected lanes in preference order while the budget lasts, then
## tops up with painted ones. The cap stops the top-up pass turning leftover
## change into a dozen trivial purchases, which no participant would do.
const MAX_PICKS_PER_ROUND: int = 8

## Survey answers per participant, chosen so the three land in different
## personality bands: p001 cautious, p002 average, p003 confident.
const PRE_RESPONSES: Dictionary = {
	"p001": {
		"q1": "25-29", "q2": "Female", "q3": "Employed full-time",
		"q4": "Hybrid", "q5": "Yes", "q6": "1-2 days", "q7": "1-3 years",
		"q8": 2, "q9": 2, "q10": 1, "q11": 2,          # mean 1.75 -> cautious
	},
	"p002": {
		"q1": "35-39", "q2": "Male", "q3": "Self-employed",
		"q4": "Completely in-person", "q5": "Yes", "q6": "3-4 days", "q7": ">3 years",
		"q8": 3, "q9": 3, "q10": 3, "q11": 3,          # mean 3.00 -> average
	},
	"p003": {
		"q1": "18-24", "q2": "Non-binary", "q3": "Student",
		"q4": "Completely remote", "q5": "No", "q6": "5+ days", "q7": ">3 years",
		"q8": 4, "q9": 4, "q10": 5, "q11": 4,          # mean 4.25 -> confident
	},
}

## Closing survey. q5 to q7 are group_only and are supplied only for the group
## session, matching what the survey scene would actually collect.
## p002 answers "dk" on one item on purpose, so the _dk columns are exercised.
const POST_RESPONSES: Dictionary = {
	"p001": {"q1": 4, "q2": 2, "q3": 5, "q4": 2},
	"p002": {"q1": 3, "q2": SurveyScale.DK, "q3": 3, "q4": 4},
	"p003": {"q1": 5, "q2": 4, "q3": 2, "q4": 5},
}
const POST_GROUP_EXTRA: Dictionary = {
	"p001": {"q5": 4, "q6": 3, "q7": 4},
	"p002": {"q5": 3, "q6": 4, "q7": 4},
	"p003": {"q5": 2, "q6": 5, "q7": 3},
}

## How each participant allocates. Kept distinct so the sample still separates
## self-interested from city-minded play, which is the study's whole point.
const STRATEGY_BY_ID: Dictionary = {
	"p001": "self",    # spends on their own commute
	"p002": "mixed",
	"p003": "city",    # spends on the busiest arterials regardless of own route
}

## The autoload's own script, for its enums and action constants. An autoload
## name is not a compile-time global the way a class_name is, so under --script
## it cannot be referenced directly and the instance is fetched at runtime below.
const GameManagerScript := preload("res://scripts/GameManager.gd")

var _done: bool = false
## The live GameManager autoload. Resolved on the first frame, never earlier.
var gm: Node = null


## Autoloads are unreachable from _initialize(), so all work happens on the
## first frame. Returning true ends the run.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run_study()
	return true


func _run_study() -> void:
	gm = root.get_node("/root/GameManager")
	var ids: Array = ["p001", "p002", "p003"]
	var written: Array = []

	print("=== generating sample study ===")
	for pid: String in ids:
		written.append(_run_session(GameManagerScript.Treatment.INDIVIDUAL, [pid], "", ""))
	for pid: String in ids:
		# The solo halves of one sitting: T2 follows T1 for the same person, and
		# records which session it followed so the pair can be rejoined.
		written.append(_run_session(GameManagerScript.Treatment.COLLECTIVE_INFO, [pid], "",
				_session_for(written, "T1", pid)))
	written.append(_run_session(GameManagerScript.Treatment.GROUP_DISCUSSION, ids, "g01", ""))

	print("=== done, %d sessions ===" % written.size())
	for s: String in written:
		print("  " + s)


## The T1 folder belonging to this participant, so the T2 half can point at it.
func _session_for(written: Array, prefix: String, pid: String) -> String:
	for s: String in written:
		if s.begins_with(prefix) and s.contains(pid):
			return s
	return ""


func _run_session(treatment: int, participant_ids: Array, group_id: String,
		chained_from: String) -> String:
	var num_players: int = participant_ids.size()

	# Mirrors scenes/main.gd:_enter_tree. A logger is one session: it is created
	# per session and torn down after, so a second session cannot append to the
	# first one's files.
	var logger := DataLogger.new()
	root.add_child(logger)
	gm.round_ended.connect(logger.on_round_ended)
	gm.game_over.connect(logger.on_game_over)

	# Read before any treatment is recorded, so it counts what came before.
	var ordinals: Array[int] = []
	for pid: String in participant_ids:
		ordinals.append(ParticipantStore.next_treatment_ordinal(pid))

	var alphas: Array[float] = []
	var responses_list: Array = []
	var sources: Array[String] = []
	var uses_default: bool = ResearchConfig.GROUP_TREATMENT_USES_DEFAULT_ALPHA \
			and treatment == int(GameManagerScript.Treatment.GROUP_DISCUSSION)

	for i: int in range(num_players):
		var pid: String = participant_ids[i]
		if uses_default:
			# The group treatment skips the survey and runs everyone at the
			# average personality (ResearchConfig, owner decision 5 Aug 2026).
			alphas.append(PersonalityConfig.ALPHA_AVERAGE)
			responses_list.append({})
			sources.append(ParticipantStore.SOURCE_DEFAULT)
			continue
		var record: Dictionary = ParticipantStore.load_record(pid)
		if record.is_empty():
			var pre: Dictionary = PRE_RESPONSES[pid]
			var alpha: float = PersonalityConfig.alpha_for_survey_mean(
					SurveyQuestions.alpha_mean(pre))
			ParticipantStore.save_survey(pid, alpha, pre)
			alphas.append(alpha)
			responses_list.append(pre)
			sources.append(ParticipantStore.SOURCE_SURVEY)
		else:
			# Known participant: reuse the measured value rather than re-asking.
			alphas.append(float(record["alpha"]))
			responses_list.append(record.get("responses", {}))
			sources.append(ParticipantStore.SOURCE_STORED)

	gm.start_game(alphas, treatment)
	logger.treatment = int(gm.treatment)
	# Everything this tool writes is synthetic, so it is marked as such and can
	# never be mistaken for a participant session. This is the case the session
	# kind exists for.
	logger.session_kind = ResearchConfig.SESSION_KIND_TEST
	logger.game_parameters = gm.session_parameters()
	logger.network_tables = gm.network_tables()
	logger.on_consent_external()
	logger.set_participant_identity(participant_ids, group_id, ordinals, chained_from)
	for i: int in range(num_players):
		logger.on_pre_survey_completed(i + 1, responses_list[i], alphas[i],
				participant_ids[i], sources[i])
		ParticipantStore.record_treatment(participant_ids[i], int(gm.treatment))
	# Same point scenes/main.gd calls it: the folder exists before round 1.
	logger.begin_session()

	var strategy: String = STRATEGY_BY_ID.get(participant_ids[0], "mixed")
	if num_players > 1:
		# One screen, one budget, three people arguing: the group ends up
		# somewhere between the individual strategies.
		strategy = "mixed"

	for round_num: int in range(1, gm.total_rounds + 1):
		_play_round(strategy, round_num)
		gm.advance_round()

	for i: int in range(num_players):
		logger.on_post_survey_completed(i + 1, num_players, participant_ids[i],
				_post_for(participant_ids[i], treatment))

	var session_id: String = logger.session_id
	gm.round_ended.disconnect(logger.on_round_ended)
	gm.game_over.disconnect(logger.on_game_over)
	root.remove_child(logger)
	logger.free()

	print("%s  spent %s" % [session_id, _spend_summary()])
	return session_id


func _post_for(pid: String, treatment: int) -> Dictionary:
	var out: Dictionary = (POST_RESPONSES[pid] as Dictionary).duplicate()
	if treatment == int(GameManagerScript.Treatment.GROUP_DISCUSSION):
		for key: String in POST_GROUP_EXTRA[pid]:
			out[key] = POST_GROUP_EXTRA[pid][key]
	return out


## Stages a round's picks one at a time (so decisions.csv records the order),
## then confirms them together, exactly as the click path does.
func _play_round(strategy: String, round_num: int) -> void:
	var budget: int = gm.human_player.credits_per_round
	var picks: Array = _plan_purchases(strategy, budget)

	var first: bool = true
	for pick: Dictionary in picks:
		if first and int(pick["level"]) == 2:
			# Looked at the cheap option first, then went protected. Produces a
			# changed_or_removed row, which is a real behavioural measure.
			gm.record_interaction(GameManagerScript.ACTION_SELECT, pick["link_id"], 1)
			OS.delay_msec(DELAY_MS)
			gm.record_interaction(GameManagerScript.ACTION_CHANGE_LEVEL, pick["link_id"], 2)
		else:
			gm.record_interaction(GameManagerScript.ACTION_SELECT,
					pick["link_id"], int(pick["level"]))
		first = false
		OS.delay_msec(DELAY_MS)

	if round_num == 2:
		# One pick considered and withdrawn before confirming, so the gap between
		# decisions.csv and upgrades.csv is exercised rather than always empty.
		var withdrawn: String = _first_unpicked(picks)
		if withdrawn != "":
			gm.record_interaction(GameManagerScript.ACTION_SELECT, withdrawn, 1)
			OS.delay_msec(DELAY_MS)
			gm.record_interaction(GameManagerScript.ACTION_UNSTAGE, withdrawn, 1)
			OS.delay_msec(DELAY_MS)

	OS.delay_msec(CONFIRM_DELAY_MS)
	gm.submit_upgrades(picks)


## Chooses what to buy this round, spending as much of the budget as the
## remaining link prices allow.
##
## Protected lanes are bought first in preference order while they fit, then a
## top-up pass adds painted lanes to use what is left. What survives at the end
## is smaller than the cheapest upgrade still on the board, so the round is
## spent out rather than merely sampled.
func _plan_purchases(strategy: String, budget: int) -> Array:
	var net: CityNetwork = gm.network
	var usage: Dictionary = _resident_usage(net)

	var own: Dictionary = {}
	for link_id: String in Player.route_link_ids(gm.human_player.current_route):
		own[link_id] = true

	var candidates: Array = []
	var seen: Dictionary = {}
	for key: String in net.links:
		var link: CityNetwork.Link = net.links[key]
		var cid: String = CityNetwork.canonical_link_id(link.from_node, link.to_node)
		if seen.has(cid):
			continue
		seen[cid] = true
		if link.upgrade_level >= 2:
			continue
		var riders: float = float(usage.get(cid, 0))
		var score: float = 0.0
		match strategy:
			"self":
				score = (1000.0 if own.has(cid) else 0.0) + link.stress_score * 20.0 + riders
			"city":
				score = riders * 10.0 + link.stress_score * 20.0
			_:
				score = (400.0 if own.has(cid) else 0.0) + riders * 5.0 + link.stress_score * 20.0
		candidates.append({
			"link_id": cid,
			"score": score,
			"cost_protected": Player.cost_for_link(link, 2),
			"cost_painted": Player.cost_for_link(link, 1),
		})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))

	var picks: Array = []
	var taken: Dictionary = {}
	var spent: int = 0

	for c: Dictionary in candidates:
		if picks.size() >= MAX_PICKS_PER_ROUND:
			break
		var cost: int = int(c["cost_protected"])
		if spent + cost <= budget:
			picks.append({"link_id": c["link_id"], "level": 2})
			taken[c["link_id"]] = true
			spent += cost

	for c: Dictionary in candidates:
		if picks.size() >= MAX_PICKS_PER_ROUND:
			break
		if taken.has(c["link_id"]):
			continue
		var cost: int = int(c["cost_painted"])
		if spent + cost <= budget:
			picks.append({"link_id": c["link_id"], "level": 1})
			taken[c["link_id"]] = true
			spent += cost

	return picks


## The best-scoring link this round did not buy, used for the withdrawn pick.
func _first_unpicked(picks: Array) -> String:
	var chosen: Dictionary = {}
	for p: Dictionary in picks:
		chosen[p["link_id"]] = true
	var net: CityNetwork = gm.network
	for key: String in net.links:
		var link: CityNetwork.Link = net.links[key]
		if link.upgrade_level >= 2:
			continue
		var cid: String = CityNetwork.canonical_link_id(link.from_node, link.to_node)
		if not chosen.has(cid):
			return cid
	return ""


## How many residents ride each link on the network as it currently stands.
## Recomputed per round because upgrades move people onto different roads.
func _resident_usage(net: CityNetwork) -> Dictionary:
	var usage: Dictionary = {}
	for commuter: Dictionary in gm.ai_commuters:
		var route: Dictionary = net.find_route(commuter["start"], commuter["goal"],
				commuter["alpha"])
		for link_id: String in Player.route_link_ids(route):
			usage[link_id] = int(usage.get(link_id, 0)) + 1
	return usage


## Per-round spend, for the progress line.
func _spend_summary() -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in gm.human_player.round_log:
		var available: int = int(entry.get("budget_available", 0))
		var used: int = int(entry.get("credits_spent", 0))
		var pct: float = 0.0 if available == 0 else (float(used) / float(available)) * 100.0
		parts.append("R%d %.0f%%" % [int(entry.get("round", 0)), pct])
	return ", ".join(parts)
