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
@export var total_rounds: int = 6
@export var treatment: Treatment = Treatment.INDIVIDUAL
@export var num_ai_commuters: int = 30
@export var home_work_pair: int = 0

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


func _ready() -> void:
	pass


func start_game(alphas: Array, chosen_treatment: Treatment) -> void:
	treatment = chosen_treatment
	network = null
	human_players.clear()
	human_player = null
	game_running = false
	network = CityNetwork.new(home_work_pair)

	human_players.clear()
	for i in range(alphas.size()):
		var pair_idx: int = i % CityNetwork.HOME_WORK_PAIRS.size()
		var pair: Array = CityNetwork.HOME_WORK_PAIRS[pair_idx]
		var home: Vector2i = pair[0]
		var work: Vector2i = pair[1]
		var p := Player.new("player_%d" % i, home, work, alphas[i])
		human_players.append(p)

	human_player = human_players[0]

	_seed_ai_commuters(num_ai_commuters)

	for p in human_players:
		var baseline_route = network.find_route(p.home, p.work, p.alpha)
		p.baseline_time         = baseline_route.get("total_time", 30.0)
		p.initial_baseline_time = p.baseline_time
		p.current_route         = baseline_route
		p.safety_score          = p._compute_safety(baseline_route, network)

	game_running = true
	_start_round(1)


func submit_upgrades(upgrade_requests: Array) -> void:
	if not game_running:
		return

	for req in upgrade_requests:
		var level: int = req.get("level", 0)
		if level == 0:
			var link: CityNetwork.Link = network.links.get(req["link_id"])
			if link and link.upgrade_level > 0:
				var refund: int = Player.COST_PAINTED_LANE if link.upgrade_level == 1 \
								  else Player.COST_PROTECTED_TRACK
				network.downgrade_link(req["link_id"])
				human_player.credits_remaining = mini(
					human_player.credits_remaining + refund,
					human_player.credits_per_round
				)
		else:
			human_player.buy_upgrade(req["link_id"], level, network)

	_recalculate_and_end_round()


# --- Private Round Logic ---

func _start_round(round_num: int) -> void:
	current_round = round_num
	_round_start_player_data.clear()
	for p in human_players:
		_round_start_player_data.append({
			"safety": p.safety_score,
			"time": p.current_route.get("total_time", 0.0),
		})
	if treatment != Treatment.INDIVIDUAL:
		_round_start_city_metrics = _compute_city_metrics()
	for p in human_players:
		p.start_round(round_num)
	emit_signal("round_started", round_num, human_player.credits_per_round)

	if treatment == Treatment.COLLECTIVE_CHAT:
		_emit_simulated_chat_message()


func _recalculate_and_end_round() -> void:
	for p in human_players:
		p.current_route = network.find_route(p.home, p.work, p.alpha)

	for p in human_players:
		var updated_route := network.find_route(p.home, p.work, p.alpha)
		p.end_round(updated_route)
		p.baseline_time = updated_route.get("total_time", p.baseline_time)
		p.safety_score = p._compute_safety(updated_route, network)
		emit_signal("route_updated", p.player_id, updated_route)

	var players_data: Array = []
	for i in range(human_players.size()):
		var p: Player = human_players[i]
		players_data.append({
			"player_id": p.player_id,
			"alpha": p.alpha,
			"time": p.current_route.get("total_time", 0.0),
			"time_before": _round_start_player_data[i]["time"],
			"safety": p.safety_score,
			"safety_before": _round_start_player_data[i]["safety"],
			"safety_delta": p.safety_score - _round_start_player_data[i]["safety"],
			"time_delta": p.time_delta_from_baseline(),
			"own_route_upgrade_share": Player.own_route_share(p.round_log.back()),
			"cumulative_own_route_upgrade_share": p.cumulative_own_route_share(),
		})

	var results: Dictionary = {
		"round":             current_round,
		"alpha":             human_player.alpha,
		"group_mode":        treatment == Treatment.COLLECTIVE_CHAT,
		"personal_time":     human_player.current_route.get("total_time", 0.0),
		"personal_time_before": _round_start_player_data[0]["time"],
		"personal_safety":   human_player.safety_score,
		"safety_before":     _round_start_player_data[0]["safety"],
		"safety_delta":      human_player.safety_score - _round_start_player_data[0]["safety"],
		"time_delta":        human_player.time_delta_from_baseline(),
		"credits_spent":     human_player.round_log.back().get("credits_spent", 0),
		"credits_remaining": human_player.credits_remaining,
		"upgrades":          human_player.round_log.back().get("upgrades", []),
		"own_route_upgrade_share": Player.own_route_share(human_player.round_log.back()),
		"cumulative_own_route_upgrade_share": human_player.cumulative_own_route_share(),
		"players":           players_data,
	}

	if treatment != Treatment.INDIVIDUAL:
		var city_metrics = _compute_city_metrics()
		results["city_avg_time"]          = city_metrics["avg_time"]
		results["city_avg_safety"]        = city_metrics["avg_safety"]
		results["city_coverage"]          = city_metrics["coverage"]
		results["city_avg_time_before"]   = _round_start_city_metrics.get("avg_time", null)
		results["city_avg_safety_before"] = _round_start_city_metrics.get("avg_safety", null)
		results["city_coverage_before"]   = _round_start_city_metrics.get("coverage", null)
		if _round_start_city_metrics.has("avg_time"):
			results["city_avg_time_delta"] = city_metrics["avg_time"] - _round_start_city_metrics["avg_time"]
		if _round_start_city_metrics.has("avg_safety"):
			results["city_avg_safety_delta"] = city_metrics["avg_safety"] - _round_start_city_metrics["avg_safety"]
		emit_signal("city_metrics_updated", city_metrics)

	emit_signal("round_ended", current_round, results)


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
	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	ai_commuters.clear()
	var node_count: int = network.all_nodes.size()
	for i in range(count):
		var start: Vector2i = network.all_nodes[rng.randi_range(0, node_count - 1)]
		var goal: Vector2i  = network.all_nodes[rng.randi_range(0, node_count - 1)]
		while goal == start:
			goal = network.all_nodes[rng.randi_range(0, node_count - 1)]

		ai_commuters.append({ "start": start, "goal": goal, "alpha": 1.5 })


func _compute_city_metrics() -> Dictionary:
	var total_time: float = 0.0
	var total_safety: float = 0.0
	for commuter in ai_commuters:
		var route = network.find_route(commuter["start"], commuter["goal"], commuter["alpha"])
		total_time += route.get("total_time", 0.0)
		total_safety += Player.route_safety(route, network, commuter["alpha"])

	for p: Player in human_players:
		total_time += p.current_route.get("total_time", 0.0)
		total_safety += p.safety_score

	var count: float = float(ai_commuters.size() + human_players.size())
	return {
		"avg_time":   total_time / count,
		"avg_safety": total_safety / count,
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
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var msg = messages[rng.randi_range(0, messages.size() - 1)]

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
