extends Node
## GameManager.gd
## The authoritative game state machine.
## Owns: round progression, treatment conditions, AI bots, and data logging.
## UI nodes should connect to signals here rather than reading state directly.

# --- Signals (UI listens to these) ---
signal round_started(round_num: int, budget: int)
signal round_ended(round_num: int, results: Dictionary)
signal game_over(final_results: Dictionary)
signal route_updated(player_id: String, route: Dictionary)
signal city_metrics_updated(metrics: Dictionary)        # only emitted in T2/T3
signal chat_message_received(round_num: int, text: String)  # only emitted in T3

# --- Treatment Enum ---
enum Treatment {
	INDIVIDUAL,        # T1: personal stats only
	COLLECTIVE_INFO,   # T2: personal + city averages
	COLLECTIVE_CHAT,   # T3: T2 + simulated chat/coordination
}

# --- Configuration ---
@export var total_rounds: int = 3
@export var treatment: Treatment = Treatment.INDIVIDUAL
@export var num_ai_commuters: int = 99
@export var home_work_pair: int = 0

## Staging actions recorded in the interaction event log (see
## record_interaction). Named constants rather than bare strings so the log's
## vocabulary is defined in exactly one place.
const ACTION_SELECT: String        = "select"          # staged an upgrade on a fresh link
const ACTION_CHANGE_LEVEL: String  = "change_level"    # re-picked a different level on an already-staged link
const ACTION_UNSTAGE: String       = "unstage"         # withdrew a staged action before confirming
const ACTION_STAGE_REMOVAL: String = "stage_removal"   # staged the removal of an already-built upgrade

## How much a resident's travel time or safety must move before it counts as a
## real change rather than floating-point drift. Route times are sums of many
## floats, so exact equality would classify numerical dust as a benefit and
## report an inflated percentage.
##
## A resident is counted as benefiting on TIME and on SAFETY separately — the
## two are never combined into one weighted score. Anyone who is neither better
## nor worse by more than these thresholds is "unchanged".
const BENEFIT_EPSILON_TIME: float   = 0.01   # minutes
const BENEFIT_EPSILON_SAFETY: float = 0.01   # points on the 0-100 safety scale
const BENEFIT_EPSILON_STRESS: float = 0.001  # raw stress units, a smaller scale than safety

const PLAYER_COLORS: Array = [
	Color(0.42, 0.64, 0.84),   # blue
	Color(0.88, 0.47, 0.32),   # coral
	Color(0.35, 0.72, 0.40),   # green
	Color(0.62, 0.42, 0.78),   # purple
	Color(0.85, 0.68, 0.25),   # amber
]

# --- State ---
var network: CityNetwork
var human_players: Array[Player] = []
var human_player: Player
var ai_commuters: Array[Dictionary]
var current_round: int = 0
var game_running: bool = false
var _round_start_player_data: Array = []
var _round_start_city_metrics: Dictionary = {}

## City metrics as they stood before ANY investment — the static Prospect
## Theory reference for the city-wide deltas, captured once at Round 1.
var _initial_city_metrics: Dictionary = {}

## Every resident's route/time/stress/safety on the UNTOUCHED network, captured
## once at Round 1. This is the reference the "residents benefiting" measures
## compare against, so a resident who gained in Round 1 still counts as having
## benefited in Round 3 — the same static reference point used for every other
## gain/loss in the game.
var _initial_residents: Array = []

## Every simulated resident's route/time/stress as it stood when the round
## opened, so the log can report each resident's before AND after state. Taken
## once and reused for the city averages, rather than re-solving the same
## routes for each metric.
var _round_start_residents: Array = []

## Append-only record of every staging action taken before a round is
## confirmed — selection order, level changes, and withdrawals. The confirmed
## `upgrades` array only shows the end state, so this is what preserves the
## order links were chosen in and whether a choice was changed or removed
## before confirmation.
var _interaction_events: Array = []
var _interaction_seq: int = 0

## Engine-tick second the current round began, so each round's decision time
## (round start → confirm) can be measured.
var _round_start_time_s: float = 0.0

## The same moment as an absolute Unix timestamp. Kept separately because the
## tick clock above is only meaningful inside this process — lining a round up
## against an audio recording made on a separate device needs real clock time.
## See DataLogger's audio manifest.
var _round_start_unix: float = 0.0


func _ready() -> void:
	pass


func start_game(alphas: Array, chosen_treatment: Treatment) -> void:
	treatment = chosen_treatment
	network = null
	human_players.clear()
	human_player = null
	game_running = false
	_interaction_events.clear()
	_interaction_seq = 0
	network = CityNetwork.new(home_work_pair)

	human_players.clear()
	# Two players sharing a home or workplace would make their routes converge
	# by construction and their outcomes non-independent. The table is supposed
	# to guarantee this; say so loudly if an edit ever breaks it, since nothing
	# else about a clash is visible while playing.
	var clashes: Array = CityNetwork.player_pairs_overlap(alphas.size())
	if not clashes.is_empty():
		push_error("HOME_WORK_PAIRS: node(s) %s shared between players" % str(clashes))
	for i in range(alphas.size()):
		var pair_idx: int = i % CityNetwork.HOME_WORK_PAIRS.size()
		var pair: Array = CityNetwork.HOME_WORK_PAIRS[pair_idx]
		var home: Vector2i = pair[0]
		var work: Vector2i = pair[1]
		var p := Player.new("player_%d" % i, home, work, alphas[i])
		human_players.append(p)

	human_player = human_players[0]

	_seed_ai_commuters(num_ai_commuters)

	# Round-1 baseline: the static Prospect Theory reference point every later
	# round's gain/loss is measured against. Captured once, never updated.
	for p in human_players:
		var baseline_route = network.find_route(p.home, p.work, p.alpha)
		p.baseline_time         = baseline_route.get("total_time", 30.0)
		p.initial_baseline_time = p.baseline_time
		p.current_route         = baseline_route
		p.safety_score          = p._compute_safety(baseline_route, network)
		p.initial_baseline_safety    = p.safety_score
		p.initial_baseline_stress    = Player.route_stress(baseline_route, network, p.alpha)
		p.initial_baseline_impedance = baseline_route.get("total_impedance", 0.0)
		p.initial_baseline_route_links = Player.route_link_ids(baseline_route)

	game_running = true
	_start_round(1)


func submit_upgrades(upgrade_requests: Array) -> void:
	if not game_running:
		return

	for req in upgrade_requests:
		var level: int = req.get("level", 0)
		if level == 0:
			var link: CityNetwork.Link = network.links.get(req["link_id"])
			# Only what the player built can be taken back. The refund is paid
			# strictly on downgrade_link() having succeeded, never on the link
			# merely being upgraded: the city starts with a few lanes nobody
			# paid for, and refunding those was money from nowhere.
			if link and link.has_player_upgrade():
				var from_level: int = link.upgrade_level
				var refund: int = Player.cost_for_link(link, from_level)
				if network.downgrade_link(req["link_id"]):
					human_player.record_downgrade(req["link_id"], from_level, refund, link)
					human_player.credits_remaining = mini(
						human_player.credits_remaining + refund,
						human_player.credits_per_round
					)
		else:
			human_player.buy_upgrade(req["link_id"], level, network)

	_recalculate_and_end_round()


## Records one staging action taken while a round is still open. Called by the
## scene layer each time a player stages an upgrade, changes its level, or
## withdraws it — the confirmed `upgrades` array shows only the end state, so
## this is the sole record of the ORDER links were chosen in and of any choice
## that was changed or removed before confirmation.
##
## `level` carries the level staged by this action; for ACTION_UNSTAGE it is
## the level being withdrawn.
func record_interaction(action: String, link_id: String, level: int) -> void:
	if not game_running:
		return
	_interaction_seq += 1
	_interaction_events.append({
		"seq":     _interaction_seq,
		"round":   current_round,
		"t_s":     (Time.get_ticks_msec() / 1000.0) - _round_start_time_s,
		"action":  action,
		"link":    link_id,
		"level":   level,
	})


func _events_for_round(round_num: int) -> Array:
	var out: Array = []
	for e: Dictionary in _interaction_events:
		if e["round"] == round_num:
			out.append(e)
	return out


## Canonical (direction-independent) form of a stored link_id, so an upgrade
## record can be matched against a route's links regardless of which way the
## rider travelled it.
static func _canonical_of(link_id: String) -> String:
	var parts := link_id.split("-")
	if parts.size() != 2:
		return link_id
	return CityNetwork.canonical_link_id(
		CityNetwork.parse_node(parts[0]), CityNetwork.parse_node(parts[1]))


## Which of this round's purchased links ended up on `route_links`. Answers
## "did the upgraded link become part of this rider's NEW route" — distinct
## from each upgrade's `own_route` flag, which was recorded at purchase time
## against the route they were riding BEFORE the recalculation.
static func _upgraded_links_on_route(upgrades: Array, route_links: Array) -> Array:
	var out: Array = []
	for u: Dictionary in upgrades:
		var canonical := _canonical_of(u.get("link", ""))
		if route_links.has(canonical):
			out.append(canonical)
	return out


## The board itself, for the log: one entry per undirected link and one per
## junction.
##
## parameters.json already records the rates and coefficients, but until now
## nothing recorded what a link WAS, so `link_id` appeared in five tables as an
## opaque key and the network's own numbers were unauditable. With this, the
## per-metre rates and the beta tables, an analyst can rebuild the graph and
## re-run Dijkstra without the game.
##
## Immutable properties only. `upgrade_level` is deliberately absent because it
## is what players change and it is already recorded per purchase in
## upgrades.csv; `initial_upgrade_level` is present because it is not.
##
## Links are emitted once each, keyed canonically. The graph stores both
## directions of every road as separate Link objects, and exporting both would
## double every count taken off this file for no gain, since the pair is
## identical in every column here.
func network_tables() -> Dictionary:
	if network == null:
		return {"links": [], "nodes": []}

	var links: Array = []
	var degree: Dictionary = {}
	var seen: Dictionary = {}
	var link_ids: Array = network.links.keys()
	link_ids.sort()
	for link_id: String in link_ids:
		var link: CityNetwork.Link = network.links[link_id]
		var canonical: String = CityNetwork.canonical_link_id(link.from_node, link.to_node)
		degree[link.from_node] = int(degree.get(link.from_node, 0)) + 1
		if seen.has(canonical):
			continue
		seen[canonical] = true
		links.append({
			"link_id":        canonical,
			"from_node":      "%d,%d" % [link.from_node.x, link.from_node.y],
			"to_node":        "%d,%d" % [link.to_node.x, link.to_node.y],
			"from_name":      network.node_names.get(link.from_node, ""),
			"to_name":        network.node_names.get(link.to_node, ""),
			"length_m":       Player.link_length_m(link),
			"base_time_min":  link.base_time,
			"base_stress":    link.stress_score,
			"beta_painted":   0.8 - 0.3 * link.stress_score,
			"initial_upgrade_level": link.initial_upgrade_level,
			"initial_level_name":    LogSchema.infra_level_name(link.initial_upgrade_level),
			"cost_painted":   Player.cost_for_link(link, 1),
			"cost_protected": Player.cost_for_link(link, 2),
		})

	var nodes: Array = []
	for node: Vector2i in network.all_nodes:
		var pos: Vector2 = network.node_positions.get(node, Vector2.ZERO)
		nodes.append({
			"node_id":   "%d,%d" % [node.x, node.y],
			"name":      network.node_names.get(node, ""),
			"map_label": network.node_labels.get(node, ""),
			"map_x":     pos.x,
			"map_y":     pos.y,
			"degree":    int(degree.get(node, 0)),
		})
	return {"links": links, "nodes": nodes}


## Everything that decided how this session played, gathered for the log.
##
## Read from the config classes at the moment a session starts, not copied into
## a list that would go stale the next time a value is retuned. The parameters
## have moved repeatedly — six rounds became three, the stress model was
## restructured — and a session that does not record what produced it cannot be
## told apart from one run under different settings. Snapshotting it makes every
## session folder self-describing and means a pilot can be separated from the
## main study without consulting the commit history.
func session_parameters() -> Dictionary:
	return {
		"total_rounds":      total_rounds,
		"num_residents":     num_ai_commuters,
		"home_work_pair":    home_work_pair,
		"budget_per_round":  Player.DEFAULT_CREDITS_PER_ROUND,
		"cost_per_metre_painted":   Player.COST_PER_METRE_PAINTED,
		"cost_per_metre_protected": Player.COST_PER_METRE_PROTECTED,
		"time_factor_by_level":     CityNetwork.Link.TIME_FACTOR,
		"alpha_cautious":   PersonalityConfig.ALPHA_CAUTIOUS,
		"alpha_average":    PersonalityConfig.ALPHA_AVERAGE,
		"alpha_confident":  PersonalityConfig.ALPHA_CONFIDENT,
		"survey_mean_cautious_max":  PersonalityConfig.SURVEY_MEAN_CAUTIOUS_MAX,
		"survey_mean_confident_min": PersonalityConfig.SURVEY_MEAN_CONFIDENT_MIN,
		"beta_protected_cautious":  PersonalityConfig.BETA_PROTECTED_CAUTIOUS,
		"beta_protected_average":   PersonalityConfig.BETA_PROTECTED_AVERAGE,
		"beta_protected_confident": PersonalityConfig.BETA_PROTECTED_CONFIDENT,
		"benefit_epsilon_time":   BENEFIT_EPSILON_TIME,
		"benefit_epsilon_safety": BENEFIT_EPSILON_SAFETY,
		# How "a resident benefited" was defined when these numbers were
		# produced. A percentage of residents benefiting means nothing later
		# without it, and the definition is exactly the kind of thing that gets
		# retuned between a pilot and a main study.
		"benefit_metric":    "time_and_safety_counted_separately_never_combined",
		"benefit_reference": "round1_baseline",
		"group_size": ResearchConfig.GROUP_SIZE,
		# True means the group treatment assigned every player the average
		# personality instead of surveying them, so their routing input differs
		# from their own individual sessions.
		"group_treatment_uses_default_alpha": ResearchConfig.GROUP_TREATMENT_USES_DEFAULT_ALPHA,
		"network_signature": network.signature() if network != null else null,
		"prospect_theory_reference": "static_round1",
	}


## Share of a round's confirmed spending that landed on `route_links`.
##
## Distinct from Player.own_route_share(), which reads the BUYER's own tally.
## In group mode every purchase is recorded against player 0, because the group
## shares one screen, one mouse and one budget — so players 2..n have an empty
## tally and their share reads as the -1.0 "nothing spent" sentinel rather than
## a real value. Computing it from the round's upgrades against any rider's
## route makes "what share of the group's spending helped MY commute" answerable
## for every member of the group, not only whoever's Player object holds the
## purse. That comparison — self-interested vs. collective allocation, alone vs.
## negotiating — is the study's dependent variable, so it has to exist for
## everyone at the table.
##
## Pass the route the rider held WHILE DECIDING. That is the same route
## Player.buy_upgrade() flags each purchase against, so for player 0 this
## reproduces own_route_upgrade_share exactly and any disagreement between the
## two is a bug in one of them.
##
## Returns the same -1.0 sentinel as own_route_share() when nothing was spent:
## callers must not read it as "0% own-route".
static func _spend_share_on_route(upgrades: Array, route_links: Array) -> float:
	var total: int = 0
	var own: int = 0
	for u: Dictionary in upgrades:
		var cost: int = int(u.get("cost", 0))
		total += cost
		if route_links.has(_canonical_of(u.get("link", ""))):
			own += cost
	if total <= 0:
		return -1.0
	return float(own) / float(total)


# --- Private Round Logic ---

func _start_round(round_num: int) -> void:
	current_round = round_num
	_round_start_time_s = Time.get_ticks_msec() / 1000.0
	_round_start_unix   = Time.get_unix_time_from_system()
	_round_start_player_data.clear()
	for p in human_players:
		# Full before-investment snapshot, not just time/safety: the research
		# log records the route itself, its raw stress and its impedance
		# before AND after every round, and none of those can be recovered
		# once the network has been mutated.
		_round_start_player_data.append({
			"safety": p.safety_score,
			"time": p.current_route.get("total_time", 0.0),
			"stress": Player.route_stress(p.current_route, network, p.alpha),
			"impedance": p.current_route.get("total_impedance", 0.0),
			"route": _path_to_ids(p.current_route.get("path", [])),
			"route_links": Player.route_link_ids(p.current_route),
		})
	# Computed in EVERY treatment, including T1 where none of it is shown.
	# The research design requires the same core variables in all three
	# treatments so they stay comparable; treatment decides only what is
	# DISPLAYED (see the emit guard in _recalculate_and_end_round).
	_round_start_residents    = _resident_snapshot()
	_round_start_city_metrics = _compute_city_metrics(_round_start_residents)
	if round_num == 1:
		_initial_city_metrics = _round_start_city_metrics.duplicate()
		_initial_residents    = _round_start_residents.duplicate(true)
	for p in human_players:
		p.start_round(round_num)
	emit_signal("round_started", round_num, human_player.credits_per_round)

	if treatment == Treatment.COLLECTIVE_CHAT:
		_emit_simulated_chat_message()


func _recalculate_and_end_round() -> void:
	var decision_time_s: float = (Time.get_ticks_msec() / 1000.0) - _round_start_time_s
	var confirmed_unix: float = Time.get_unix_time_from_system()
	for p in human_players:
		p.current_route = network.find_route(p.home, p.work, p.alpha)

	for p in human_players:
		var updated_route := network.find_route(p.home, p.work, p.alpha)
		p.end_round(updated_route)
		# baseline_time is deliberately NOT updated here. It used to roll
		# forward each round, which made the Prospect Theory reference dynamic
		# (each round compared to the last). The reference is static: always
		# the Round-1 baseline.
		p.safety_score = p._compute_safety(updated_route, network)
		emit_signal("route_updated", p.player_id, updated_route)

	var round_upgrades: Array = human_player.round_log.back().get("upgrades", [])

	# Two different comparisons are recorded per metric and must not be
	# confused:
	#   *_before  — this round's starting value, i.e. the "before and after
	#               each investment" pair the data spec asks for.
	#   *_baseline — the Round-1 value.
	#   *_delta   — the Prospect Theory gain/loss, measured against
	#               *_baseline (STATIC reference), NOT against *_before.
	# All deltas are signed so POSITIVE = improvement: time, stress and
	# impedance are better when lower, so those read (baseline - now);
	# safety is better when higher, so it reads (now - baseline).
	var players_data: Array = []
	for i in range(human_players.size()):
		var p: Player = human_players[i]
		var before: Dictionary = _round_start_player_data[i]
		var route_links: Array   = Player.route_link_ids(p.current_route)
		var stress_after: float  = Player.route_stress(p.current_route, network, p.alpha)
		var impedance_after: float = p.current_route.get("total_impedance", 0.0)
		players_data.append({
			"player_id": p.player_id,
			"alpha": p.alpha,
			"time": p.current_route.get("total_time", 0.0),
			"time_before": before["time"],
			"safety": p.safety_score,
			"safety_before": before["safety"],
			"safety_baseline": p.initial_baseline_safety,
			"safety_delta": p.safety_score - p.initial_baseline_safety,
			"time_baseline": p.initial_baseline_time,
			"time_delta": p.time_delta_from_baseline(),
			"stress": stress_after,
			"stress_before": before["stress"],
			"stress_baseline": p.initial_baseline_stress,
			"stress_delta": p.initial_baseline_stress - stress_after,
			"impedance": impedance_after,
			"impedance_before": before["impedance"],
			"impedance_baseline": p.initial_baseline_impedance,
			"impedance_delta": p.initial_baseline_impedance - impedance_after,
			"own_route_upgrade_share": Player.own_route_share(p.round_log.back()),
			"cumulative_own_route_upgrade_share": p.cumulative_own_route_share(),
			# The same measure computed from the round's purchases rather than
			# from this player's own purse, so it is a real value for every
			# member of a T3 group and not just the one holding the budget.
			"group_spend_on_my_route_share": _spend_share_on_route(
					round_upgrades, before["route_links"]),
			# This rider's own origin and destination, in the same form the
			# simulated residents use, so a player's commute can be compared
			# against the resident population without reformatting either.
			"home": "%d,%d" % [p.home.x, p.home.y],
			"work": "%d,%d" % [p.work.x, p.work.y],
			"route": _path_to_ids(p.current_route.get("path", [])),
			"route_before": before["route"],
			"route_links": route_links,
			"route_links_before": before["route_links"],
			# The Round-1 route, carried on every round so "still on the route
			# they started with" is answerable without going back to Round 1.
			"route_links_baseline": p.initial_baseline_route_links,
			"route_changed": route_links != before["route_links"],
			"route_changed_from_baseline": route_links != p.initial_baseline_route_links,
			"upgraded_links_on_new_route": _upgraded_links_on_route(round_upgrades, route_links),
		})

	# Stamp each purchase with whether it landed on the buyer's own new route.
	for u: Dictionary in round_upgrades:
		u["on_new_route"] = players_data[0]["route_links"].has(_canonical_of(u.get("link", "")))

	var results: Dictionary = {
		"round":             current_round,
		"alpha":             human_player.alpha,
		"group_mode":        treatment == Treatment.COLLECTIVE_CHAT,
		# Whether the city-wide figures were on screen this round. They are
		# COMPUTED in every treatment, including T1 where they are never shown,
		# so a blank city column would otherwise be ambiguous between "not
		# calculated" and "calculated but hidden". Recording which it was is
		# what makes the T1 city numbers usable: they are the counterfactual for
		# "would this player have helped the city had they been able to see it".
		"city_metrics_shown": treatment != Treatment.INDIVIDUAL,
		"personal_time":     human_player.current_route.get("total_time", 0.0),
		"personal_time_before": _round_start_player_data[0]["time"],
		"personal_safety":   human_player.safety_score,
		"safety_before":     _round_start_player_data[0]["safety"],
		"safety_baseline":   players_data[0]["safety_baseline"],
		"safety_delta":      players_data[0]["safety_delta"],
		"time_baseline":     players_data[0]["time_baseline"],
		"time_delta":        players_data[0]["time_delta"],
		"personal_stress":        players_data[0]["stress"],
		"personal_stress_before": players_data[0]["stress_before"],
		"personal_stress_baseline": players_data[0]["stress_baseline"],
		"stress_delta":           players_data[0]["stress_delta"],
		"personal_impedance":        players_data[0]["impedance"],
		"personal_impedance_before": players_data[0]["impedance_before"],
		"personal_impedance_baseline": players_data[0]["impedance_baseline"],
		"impedance_delta":           players_data[0]["impedance_delta"],
		"route_links":        players_data[0]["route_links"],
		"route_before":       players_data[0]["route_before"],
		"route_links_before": players_data[0]["route_links_before"],
		"route_links_baseline": players_data[0]["route_links_baseline"],
		"route_changed":      players_data[0]["route_changed"],
		"route_changed_from_baseline": players_data[0]["route_changed_from_baseline"],
		"upgraded_links_on_new_route": players_data[0]["upgraded_links_on_new_route"],
		"budget_available":  human_player.credits_per_round,
		"credits_spent":     human_player.round_log.back().get("credits_spent", 0),
		# Spend across every round so far. A group session has one shared purse,
		# so this is a property of the session rather than of any one player.
		"credits_spent_cumulative": human_player.cumulative_credits_spent(),
		"credits_remaining": human_player.credits_remaining,
		"upgrades":          round_upgrades,
		"removals":          human_player.round_log.back().get("removals", []),
		"decision_time_s":   decision_time_s,
		# Absolute clock bounds of this round, for aligning an externally
		# recorded T3 discussion against the decisions made during it.
		"round_started_unix":   _round_start_unix,
		"round_confirmed_unix": confirmed_unix,
		"interaction_events": _events_for_round(current_round),
		"own_route_upgrade_share": Player.own_route_share(human_player.round_log.back()),
		"cumulative_own_route_upgrade_share": human_player.cumulative_own_route_share(),
		# Player 0's copy of the per-player measure above. Must equal
		# own_route_upgrade_share on every round; kept alongside it so the two
		# definitions can be cross-checked directly in the log.
		"group_spend_on_my_route_share": players_data[0]["group_spend_on_my_route_share"],
		"players":           players_data,
		"final_route":       _path_to_ids(human_player.current_route.get("path", [])),
	}

	# City metrics and the per-resident snapshot are computed and logged in
	# ALL treatments, including T1 where they are never shown — the research
	# design needs the same variables across treatments to keep them
	# comparable. Only the DISPLAY signal at the end is treatment-gated.
	var residents_after: Array = _resident_snapshot()
	var city_metrics: Dictionary = _compute_city_metrics(residents_after)
	results["residents_before"]       = _round_start_residents
	results["residents_after"]        = residents_after
	results["city_avg_time"]          = city_metrics["avg_time"]
	results["city_avg_safety"]        = city_metrics["avg_safety"]
	results["city_coverage"]          = city_metrics["coverage"]
	results["city_avg_stress"]        = city_metrics["avg_stress"]
	results["city_avg_time_before"]   = _round_start_city_metrics.get("avg_time", null)
	results["city_avg_safety_before"] = _round_start_city_metrics.get("avg_safety", null)
	results["city_avg_stress_before"] = _round_start_city_metrics.get("avg_stress", null)
	results["city_coverage_before"]   = _round_start_city_metrics.get("coverage", null)
	# Baselines + static deltas, same convention as the personal metrics above.
	results["city_avg_time_baseline"]   = _initial_city_metrics.get("avg_time", null)
	results["city_avg_safety_baseline"] = _initial_city_metrics.get("avg_safety", null)
	results["city_avg_stress_baseline"] = _initial_city_metrics.get("avg_stress", null)
	results["city_coverage_baseline"]   = _initial_city_metrics.get("coverage", null)
	results["city_avg_time_delta"]    = _initial_city_metrics["avg_time"] - city_metrics["avg_time"]
	results["city_avg_safety_delta"]  = city_metrics["avg_safety"] - _initial_city_metrics["avg_safety"]
	results["city_avg_stress_delta"]  = _initial_city_metrics["avg_stress"] - city_metrics["avg_stress"]

	# How many residents are better off than on the untouched network, and by
	# how much. Merged into city_metrics as well as results so the T2/T3 panel
	# renders from the same dictionary the log records.
	var benefit: Dictionary = _compute_benefit_metrics(residents_after, _initial_residents)
	for key in benefit:
		results[key] = benefit[key]
		city_metrics[key] = benefit[key]

	# The only treatment branch: T1 computes and logs everything above but is
	# never shown it. T2/T3 additionally record the exact feedback text the
	# participant reads, built from the same CityFeedback source the UI
	# renders from, so the log cannot drift from what was on screen.
	if treatment != Treatment.INDIVIDUAL:
		# Compared against the Round-1 baseline, not the round's start — the
		# participant sees the same static gain/loss framing the log records.
		# The benefit sentences are appended in the order they appear on
		# screen, so this stays a faithful record of what was read.
		var shown := CityFeedback.lines_with_change(city_metrics, _initial_city_metrics)
		shown.append_array(CityFeedback.benefit_lines(city_metrics))
		results["city_feedback_shown"] = shown
		emit_signal("city_metrics_updated", city_metrics)
	else:
		results["city_feedback_shown"] = []

	emit_signal("round_ended", current_round, results)


## Converts a Dijkstra path (Array[Vector2i]) into JSON-serializable "x,y"
## node IDs — Vector2i isn't natively JSON-encodable, and this matches the
## link_id format used elsewhere (CityGrid._vec_to_id, CityNetwork link IDs).
func _path_to_ids(path: Array) -> Array:
	var ids: Array = []
	for node_vec: Vector2i in path:
		ids.append("%d,%d" % [node_vec.x, node_vec.y])
	return ids


func advance_round() -> void:
	if current_round >= total_rounds:
		_end_game()
	else:
		_start_round(current_round + 1)


func _end_game() -> void:
	game_running = false
	var players_data: Array = []
	for p in human_players:
		var ft: float = p.current_route.get("total_time", 0.0)
		players_data.append({
			"player_id": p.player_id,
			"final_time": ft,
			"baseline_time": p.initial_baseline_time,
			"total_time_saved": p.initial_baseline_time - ft,
			"final_safety": p.safety_score,
			"alpha": p.alpha,
			"cumulative_own_route_upgrade_share": p.cumulative_own_route_share(),
			"log": p.export_log(),
		})
	var final_time: float = human_player.current_route.get("total_time", 0.0)
	var final_results: Dictionary = {
		"total_rounds":     total_rounds,
		"final_time":       final_time,
		"baseline_time":    human_player.initial_baseline_time,
		"total_time_saved": human_player.initial_baseline_time - final_time,
		"final_safety":     human_player.safety_score,
		"city_coverage":    network.coverage_percent(),
		"alpha":            human_player.alpha,
		"cumulative_own_route_upgrade_share": human_player.cumulative_own_route_share(),
		"log":              human_player.export_log(),
		"players":          players_data,
	}
	emit_signal("game_over", final_results)



# --- AI Commuters ---

func _seed_ai_commuters(count: int) -> void:
	ai_commuters.clear()
	var pairs: Array = CityNetwork.RESIDENT_COMMUTE_PAIRS
	var n: int = mini(count, pairs.size())
	for i in range(n):
		ai_commuters.append({ "start": pairs[i][0], "goal": pairs[i][1], "alpha": 1.5 })


## One row per simulated resident describing their current best route. Taken
## at round start and again at round end, so the log holds every resident's
## route, travel time and stress before AND after each investment — not just
## the city-wide averages derived from them.
func _resident_snapshot() -> Array:
	var rows: Array = []
	for i in range(ai_commuters.size()):
		var c: Dictionary = ai_commuters[i]
		var route: Dictionary = network.find_route(c["start"], c["goal"], c["alpha"])
		rows.append({
			"resident_index": i,
			"home":      "%d,%d" % [c["start"].x, c["start"].y],
			"work":      "%d,%d" % [c["goal"].x, c["goal"].y],
			"alpha":     c["alpha"],
			"time":      route.get("total_time", 0.0),
			"stress":    Player.route_stress(route, network, c["alpha"]),
			"safety":    Player.route_safety(route, network, c["alpha"]),
			"impedance": route.get("total_impedance", 0.0),
			"route_links": Player.route_link_ids(route),
		})
	return rows


## How many simulated residents are better off than they were on the untouched
## Round-1 network, and by how much.
##
## Reported as TWO independent measures, never one weighted score: a resident
## can benefit on travel time, on safety, on both, or on neither, and each is
## counted separately. Impedance deliberately takes no part here — it is a
## routing quantity that means nothing to a participant, so it stays backend-only.
##
## `baseline` is the Round-1 snapshot, not the previous round's, so gains
## accumulate across the session rather than resetting — the same static
## reference point every other delta in the game uses.
##
## Averages are taken over the BENEFITING subset only, not over all residents:
## "the average travel time decrease was 1.3 minutes" describes the people who
## actually gained, and dividing by the whole city would dilute it toward zero.
##
## The totals are the "benefit generated for residents other than the
## participant" figure — `residents` holds only simulated residents, never the
## human player(s), so that exclusion is structural rather than a filter that
## could rot. They are NET sums across everyone, including anyone made worse
## off; the gains-only figure is recoverable as count x mean.
func _compute_benefit_metrics(now: Array, baseline: Array) -> Dictionary:
	var total: int = mini(now.size(), baseline.size())

	var time_improved: int  = 0
	var time_worsened: int  = 0
	var safety_improved: int = 0
	var safety_worsened: int = 0
	# Raw route stress, reported alongside the normalised 0-100 safety score.
	# Safety is a transform of stress, so the two move together, but the data
	# spec asks for "average stress improvement among affected residents" in raw
	# model units and a normalised score is not that. Kept as its own block
	# rather than substituted, since the transform is not linear across routes
	# of different lengths.
	var stress_improved: int = 0
	var stress_worsened: int = 0
	var time_gain_sum: float   = 0.0   # over improved residents only
	var safety_gain_sum: float = 0.0   # over improved residents only
	var stress_gain_sum: float = 0.0   # over improved residents only
	var time_net_sum: float    = 0.0   # over everyone
	var safety_net_sum: float  = 0.0   # over everyone
	var stress_net_sum: float  = 0.0   # over everyone

	for i in range(total):
		var before: Dictionary = baseline[i]
		var after: Dictionary  = now[i]
		# Signed so POSITIVE = improvement, matching every other delta in the
		# log: time and stress are better when lower, safety when higher.
		var time_gain: float   = before.get("time", 0.0) - after.get("time", 0.0)
		var safety_gain: float = after.get("safety", 0.0) - before.get("safety", 0.0)
		var stress_gain: float = before.get("stress", 0.0) - after.get("stress", 0.0)

		time_net_sum   += time_gain
		safety_net_sum += safety_gain
		stress_net_sum += stress_gain

		if time_gain > BENEFIT_EPSILON_TIME:
			time_improved += 1
			time_gain_sum += time_gain
		elif time_gain < -BENEFIT_EPSILON_TIME:
			time_worsened += 1

		if safety_gain > BENEFIT_EPSILON_SAFETY:
			safety_improved += 1
			safety_gain_sum += safety_gain
		elif safety_gain < -BENEFIT_EPSILON_SAFETY:
			safety_worsened += 1

		if stress_gain > BENEFIT_EPSILON_STRESS:
			stress_improved += 1
			stress_gain_sum += stress_gain
		elif stress_gain < -BENEFIT_EPSILON_STRESS:
			stress_worsened += 1

	var denom: float = float(total) if total > 0 else 1.0
	return {
		"residents_total": total,

		"residents_time_improved":       time_improved,
		"residents_time_improved_pct":   100.0 * float(time_improved) / denom,
		"residents_time_worsened":       time_worsened,
		# "No benefit" is the complement of "improved", so it includes anyone
		# made worse off as well as the unchanged. Worsened is broken out
		# separately above so the two can be told apart in analysis.
		"residents_time_no_benefit":     total - time_improved,
		"residents_time_no_benefit_pct": 100.0 * float(total - time_improved) / denom,
		"residents_time_improvement_mean": (time_gain_sum / float(time_improved)) if time_improved > 0 else 0.0,

		"residents_safety_improved":       safety_improved,
		"residents_safety_improved_pct":   100.0 * float(safety_improved) / denom,
		"residents_safety_worsened":       safety_worsened,
		"residents_safety_no_benefit":     total - safety_improved,
		"residents_safety_no_benefit_pct": 100.0 * float(total - safety_improved) / denom,
		"residents_safety_improvement_mean": (safety_gain_sum / float(safety_improved)) if safety_improved > 0 else 0.0,

		"residents_stress_improved":       stress_improved,
		"residents_stress_improved_pct":   100.0 * float(stress_improved) / denom,
		"residents_stress_worsened":       stress_worsened,
		"residents_stress_no_benefit":     total - stress_improved,
		"residents_stress_no_benefit_pct": 100.0 * float(total - stress_improved) / denom,
		"residents_stress_improvement_mean": (stress_gain_sum / float(stress_improved)) if stress_improved > 0 else 0.0,

		"residents_total_time_saved_min": time_net_sum,
		"residents_total_safety_gained":  safety_net_sum,
		"residents_total_stress_reduced": stress_net_sum,
	}


## City-wide averages across the simulated residents plus the human player(s).
## Takes an already-computed resident snapshot so residents' routes are solved
## once per round-boundary instead of once per metric.
func _compute_city_metrics(residents: Array) -> Dictionary:
	var total_time: float = 0.0
	var total_safety: float = 0.0
	var total_stress: float = 0.0
	for r: Dictionary in residents:
		total_time += r["time"]
		total_safety += r["safety"]
		total_stress += r["stress"]

	for p: Player in human_players:
		total_time += p.current_route.get("total_time", 0.0)
		total_safety += p.safety_score
		total_stress += Player.route_stress(p.current_route, network, p.alpha)

	var count: float = float(residents.size() + human_players.size())
	return {
		"avg_time":   total_time / count,
		"avg_safety": total_safety / count,
		# Raw average stress exposure, alongside the normalized 0-100 safety
		# index — the research log records both.
		"avg_stress": total_stress / count,
		"coverage":   network.coverage_percent(),
	}


# --- T3 Simulated Chat ---

func _emit_simulated_chat_message() -> void:
	var worst_link_id: String = _find_worst_unimproved_link()
	if worst_link_id.is_empty():
		return

	var friendly_name := network.link_display_name(worst_link_id)
	var messages = [
		"Hey, %s is still unprotected — want to fix it together this round?" % friendly_name,
		"If we both invest in %s, everyone's route improves." % friendly_name,
		"That stretch at %s keeps slowing down traffic." % friendly_name,
	]
	# Chosen by round number rather than at random. randomize() seeds from
	# system entropy, which made this the one unseeded choice in the build: two
	# runs of an otherwise identical session could not be reproduced message for
	# message. Cycling by round is deterministic and still varies each round.
	var msg = messages[(current_round - 1) % messages.size()]

	emit_signal("chat_message_received", current_round, msg)


func _find_worst_unimproved_link() -> String:
	var path: Array = human_player.current_route.get("path", [])
	var worst_stress: float = -1.0
	var worst_id: String = ""

	for i in range(path.size() - 1):
		var link_id = "%d,%d-%d,%d" % [path[i].x, path[i].y, path[i+1].x, path[i+1].y]
		if network.links.has(link_id):
			var link: CityNetwork.Link = network.links[link_id]
			if link.upgrade_level == 0 and link.stress_score > worst_stress:
				worst_stress = link.stress_score
				worst_id = link_id

	return worst_id
