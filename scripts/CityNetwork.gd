class_name CityNetwork
## CityNetwork.gd
## Base topology matches the "Sioux Falls" transportation-research test
## network (24 nodes / 38 undirected links —
## github.com/bstabler/TransportationNetworks), plus an owner-designed
## 20-node "West Extension" (nodes 27-42 + 44-47, 4 Aug 2026 — see the
## comment block above the `nodes` array in _build_network), plus 2 midpoint
## nodes (48, 49) splitting the two longest original links so each half is
## independently affordable (see that comment too). Total: 46 nodes / 69
## undirected links. Node positions for the original 24 match the
## network's standard published diagram layout (Yang & Qiang, HKUST) rather
## than the dataset's raw lat/long, which clusters several nodes together at
## any sane canvas scale.
## Each link's base_time is derived from the actual on-screen pixel distance
## between its two nodes (see _build_network) rather than the dataset's own
## free-flow time — the dataset's times were measured against the real
## geographic layout, which has no relation to this diagram-based layout, so
## using them here let some short-looking roads cost more/take longer than
## long ones. Nodes use the dataset's own numeric IDs and
## carry no participant-facing name — the fictional-city design rule means
## no real-world label is ever shown to a player, so unlike the previous
## hand-authored network there is nothing to rename: it's just unlabeled.
## base_stress per link is hand-assigned from the dataset's link capacity
## (higher-capacity roads read as busier / more stressful to cycle on).
## Routing delegates to Dijkstra.gd; the game never hardcodes routes.

# --- Data Structures ---

class Link:
	var id: String
	var from_node: Vector2i
	var to_node: Vector2i
	var base_time: float
	var stress_score: float
	var upgrade_level: int
	## What this link already had before anyone played, from
	## _apply_initial_infrastructure(). The city starts with a few lanes so the
	## network is not blank on round one, and the player did not pay for them.
	##
	## Tracked separately because upgrade_level alone cannot tell an upgrade the
	## player bought from one that was always there, and removal refunds money.
	## Without it, demolishing a pre-existing protected lane paid out its full
	## price, so a player could spend their budget and then top it back up by
	## tearing out infrastructure they never funded.
	var initial_upgrade_level: int = 0
	func _init(fid: String, fn: Vector2i, tn: Vector2i, bt: float, ss: float) -> void:
		id = fid
		from_node = fn
		to_node = tn
		base_time = bt
		stress_score = ss
		upgrade_level = 0

	## Whether there is anything here the PLAYER put in, and so anything they
	## may take back out.
	func has_player_upgrade() -> bool:
		return upgrade_level > initial_upgrade_level

	## Infrastructure speed bonus, indexed by upgrade_level
	## (unimproved / painted / protected). Better cycling infrastructure lets a
	## rider cover the same road slightly FASTER: more room, fewer conflicts
	## with motor traffic, less weaving around parked cars and less slowing at
	## pinch points. A painted lane helps a little; a protected track helps a
	## little more. Applies to every rider regardless of personality — it is a
	## property of the road, not of how nervous the cyclist is.
	##
	## Deliberately small. Stress relief already moves impedance by 20-60%, so
	## an 8% time gain stays clearly secondary: the router still prefers a
	## longer, calmer route over a shorter, stressful one wherever that choice
	## exists. Raising these much above ~0.90 would start letting raw speed
	## outrank safety in route choice, which is not the intent.
	const TIME_FACTOR: Array = [1.0, 0.96, 0.92]

	## Travel time actually experienced on this link, i.e. base_time with the
	## infrastructure speed bonus applied.
	##
	## NOTE base_time itself is never modified — it remains the immutable
	## physical fact, and is still what upgrade costs and link lengths are
	## derived from (see Player.link_length_m). This is a derived value.
	func effective_time() -> float:
		return base_time * TIME_FACTOR[clampi(upgrade_level, 0, TIME_FACTOR.size() - 1)]

	## Infrastructure relief factor (β).
	## Painted relief is stress-derived (spec gives it as a flat 0.5-0.8 range).
	## Protected relief depends on the rider's personality, not the road —
	## so it's computed per-caller from their alpha rather than stored on the link.
	func effective_beta(alpha: float) -> float:
		match upgrade_level:
			0: return 1.0
			1: return 0.8 - 0.3 * stress_score
			2: return PersonalityConfig.beta_protected_for_alpha(alpha)
			_: return 1.0

	func impedance(alpha: float) -> float:
		return effective_time() * (1.0 + alpha * effective_beta(alpha) * stress_score)


# --- Network State ---

var links: Dictionary = {}
var adjacency: Dictionary = {}
var node_positions: Dictionary = {}   # Vector2i → Vector2 (screen coords)
var node_names: Dictionary = {}       # Vector2i → String (full name for link_display_name)
var node_labels: Dictionary = {}      # Vector2i → String (short label for map, "" = hidden)
var all_nodes: Array[Vector2i] = []
var home_node: Vector2i
var work_node: Vector2i
var river_points: PackedVector2Array  # cosmetic curve drawn by CityGrid

## [home, work] — node IDs are the Sioux Falls dataset's own numbering (plus
## the West Extension's own numbering for the 3 pairs updated below).
## Peripheral nodes chosen as homes, spread across the network, paired with
## work nodes on the far side so every pair crosses several links.
## Index 0 is used by T1/T2 (single-player) AND is T3's player 1 — left
## untouched so single-player behavior doesn't shift. Indices 1-4 are T3's
## "extra" players (2-5); 3 of the 4 had their work node moved into the West
## Extension (4 Aug 2026, owner: "incorporate the new roads and nodes with
## the T3 extra players' homes and works") so those players' commutes now
## actually cross the new district instead of never touching it. Index 3
## (18,1) was left as-is — it's the pair already discussed above in the West
## Extension comment (the 1-30-12 shortcut analysis); changing its work node
## would make that note stale, so it's the one pair keeping its original
## work node.
##
## INVARIANT (10 Aug 2026): across all five pairs, every home and every work
## node is DISTINCT — no node appears twice, whether as two homes, two works, or
## one player's home and another's work. A group session seats up to five
## players at once, and two of them sharing an endpoint means one person's
## workplace is another's front door: their routes converge by construction,
## the map draws two markers on one node, and the per-player outcomes stop being
## independent observations. Keep this true when editing the table; the check in
## player_pairs_overlap() enforces it at startup.
##
## Index 2's home was 7,0 until 10 Aug 2026, which collided with index 0's WORK
## node and so broke the invariant for every group of 3 or more. Index 0 is the
## single-player commute and could not move, so index 2's home did. Node 19 was
## chosen to preserve that pair's character: it is not a resident neighbourhood,
## it keeps the same 7-link structure, it is still the longest of the five
## commutes, and it still starts in the original grid and crosses into the West
## Extension rather than sitting inside it (37.3 min, was 41.9).
const HOME_WORK_PAIRS: Array = [
	[Vector2i(23, 0), Vector2i(7, 0)],
	[Vector2i(13, 0), Vector2i(46, 0)],  # was work=2; now West Extension hub node 46
	[Vector2i(19, 0), Vector2i(41, 0)],  # was home=7 (clashed with pair 0's work); was work=12
	[Vector2i(18, 0), Vector2i(1, 0)],
	[Vector2i(24, 0), Vector2i(45, 0)],  # was work=6; now West Extension node 45
]


## Any node used by more than one player as a home or a workplace, as
## "x,y" strings. Empty means the table is sound.
##
## Exists because the table is hand-edited and the clash it guards against is
## invisible on inspection: it is not two identical pairs, it is one pair's home
## equal to a different pair's work, several lines apart. That was live in the
## build for every group of three or more and nothing surfaced it.
static func player_pairs_overlap(player_count: int = HOME_WORK_PAIRS.size()) -> Array:
	var seen: Dictionary = {}
	var clashes: Dictionary = {}
	for i in range(mini(player_count, HOME_WORK_PAIRS.size())):
		for node: Vector2i in HOME_WORK_PAIRS[i]:
			var key: String = "%d,%d" % [node.x, node.y]
			if seen.has(key):
				clashes[key] = true
			seen[key] = true
	return clashes.keys()

## Fixed set of resident commute pairs (home node → destination node). 12
## "neighbourhoods" (home nodes), 99 residents total.
##
## DESTINATIONS REWRITTEN 9 Aug 2026: the commutes were too short to have a
## route at all. Measured on this network before the rewrite: 34 of the 99
## residents had a ONE-LINK commute, so Dijkstra had no choice to make for a
## third of the city, and 61 had two links or fewer. Median resident commute
## was 8.5 min against a median node-to-node trip of 22.8 min, i.e. residents
## sat at the 9th percentile of all possible trips while the five player
## commutes ran 20-42 min. Consequences: the emergent-rerouting mechanism the
## whole model rests on (§3.1) barely fired, the best single protected upgrade
## anywhere moved only 5 of 99 residents, and the time and safety benefit
## measures collapsed onto the same residents instead of telling two stories.
##
## Cause was the previous selection rule, "nearest not-yet-used node", which
## optimised commutes toward zero length. That rule was an implementation
## choice made to keep commutes plausible, NOT one of the owner's 28 Jul
## instructions. Both of those are preserved intact, see below.
##
## New rule: each neighbourhood's destinations are drawn from the SAME 20-node
## hub pool as before, restricted to nodes 18-35 min away by that
## neighbourhood's own Dijkstra distance on raw base_time (no personality, so
## the list does not shift if alpha values are ever retuned), ordered
## amenity-nodes-first and then by distance. Deterministic and authored, no
## RNG, so guardrail 3 is untouched.
##
## Preserved exactly from the 28 Jul design:
##   - owner: "at most 2 people from each neighbourhood go to the same
##     workplace". Still at most 2 per (home, destination) pair.
##   - owner: "add another neighbourhood at node 16, and increase all the
##     neighbourhoods' amounts by 2-3". Node 16 is still a 6-resident
##     neighbourhood; every per-neighbourhood resident count is unchanged.
##   - the 12 home nodes, the 20-node hub pool as the candidate set, and the
##     invariant that no home node is also a destination. 15 of the 20 hubs
##     are actually selected; nodes 2, 5, 6, 10 and 22 now sit outside every
##     neighbourhood's 18-35 min band and so no longer receive commuters.
##   - all 7 WORK_NODE_ICONS amenity nodes keep feeders (2-7 neighbourhoods
##     each), so the school/coffee/market/bank/gym/shopping icons still have
##     commuters going to them.
##
## Effect: one-link commutes 34 → 0, median commute 2 → 5 links and 8.5 →
## 24.1 min, residents' routes now touch 56 of 69 links (was 47), and the best
## single protected upgrade moves 14 of 99 residents (was 5). Residents now
## commute at roughly the same scale as the player.
##
## Still open after this change: the impedance-optimal route equals the
## pure-fastest route for 79% of residents, and is identical across all three
## personalities, because base_stress has sd 0.09 around mean 0.603 and so
## nearly cancels out of the path comparison. Fixing that needs the stress
## column restructured into corridors, which reverses a direct owner
## instruction and is therefore not done here.
##
## Route-independence note (predates this rewrite): the original clusters'
## routes were once chosen to share zero links with HOME_WORK_PAIRS. The
## 4 Aug 2026 network-wide stress rewrite already broke that property
## (reported to the owner, left as-is), and this rewrite does not restore it;
## resident routes may cross player nodes as intermediate stops. Accepted,
## consistent with the owner's standing call on this property.
##
## Same pairs every session, for reproducibility.


## Which amenity icon each simulated-resident workplace node shows, so the
## city's job clusters read as distinct destinations (a school, a café)
## instead of one repeated generic building — purely cosmetic, drawn by
## NodeMarker. Any NPC_WORK node not listed here (e.g. a future cluster)
## falls back to the generic "workbuildings" icon.
const WORK_NODE_ICONS: Dictionary = {
	Vector2i(15, 0): "school",   # fed by 21 + 14 + 28
	Vector2i(4, 0):  "coffee",   # fed by 9
	Vector2i(17, 0): "market",   # fed by 29 + 16
	Vector2i(35, 0): "bank",     # fed by 34 + 38
	Vector2i(44, 0): "gym",      # fed by 34 + 38 + 32 + 40 + 42
	Vector2i(33, 0): "shopping", # fed by 38 + 32 + 40 + 34 + 42
	Vector2i(8, 0):  "shopping_bag", # fed by 9 + 29 + 16
}

## Destinations rewritten 9 Aug 2026 (see the comment block above): drawn
## from the existing hub pool at 18-35 min out, replacing the previous
## nearest-node rule that left a third of the city with no route choice.
## Per-neighbourhood breakdown is inline below, with each destination's
## distance from its home node.
const RESIDENT_COMMUTE_PAIRS: Array = [
	# Node 1 (4): 35x2 "bank", 8x2 "shopping_bag"
	#   destination distances: 35=21min, 8=21min
	[Vector2i(1, 0), Vector2i(35, 0)],
	[Vector2i(1, 0), Vector2i(35, 0)],
	[Vector2i(1, 0), Vector2i(8, 0)],
	[Vector2i(1, 0), Vector2i(8, 0)],
	# Node 9 (10): 33x2 "shopping", 44x2 "gym", 20x2, 30x2, 36x2
	#   destination distances: 33=25min, 44=27min, 20=20min, 30=20min, 36=31min
	[Vector2i(9, 0), Vector2i(33, 0)],
	[Vector2i(9, 0), Vector2i(33, 0)],
	[Vector2i(9, 0), Vector2i(44, 0)],
	[Vector2i(9, 0), Vector2i(44, 0)],
	[Vector2i(9, 0), Vector2i(20, 0)],
	[Vector2i(9, 0), Vector2i(20, 0)],
	[Vector2i(9, 0), Vector2i(30, 0)],
	[Vector2i(9, 0), Vector2i(30, 0)],
	[Vector2i(9, 0), Vector2i(36, 0)],
	[Vector2i(9, 0), Vector2i(36, 0)],
	# Node 14 (9): 8x2 "shopping_bag", 33x2 "shopping", 44x2 "gym", 35x2 "bank", 30x1
	#   destination distances: 8=20min, 33=24min, 44=26min, 35=34min, 30=18min
	[Vector2i(14, 0), Vector2i(8, 0)],
	[Vector2i(14, 0), Vector2i(8, 0)],
	[Vector2i(14, 0), Vector2i(33, 0)],
	[Vector2i(14, 0), Vector2i(33, 0)],
	[Vector2i(14, 0), Vector2i(44, 0)],
	[Vector2i(14, 0), Vector2i(44, 0)],
	[Vector2i(14, 0), Vector2i(35, 0)],
	[Vector2i(14, 0), Vector2i(35, 0)],
	[Vector2i(14, 0), Vector2i(30, 0)],
	# Node 16 (6): 33x2 "shopping", 44x2 "gym", 3x2
	#   destination distances: 33=28min, 44=30min, 3=21min
	[Vector2i(16, 0), Vector2i(33, 0)],
	[Vector2i(16, 0), Vector2i(33, 0)],
	[Vector2i(16, 0), Vector2i(44, 0)],
	[Vector2i(16, 0), Vector2i(44, 0)],
	[Vector2i(16, 0), Vector2i(3, 0)],
	[Vector2i(16, 0), Vector2i(3, 0)],
	# Node 21 (10): 8x2 "shopping_bag", 4x2 "coffee", 44x2 "gym", 33x2 "shopping", 35x2 "bank"
	#   destination distances: 8=22min, 4=25min, 44=25min, 33=33min, 35=33min
	[Vector2i(21, 0), Vector2i(8, 0)],
	[Vector2i(21, 0), Vector2i(8, 0)],
	[Vector2i(21, 0), Vector2i(4, 0)],
	[Vector2i(21, 0), Vector2i(4, 0)],
	[Vector2i(21, 0), Vector2i(44, 0)],
	[Vector2i(21, 0), Vector2i(44, 0)],
	[Vector2i(21, 0), Vector2i(33, 0)],
	[Vector2i(21, 0), Vector2i(33, 0)],
	[Vector2i(21, 0), Vector2i(35, 0)],
	[Vector2i(21, 0), Vector2i(35, 0)],
	# Node 28 (9): 4x2 "coffee", 17x2 "market", 8x2 "shopping_bag", 44x2 "gym", 33x1 "shopping"
	#   destination distances: 4=22min, 17=24min, 8=30min, 44=32min, 33=34min
	[Vector2i(28, 0), Vector2i(4, 0)],
	[Vector2i(28, 0), Vector2i(4, 0)],
	[Vector2i(28, 0), Vector2i(17, 0)],
	[Vector2i(28, 0), Vector2i(17, 0)],
	[Vector2i(28, 0), Vector2i(8, 0)],
	[Vector2i(28, 0), Vector2i(8, 0)],
	[Vector2i(28, 0), Vector2i(44, 0)],
	[Vector2i(28, 0), Vector2i(44, 0)],
	[Vector2i(28, 0), Vector2i(33, 0)],
	# Node 29 (9): 15x2 "school", 33x2 "shopping", 44x2 "gym", 19x2, 3x1
	#   destination distances: 15=24min, 33=29min, 44=31min, 19=19min, 3=22min
	[Vector2i(29, 0), Vector2i(15, 0)],
	[Vector2i(29, 0), Vector2i(15, 0)],
	[Vector2i(29, 0), Vector2i(33, 0)],
	[Vector2i(29, 0), Vector2i(33, 0)],
	[Vector2i(29, 0), Vector2i(44, 0)],
	[Vector2i(29, 0), Vector2i(44, 0)],
	[Vector2i(29, 0), Vector2i(19, 0)],
	[Vector2i(29, 0), Vector2i(19, 0)],
	[Vector2i(29, 0), Vector2i(3, 0)],
	# Node 32 (8): 35x2 "bank", 4x2 "coffee", 17x2 "market", 15x2 "school"
	#   destination distances: 35=20min, 4=22min, 17=32min, 15=32min
	[Vector2i(32, 0), Vector2i(35, 0)],
	[Vector2i(32, 0), Vector2i(35, 0)],
	[Vector2i(32, 0), Vector2i(4, 0)],
	[Vector2i(32, 0), Vector2i(4, 0)],
	[Vector2i(32, 0), Vector2i(17, 0)],
	[Vector2i(32, 0), Vector2i(17, 0)],
	[Vector2i(32, 0), Vector2i(15, 0)],
	[Vector2i(32, 0), Vector2i(15, 0)],
	# Node 34 (9): 4x2 "coffee", 39x2, 12x2, 3x2, 11x1
	#   destination distances: 4=28min, 39=18min, 12=22min, 3=24min, 11=27min
	[Vector2i(34, 0), Vector2i(4, 0)],
	[Vector2i(34, 0), Vector2i(4, 0)],
	[Vector2i(34, 0), Vector2i(39, 0)],
	[Vector2i(34, 0), Vector2i(39, 0)],
	[Vector2i(34, 0), Vector2i(12, 0)],
	[Vector2i(34, 0), Vector2i(12, 0)],
	[Vector2i(34, 0), Vector2i(3, 0)],
	[Vector2i(34, 0), Vector2i(3, 0)],
	[Vector2i(34, 0), Vector2i(11, 0)],
	# Node 38 (8): 33x2 "shopping", 35x2 "bank", 36x2, 30x2
	#   destination distances: 33=23min, 35=23min, 36=19min, 30=23min
	[Vector2i(38, 0), Vector2i(33, 0)],
	[Vector2i(38, 0), Vector2i(33, 0)],
	[Vector2i(38, 0), Vector2i(35, 0)],
	[Vector2i(38, 0), Vector2i(35, 0)],
	[Vector2i(38, 0), Vector2i(36, 0)],
	[Vector2i(38, 0), Vector2i(36, 0)],
	[Vector2i(38, 0), Vector2i(30, 0)],
	[Vector2i(38, 0), Vector2i(30, 0)],
	# Node 40 (8): 35x2 "bank", 4x2 "coffee", 36x2, 12x2
	#   destination distances: 35=24min, 4=29min, 36=20min, 12=22min
	[Vector2i(40, 0), Vector2i(35, 0)],
	[Vector2i(40, 0), Vector2i(35, 0)],
	[Vector2i(40, 0), Vector2i(4, 0)],
	[Vector2i(40, 0), Vector2i(4, 0)],
	[Vector2i(40, 0), Vector2i(36, 0)],
	[Vector2i(40, 0), Vector2i(36, 0)],
	[Vector2i(40, 0), Vector2i(12, 0)],
	[Vector2i(40, 0), Vector2i(12, 0)],
	# Node 42 (9): 35x2 "bank", 4x2 "coffee", 17x2 "market", 12x2, 36x1
	#   destination distances: 35=23min, 4=25min, 17=35min, 12=19min, 36=19min
	[Vector2i(42, 0), Vector2i(35, 0)],
	[Vector2i(42, 0), Vector2i(35, 0)],
	[Vector2i(42, 0), Vector2i(4, 0)],
	[Vector2i(42, 0), Vector2i(4, 0)],
	[Vector2i(42, 0), Vector2i(17, 0)],
	[Vector2i(42, 0), Vector2i(17, 0)],
	[Vector2i(42, 0), Vector2i(12, 0)],
	[Vector2i(42, 0), Vector2i(12, 0)],
	[Vector2i(42, 0), Vector2i(36, 0)],
]


func _init(pair_index: int = 0) -> void:
	_build_network(pair_index)


# --- Sioux Falls test network — 24 nodes, 38 undirected links ---
# Node IDs are the dataset's own numbering (Vector2i(n, 0) — the 0 is
# unused, just satisfying Vector2i's two-int shape so the rest of the
# codebase's Vector2i-keyed adjacency/link-ID machinery needs no changes).
# Positions are laid out on a clean grid matching the network's standard
# published diagram (bstabler/TransportationNetworks / countless transport-
# engineering papers) — NOT the dataset's raw lat/long, which clusters
# several nodes (e.g. 16/17/19) only ~20px apart at any sane canvas scale
# and produces a tangled, overlapping map instead of the clean layout the
# diagram shows. No node has a participant-facing name (see class comment above).

func _build_network(pair_index: int = 0) -> void:
	# --- Node positions: [ID, screen_pos] ---
	# Coordinates read directly off the canonical published diagram (Yang &
	# Qiang, HKUST — "Sioux Falls Test Network"), then scaled up 50% (3 Aug
	# 2026, owner request) to space the nodes out more on screen — a uniform
	# scale from the origin, so every pairwise node distance (and therefore
	# every edge's base_time below, re-derived from these coordinates by the
	# same pixel-distance formula) is exactly 1.5x what it was. It's a strict
	# column/row grid with exactly three diagonal exceptions: 10↔17, 22↔20,
	# and the long 18↔20 spoke — everything else is a straight horizontal/
	# vertical line, which is what makes the source diagram read as clean/
	# planar.
	# Columns: A=295.5 (1,3,12,13)  B=478.5 (4,11,14,23,24)  C=682.5 (5,9,10,15,22,21)
	#          D=895.5 (6,8,16,17,19,20/2)  E=1120.5 (7,18)
	# Rows:    249 (1,2)  385.5 (3,4,5,6)  498 (7,8,9)  618 (10,11,12,16,18)
	#          738 (17 only)  879 (14,15,19)  997.5 (22,23)  1177.5 (13,20,21,24)
	#
	# --- West Extension (nodes 27-42 + 44-47, updated 4 Aug 2026 — owner
	# hand-designed this directly with a purpose-built visual editor (a
	# click-to-place/connect/drag tool built specifically so placement didn't
	# depend on manually re-tracing a sketch by eye) and exported the exact
	# GDScript node/edge arrays from it — pasted in verbatim below, not
	# re-interpreted. Node IDs have gaps (25/26/43 missing) because the
	# editor never reuses an ID once assigned, even for nodes added then
	# deleted mid-design. Second pass added nodes 45-47 and rewired 40/39's
	# connection through the new node 45 instead of a direct 40-39 edge.
	#
	# Five separate attachment points into the existing network this time —
	# nodes 1, 2, 12, 13, and 23 — not one or two, so route-independence is
	# even less automatic than prior versions and was checked accordingly
	# (script, not eyeballed) against all 5 HOME_WORK_PAIRS and all 4 unique
	# RESIDENT_COMMUTE_PAIRS routes at all 3 personality alphas. Result: NOT
	# fully independent, and this is expected/inherent to the design, not a
	# bug — node 30 connects directly to BOTH node 1 and node 12, which
	# already sit on the existing 1-3-12 path, so 1-30-12 is a genuine
	# shortcut. At alpha 1.5 and 3.0 (average/cautious riders) this changes
	# two routes: HOME_WORK_PAIRS[3] (18,1) and the (1,17) resident cluster
	# both reroute through 30 instead of 3-4-11, because the new streets are
	# lower-stress (0.20) than the old ones they bypass. Confident riders
	# (alpha 0.4) are unaffected — their impedance formula barely weights
	# stress, so the detour never pays off for them. Flagged to the owner,
	# not silently patched — if this pairing shouldn't reroute, break the
	# 1-30 or 12-30 edge; both are needed for the shortcut to exist.
	var nodes: Array = [
		[Vector2i(1, 0),  Vector2(295.5, 249.0)],
		[Vector2i(2, 0),  Vector2(895.5, 249.0)],
		[Vector2i(3, 0),  Vector2(295.5, 385.5)],
		[Vector2i(4, 0),  Vector2(478.5, 385.5)],
		[Vector2i(5, 0),  Vector2(682.5, 385.5)],
		[Vector2i(6, 0),  Vector2(895.5, 385.5)],
		[Vector2i(7, 0),  Vector2(1120.5, 498.0)],
		[Vector2i(8, 0),  Vector2(895.5, 498.0)],
		[Vector2i(9, 0),  Vector2(682.5, 498.0)],
		[Vector2i(10, 0), Vector2(682.5, 618.0)],
		[Vector2i(11, 0), Vector2(478.5, 618.0)],
		[Vector2i(12, 0), Vector2(295.5, 618.0)],
		[Vector2i(13, 0), Vector2(295.5, 1177.5)],
		[Vector2i(14, 0), Vector2(478.5, 879.0)],
		[Vector2i(15, 0), Vector2(682.5, 879.0)],
		[Vector2i(16, 0), Vector2(895.5, 618.0)],
		[Vector2i(17, 0), Vector2(895.5, 738.0)],
		[Vector2i(18, 0), Vector2(1120.5, 618.0)],
		[Vector2i(19, 0), Vector2(895.5, 879.0)],
		[Vector2i(20, 0), Vector2(895.5, 1177.5)],
		[Vector2i(21, 0), Vector2(682.5, 1177.5)],
		[Vector2i(22, 0), Vector2(682.5, 997.5)],
		[Vector2i(23, 0), Vector2(478.5, 997.5)],
		[Vector2i(24, 0), Vector2(478.5, 1177.5)],
		# West Extension — owner-designed, exported from the node editor.
		[Vector2i(27, 0), Vector2(386.1, 944.7)],
		[Vector2i(28, 0), Vector2(386.1, 767.0)],
		[Vector2i(29, 0), Vector2(1004.9, 320.1)],
		[Vector2i(30, 0), Vector2(146.9, 385.5)],
		[Vector2i(31, 0), Vector2(146.9, 231.3)],
		[Vector2i(32, 0), Vector2(-73.7, 231.3)],
		[Vector2i(33, 0), Vector2(-73.7, 385.5)],
		[Vector2i(34, 0), Vector2(200.0, 622.4)],
		[Vector2i(35, 0), Vector2(200.0, 937.5)],
		[Vector2i(36, 0), Vector2(200.0, 775.6)],
		[Vector2i(37, 0), Vector2(9.3, 917.4)],
		[Vector2i(38, 0), Vector2(3.6, 1039.2)],
		[Vector2i(39, 0), Vector2(-161.1, 981.9)],
		[Vector2i(40, 0), Vector2(-265.7, 659.6)],
		[Vector2i(41, 0), Vector2(-101.0, 613.8)],
		[Vector2i(42, 0), Vector2(-333.0, 439.0)],
		[Vector2i(44, 0), Vector2(70.9, 681.1)],
		[Vector2i(45, 0), Vector2(-216.8, 809.4)],
		[Vector2i(46, 0), Vector2(28.0, 478.8)],
		[Vector2i(47, 0), Vector2(115.6, 848.1)],
		# Midpoint nodes splitting the two longest original links (owner
		# request, 4 Aug 2026) — 12-13 and 18-20 were both ~14-15 min, too
		# long/expensive to upgrade in one purchase (see cost note in
		# Player.gd). Splitting each at its exact geometric midpoint keeps
		# the total route time identical to before (verified: no existing
		# route's total time changes) while letting a player afford one half
		# at a time instead of the whole link in a single transaction.
		[Vector2i(48, 0), Vector2(295.5, 897.75)],   # midpoint of 12-13
		[Vector2i(49, 0), Vector2(1008.0, 897.75)],  # midpoint of 18-20
	]

	for entry: Array in nodes:
		var nid: Vector2i = entry[0]
		node_positions[nid] = entry[1]
		node_names[nid] = "Node %d" % nid.x
		node_labels[nid] = ""   # no participant-facing name
		adjacency[nid] = []
		all_nodes.append(nid)

	var idx: int = clampi(pair_index, 0, HOME_WORK_PAIRS.size() - 1)
	home_node = HOME_WORK_PAIRS[idx][0]
	work_node = HOME_WORK_PAIRS[idx][1]

	river_points = PackedVector2Array()   # no river in this topology

	# --- Edges: [from, to, base_time (min), stress] ---
	# base_time is derived from the ACTUAL on-screen pixel distance between
	# the two node_positions above (not the dataset's free_flow_time, which
	# was measured against the real geographic layout and had no relation to
	# this diagram-based layout — that mismatch is what let short-looking
	# roads cost more/take longer than long ones). Each pixel distance is
	# rounded to the nearest 5px, then divided by 40. Re-derived from the
	# node positions above after the 3 Aug 2026 50% spacing increase, so
	# every value here is ~1.5x its pre-scale figure (exactly what the
	# formula produces from the new, 1.5x-scaled coordinates — not just the
	# old number multiplied by 1.5, though the two agree to within rounding).
	#
	# stress: REDERIVED 10 Aug 2026 as an ARTERIAL SKELETON, replacing the
	# 4 Aug 2026 length-derived column. That column was written to the owner's
	# instruction, "same high stress with some variation, longer roads higher
	# on average", and this change reverses it. Recorded here rather than
	# dropped, because the reversal is the point: deriving stress from length
	# made "avoid stress" and "avoid time" the same instruction, so there was
	# nothing to detour around.
	#
	# Measured before the rewrite: stress sd was 0.09 around mean 0.603, so
	# (1 + alpha x stress) scaled every candidate path about equally and
	# cancelled out of the comparison. Consequence: cautious, average and
	# confident riders picked the IDENTICAL route for all 99 residents. Alpha,
	# the mechanism the study rests on, moved the safety readout and nothing
	# else. The impedance-optimal route also equalled the pure-fastest route
	# for 79% of residents.
	#
	# New rule: the 24 of 69 links most ridden by the simulated residents form
	# an arterial skeleton at 0.82; the other 45 are backstreets at 0.22. Each
	# gets +/- up to 0.06 of deterministic noise from Python's
	# random.Random(42) (fixed seed, same convention as the column it
	# replaces, not read at runtime) in the exact order the edges are listed,
	# clamped to [0.10, 0.92]. Selection is by resident usage rather than
	# betweenness centrality: betweenness scores all-pairs traffic and picked
	# two links (16-18, 20-21) that no resident rides, and measured worse on
	# every other count. The skeleton is one connected component of 22 nodes
	# plus two fragments, hubbed on node 30 (degree 4) with 10/11/36/44 at
	# degree 3 - a branching spine through the core (1-3-4, 8-9-10-11-12) and
	# the West Extension (30-33-42, 36-44-37).
	#
	# Selection bootstraps off the routes the OLD stress column produced. That
	# is deliberate and one-shot: it picks the roads people actually rode, and
	# re-running it against the new column would chase its own tail.
	#
	# Result: network mean stress 0.603 -> ~0.42, sd 0.09 -> ~0.28, and the
	# correlation with link length drops from +0.65 to ~+0.2. Route-equals-
	# fastest falls to 42/51/72% (cautious/average/confident) and 31 of 99
	# residents now route DIFFERENTLY depending on personality, up from zero.
	# Like the 4 Aug rewrite this deliberately moves existing routes.
	#
	# Note the visual layer reads this column directly: LinkSegment draws road
	# WIDTH from base_stress (fixed road character) and car count/speed plus
	# the centre-line stress view from effective stress (post-beta). A change
	# here is visible on the map, by design.
	var edges: Array = [
		[Vector2i(1, 0),  Vector2i(2, 0),  15.0, 0.24],
		[Vector2i(1, 0),  Vector2i(3, 0),  3.4, 0.76],
		[Vector2i(2, 0),  Vector2i(6, 0),  3.4, 0.19],
		[Vector2i(3, 0),  Vector2i(4, 0),  4.6, 0.79],
		[Vector2i(3, 0),  Vector2i(12, 0), 5.8, 0.25],
		[Vector2i(4, 0),  Vector2i(5, 0),  5.1, 0.24],
		[Vector2i(4, 0),  Vector2i(11, 0), 5.8, 0.27],
		[Vector2i(5, 0),  Vector2i(6, 0),  5.4, 0.17],
		[Vector2i(5, 0),  Vector2i(9, 0),  2.8, 0.21],
		[Vector2i(6, 0),  Vector2i(8, 0),  2.8, 0.76],
		[Vector2i(7, 0),  Vector2i(8, 0),  5.6, 0.19],
		[Vector2i(7, 0),  Vector2i(18, 0), 3.0, 0.22],
		[Vector2i(8, 0),  Vector2i(9, 0),  5.4, 0.76],
		[Vector2i(8, 0),  Vector2i(16, 0), 3.0, 0.18],
		[Vector2i(9, 0),  Vector2i(10, 0), 3.0, 0.84],
		[Vector2i(10, 0), Vector2i(11, 0), 5.1, 0.83],
		[Vector2i(10, 0), Vector2i(15, 0), 6.5, 0.79],
		[Vector2i(10, 0), Vector2i(16, 0), 5.4, 0.23],
		[Vector2i(10, 0), Vector2i(17, 0), 6.1, 0.26],
		[Vector2i(11, 0), Vector2i(12, 0), 4.6, 0.76],
		[Vector2i(11, 0), Vector2i(14, 0), 6.5, 0.86],
		[Vector2i(12, 0), Vector2i(48, 0), 7.0, 0.24],   # split of former 12-13
		[Vector2i(48, 0), Vector2i(13, 0), 7.0, 0.20],
		[Vector2i(13, 0), Vector2i(24, 0), 4.6, 0.78],
		[Vector2i(14, 0), Vector2i(15, 0), 5.1, 0.27],
		[Vector2i(14, 0), Vector2i(23, 0), 3.0, 0.20],
		[Vector2i(15, 0), Vector2i(19, 0), 5.4, 0.17],
		[Vector2i(15, 0), Vector2i(22, 0), 3.0, 0.77],
		[Vector2i(16, 0), Vector2i(17, 0), 3.0, 0.26],
		[Vector2i(16, 0), Vector2i(18, 0), 5.6, 0.23],
		[Vector2i(17, 0), Vector2i(19, 0), 3.5, 0.26],
		[Vector2i(18, 0), Vector2i(49, 0), 7.5, 0.25],   # split of former 18-20
		[Vector2i(49, 0), Vector2i(20, 0), 7.5, 0.22],
		[Vector2i(19, 0), Vector2i(20, 0), 7.5, 0.28],
		[Vector2i(20, 0), Vector2i(21, 0), 5.4, 0.21],
		[Vector2i(20, 0), Vector2i(22, 0), 7.0, 0.23],
		[Vector2i(21, 0), Vector2i(22, 0), 4.5, 0.26],
		[Vector2i(21, 0), Vector2i(24, 0), 5.1, 0.23],
		[Vector2i(22, 0), Vector2i(23, 0), 5.1, 0.26],
		[Vector2i(23, 0), Vector2i(24, 0), 4.5, 0.23],
		# West Extension edges — owner-designed topology from the node
		# editor; stress values re-derived by the same formula above, not
		# the editor's uniform 0.20 default.
		[Vector2i(23, 0), Vector2i(27, 0), 2.6, 0.84],
		[Vector2i(27, 0), Vector2i(28, 0), 4.5, 0.77],
		[Vector2i(2, 0),  Vector2i(29, 0), 3.3, 0.79],
		[Vector2i(12, 0), Vector2i(30, 0), 6.9, 0.79],
		[Vector2i(1, 0),  Vector2i(30, 0), 5.0, 0.77],
		[Vector2i(33, 0), Vector2i(30, 0), 5.5, 0.79],
		[Vector2i(30, 0), Vector2i(31, 0), 3.9, 0.17],
		[Vector2i(31, 0), Vector2i(32, 0), 5.5, 0.19],
		[Vector2i(32, 0), Vector2i(33, 0), 3.9, 0.24],
		[Vector2i(33, 0), Vector2i(42, 0), 6.6, 0.80],
		[Vector2i(42, 0), Vector2i(40, 0), 5.8, 0.20],
		[Vector2i(40, 0), Vector2i(41, 0), 4.3, 0.19],
		[Vector2i(41, 0), Vector2i(33, 0), 5.8, 0.19],
		[Vector2i(41, 0), Vector2i(37, 0), 8.1, 0.27],
		[Vector2i(39, 0), Vector2i(38, 0), 4.4, 0.24],
		[Vector2i(39, 0), Vector2i(37, 0), 4.5, 0.23],
		[Vector2i(30, 0), Vector2i(44, 0), 7.6, 0.78],
		[Vector2i(44, 0), Vector2i(37, 0), 6.1, 0.85],
		[Vector2i(37, 0), Vector2i(13, 0), 9.6, 0.78],
		[Vector2i(44, 0), Vector2i(36, 0), 4.0, 0.81],
		[Vector2i(36, 0), Vector2i(34, 0), 3.9, 0.88],
		[Vector2i(36, 0), Vector2i(35, 0), 4.0, 0.84],
		[Vector2i(40, 0), Vector2i(45, 0), 4.0, 0.23],
		[Vector2i(39, 0), Vector2i(45, 0), 4.5, 0.24],
		[Vector2i(45, 0), Vector2i(37, 0), 6.3, 0.26],
		[Vector2i(44, 0), Vector2i(46, 0), 5.1, 0.25],
		[Vector2i(46, 0), Vector2i(33, 0), 3.5, 0.19],
		[Vector2i(47, 0), Vector2i(35, 0), 3.1, 0.16],
		[Vector2i(36, 0), Vector2i(47, 0), 2.8, 0.20],
	]

	for edge: Array in edges:
		_add_undirected_link(edge[0], edge[1], edge[2], edge[3])

	_apply_initial_infrastructure()


func _apply_initial_infrastructure() -> void:
	# A few pre-existing upgrades so the game doesn't start with a fully
	# blank network — same role as the previous network's seeded lanes.
	_set_initial_upgrade(Vector2i(21, 0), Vector2i(22, 0), 1)   # painted
	_set_initial_upgrade(Vector2i(35, 0), Vector2i(36, 0), 1)   # painted
	_set_initial_upgrade(Vector2i(1, 0),  Vector2i(2, 0),  2)   # protected
	_set_initial_upgrade(Vector2i(42, 0), Vector2i(33, 0), 2)   # protected
	_set_initial_upgrade(Vector2i(11, 0), Vector2i(10, 0), 1)   # painted
	_set_initial_upgrade(Vector2i(5, 0),  Vector2i(9, 0),  2)   # protected
	_set_initial_upgrade(Vector2i(18, 0), Vector2i(49, 0), 2)   # protected — top half of the old 18-20 (49 = its midpoint split node)
	_set_initial_upgrade(Vector2i(45, 0), Vector2i(39, 0), 1)   # painted


func _set_initial_upgrade(a: Vector2i, b: Vector2i, level: int) -> void:
	var id_ab := "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]
	var id_ba := "%d,%d-%d,%d" % [b.x, b.y, a.x, a.y]
	for lid in [id_ab, id_ba]:
		if links.has(lid):
			var link: Link = links[lid]
			link.upgrade_level = level
			# Remembered so this can never be removed for a refund, and so
			# raising it and then changing your mind returns it to here rather
			# than stripping the road bare.
			link.initial_upgrade_level = level


# --- Graph Building ---

func _add_undirected_link(a: Vector2i, b: Vector2i, base_time: float, stress: float) -> void:
	var id_ab = "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]
	var id_ba = "%d,%d-%d,%d" % [b.x, b.y, a.x, a.y]
	var link_ab = Link.new(id_ab, a, b, base_time, stress)
	var link_ba = Link.new(id_ba, b, a, base_time, stress)
	links[id_ab] = link_ab
	links[id_ba] = link_ba
	adjacency[a].append(link_ab)
	adjacency[b].append(link_ba)


## Takes back what the PLAYER built here, returning the link to whatever it
## started the game with rather than to bare road. Returns false, changing
## nothing, when there is nothing of theirs to take back.
##
## The floor matters in two ways. A link that came pre-upgraded cannot be
## removed at all, so its refund can never be claimed. And a pre-existing
## painted lane the player raised to protected drops back to painted, not to
## nothing, so changing your mind cannot destroy infrastructure that was there
## before you arrived.
func downgrade_link(link_id: String) -> bool:
	if not links.has(link_id):
		return false
	var link: Link = links[link_id]
	if not link.has_player_upgrade():
		return false
	link.upgrade_level = link.initial_upgrade_level
	var parts      := link_id.split("-")
	var reverse_id := "%s-%s" % [parts[1], parts[0]]
	if links.has(reverse_id):
		var rev: Link = links[reverse_id]
		rev.upgrade_level = rev.initial_upgrade_level
	return true



func upgrade_link(link_id: String, upgrade_level: int) -> bool:
	if not links.has(link_id):
		return false
	var link: Link = links[link_id]
	if link.upgrade_level >= upgrade_level:
		return false
	link.upgrade_level = upgrade_level
	var parts = link_id.split("-")
	var reverse_id = "%s-%s" % [parts[1], parts[0]]
	if links.has(reverse_id):
		var reverse_link: Link = links[reverse_id]
		reverse_link.upgrade_level = upgrade_level
	return true


# --- Routing (delegates to Dijkstra) ---

func find_route(start: Vector2i, goal: Vector2i, alpha: float) -> Dictionary:
	return Dijkstra.find_route(adjacency, start, goal, alpha)


# --- City-Wide Metrics ---

func city_average_time(commuters: Array, _upgrade_state: Dictionary = {}) -> float:
	var total_time: float = 0.0
	var count: int = commuters.size()
	if count == 0:
		return 0.0
	for commuter in commuters:
		var route = find_route(commuter["start"], commuter["goal"], commuter["alpha"])
		total_time += route.get("total_time", 0.0)
	return total_time / count


func coverage_percent() -> float:
	var total_undirected: int = 0
	var upgraded: int = 0
	var counted: Dictionary = {}
	for link_id in links:
		var link: Link = links[link_id]
		var canonical = canonical_link_id(link.from_node, link.to_node)
		if counted.has(canonical):
			continue
		counted[canonical] = true
		total_undirected += 1
		if link.upgrade_level > 0:
			upgraded += 1
	return (float(upgraded) / float(total_undirected)) * 100.0 if total_undirected > 0 else 0.0


## A short fingerprint of the network's immutable structure: which links exist,
## how long they take and how stressful they are, plus the resident commute
## list.
##
## Recorded with every session so data can be told apart across builds. The
## network has been restructured more than once — the arterial stress rewrite of
## 10 August 2026 changed route choice substantially — and sessions run either
## side of such a change are not directly comparable. Without a fingerprint that
## difference is invisible in the data, and the only way to date a session is to
## match its timestamp against the commit history by hand.
##
## Deliberately excludes upgrade_level, which is what players change: the point
## is to identify the board, not the state of play on it. Links are sorted so
## the value depends on the network rather than on dictionary iteration order.
func signature() -> String:
	var ids: Array = links.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for link_id: String in ids:
		var link: Link = links[link_id]
		parts.append("%s:%.4f:%.4f" % [link_id, link.base_time, link.stress_score])
	parts.append("commutes:%d" % RESIDENT_COMMUTE_PAIRS.size())
	return "%x" % hash("|".join(parts))


# --- Display Helpers ---

func link_display_name(link_id: String) -> String:
	var parts := link_id.split("-")
	if parts.size() != 2:
		return link_id
	var a := CityNetwork.parse_node(parts[0])
	var b := CityNetwork.parse_node(parts[1])
	var name_a: String = node_names.get(a, parts[0])
	var name_b: String = node_names.get(b, parts[1])
	return "%s → %s" % [name_a, name_b]


func get_bounds() -> Rect2:
	if node_positions.is_empty():
		return Rect2()
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for pos: Vector2 in node_positions.values():
		min_pos.x = minf(min_pos.x, pos.x)
		min_pos.y = minf(min_pos.y, pos.y)
		max_pos.x = maxf(max_pos.x, pos.x)
		max_pos.y = maxf(max_pos.y, pos.y)
	return Rect2(min_pos, max_pos - min_pos)


## Undirected link ID — same string regardless of which direction the link
## is stored/traversed in. Used to de-duplicate the two directional Link
## entries a<->b, and to compare a route's traversal direction against an
## upgrade's link_id regardless of direction.
static func canonical_link_id(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d-%d,%d" % [b.x, b.y, a.x, a.y]


static func parse_node(s: String) -> Vector2i:
	var p := s.split(",")
	return Vector2i(int(p[0]), int(p[1]))
