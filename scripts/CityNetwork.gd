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
	func _init(fid: String, fn: Vector2i, tn: Vector2i, bt: float, ss: float) -> void:
		id = fid
		from_node = fn
		to_node = tn
		base_time = bt
		stress_score = ss
		upgrade_level = 0

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
const HOME_WORK_PAIRS: Array = [
	[Vector2i(23, 0), Vector2i(7, 0)],
	[Vector2i(13, 0), Vector2i(46, 0)],  # was work=2; now West Extension hub node 46
	[Vector2i(7, 0),  Vector2i(41, 0)],  # was work=12; now West Extension node 41
	[Vector2i(18, 0), Vector2i(1, 0)],
	[Vector2i(24, 0), Vector2i(45, 0)],  # was work=6; now West Extension node 45
]

## Fixed set of resident commute pairs (home node → destination node). 12
## "neighbourhoods" (home nodes), 99 residents total.
##
## REDESIGNED 28 Jul 2026, twice the same day:
## (1) owner: "at most 2 people from each neighbourhood go to the same
##     workplace, so there's more road traffic on other parts of the
##     network." Before this, each neighbourhood sent 100% of its residents
##     to ONE shared workplace — only 9-11 distinct routes existed across all
##     60 residents, so nearly every link's NPC-heatmap count came from just
##     a couple of corridors and most of the network's ~69 links never lit up
##     at all. Every neighbourhood was split across enough distinct
##     workplaces that no single (home, work) pair exceeds 2 residents.
## (2) owner: "add another neighbourhood at node 16, and increase all the
##     neighbourhoods' amounts by 2-3." Node 16 had just been vacated as a
##     destination by change (1) above (it was node 29's sole workplace
##     before), so it was free to become a brand-new 6-resident neighbourhood
##     — all 3 of its destinations (8, 10, 17) are direct 1-hop neighbours of
##     16 itself. Every one of the 11 pre-existing neighbourhoods then grew
##     by 3: first topping up any of its groups still under the 2-per-pair
##     cap, then adding 1-2 more distinct destinations for the remainder.
## In both passes, new destinations were chosen as the NEAREST not-yet-used
## (by that specific neighbourhood) node — by that neighbourhood's own
## Dijkstra distance — from a ~20-node pool of hub candidates spanning both
## the original core and the West Extension, so commutes stay plausible
## rather than artificially long detours.
##
## Per-neighbourhood breakdown (home: work×residents, ...):
##   Node 21 (10): 22×2, 20×2, 15×2, 19×2, 10×2
##   Node 14 (9):  15×2, 11×2, 22×2, 19×2, 12×1
##   Node 9  (10): 5×2,  10×2, 8×2 "shopping_bag", 6×2, 4×2 "coffee"
##   Node 1  (4):  3×2,  30×2
##   Node 28 (9):  22×2, 15×2, 11×2, 20×2, 19×1
##   Node 34 (9):  36×2, 35×2 "bank", 44×2 "gym", 30×2, 33×1 "shopping"
##   Node 38 (8):  39×2, 44×2 "gym", 36×2, 35×2 "bank"
##   Node 32 (8):  33×2 "shopping", 30×2, 44×2 "gym", 12×2
##   Node 40 (8):  39×2, 33×2 "shopping", 30×2, 44×2 "gym"
##   Node 29 (9):  2×2,  6×2,  8×2 "shopping_bag", 5×2, 17×1 "market"
##   Node 42 (9):  33×2 "shopping", 30×2, 39×2, 44×2 "gym", 12×1
##   Node 16 (6, NEW): 8×2 "shopping_bag", 10×2, 17×2 "market"
## The 7 WORK_NODE_ICONS nodes (15/4/17/35/44/33/8 — school/coffee/market/
## bank/gym/shopping/shopping_bag) now each have 2-4 feeder neighbourhoods
## instead of 1-2; every other destination (22/20/19/11/10/6/3/30/36/12)
## falls back to the generic building icon, as before.
##
## Route-independence note (predates both redesigns, still applies): the
## original three clusters' single routes were chosen to share ZERO links
## with any of the 5 HOME_WORK_PAIRS above, across all three personality
## alphas — so upgrading only the player's own commute never helped these
## residents and vice versa. The 4 Aug 2026 network-wide stress rewrite
## already broke that property for those clusters (confirmed, reported to
## the owner, left as-is), and neither 28 Jul redesign attempts to restore or
## re-verify it — several routes incidentally pass through HOME_WORK_PAIRS
## nodes as intermediate stops (e.g. several routes above cross node 46, a
## human player's own work node), the same way the West Extension's 28→35
## cluster already did. Accepted, not fixed, consistent with the owner's
## standing call on this property.
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

## Redesigned 28 Jul 2026 (twice — see the breakdown table in the comment
## block above): first split every neighbourhood's residents across 3-4
## distinct workplaces (≤2 each), then grew every neighbourhood by 3 more
## residents and added a brand-new 6-resident neighbourhood at node 16.
const RESIDENT_COMMUTE_PAIRS: Array = [
	# Node 21 (10): 22x2, 20x2, 15x2, 19x2, 10x2
	[Vector2i(21, 0), Vector2i(22, 0)],
	[Vector2i(21, 0), Vector2i(22, 0)],
	[Vector2i(21, 0), Vector2i(20, 0)],
	[Vector2i(21, 0), Vector2i(20, 0)],
	[Vector2i(21, 0), Vector2i(15, 0)],
	[Vector2i(21, 0), Vector2i(15, 0)],
	[Vector2i(21, 0), Vector2i(19, 0)],
	[Vector2i(21, 0), Vector2i(19, 0)],
	[Vector2i(21, 0), Vector2i(10, 0)],
	[Vector2i(21, 0), Vector2i(10, 0)],
	# Node 14 (9): 15x2, 11x2, 22x2, 19x2, 12x1
	[Vector2i(14, 0), Vector2i(15, 0)],
	[Vector2i(14, 0), Vector2i(15, 0)],
	[Vector2i(14, 0), Vector2i(11, 0)],
	[Vector2i(14, 0), Vector2i(11, 0)],
	[Vector2i(14, 0), Vector2i(22, 0)],
	[Vector2i(14, 0), Vector2i(22, 0)],
	[Vector2i(14, 0), Vector2i(19, 0)],
	[Vector2i(14, 0), Vector2i(19, 0)],
	[Vector2i(14, 0), Vector2i(12, 0)],
	# Node 9 (10): 5x2, 10x2, 8x2 "shopping_bag", 6x2, 4x2 "coffee"
	[Vector2i(9, 0),  Vector2i(5, 0)],
	[Vector2i(9, 0),  Vector2i(5, 0)],
	[Vector2i(9, 0),  Vector2i(10, 0)],
	[Vector2i(9, 0),  Vector2i(10, 0)],
	[Vector2i(9, 0),  Vector2i(8, 0)],
	[Vector2i(9, 0),  Vector2i(8, 0)],
	[Vector2i(9, 0),  Vector2i(6, 0)],
	[Vector2i(9, 0),  Vector2i(6, 0)],
	[Vector2i(9, 0),  Vector2i(4, 0)],
	[Vector2i(9, 0),  Vector2i(4, 0)],
	# Node 1 (4): 3x2, 30x2
	[Vector2i(1, 0),  Vector2i(3, 0)],
	[Vector2i(1, 0),  Vector2i(3, 0)],
	[Vector2i(1, 0),  Vector2i(30, 0)],
	[Vector2i(1, 0),  Vector2i(30, 0)],
	# West Extension clusters (originally added 4 Aug 2026, redistributed
	# 28 Jul 2026 — see comment block above)
	# Node 28 (9): 22x2, 15x2, 11x2, 20x2, 19x1
	[Vector2i(28, 0), Vector2i(22, 0)],
	[Vector2i(28, 0), Vector2i(22, 0)],
	[Vector2i(28, 0), Vector2i(15, 0)],
	[Vector2i(28, 0), Vector2i(15, 0)],
	[Vector2i(28, 0), Vector2i(11, 0)],
	[Vector2i(28, 0), Vector2i(11, 0)],
	[Vector2i(28, 0), Vector2i(20, 0)],
	[Vector2i(28, 0), Vector2i(20, 0)],
	[Vector2i(28, 0), Vector2i(19, 0)],
	# Node 34 (9): 36x2, 35x2 "bank", 44x2 "gym", 30x2, 33x1 "shopping"
	[Vector2i(34, 0), Vector2i(36, 0)],
	[Vector2i(34, 0), Vector2i(36, 0)],
	[Vector2i(34, 0), Vector2i(35, 0)],
	[Vector2i(34, 0), Vector2i(35, 0)],
	[Vector2i(34, 0), Vector2i(44, 0)],
	[Vector2i(34, 0), Vector2i(44, 0)],
	[Vector2i(34, 0), Vector2i(30, 0)],
	[Vector2i(34, 0), Vector2i(30, 0)],
	[Vector2i(34, 0), Vector2i(33, 0)],
	# Node 38 (8): 39x2, 44x2 "gym", 36x2, 35x2 "bank"
	[Vector2i(38, 0), Vector2i(39, 0)],
	[Vector2i(38, 0), Vector2i(39, 0)],
	[Vector2i(38, 0), Vector2i(44, 0)],
	[Vector2i(38, 0), Vector2i(44, 0)],
	[Vector2i(38, 0), Vector2i(36, 0)],
	[Vector2i(38, 0), Vector2i(36, 0)],
	[Vector2i(38, 0), Vector2i(35, 0)],
	[Vector2i(38, 0), Vector2i(35, 0)],
	# "Left side" clusters (originally added 4 Aug 2026, home moved from 42
	# to 32 same day, redistributed 28 Jul 2026 — see comment block above).
	# Node 32 (8): 33x2 "shopping", 30x2, 44x2 "gym", 12x2
	[Vector2i(32, 0), Vector2i(33, 0)],
	[Vector2i(32, 0), Vector2i(33, 0)],
	[Vector2i(32, 0), Vector2i(30, 0)],
	[Vector2i(32, 0), Vector2i(30, 0)],
	[Vector2i(32, 0), Vector2i(44, 0)],
	[Vector2i(32, 0), Vector2i(44, 0)],
	[Vector2i(32, 0), Vector2i(12, 0)],
	[Vector2i(32, 0), Vector2i(12, 0)],
	# Node 40 (8): 39x2, 33x2 "shopping", 30x2, 44x2 "gym"
	[Vector2i(40, 0), Vector2i(39, 0)],
	[Vector2i(40, 0), Vector2i(39, 0)],
	[Vector2i(40, 0), Vector2i(33, 0)],
	[Vector2i(40, 0), Vector2i(33, 0)],
	[Vector2i(40, 0), Vector2i(30, 0)],
	[Vector2i(40, 0), Vector2i(30, 0)],
	[Vector2i(40, 0), Vector2i(44, 0)],
	[Vector2i(40, 0), Vector2i(44, 0)],
	# 2 more clusters (originally added 28 Jul 2026 — see comment block
	# above), redistributed the same day into the ≤2-per-pair design.
	# Node 29 (9): 2x2, 6x2, 8x2 "shopping_bag", 5x2, 17x1 "market"
	[Vector2i(29, 0), Vector2i(2, 0)],
	[Vector2i(29, 0), Vector2i(2, 0)],
	[Vector2i(29, 0), Vector2i(6, 0)],
	[Vector2i(29, 0), Vector2i(6, 0)],
	[Vector2i(29, 0), Vector2i(8, 0)],
	[Vector2i(29, 0), Vector2i(8, 0)],
	[Vector2i(29, 0), Vector2i(5, 0)],
	[Vector2i(29, 0), Vector2i(5, 0)],
	[Vector2i(29, 0), Vector2i(17, 0)],
	# Node 42 (9): 33x2 "shopping", 30x2, 39x2, 44x2 "gym", 12x1
	[Vector2i(42, 0), Vector2i(33, 0)],
	[Vector2i(42, 0), Vector2i(33, 0)],
	[Vector2i(42, 0), Vector2i(30, 0)],
	[Vector2i(42, 0), Vector2i(30, 0)],
	[Vector2i(42, 0), Vector2i(39, 0)],
	[Vector2i(42, 0), Vector2i(39, 0)],
	[Vector2i(42, 0), Vector2i(44, 0)],
	[Vector2i(42, 0), Vector2i(44, 0)],
	[Vector2i(42, 0), Vector2i(12, 0)],
	# New neighbourhood (added 28 Jul 2026 — see comment block above), on
	# node 16, vacated by the ≤2-per-pair redesign earlier the same day. All
	# 3 destinations are direct 1-hop neighbours of 16 itself.
	# Node 16 (6, NEW): 8x2 "shopping_bag", 10x2, 17x2 "market"
	[Vector2i(16, 0), Vector2i(8, 0)],
	[Vector2i(16, 0), Vector2i(8, 0)],
	[Vector2i(16, 0), Vector2i(10, 0)],
	[Vector2i(16, 0), Vector2i(10, 0)],
	[Vector2i(16, 0), Vector2i(17, 0)],
	[Vector2i(16, 0), Vector2i(17, 0)],
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
	# stress (4 Aug 2026, owner request — "same high stress with some
	# variation, longer roads higher on average" — replaces the old
	# hand-assigned-per-link values, including the West Extension's uniform
	# 0.20): every one of these 69 links, old and new alike, was regenerated
	# from one formula rather than tuned individually — mean_stress =
	# 0.55 + 0.30 x (this link's base_time, normalized 0-1 against the
	# network's own min/max base_time), then +/- up to 0.12 of deterministic
	# noise, clamped to [0.40, 0.92]. The noise is drawn from Python's
	# random.Random(42) (fixed seed, same convention as the game's own RNG
	# seed — not read at runtime, just used once here to author these
	# numbers) in the exact order the edges are listed, so it's fully
	# reproducible from the derivation script (kept in git history) rather
	# than hand-picked. Result: network-wide average stress 0.603 (was much
	# lower — most streets used to sit at 0.15-0.20), longer links average
	# 0.65 vs. 0.56 for shorter ones, and no link reads as "quiet" anymore —
	# even the calmest street is 0.40+. This is a deliberate, large routing
	# change (previous additions to this file went out of their way to
	# preserve existing routes; this one doesn't, by design) — see the P0
	# verification note in the code-review/session log for which specific
	# routes it moves.
	var edges: Array = [
		[Vector2i(1, 0),  Vector2i(2, 0),  15.0, 0.88],
		[Vector2i(1, 0),  Vector2i(3, 0),  3.4, 0.46],
		[Vector2i(2, 0),  Vector2i(6, 0),  3.4, 0.52],
		[Vector2i(3, 0),  Vector2i(4, 0),  4.6, 0.53],
		[Vector2i(3, 0),  Vector2i(12, 0), 5.8, 0.68],
		[Vector2i(4, 0),  Vector2i(5, 0),  5.1, 0.65],
		[Vector2i(4, 0),  Vector2i(11, 0), 5.8, 0.72],
		[Vector2i(5, 0),  Vector2i(6, 0),  5.4, 0.52],
		[Vector2i(5, 0),  Vector2i(9, 0),  2.8, 0.54],
		[Vector2i(6, 0),  Vector2i(8, 0),  2.8, 0.44],
		[Vector2i(7, 0),  Vector2i(8, 0),  5.6, 0.56],
		[Vector2i(7, 0),  Vector2i(18, 0), 3.0, 0.56],
		[Vector2i(8, 0),  Vector2i(9, 0),  5.4, 0.50],
		[Vector2i(8, 0),  Vector2i(16, 0), 3.0, 0.49],
		[Vector2i(9, 0),  Vector2i(10, 0), 3.0, 0.60],
		[Vector2i(10, 0), Vector2i(11, 0), 5.1, 0.62],
		[Vector2i(10, 0), Vector2i(15, 0), 6.5, 0.58],
		[Vector2i(10, 0), Vector2i(16, 0), 5.4, 0.64],
		[Vector2i(10, 0), Vector2i(17, 0), 6.1, 0.71],
		[Vector2i(11, 0), Vector2i(12, 0), 4.6, 0.48],
		[Vector2i(11, 0), Vector2i(14, 0), 6.5, 0.72],
		[Vector2i(12, 0), Vector2i(48, 0), 7.0, 0.70],   # split of former 12-13
		[Vector2i(48, 0), Vector2i(13, 0), 7.0, 0.62],
		[Vector2i(13, 0), Vector2i(24, 0), 4.6, 0.52],
		[Vector2i(14, 0), Vector2i(15, 0), 5.1, 0.72],
		[Vector2i(14, 0), Vector2i(23, 0), 3.0, 0.52],
		[Vector2i(15, 0), Vector2i(19, 0), 5.4, 0.52],
		[Vector2i(15, 0), Vector2i(22, 0), 3.0, 0.46],
		[Vector2i(16, 0), Vector2i(17, 0), 3.0, 0.64],
		[Vector2i(16, 0), Vector2i(18, 0), 5.6, 0.65],
		[Vector2i(17, 0), Vector2i(19, 0), 3.5, 0.65],
		[Vector2i(18, 0), Vector2i(49, 0), 7.5, 0.72],   # split of former 18-20
		[Vector2i(49, 0), Vector2i(20, 0), 7.5, 0.68],
		[Vector2i(19, 0), Vector2i(20, 0), 7.5, 0.78],
		[Vector2i(20, 0), Vector2i(21, 0), 5.4, 0.59],
		[Vector2i(20, 0), Vector2i(22, 0), 7.0, 0.67],
		[Vector2i(21, 0), Vector2i(22, 0), 4.5, 0.68],
		[Vector2i(21, 0), Vector2i(24, 0), 5.1, 0.64],
		[Vector2i(22, 0), Vector2i(23, 0), 5.1, 0.70],
		[Vector2i(23, 0), Vector2i(24, 0), 4.5, 0.61],
		# West Extension edges — owner-designed topology from the node
		# editor; stress values re-derived by the same formula above, not
		# the editor's uniform 0.20 default.
		[Vector2i(23, 0), Vector2i(27, 0), 2.6, 0.60],
		[Vector2i(27, 0), Vector2i(28, 0), 4.5, 0.49],
		[Vector2i(2, 0),  Vector2i(29, 0), 3.3, 0.50],
		[Vector2i(12, 0), Vector2i(30, 0), 6.9, 0.60],
		[Vector2i(1, 0),  Vector2i(30, 0), 5.0, 0.51],
		[Vector2i(33, 0), Vector2i(30, 0), 5.5, 0.56],
		[Vector2i(30, 0), Vector2i(31, 0), 3.9, 0.49],
		[Vector2i(31, 0), Vector2i(32, 0), 5.5, 0.57],
		[Vector2i(32, 0), Vector2i(33, 0), 3.9, 0.61],
		[Vector2i(33, 0), Vector2i(42, 0), 6.6, 0.61],
		[Vector2i(42, 0), Vector2i(40, 0), 5.8, 0.60],
		[Vector2i(40, 0), Vector2i(41, 0), 4.3, 0.52],
		[Vector2i(41, 0), Vector2i(33, 0), 5.8, 0.57],
		[Vector2i(41, 0), Vector2i(37, 0), 8.1, 0.79],
		[Vector2i(39, 0), Vector2i(38, 0), 4.4, 0.63],
		[Vector2i(39, 0), Vector2i(37, 0), 4.5, 0.62],
		[Vector2i(30, 0), Vector2i(44, 0), 7.6, 0.59],
		[Vector2i(44, 0), Vector2i(37, 0), 6.1, 0.69],
		[Vector2i(37, 0), Vector2i(13, 0), 9.6, 0.64],
		[Vector2i(44, 0), Vector2i(36, 0), 4.0, 0.55],
		[Vector2i(36, 0), Vector2i(34, 0), 3.9, 0.70],
		[Vector2i(36, 0), Vector2i(35, 0), 4.0, 0.62],
		[Vector2i(40, 0), Vector2i(45, 0), 4.0, 0.60],
		[Vector2i(39, 0), Vector2i(45, 0), 4.5, 0.64],
		[Vector2i(45, 0), Vector2i(37, 0), 6.3, 0.72],
		[Vector2i(44, 0), Vector2i(46, 0), 5.1, 0.68],
		[Vector2i(46, 0), Vector2i(33, 0), 3.5, 0.51],
		[Vector2i(47, 0), Vector2i(35, 0), 3.1, 0.45],
		[Vector2i(36, 0), Vector2i(47, 0), 2.8, 0.51],
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


func downgrade_link(link_id: String) -> bool:
	if not links.has(link_id):
		return false
	var link: Link = links[link_id]
	if link.upgrade_level == 0:
		return false
	link.upgrade_level = 0
	var parts      := link_id.split("-")
	var reverse_id := "%s-%s" % [parts[1], parts[0]]
	if links.has(reverse_id):
		var rev: Link = links[reverse_id]
		rev.upgrade_level = 0
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
