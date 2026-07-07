class_name Player
## Player.gd
## Owns one player's commute context, budget, and per-round actions.
## Deliberately thin: it stores state and validates moves; it doesn't touch UI.

# --- Upgrade Cost Constants ---
## Defined here (not in the network) because cost is a game/economy rule.
const COST_PAINTED_LANE: int = 10   # Dollars
const COST_PROTECTED_TRACK: int = 30

# --- Identity ---
var player_id: String
var home: Vector2i
var work: Vector2i

## Alpha = stress sensitivity from pre-survey.
## High alpha → player avoids high-LTS roads more strongly.
## Range 0.5 (risk-tolerant) to 2.0 (very cautious)
var alpha: float = 1.0

# --- Budget ---
var credits_per_round: int = 100
var credits_remaining: int = 0

# --- Route Cache ---
## Populated each round by GameManager after network updates.
var current_route: Dictionary = {}   # { path, total_time, total_impedance }
var baseline_time: float = 0.0         # rolls forward each round (Prospect Theory per-round delta)
var initial_baseline_time: float = 0.0 # set once at game start; used for end-of-game comparison

# --- Round Log ---
## Each entry: { round: int, upgrades: Array, time_before: float, time_after: float, credits_spent: int }
## Used for data logging and post-game analysis.
var round_log: Array = []

# --- Safety Score ---
## 100 minus the sum of stress weights along the current route.
## Gives players a second axis (safety vs time) to optimize.
var safety_score: float = 100.0


func _init(pid: String, home_node: Vector2i, work_node: Vector2i, stress_alpha: float) -> void:
	player_id = pid
	home = home_node
	work = work_node
	alpha = stress_alpha


## Called by GameManager at the start of each round.
func start_round(round_num: int) -> void:
	credits_remaining = credits_per_round
	round_log.append({
		"round": round_num,
		"upgrades": [],
		"time_before": current_route.get("total_time", 0.0),
		"time_after": 0.0,
		"credits_spent": 0,
	})


## Attempt to purchase an upgrade for a link.
## Returns true on success, false if insufficient credits or invalid upgrade.
func buy_upgrade(link_id: String, upgrade_level: int, network: CityNetwork) -> bool:
	var cost: int = COST_PAINTED_LANE if upgrade_level == 1 else COST_PROTECTED_TRACK

	# Validate: can we afford it?
	if credits_remaining < cost:
		push_warning("Player %s: not enough credits for upgrade (need %d, have %d)" \
			% [player_id, cost, credits_remaining])
		return false

	# Delegate actual network mutation to the network object
	if not network.upgrade_link(link_id, upgrade_level):
		return false  # already upgraded or link not found

	credits_remaining -= cost

	# Record in the current round log entry
	var entry: Dictionary = round_log.back()
	entry["upgrades"].append({ "link": link_id, "level": upgrade_level, "cost": cost })
	entry["credits_spent"] += cost

	return true


## Finalise the round after routes are recalculated.
func end_round(updated_route: Dictionary) -> void:
	current_route = updated_route
	var entry: Dictionary = round_log.back()
	entry["time_after"] = updated_route.get("total_time", 0.0)
	# Safety is now computed by GameManager which has network access


## Compute safety score from the route path.
## network reference needed to look up link stress — passed as param to avoid tight coupling.
func _compute_safety(route: Dictionary, network: CityNetwork) -> float:
	if route.is_empty() or network == null:
		return safety_score  # retain last value if no data
	# Safety = 100 - sum(beta * stress_score * base_time) along path.
	# beta is the infrastructure relief (1.0 unimproved → ~0.1 protected track),
	# so upgrades directly reduce the stress contribution of each link.
	var stress_sum: float = 0.0
	var path: Array = route.get("path", [])
	for i in range(path.size() - 1):
		var link_id: String = "%d,%d-%d,%d" % [path[i].x, path[i].y, path[i+1].x, path[i+1].y]
		if network.links.has(link_id):
			var link: CityNetwork.Link = network.links[link_id]
			stress_sum += link.beta * link.stress_score * link.base_time
	return maxf(0.0, 100.0 - stress_sum * 5.0)


## Prospect Theory helper: time change relative to the player's personal baseline.
## Positive = gain (faster), Negative = loss (slower).
## Used by the analytics layer; not needed for core game flow.
func time_delta_from_baseline() -> float:
	return baseline_time - current_route.get("total_time", baseline_time)


## Export the full log as a flat array of Dictionaries for CSV / backend submission.
func export_log() -> Array:
	var rows: Array = []
	for entry in round_log:
		rows.append({
			"player_id": player_id,
			"round": entry["round"],
			"time_before": entry["time_before"],
			"time_after": entry["time_after"],
			"credits_spent": entry["credits_spent"],
			"upgrades": JSON.stringify(entry["upgrades"]),
		})
	return rows
