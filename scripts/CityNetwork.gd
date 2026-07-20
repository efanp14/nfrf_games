class_name CityNetwork
## CityNetwork.gd
## Represents a fictional city's downtown road network, laid out as an
## organic hub-and-spoke shape (a European-style old-town core, a river
## bend, and a handful of residential districts) rather than a rigid grid.
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
		return base_time * (1.0 + alpha * effective_beta(alpha) * stress_score)


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

const HOME_WORK_PAIRS: Array = [
	[Vector2i(2, 0), Vector2i(1, 0), "Village Green → Harbor Quay"],
	[Vector2i(3, 0), Vector2i(0, 1), "Eastwick Square → Market Row"],
	[Vector2i(4, 0), Vector2i(0, 4), "Southmere Green → Clocktower"],
	[Vector2i(5, 0), Vector2i(0, 5), "Westhaven Square → Riverside Plaza"],
	[Vector2i(2, 3), Vector2i(1, 1), "Hilltop Row → Old Mill"],
]

## Fixed set of resident commute pairs (home node → destination node).
## Homes are drawn from the four residential districts; destinations are
## mostly the Downtown Core hub with a smaller share going to the Harbor
## District, so many residents share the same handful of spoke/bridge
## roads into the hub — regardless of which specific route the player
## themself commutes on. Same 30 pairs every session, for reproducibility.
const RESIDENT_COMMUTE_PAIRS: Array = [
	[Vector2i(2, 0), Vector2i(0, 0)],
	[Vector2i(2, 1), Vector2i(0, 1)],
	[Vector2i(2, 2), Vector2i(0, 2)],
	[Vector2i(2, 3), Vector2i(0, 3)],
	[Vector2i(2, 4), Vector2i(0, 4)],
	[Vector2i(2, 0), Vector2i(1, 0)],
	[Vector2i(2, 1), Vector2i(0, 5)],
	[Vector2i(2, 2), Vector2i(1, 1)],
	[Vector2i(3, 0), Vector2i(0, 0)],
	[Vector2i(3, 1), Vector2i(0, 1)],
	[Vector2i(3, 2), Vector2i(0, 2)],
	[Vector2i(3, 3), Vector2i(1, 0)],
	[Vector2i(3, 4), Vector2i(0, 4)],
	[Vector2i(3, 0), Vector2i(0, 5)],
	[Vector2i(3, 1), Vector2i(1, 1)],
	[Vector2i(3, 2), Vector2i(0, 3)],
	[Vector2i(4, 0), Vector2i(0, 0)],
	[Vector2i(4, 1), Vector2i(0, 1)],
	[Vector2i(4, 2), Vector2i(1, 0)],
	[Vector2i(4, 3), Vector2i(0, 3)],
	[Vector2i(4, 4), Vector2i(0, 4)],
	[Vector2i(4, 0), Vector2i(0, 5)],
	[Vector2i(4, 1), Vector2i(1, 2)],
	[Vector2i(5, 0), Vector2i(0, 0)],
	[Vector2i(5, 1), Vector2i(0, 1)],
	[Vector2i(5, 2), Vector2i(0, 2)],
	[Vector2i(5, 3), Vector2i(1, 1)],
	[Vector2i(5, 4), Vector2i(0, 4)],
	[Vector2i(5, 0), Vector2i(0, 5)],
	[Vector2i(5, 1), Vector2i(1, 2)],
]


func _init(pair_index: int = 0) -> void:
	_build_network(pair_index)


# --- Fictional Downtown Map (29 nodes, ~45 edges) ---
#
# Clusters (Vector2i node IDs are "cluster, index within cluster" — not a
# screen grid; actual screen layout comes from node_positions):
#   0: Downtown Core   — the old-town hub, 6 tightly-linked nodes (HOME/WORK for T2/T3 city metrics land here most often)
#   1: Harbor District — a smaller secondary hub, 3 nodes
#   2: Northgate Village — residential district, north bank across the river, 5 nodes
#   3: Eastwick         — residential district, east side, 5 nodes
#   4: Southmere        — residential district, south side, 5 nodes
#   5: Westhaven        — residential district, west side (limited road access), 5 nodes
#
# The river runs roughly west-to-east north of the Core, so Northgate is the
# only district that needs a bridge; the other three districts are already
# south of the river and connect to the Core via arterial "spokes."

func _build_network(pair_index: int = 0) -> void:
	# --- Node definitions: [ID, screen_pos, full_name, map_label] ---
	var nodes: Array = [
		# Downtown Core — old-town plaza cluster
		[Vector2i(0, 0), Vector2(420.0, 300.0), "Old Square",              "Old Square"],
		[Vector2i(0, 1), Vector2(475.0, 285.0), "Market Row",              "Market Row"],
		[Vector2i(0, 2), Vector2(460.0, 345.0), "Guildhall",               "Guildhall"],
		[Vector2i(0, 3), Vector2(390.0, 340.0), "Cathedral Steps",         "Cathedral Steps"],
		[Vector2i(0, 4), Vector2(405.0, 385.0), "Clocktower",              "Clocktower"],
		[Vector2i(0, 5), Vector2(485.0, 390.0), "Riverside Plaza",         "Riverside Plaza"],

		# Harbor District — secondary hub
		[Vector2i(1, 0), Vector2(610.0, 400.0), "Harbor Quay",             "Harbor Quay"],
		[Vector2i(1, 1), Vector2(645.0, 445.0), "Old Mill",                "Old Mill"],
		[Vector2i(1, 2), Vector2(585.0, 455.0), "Warehouse Row",           "Warehouse Row"],

		# Northgate Village — across the river, north
		[Vector2i(2, 0), Vector2(330.0,  55.0), "Village Green",           "Village Green"],
		[Vector2i(2, 1), Vector2(385.0,  90.0), "Northgate Cross",         "Northgate Cross"],
		[Vector2i(2, 2), Vector2(290.0, 105.0), "Millpond Lane",           "Millpond Lane"],
		[Vector2i(2, 3), Vector2(430.0,  50.0), "Hilltop Row",             "Hilltop Row"],
		[Vector2i(2, 4), Vector2(355.0, 150.0), "Orchard Path",            ""],

		# Eastwick — east side, same bank as the Core
		[Vector2i(3, 0), Vector2(700.0, 295.0), "Eastwick Square",         "Eastwick Square"],
		[Vector2i(3, 1), Vector2(745.0, 340.0), "Ropewalk",                "Ropewalk"],
		[Vector2i(3, 2), Vector2(665.0, 250.0), "Chapel Fields",           "Chapel Fields"],
		[Vector2i(3, 3), Vector2(725.0, 390.0), "Foundry Row",             "Foundry Row"],
		[Vector2i(3, 4), Vector2(640.0, 415.0), "Riverbend East",          ""],

		# Southmere — south side, same bank as the Core
		[Vector2i(4, 0), Vector2(345.0, 580.0), "Southmere Green",         "Southmere Green"],
		[Vector2i(4, 1), Vector2(390.0, 555.0), "Mill Race",               "Mill Race"],
		[Vector2i(4, 2), Vector2(295.0, 615.0), "Cobble Lane",             "Cobble Lane"],
		[Vector2i(4, 3), Vector2(420.0, 620.0), "Fisher's Row",            "Fisher's Row"],
		[Vector2i(4, 4), Vector2(380.0, 495.0), "Lower Bridge Road",       ""],

		# Westhaven — west side, reached by only a couple of roads
		[Vector2i(5, 0), Vector2(65.0,  300.0), "Westhaven Square",        "Westhaven Sq."],
		[Vector2i(5, 1), Vector2(110.0, 345.0), "Weaver's Lane",           "Weaver's Lane"],
		[Vector2i(5, 2), Vector2(45.0,  245.0), "Old Toll Road",           "Old Toll Rd"],
		[Vector2i(5, 3), Vector2(135.0, 255.0), "Greengate",               "Greengate"],
		[Vector2i(5, 4), Vector2(165.0, 385.0), "Ferry Point",             ""],
	]

	for entry: Array in nodes:
		var nid: Vector2i = entry[0]
		node_positions[nid] = entry[1]
		node_names[nid] = entry[2]
		node_labels[nid] = entry[3]
		adjacency[nid] = []
		all_nodes.append(nid)

	var idx: int = clampi(pair_index, 0, HOME_WORK_PAIRS.size() - 1)
	home_node = HOME_WORK_PAIRS[idx][0]
	work_node = HOME_WORK_PAIRS[idx][1]

	# --- River visual curve (drawn by CityGrid, no gameplay effect) ---
	# Runs roughly west-to-east, dipping and rising organically, north of the
	# Core — only Northgate Village sits on the far bank.
	river_points = PackedVector2Array([
		Vector2(-20.0, 175.0), Vector2(90.0, 168.0), Vector2(190.0, 178.0),
		Vector2(300.0, 198.0), Vector2(400.0, 212.0), Vector2(500.0, 202.0),
		Vector2(600.0, 188.0), Vector2(700.0, 178.0), Vector2(820.0, 168.0),
	])

	# --- Edge definitions: [from, to, base_time (min), stress (0.0–1.0)] ---
	var edges: Array = [

		# ===================================================================
		#  RIVER CROSSINGS — Northgate Village ↔ Downtown Core
		# ===================================================================
		[Vector2i(2, 4), Vector2i(0, 3), 3.0, 0.55],  # Orchard Path — Cathedral Steps (direct bridge)
		[Vector2i(2, 1), Vector2i(0, 0), 3.5, 0.65],  # Northgate Cross — Old Square (busier arterial bridge)
		[Vector2i(2, 3), Vector2i(0, 1), 4.2, 0.25],  # Hilltop Row — Market Row (quiet footbridge, longer)

		# ===================================================================
		#  SPOKES — Downtown Core ↔ Eastwick
		# ===================================================================
		[Vector2i(0, 1), Vector2i(3, 2), 3.0, 0.75],  # Market Row — Chapel Fields (busy arterial)
		[Vector2i(0, 5), Vector2i(3, 4), 2.8, 0.45],  # Riverside Plaza — Riverbend East (quieter riverside path)

		# ===================================================================
		#  SPOKES — Downtown Core ↔ Southmere
		# ===================================================================
		[Vector2i(0, 4), Vector2i(4, 4), 2.2, 0.70],  # Clocktower — Lower Bridge Road (main arterial)
		[Vector2i(0, 2), Vector2i(4, 1), 3.0, 0.50],  # Guildhall — Mill Race (secondary, moderate)

		# ===================================================================
		#  SPOKES — Downtown Core ↔ Westhaven (limited access district)
		# ===================================================================
		[Vector2i(0, 3), Vector2i(5, 1), 4.0, 0.80],  # Cathedral Steps — Weaver's Lane (the main busy route in)
		[Vector2i(0, 4), Vector2i(5, 4), 4.8, 0.30],  # Clocktower — Ferry Point (longer, scenic, low-stress)

		# ===================================================================
		#  SPOKES — Downtown Core ↔ Harbor District
		# ===================================================================
		[Vector2i(0, 5), Vector2i(1, 0), 2.0, 0.40],  # Riverside Plaza — Harbor Quay (waterfront promenade)
		[Vector2i(0, 2), Vector2i(1, 2), 2.5, 0.60],  # Guildhall — Warehouse Row (industrial back street)

		# ===================================================================
		#  RING ROADS — residential districts connecting directly, bypassing the Core
		# ===================================================================
		[Vector2i(3, 3), Vector2i(4, 3), 4.5, 0.60],  # Foundry Row — Fisher's Row (outskirts connector)
		[Vector2i(4, 2), Vector2i(5, 2), 5.0, 0.55],  # Cobble Lane — Old Toll Road (outskirts connector)
		[Vector2i(3, 4), Vector2i(1, 1), 2.0, 0.45],  # Riverbend East — Old Mill (short Eastwick/Harbor link)

		# ===================================================================
		#  DOWNTOWN CORE — internal plaza streets (dense, pedestrian-scaled)
		# ===================================================================
		[Vector2i(0, 0), Vector2i(0, 1), 1.2, 0.35],  # Old Square — Market Row
		[Vector2i(0, 0), Vector2i(0, 3), 1.0, 0.30],  # Old Square — Cathedral Steps
		[Vector2i(0, 0), Vector2i(0, 2), 1.5, 0.38],  # Old Square — Guildhall
		[Vector2i(0, 1), Vector2i(0, 2), 1.3, 0.35],  # Market Row — Guildhall
		[Vector2i(0, 2), Vector2i(0, 3), 1.5, 0.40],  # Guildhall — Cathedral Steps
		[Vector2i(0, 2), Vector2i(0, 5), 1.2, 0.35],  # Guildhall — Riverside Plaza
		[Vector2i(0, 3), Vector2i(0, 4), 1.0, 0.30],  # Cathedral Steps — Clocktower
		[Vector2i(0, 4), Vector2i(0, 5), 1.4, 0.40],  # Clocktower — Riverside Plaza

		# ===================================================================
		#  HARBOR DISTRICT — internal streets
		# ===================================================================
		[Vector2i(1, 0), Vector2i(1, 1), 1.3, 0.45],  # Harbor Quay — Old Mill
		[Vector2i(1, 1), Vector2i(1, 2), 1.2, 0.50],  # Old Mill — Warehouse Row
		[Vector2i(1, 0), Vector2i(1, 2), 1.5, 0.48],  # Harbor Quay — Warehouse Row

		# ===================================================================
		#  NORTHGATE VILLAGE — internal streets
		# ===================================================================
		[Vector2i(2, 0), Vector2i(2, 1), 1.5, 0.40],  # Village Green — Northgate Cross
		[Vector2i(2, 0), Vector2i(2, 2), 1.3, 0.38],  # Village Green — Millpond Lane
		[Vector2i(2, 1), Vector2i(2, 3), 1.4, 0.42],  # Northgate Cross — Hilltop Row
		[Vector2i(2, 1), Vector2i(2, 4), 1.6, 0.45],  # Northgate Cross — Orchard Path
		[Vector2i(2, 2), Vector2i(2, 4), 1.8, 0.40],  # Millpond Lane — Orchard Path

		# ===================================================================
		#  EASTWICK — internal streets
		# ===================================================================
		[Vector2i(3, 0), Vector2i(3, 2), 1.4, 0.42],  # Eastwick Square — Chapel Fields
		[Vector2i(3, 0), Vector2i(3, 1), 1.3, 0.45],  # Eastwick Square — Ropewalk
		[Vector2i(3, 0), Vector2i(3, 3), 1.6, 0.48],  # Eastwick Square — Foundry Row
		[Vector2i(3, 3), Vector2i(3, 4), 1.5, 0.45],  # Foundry Row — Riverbend East
		[Vector2i(3, 1), Vector2i(3, 3), 1.4, 0.50],  # Ropewalk — Foundry Row

		# ===================================================================
		#  SOUTHMERE — internal streets
		# ===================================================================
		[Vector2i(4, 0), Vector2i(4, 1), 1.3, 0.40],  # Southmere Green — Mill Race
		[Vector2i(4, 0), Vector2i(4, 2), 1.5, 0.42],  # Southmere Green — Cobble Lane
		[Vector2i(4, 1), Vector2i(4, 4), 1.4, 0.45],  # Mill Race — Lower Bridge Road
		[Vector2i(4, 2), Vector2i(4, 3), 1.6, 0.42],  # Cobble Lane — Fisher's Row
		[Vector2i(4, 1), Vector2i(4, 3), 1.5, 0.44],  # Mill Race — Fisher's Row

		# ===================================================================
		#  WESTHAVEN — internal streets
		# ===================================================================
		[Vector2i(5, 0), Vector2i(5, 1), 1.3, 0.40],  # Westhaven Square — Weaver's Lane
		[Vector2i(5, 0), Vector2i(5, 2), 1.4, 0.38],  # Westhaven Square — Old Toll Road
		[Vector2i(5, 0), Vector2i(5, 3), 1.2, 0.42],  # Westhaven Square — Greengate
		[Vector2i(5, 1), Vector2i(5, 4), 1.5, 0.45],  # Weaver's Lane — Ferry Point
		[Vector2i(5, 3), Vector2i(5, 2), 1.3, 0.40],  # Greengate — Old Toll Road
	]

	for edge: Array in edges:
		_add_undirected_link(edge[0], edge[1], edge[2], edge[3])

	_apply_initial_infrastructure()


func _apply_initial_infrastructure() -> void:
	# Cathedral Steps — Clocktower: the city's flagship protected bike lane
	_set_initial_upgrade(Vector2i(0, 3), Vector2i(0, 4), 2)
	# Hilltop Row — Market Row: dedicated ped/cycle footbridge over the river
	_set_initial_upgrade(Vector2i(2, 3), Vector2i(0, 1), 2)
	# Riverside Plaza — Harbor Quay: waterfront promenade, already has a painted lane
	_set_initial_upgrade(Vector2i(0, 5), Vector2i(1, 0), 1)


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
