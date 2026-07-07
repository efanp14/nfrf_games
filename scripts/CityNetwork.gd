class_name CityNetwork
## CityNetwork.gd
## Represents central Calgary's road network as a graph.
## The Bow River divides north from south; bridges are the only crossings.
## Routing delegates to Dijkstra.gd; the game never hardcodes routes.

# --- Data Structures ---

class Link:
	var id: String
	var from_node: Vector2i
	var to_node: Vector2i
	var base_time: float
	var stress_score: float
	var beta: float
	var upgrade_level: int
	func _init(fid: String, fn: Vector2i, tn: Vector2i, bt: float, ss: float) -> void:
		id = fid
		from_node = fn
		to_node = tn
		base_time = bt
		stress_score = ss
		beta = 1.0
		upgrade_level = 0

	func impedance(alpha: float) -> float:
		return base_time * (1.0 + alpha * beta * stress_score)


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
	[Vector2i(1, 0), Vector2i(7, 8), "Kensington → Stampede Park"],
	[Vector2i(7, 0), Vector2i(2, 9), "Bridgeland → 17 Ave SW"],
	[Vector2i(5, 0), Vector2i(2, 8), "North Hill → Beltline"],
	[Vector2i(1, 1), Vector2i(7, 7), "Sunnyside → Victoria Park"],
	[Vector2i(0, 1), Vector2i(5, 9), "Crowchild → 17 Ave & Centre"],
]


func _init(pair_index: int = 0) -> void:
	_build_calgary(pair_index)


# --- Calgary Central Map (51 nodes, ~93 edges) ---
#
# Columns (north-south streets, west to east):
#   0: Crowchild Trail       4: 1 St SW             (HOME = Kensington, col 1 row 0)
#   1: 10 St NW/SW           5: Centre Street        (WORK = Stampede Park, col 7 row 8)
#   2: 5 St SW               6: 1 St SE
#   3: 2 St SW (cycle track) 7: Macleod Trail / Edmonton Trail
#
# Rows (east-west avenues / features, north to south):
#   0: North residential (Kensington, Bridgeland)
#   1: Memorial Drive (north bank of Bow River)
#   2: Bow River crossings — bridges & pathway
#   3: 4th Avenue (north downtown / Eau Claire)
#   4: 7th Avenue (C-Train corridor)
#   5: 8th Avenue (Stephen Avenue pedestrian mall)
#   6: 9th Avenue (one-way arterial)
#   7: 11th Avenue
#   8: 12th Avenue (Beltline)
#   9: 17th Avenue (Red Mile)

func _build_calgary(pair_index: int = 0) -> void:
	# --- Node definitions: [ID, screen_pos, full_name, map_label] ---
	var nodes: Array = [
		# Row 0 — North residential
		[Vector2i(1, 0), Vector2(140.0,  22.0),  "Kensington Rd & 10 St NW",     "Kensington"],
		[Vector2i(5, 0), Vector2(540.0,  18.0),  "Centre St N & 16 Ave",          "North Hill"],
		[Vector2i(7, 0), Vector2(800.0,  25.0),  "1 Ave NE & Edmonton Trail",     "Bridgeland"],

		# Row 1 — Memorial Drive (north bank)
		[Vector2i(0, 1), Vector2(30.0,   95.0),  "Crowchild Tr & Memorial Dr",    "Crowchild"],
		[Vector2i(1, 1), Vector2(140.0, 100.0),  "10 St NW & Memorial Dr",        "Sunnyside"],
		[Vector2i(2, 1), Vector2(265.0, 100.0),  "5 St NW & Memorial Dr",         ""],
		[Vector2i(5, 1), Vector2(540.0,  95.0),  "Centre St N & Memorial Dr",     ""],
		[Vector2i(6, 1), Vector2(640.0, 100.0),  "4 St NE & Memorial Dr",         ""],
		[Vector2i(7, 1), Vector2(800.0, 100.0),  "Edmonton Tr & Memorial Dr",     ""],

		# Row 2 — Bow River crossings & pathway
		[Vector2i(0, 2), Vector2(30.0,  190.0),  "Bow River Path West",           ""],
		[Vector2i(1, 2), Vector2(148.0, 182.0),  "10 St Bridge (Louise)",         "Louise Br."],
		[Vector2i(2, 2), Vector2(270.0, 176.0),  "Peace Bridge",                  "Peace Bridge"],
		[Vector2i(4, 2), Vector2(445.0, 180.0),  "Prince's Island Park",          "Prince's Isl."],
		[Vector2i(5, 2), Vector2(540.0, 185.0),  "Centre Street Bridge",          "Centre St Br."],
		[Vector2i(6, 2), Vector2(645.0, 188.0),  "Reconciliation Bridge",         "Reconciliation"],
		[Vector2i(7, 2), Vector2(800.0, 195.0),  "Zoo Bridge",                    "Zoo Bridge"],

		# Row 3 — 4th Avenue (north downtown / Eau Claire)
		[Vector2i(1, 3), Vector2(140.0, 265.0),  "4 Ave & 10 St SW",             ""],
		[Vector2i(2, 3), Vector2(265.0, 265.0),  "4 Ave & 5 St SW",              ""],
		[Vector2i(3, 3), Vector2(365.0, 265.0),  "4 Ave & 2 St SW",              "2 St SW"],
		[Vector2i(4, 3), Vector2(450.0, 265.0),  "Eau Claire (4 Ave & 1 St SW)", "Eau Claire"],
		[Vector2i(5, 3), Vector2(540.0, 265.0),  "4 Ave & Centre St",            ""],
		[Vector2i(6, 3), Vector2(640.0, 265.0),  "4 Ave & 1 St SE",              ""],
		[Vector2i(7, 3), Vector2(800.0, 265.0),  "4 Ave & Macleod Trail",        "Macleod Tr"],

		# Row 4 — 7th Avenue (C-Train corridor)
		[Vector2i(1, 4), Vector2(140.0, 340.0),  "7 Ave & 10 St SW",             "Sunalta"],
		[Vector2i(2, 4), Vector2(265.0, 340.0),  "7 Ave & 5 St SW",              "Kerby"],
		[Vector2i(3, 4), Vector2(365.0, 340.0),  "7 Ave & 2 St SW",              ""],
		[Vector2i(4, 4), Vector2(450.0, 340.0),  "7 Ave & 1 St SW",              ""],
		[Vector2i(5, 4), Vector2(540.0, 340.0),  "7 Ave & Centre St",            "City Hall"],
		[Vector2i(6, 4), Vector2(640.0, 340.0),  "7 Ave & 1 St SE",              ""],
		[Vector2i(7, 4), Vector2(800.0, 340.0),  "7 Ave & Macleod Trail",        ""],

		# Row 5 — Stephen Avenue / 8th Ave (pedestrian mall — low stress)
		[Vector2i(2, 5), Vector2(265.0, 395.0),  "Stephen Ave & 5 St SW",        "Stephen Ave"],
		[Vector2i(4, 5), Vector2(450.0, 395.0),  "Stephen Ave & 1 St SW",        ""],
		[Vector2i(5, 5), Vector2(540.0, 395.0),  "Stephen Ave & Centre St",      ""],
		[Vector2i(6, 5), Vector2(640.0, 395.0),  "Stephen Ave & 1 St SE",        ""],

		# Row 6 — 9th Avenue (one-way arterial, high stress)
		[Vector2i(2, 6), Vector2(265.0, 445.0),  "9 Ave & 5 St SW",              "9 Ave"],
		[Vector2i(4, 6), Vector2(450.0, 445.0),  "9 Ave & 1 St SW",              ""],
		[Vector2i(5, 6), Vector2(540.0, 445.0),  "9 Ave & Centre St",            ""],
		[Vector2i(6, 6), Vector2(640.0, 445.0),  "9 Ave & 1 St SE",              ""],
		[Vector2i(7, 6), Vector2(800.0, 445.0),  "9 Ave & Macleod Trail",        ""],

		# Row 7 — 11th Avenue
		[Vector2i(1, 7), Vector2(140.0, 515.0),  "11 Ave & 10 St SW",            "11 Ave"],
		[Vector2i(4, 7), Vector2(450.0, 515.0),  "11 Ave & 1 St SW",             ""],
		[Vector2i(5, 7), Vector2(540.0, 515.0),  "11 Ave & Centre St",           ""],
		[Vector2i(7, 7), Vector2(800.0, 520.0),  "Victoria Park",                "Victoria Park"],

		# Row 8 — 12th Avenue (Beltline)
		[Vector2i(2, 8), Vector2(265.0, 585.0),  "12 Ave & 5 St SW",             "12 Ave"],
		[Vector2i(4, 8), Vector2(450.0, 585.0),  "12 Ave & 1 St SW",             ""],
		[Vector2i(5, 8), Vector2(540.0, 585.0),  "12 Ave & Centre St",           ""],
		[Vector2i(7, 8), Vector2(800.0, 590.0),  "Stampede Park",                "Stampede Park"],

		# Row 9 — 17th Avenue (Red Mile)
		[Vector2i(2, 9), Vector2(265.0, 650.0),  "17 Ave & 4 St SW",             "17 Ave SW"],
		[Vector2i(4, 9), Vector2(450.0, 650.0),  "17 Ave & 1 St SW",             ""],
		[Vector2i(5, 9), Vector2(540.0, 650.0),  "17 Ave & Centre St",           ""],
		[Vector2i(7, 9), Vector2(800.0, 655.0),  "17 Ave & Macleod Trail",       ""],
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

	# --- Bow River visual curve (drawn by CityGrid, no gameplay effect) ---
	river_points = PackedVector2Array([
		Vector2(-20.0, 138.0), Vector2(80.0, 140.0), Vector2(170.0, 139.0),
		Vector2(260.0, 141.0), Vector2(350.0, 143.0), Vector2(440.0, 145.0),
		Vector2(530.0, 148.0), Vector2(620.0, 151.0), Vector2(710.0, 155.0),
		Vector2(820.0, 160.0),
	])

	# --- Edge definitions: [from, to, base_time (min), stress (0.0–1.0)] ---
	var edges: Array = [

		# ===================================================================
		#  BOW RIVER PATHWAY (east-west along south bank, multi-use trail)
		# ===================================================================
		[Vector2i(0, 2), Vector2i(1, 2), 2.5, 0.10],  # Path West → Louise Bridge
		[Vector2i(1, 2), Vector2i(2, 2), 2.0, 0.10],  # Louise Bridge → Peace Bridge
		[Vector2i(2, 2), Vector2i(4, 2), 3.0, 0.10],  # Peace Bridge → Prince's Island
		[Vector2i(4, 2), Vector2i(5, 2), 2.0, 0.10],  # Prince's Island → Centre St Br.
		[Vector2i(5, 2), Vector2i(6, 2), 2.5, 0.12],  # Centre St Br. → Reconciliation
		[Vector2i(6, 2), Vector2i(7, 2), 3.0, 0.15],  # Reconciliation → Zoo Bridge

		# ===================================================================
		#  BRIDGES: North bank (row 1) → River crossings (row 2)
		# ===================================================================
		[Vector2i(0, 1), Vector2i(0, 2), 2.5, 0.80],  # Crowchild overpass (highway bridge)
		[Vector2i(1, 1), Vector2i(1, 2), 1.5, 0.35],  # Louise Bridge / 10 St (moderate, has sidewalks)
		[Vector2i(1, 1), Vector2i(2, 2), 2.5, 0.18],  # Sunnyside residential walk to Peace Bridge
		[Vector2i(2, 1), Vector2i(2, 2), 1.5, 0.15],  # 5 St NW direct to Peace Bridge (dedicated ped/cycle!)
		[Vector2i(5, 1), Vector2i(5, 2), 2.5, 0.65],  # Centre St Bridge (busy 4-lane arterial)
		[Vector2i(6, 1), Vector2i(6, 2), 2.0, 0.40],  # Reconciliation Bridge (has cycling lane)
		[Vector2i(7, 1), Vector2i(7, 2), 2.5, 0.50],  # Zoo / Edmonton Trail bridge

		# ===================================================================
		#  BRIDGES: River crossings (row 2) → Downtown (row 3)
		# ===================================================================
		[Vector2i(1, 2), Vector2i(1, 3), 1.5, 0.35],  # Louise Bridge south → 4 Ave & 10 St
		[Vector2i(2, 2), Vector2i(2, 3), 1.5, 0.20],  # Peace Bridge south → 4 Ave & 5 St
		[Vector2i(2, 2), Vector2i(3, 3), 2.0, 0.15],  # Peace Bridge → 2 St SW cycle track start
		[Vector2i(4, 2), Vector2i(4, 3), 1.5, 0.20],  # Prince's Island → Eau Claire (parkland paths)
		[Vector2i(5, 2), Vector2i(5, 3), 2.0, 0.55],  # Centre St Bridge south → 4 Ave & Centre
		[Vector2i(6, 2), Vector2i(6, 3), 2.0, 0.45],  # Reconciliation south → 4 Ave & 1 St SE
		[Vector2i(7, 2), Vector2i(7, 3), 2.5, 0.55],  # Zoo Bridge south → 4 Ave & Macleod

		# ===================================================================
		#  MEMORIAL DRIVE (east-west along north bank, busy arterial)
		# ===================================================================
		[Vector2i(0, 1), Vector2i(1, 1), 2.5, 0.70],  # Crowchild → Sunnyside
		[Vector2i(1, 1), Vector2i(2, 1), 2.0, 0.65],  # Sunnyside → 5 St NW
		[Vector2i(2, 1), Vector2i(5, 1), 3.5, 0.70],  # 5 St NW → Centre St N
		[Vector2i(5, 1), Vector2i(6, 1), 2.0, 0.72],  # Centre St N → 4 St NE
		[Vector2i(6, 1), Vector2i(7, 1), 2.5, 0.75],  # 4 St NE → Edmonton Trail

		# ===================================================================
		#  NORTH RESIDENTIAL (row 0 ↔ row 1)
		# ===================================================================
		[Vector2i(1, 0), Vector2i(1, 1), 2.5, 0.60],  # Kensington → Sunnyside (10 St residential)
		[Vector2i(1, 0), Vector2i(2, 1), 2.0, 0.55],  # Kensington back streets → 5 St NW
		[Vector2i(5, 0), Vector2i(5, 1), 3.0, 0.78],  # North Hill → Memorial (Centre St, busy)
		[Vector2i(7, 0), Vector2i(7, 1), 2.5, 0.68],  # Bridgeland → Memorial (Edmonton Trail)

		# ===================================================================
		#  NORTH RESIDENTIAL EAST-WEST (row 0)
		# ===================================================================
		[Vector2i(1, 0), Vector2i(5, 0), 4.0, 0.70],  # Kensington → North Hill (16 Ave)
		[Vector2i(5, 0), Vector2i(7, 0), 3.5, 0.68],  # North Hill → Bridgeland

		# ===================================================================
		#  4TH AVENUE (east-west, row 3 — moderate, some bike infra)
		# ===================================================================
		[Vector2i(1, 3), Vector2i(2, 3), 2.0, 0.70],  # 10 St → 5 St
		[Vector2i(2, 3), Vector2i(3, 3), 1.5, 0.65],  # 5 St → 2 St
		[Vector2i(3, 3), Vector2i(4, 3), 1.5, 0.65],  # 2 St → Eau Claire
		[Vector2i(4, 3), Vector2i(5, 3), 2.0, 0.68],  # Eau Claire → Centre
		[Vector2i(5, 3), Vector2i(6, 3), 2.0, 0.70],  # Centre → 1 St SE
		[Vector2i(6, 3), Vector2i(7, 3), 2.5, 0.75],  # 1 St SE → Macleod

		# ===================================================================
		#  7TH AVENUE / C-TRAIN (east-west, row 4 — busy, LRT shares road)
		# ===================================================================
		[Vector2i(1, 4), Vector2i(2, 4), 2.0, 0.70],  # Sunalta → Kerby
		[Vector2i(2, 4), Vector2i(3, 4), 1.5, 0.65],  # Kerby → 2 St
		[Vector2i(3, 4), Vector2i(4, 4), 1.5, 0.65],  # 2 St → 1 St
		[Vector2i(4, 4), Vector2i(5, 4), 2.0, 0.70],  # 1 St → City Hall
		[Vector2i(5, 4), Vector2i(6, 4), 2.0, 0.70],  # City Hall → 1 St SE
		[Vector2i(6, 4), Vector2i(7, 4), 2.5, 0.80],  # 1 St SE → Macleod

		# ===================================================================
		#  STEPHEN AVENUE / 8TH AVE (east-west, row 5 — pedestrian mall, low stress)
		# ===================================================================
		[Vector2i(2, 5), Vector2i(4, 5), 2.5, 0.20],  # 5 St → 1 St (through the mall)
		[Vector2i(4, 5), Vector2i(5, 5), 1.5, 0.20],  # 1 St → Centre
		[Vector2i(5, 5), Vector2i(6, 5), 1.5, 0.25],  # Centre → 1 St SE

		# ===================================================================
		#  9TH AVENUE (east-west, row 6 — one-way arterial, high stress)
		# ===================================================================
		[Vector2i(2, 6), Vector2i(4, 6), 2.5, 0.82],  # 5 St → 1 St
		[Vector2i(4, 6), Vector2i(5, 6), 2.0, 0.85],  # 1 St → Centre
		[Vector2i(5, 6), Vector2i(6, 6), 2.0, 0.85],  # Centre → 1 St SE
		[Vector2i(6, 6), Vector2i(7, 6), 2.5, 0.90],  # 1 St SE → Macleod

		# ===================================================================
		#  11TH AVENUE (east-west, row 7)
		# ===================================================================
		[Vector2i(1, 7), Vector2i(4, 7), 3.5, 0.75],  # 10 St → 1 St
		[Vector2i(4, 7), Vector2i(5, 7), 2.0, 0.75],  # 1 St → Centre
		[Vector2i(5, 7), Vector2i(7, 7), 3.5, 0.78],  # Centre → Victoria Park

		# ===================================================================
		#  12TH AVENUE (east-west, row 8 — Beltline)
		# ===================================================================
		[Vector2i(2, 8), Vector2i(4, 8), 2.5, 0.75],  # 5 St → 1 St
		[Vector2i(4, 8), Vector2i(5, 8), 2.0, 0.75],  # 1 St → Centre
		[Vector2i(5, 8), Vector2i(7, 8), 3.5, 0.78],  # Centre → Stampede

		# ===================================================================
		#  17TH AVENUE (east-west, row 9 — Red Mile)
		# ===================================================================
		[Vector2i(2, 9), Vector2i(4, 9), 2.5, 0.72],  # 4 St → 1 St
		[Vector2i(4, 9), Vector2i(5, 9), 2.0, 0.70],  # 1 St → Centre
		[Vector2i(5, 9), Vector2i(7, 9), 3.5, 0.75],  # Centre → Macleod

		# ===================================================================
		#  NORTH-SOUTH: 10 St NW/SW (column 1 — residential, moderate)
		# ===================================================================
		[Vector2i(1, 3), Vector2i(1, 4), 2.5, 0.68],  # 4 Ave → 7 Ave
		[Vector2i(1, 4), Vector2i(1, 7), 4.0, 0.68],  # 7 Ave → 11 Ave (long block)

		# ===================================================================
		#  NORTH-SOUTH: 5 St SW (column 2 — quieter side street)
		# ===================================================================
		[Vector2i(2, 3), Vector2i(2, 4), 2.0, 0.68],  # 4 Ave → 7 Ave
		[Vector2i(2, 4), Vector2i(2, 5), 1.5, 0.65],  # 7 Ave → Stephen Ave
		[Vector2i(2, 5), Vector2i(2, 6), 1.5, 0.68],  # Stephen Ave → 9 Ave
		[Vector2i(2, 6), Vector2i(2, 8), 3.0, 0.72],  # 9 Ave → 12 Ave
		[Vector2i(2, 8), Vector2i(2, 9), 2.5, 0.68],  # 12 Ave → 17 Ave

		# ===================================================================
		#  NORTH-SOUTH: 2 St SW cycle track (column 3 — key cycling corridor)
		# ===================================================================
		[Vector2i(3, 3), Vector2i(3, 4), 1.5, 0.60],  # 4 Ave → 7 Ave (quiet minor street, pre-upgraded)

		# ===================================================================
		#  NORTH-SOUTH: 1 St SW (column 4 — through-street, moderate)
		# ===================================================================
		[Vector2i(4, 3), Vector2i(4, 4), 1.5, 0.70],  # 4 Ave → 7 Ave
		[Vector2i(4, 4), Vector2i(4, 5), 1.0, 0.65],  # 7 Ave → Stephen Ave (1 block)
		[Vector2i(4, 5), Vector2i(4, 6), 1.0, 0.68],  # Stephen Ave → 9 Ave (1 block)
		[Vector2i(4, 6), Vector2i(4, 7), 2.5, 0.72],  # 9 Ave → 11 Ave
		[Vector2i(4, 7), Vector2i(4, 8), 2.5, 0.72],  # 11 Ave → 12 Ave
		[Vector2i(4, 8), Vector2i(4, 9), 2.5, 0.68],  # 12 Ave → 17 Ave

		# ===================================================================
		#  NORTH-SOUTH: Centre Street (column 5 — busy arterial)
		# ===================================================================
		[Vector2i(5, 3), Vector2i(5, 4), 2.0, 0.78],  # 4 Ave → 7 Ave
		[Vector2i(5, 4), Vector2i(5, 5), 1.0, 0.75],  # 7 Ave → Stephen Ave
		[Vector2i(5, 5), Vector2i(5, 6), 1.0, 0.78],  # Stephen Ave → 9 Ave
		[Vector2i(5, 6), Vector2i(5, 7), 2.5, 0.80],  # 9 Ave → 11 Ave
		[Vector2i(5, 7), Vector2i(5, 8), 2.5, 0.78],  # 11 Ave → 12 Ave
		[Vector2i(5, 8), Vector2i(5, 9), 2.5, 0.75],  # 12 Ave → 17 Ave

		# ===================================================================
		#  NORTH-SOUTH: 1 St SE (column 6 — moderate)
		# ===================================================================
		[Vector2i(6, 3), Vector2i(6, 4), 2.0, 0.68],  # 4 Ave → 7 Ave
		[Vector2i(6, 4), Vector2i(6, 5), 1.0, 0.65],  # 7 Ave → Stephen Ave
		[Vector2i(6, 5), Vector2i(6, 6), 1.0, 0.68],  # Stephen Ave → 9 Ave

		# ===================================================================
		#  NORTH-SOUTH: Macleod Trail (column 7 — high-stress arterial)
		# ===================================================================
		[Vector2i(7, 3), Vector2i(7, 4), 2.5, 0.85],  # 4 Ave → 7 Ave
		[Vector2i(7, 4), Vector2i(7, 6), 3.0, 0.85],  # 7 Ave → 9 Ave (no Stephen Ave node)
		[Vector2i(7, 6), Vector2i(7, 7), 2.5, 0.80],  # 9 Ave → Victoria Park
		[Vector2i(7, 7), Vector2i(7, 8), 2.5, 0.80],  # Victoria Park → Stampede
		[Vector2i(7, 8), Vector2i(7, 9), 2.5, 0.75],  # Stampede → 17 Ave

		# ===================================================================
		#  NON-GRID / DIAGONAL
		# ===================================================================
		[Vector2i(6, 6), Vector2i(7, 7), 2.5, 0.75],  # Olympic Way: 1 St SE at 9th → Victoria Park
	]

	for edge: Array in edges:
		_add_undirected_link(edge[0], edge[1], edge[2], edge[3])

	_apply_initial_infrastructure()


func _apply_initial_infrastructure() -> void:
	# 2 St SW cycle track — Calgary's signature protected bike lane
	_set_initial_upgrade(Vector2i(3, 3), Vector2i(3, 4), 2)
	# Peace Bridge approach — dedicated ped/cycle bridge
	_set_initial_upgrade(Vector2i(2, 1), Vector2i(2, 2), 2)
	# Reconciliation Bridge — has a cycling lane
	_set_initial_upgrade(Vector2i(6, 1), Vector2i(6, 2), 1)
	# Bow River pathway — protected multi-use trail along the river
	_set_initial_upgrade(Vector2i(0, 2), Vector2i(1, 2), 2)
	_set_initial_upgrade(Vector2i(1, 2), Vector2i(2, 2), 2)
	_set_initial_upgrade(Vector2i(2, 2), Vector2i(4, 2), 2)
	_set_initial_upgrade(Vector2i(4, 2), Vector2i(5, 2), 2)
	_set_initial_upgrade(Vector2i(5, 2), Vector2i(6, 2), 2)
	_set_initial_upgrade(Vector2i(6, 2), Vector2i(7, 2), 2)


func _set_initial_upgrade(a: Vector2i, b: Vector2i, level: int) -> void:
	var id_ab := "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]
	var id_ba := "%d,%d-%d,%d" % [b.x, b.y, a.x, a.y]
	for lid in [id_ab, id_ba]:
		if links.has(lid):
			var link: Link = links[lid]
			link.upgrade_level = level
			if level == 1:
				link.beta = 0.8 - 0.3 * link.stress_score
			else:
				link.beta = 0.6 - 0.5 * link.stress_score


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
	link.beta          = 1.0
	var parts      := link_id.split("-")
	var reverse_id := "%s-%s" % [parts[1], parts[0]]
	if links.has(reverse_id):
		var rev: Link = links[reverse_id]
		rev.upgrade_level = 0
		rev.beta          = 1.0
	return true



func upgrade_link(link_id: String, upgrade_level: int) -> bool:
	if not links.has(link_id):
		return false
	var link: Link = links[link_id]
	if link.upgrade_level >= upgrade_level:
		return false
	link.upgrade_level = upgrade_level
	if upgrade_level == 1:
		link.beta = 0.8 - 0.3 * link.stress_score
	else:
		link.beta = 0.6 - 0.5 * link.stress_score
	var parts = link_id.split("-")
	var reverse_id = "%s-%s" % [parts[1], parts[0]]
	if links.has(reverse_id):
		var reverse_link: Link = links[reverse_id]
		reverse_link.upgrade_level = upgrade_level
		reverse_link.beta = link.beta
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
		var canonical = _canonical_link_id(link.from_node, link.to_node)
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
	var a := _parse_vec(parts[0])
	var b := _parse_vec(parts[1])
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


func _canonical_link_id(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d-%d,%d" % [b.x, b.y, a.x, a.y]


func _parse_vec(s: String) -> Vector2i:
	var p := s.split(",")
	return Vector2i(int(p[0]), int(p[1]))
