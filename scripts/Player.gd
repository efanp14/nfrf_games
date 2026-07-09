class_name Player
## Player.gd
## Owns one player's commute context, budget, and per-round actions.
## Deliberately thin: it stores state and validates moves; it doesn't touch UI.

# --- Safety Score Scaling ---
## Spec formula is Safety = 100 - Σ(stress weights), but a literal unscaled
## sum barely moves across the whole unimproved→protected range (confirmed
## by owner sign-off 7 Jul 2026 — literal formula produced <2pt swings).
## This scale factor is what makes upgrades visibly register in the 0-100
## score, emoji/face display, and Prospect-Theory deltas.
const SAFETY_STRESS_SCALE: float = 5.0

# --- Upgrade Cost Constants ---
## Defined here (not in the network) because cost is a game/economy rule.
##
## Flat per-upgrade cost in dollars — every link costs the same regardless
## of its actual on-screen length; the game does not price per metre.
## The numbers themselves are grounded in real PER-LINEAR-METRE construction
## pricing for a Medicine-Hat-like city, applied to a representative run
## length per tier, then rounded to clean numbers:
##   painted:   ~$60/linear metre  × ~100m run  ≈ $6,000  → rounded to $100
##   protected: ~$200/linear metre (quick-build) × ~300m run ≈ $60,000 → rounded to $300
## Only the ratio (1:3) and relative scale carry over from that real-world
## per-metre basis — the in-game constants below are flat totals, not rates.
const COST_PAINTED_LANE: int = 100   # Dollars
const COST_PROTECTED_TRACK: int = 300

# --- Identity ---
var player_id: String
var home: Vector2i
var work: Vector2i

## Alpha = stress sensitivity from pre-survey.
## High alpha → player avoids high-LTS roads more strongly.
## Range 0.5 (risk-tolerant) to 2.0 (very cautious)
var alpha: float = 1.0

# --- Budget ---
## 600/round affords at most 2 protected upgrades (600 / 300), or a mix of
## painted + protected — the intended tight trade-off.
var credits_per_round: int = 600
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

	# Record in the current round log entry. own_route reflects the route
	# this player was actually riding at the moment of purchase (current_route
	# is last round's outcome / this round's starting route, not yet updated)
	# — used for the "own-route upgrade share" behavioral metric: how much of
	# a player's spending helps only their own commute vs. links they'll
	# never personally use (self- vs. other-oriented investment).
	var is_own_route: bool = Player.route_contains_link(current_route, link_id)
	var entry: Dictionary = round_log.back()
	entry["upgrades"].append({ "link": link_id, "level": upgrade_level, "cost": cost, "own_route": is_own_route })
	entry["credits_spent"] += cost
	if is_own_route:
		entry["own_route_spent"] = entry.get("own_route_spent", 0) + cost
	else:
		entry["other_route_spent"] = entry.get("other_route_spent", 0) + cost

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
	return Player.route_safety(route, network, alpha)


## Pure/static version of the safety formula, usable for any rider (human
## player or simulated resident) without needing a Player instance — e.g.
## for city-wide average safety in GameManager._compute_city_metrics().
## Safety = 100 - sum(beta * stress_score * base_time) along path.
## beta is the infrastructure relief; on protected track it depends on the
## rider's own alpha/personality, so upgrades reduce the stress contribution
## of each link by an amount that varies by rider.
static func route_safety(route: Dictionary, network: CityNetwork, rider_alpha: float) -> float:
	if route.is_empty() or network == null:
		return 100.0
	var stress_sum: float = 0.0
	var path: Array = route.get("path", [])
	for i in range(path.size() - 1):
		var link_id: String = "%d,%d-%d,%d" % [path[i].x, path[i].y, path[i+1].x, path[i+1].y]
		if network.links.has(link_id):
			var link: CityNetwork.Link = network.links[link_id]
			stress_sum += link.effective_beta(rider_alpha) * link.stress_score * link.base_time
	return maxf(0.0, 100.0 - stress_sum * SAFETY_STRESS_SCALE)


## Prospect Theory helper: time change relative to the player's personal baseline.
## Positive = gain (faster), Negative = loss (slower).
## Used by the analytics layer; not needed for core game flow.
func time_delta_from_baseline() -> float:
	return baseline_time - current_route.get("total_time", baseline_time)


## True if link_id (in either direction) lies along route's path — i.e. the
## rider personally travels this link. Basis for the "own-route upgrade
## share" behavioral metric (research question: selfish vs. community-minded
## investment).
static func route_contains_link(route: Dictionary, link_id: String) -> bool:
	var parts := link_id.split("-")
	if parts.size() != 2:
		return false
	var canonical := CityNetwork.canonical_link_id(
		CityNetwork.parse_node(parts[0]), CityNetwork.parse_node(parts[1]))
	var path: Array = route.get("path", [])
	for i in range(path.size() - 1):
		if CityNetwork.canonical_link_id(path[i], path[i + 1]) == canonical:
			return true
	return false


## Fraction (0.0-1.0) of a round's spending that went to links on the
## player's own route at the moment of purchase. Returns -1.0 (undefined,
## not zero) if nothing was spent that round — callers must not treat -1.0
## as "0% own-route".
static func own_route_share(round_log_entry: Dictionary) -> float:
	var spent: int = round_log_entry.get("credits_spent", 0)
	if spent <= 0:
		return -1.0
	var own: int = round_log_entry.get("own_route_spent", 0)
	return float(own) / float(spent)


## Same as own_route_share(), aggregated across every round played so far.
func cumulative_own_route_share() -> float:
	var total_spent: int = 0
	var total_own: int = 0
	for entry in round_log:
		total_spent += entry.get("credits_spent", 0)
		total_own += entry.get("own_route_spent", 0)
	if total_spent <= 0:
		return -1.0
	return float(total_own) / float(total_spent)


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
