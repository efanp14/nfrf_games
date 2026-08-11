class_name Player
## Player.gd
## Owns one player's commute context, budget, and per-round actions.
## Deliberately thin: it stores state and validates moves; it doesn't touch UI.

# --- Safety Score Scaling ---
## Spec formula is Safety = 100 - Σ(stress weights), but a literal unscaled
## sum barely moves across the whole unimproved→protected range (confirmed
## by owner sign-off 7 Jul 2026 — literal formula produced <2pt swings).
##
## A single FLAT scale on the raw stress sum (tried first: SCALE=18) cannot
## simultaneously (a) make every unimproved route read ≤50 and (b) let a
## fully protected route read ≥70 for every personality — routes vary too
## much in total length/stress for one flat multiplier to fit both ends at
## once (proven, not just missed by tuning: the scale strict enough for (a)
## makes even a confident rider's 40% protected relief (β=0.6) unable to
## climb back above "safe" on the network's longest/highest-stress routes).
##
## Fix: normalize each route's stress sum against that SAME route's own
## fully-unimproved baseline (β=1 on every link it uses), so the score
## reflects "how much of THIS route's own starting risk have I removed" —
## independent of whether the route happens to be long/short, busy/quiet.
## ratio=1.0 (still fully unimproved) always reads the same regardless of
## route, and ratio=β (fully protected, uniform β across the route) always
## reads 100 - β×DEFICIT, so a confident rider fully protected (β=0.6)
## reads 100-0.6×50=70 (right at "good"), average (β=0.2) reads 90, and
## cautious (β=0.1) reads 95 — on every route, not just short ones.
const SAFETY_TARGET_DEFICIT: float = 50.0

# --- Upgrade Cost ---
## Defined here (not in the network) because cost is a game/economy rule,
## even though it reads the link's base_time. base_time isn't a real-world
## duration on its own — it's derived from the link's on-screen pixel length
## (see CityNetwork._build_network) — so to get a real-world $ cost we first
## convert it to a real-world distance, then price that distance per metre.
##
## Distance conversion (owner reference, 3 Aug 2026): a 14-minute bike ride
## is about 5 km, so CYCLING_SPEED_M_PER_MIN = 5000/14 ≈ 357 m/min (≈21.4
## km/h).
##
## Per-metre rates come from the July 2026 data requirements document, which
## sources them from a consultant estimate on a Calgary Complete Streets
## basis: $60/m painted, $200/m protected. (Calgary is the costing basis
## only — no real place name is ever shown to a participant.)
##
## History: $60/$300 (3 Aug 2026, 5x ratio) -> $80/$280 (4 Aug 2026, owner:
## "protected is 3.5x the price of painted") -> $60/$200 here. NOTE that the
## document's figures put protected at 3.33x painted, slightly narrower than
## the 3.5x the owner asked for on 4 Aug; the document's numbers were taken
## as authoritative since they are externally sourced and defensible in
## write-up, but the ratio did move.
##
## The document also groups links into three representative lengths (150 /
## 300 / 450 m). Those are NOT used: this network's links run 929-5,357 m, so
## none fall in that range, and the decision was to keep real per-link
## lengths and adopt only the unit rates. Cost therefore stays continuous
## (length x rate) rather than bucketed into three flat prices.
const CYCLING_SPEED_M_PER_MIN: float = 5000.0 / 14.0
const COST_PER_METRE_PAINTED: float = 60.0
const COST_PER_METRE_PROTECTED: float = 200.0

## Dollar cost to buy `level` (1 = painted, 2 = protected) on `link`,
## rounded to the nearest $1,000 — at real-construction-cost scale, nearest
## $5 no longer reads as a clean number.
static func cost_for_link(link: CityNetwork.Link, level: int) -> int:
	var rate: float = COST_PER_METRE_PAINTED if level == 1 else COST_PER_METRE_PROTECTED
	return int(round(link_length_m(link) * rate / 1000.0)) * 1000


## Real-world length of a link in metres, converted from its base_time by the
## CYCLING_SPEED_M_PER_MIN figure above. Split out of cost_for_link() because
## length is also recorded per upgrade in the research log, so analysis can
## compare/price links without re-deriving the conversion.
static func link_length_m(link: CityNetwork.Link) -> float:
	return link.base_time * CYCLING_SPEED_M_PER_MIN


## "$1,100,000" instead of "$1100000" — at real-construction-cost scale
## (six/seven figures per link), comma grouping is needed for the number to
## read cleanly at a glance. GDScript's String % formatting has no built-in
## thousands separator, hence this helper.
static func format_dollars(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return ("-$" if amount < 0 else "$") + grouped

# --- Identity ---
var player_id: String
var home: Vector2i
var work: Vector2i

## Alpha = stress sensitivity from pre-survey.
## High alpha → player avoids high-LTS roads more strongly.
## Range 0.5 (risk-tolerant) to 2.0 (very cautious)
var alpha: float = 1.0

# --- Budget ---
## Sized against the network's MEDIAN protected upgrade, so the round budget
## keeps a consistent "how many typical upgrades can I buy" feel whenever the
## unit rates move. The owner's standing intent (4 Aug 2026) is **3-4 typical
## protected upgrades per round** — enough to make painted-vs-protected a real
## trade-off without letting a player simply buy everything.
##
## History: $600 -> $1.1M (3 Aug 2026, when pricing moved to real
## construction costs) -> flat $2,000,000 (4 Aug 2026, owner override to
## reach the 3-4 feel at the then-current $80/$280 rates).
##
## Re-derived here after rates dropped to $60/$200 (see cost_for_link). At
## those rates the median protected upgrade is $364,000, so the old
## $2,000,000 had drifted to 5.5 upgrades/round — well past the intended 3-4,
## because the budget had been left untouched while prices fell. 3.5x the
## median lands at $1,274,000, rounded to $1,300,000 = 3.6 median protected
## upgrades per round.
##
## Deliberately still above the network's most expensive single protected
## upgrade ($1,071,000, the 5,357 m link), so no link is ever impossible to
## protect within one round — a budget below that would silently make the
## longest roads unbuyable rather than merely expensive.
##
## A constant as well as a default, so participant-facing text can quote the
## budget without hardcoding it a second time. The main menu previously carried
## its own literal and was left saying $2,000,000 after this figure was
## re-derived, which is exactly the drift a single definition prevents.
const DEFAULT_CREDITS_PER_ROUND: int = 1300000

var credits_per_round: int = DEFAULT_CREDITS_PER_ROUND
var credits_remaining: int = 0

# --- Route Cache ---
## Populated each round by GameManager after network updates.
var current_route: Dictionary = {}   # { path, total_time, total_impedance }

## Prospect Theory reference point — **STATIC** (owner, 3 Aug 2026).
## Every round's gain/loss is measured against the Round-1 baseline, i.e. the
## untouched network, NOT against the previous round. So a player who improves
## their commute in Round 1 and then does nothing in Round 2 still sees the
## accumulated gain, rather than "no change".
##
## These are set once at game start and never move. `baseline_time` used to be
## overwritten at the end of every round (making the reference dynamic); that
## roll-forward has been removed. It is kept as a separate field from
## `initial_baseline_time` only because both names are already referenced
## elsewhere — under a static reference the two always hold the same value.
var baseline_time: float = 0.0
var initial_baseline_time: float = 0.0
var initial_baseline_safety: float = 0.0
var initial_baseline_stress: float = 0.0
var initial_baseline_impedance: float = 0.0
## The links of the Round-1 route, kept alongside the baseline scalars beside it.
## The data spec asks for "the baseline route between home and work before any
## investment" as its own output, and while it is recoverable from Round 1's
## route_links_before, that requires knowing to look there and having Round 1 to
## hand. Carrying it on every round makes the comparison "is this person still
## riding the route they started on" a direct one.
var initial_baseline_route_links: Array = []

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
		"removals": [],
		"time_before": current_route.get("total_time", 0.0),
		"time_after": 0.0,
		"credits_spent": 0,
		# Recorded explicitly rather than left to be re-derived as
		# spent + remaining, which refunds can make ambiguous.
		"budget_available": credits_per_round,
	})


## Attempt to purchase an upgrade for a link.
## Returns true on success, false if insufficient credits or invalid upgrade.
func buy_upgrade(link_id: String, upgrade_level: int, network: CityNetwork) -> bool:
	var link: CityNetwork.Link = network.links.get(link_id)
	if link == null:
		return false
	var cost: int = Player.cost_for_link(link, upgrade_level)

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
	entry["upgrades"].append({
		"link": link_id,
		"level": upgrade_level,
		"cost": cost,
		"own_route": is_own_route,
		"length_m": link_length_m(link),
		"base_time_min": link.base_time,
	})
	entry["credits_spent"] += cost
	if is_own_route:
		entry["own_route_spent"] = entry.get("own_route_spent", 0) + cost
	else:
		entry["other_route_spent"] = entry.get("other_route_spent", 0) + cost

	return true


## Records a confirmed removal of an already-built upgrade. Removals are
## applied by GameManager via CityNetwork.downgrade_link() rather than through
## buy_upgrade(), so without this they left no trace in the round log at all.
## Kept in its own array rather than appended to "upgrades" so the existing
## upgrades schema — and every metric derived from it — stays unchanged.
func record_downgrade(link_id: String, from_level: int, refund: int, link: CityNetwork.Link) -> void:
	round_log.back()["removals"].append({
		"link": link_id,
		"from_level": from_level,
		"refund": refund,
		"length_m": link_length_m(link),
		"base_time_min": link.base_time,
	})


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
## Safety = 100 - ratio * SAFETY_TARGET_DEFICIT, where ratio is this route's
## current stress sum divided by what that SAME route's stress sum would be
## fully unimproved (see SAFETY_TARGET_DEFICIT comment for why it's
## normalized this way rather than a flat scale on the raw sum).
static func route_safety(route: Dictionary, network: CityNetwork, rider_alpha: float) -> float:
	var baseline_sum: float = route_stress_unimproved(route, network)
	if baseline_sum <= 0.0:
		return 100.0
	var ratio: float = route_stress(route, network, rider_alpha) / baseline_sum
	return maxf(0.0, 100.0 - ratio * SAFETY_TARGET_DEFICIT)


## Raw, unnormalized stress exposure along a route: Σ(β × base_stress ×
## base_time). This is the "total route stress" the research log records
## before and after every round — deliberately distinct from the 0-100 safety
## score above, which normalizes this same figure against the route's own
## unimproved baseline so it reads consistently across long and short
## commutes. Analysis needs the raw sum too, hence both.
static func route_stress(route: Dictionary, network: CityNetwork, rider_alpha: float) -> float:
	return _stress_sum(route, network, rider_alpha, false)


## The same sum with every link forced to β = 1 (fully unimproved) — the
## denominator route_safety() normalizes against.
static func route_stress_unimproved(route: Dictionary, network: CityNetwork) -> float:
	return _stress_sum(route, network, 0.0, true)


static func _stress_sum(route: Dictionary, network: CityNetwork, rider_alpha: float, unimproved: bool) -> float:
	if route.is_empty() or network == null:
		return 0.0
	var total: float = 0.0
	var path: Array = route.get("path", [])
	for i in range(path.size() - 1):
		var link_id: String = "%d,%d-%d,%d" % [path[i].x, path[i].y, path[i+1].x, path[i+1].y]
		if network.links.has(link_id):
			var link: CityNetwork.Link = network.links[link_id]
			var beta: float = 1.0 if unimproved else link.effective_beta(rider_alpha)
			# Weighted by base_time, NOT effective_time: stress exposure scales
			# with the physical length of road ridden, not with how fast the
			# infrastructure lets you cover it. Using effective_time here would
			# double-count the upgrade — once as reduced stress via beta, again
			# as reduced exposure — and would shift the safety score's meaning.
			total += beta * link.stress_score * link.base_time
	return total


## Canonical link IDs along a route, in travel order — the "links included in
## each route" the research log records before and after every round. Uses
## canonical (direction-independent) IDs so a route's links join directly
## against upgrade records no matter which way the rider traversed them.
static func route_link_ids(route: Dictionary) -> Array:
	var ids: Array = []
	var path: Array = route.get("path", [])
	for i in range(path.size() - 1):
		ids.append(CityNetwork.canonical_link_id(path[i], path[i + 1]))
	return ids


## Separate scale from SAFETY_STRESS_SCALE because this previews a single
## link in isolation — no route length to sum stress-over-time across, so
## it needs its own calibration. Recalibrated 4 Aug 2026 after the
## network-wide stress rewrite raised the floor from 0.15 to 0.40 (average
## 0.60) — the old scale (210) was tuned against that old 0.15 floor, so
## stress x 210 now exceeds 100 for nearly every unimproved link, clamping
## every single-link preview to 0 stars regardless of which road it was
## (reported by owner: "all roads are currently zero stars"). New scale
## (100) means safety = 100 x (1 - stress), so the network's lowest-stress
## link (0.44) reads as exactly 3/5 stars unimproved — same design intent as
## before (never a full 5/5 while unimproved, now generalized to "never
## above 3/5" given the new higher floor), while the average link (~0.60)
## reads 2/5 and the worst (~0.92) reads 0/5. Verified by script against
## every link in the network, not just eyeballed.
const LINK_PREVIEW_STRESS_SCALE: float = 100.0

## Preview safety score for a single link in isolation, used by the upgrade
## popup before a route ever touches it (so a player can see how upgrading
## THIS link would change ITS safety, independent of their current route).
static func link_preview_safety(link: CityNetwork.Link, rider_alpha: float) -> float:
	var stress_weight: float = link.effective_beta(rider_alpha) * link.stress_score
	return maxf(0.0, 100.0 - stress_weight * LINK_PREVIEW_STRESS_SCALE)


## Prospect Theory delta: time change against the STATIC Round-1 baseline.
## Positive = gain (faster than at the start), negative = loss (slower).
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


## Money spent across every round played so far, as distinct from this round's
## spend. Refunds from removals return to the wallet but are deliberately not
## subtracted here, matching the per-round figure this sums.
func cumulative_credits_spent() -> int:
	var total: int = 0
	for entry in round_log:
		total += int(entry.get("credits_spent", 0))
	return total


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
			"budget_available": entry.get("budget_available", credits_per_round),
			"credits_spent": entry["credits_spent"],
			"upgrades": JSON.stringify(entry["upgrades"]),
			"removals": JSON.stringify(entry.get("removals", [])),
		})
	return rows
