class_name ProceduralBackground
extends Node2D
## ProceduralBackground.gd
## Flat-vector alternative to the illustrated background image — drawn
## directly from the network's own node/link positions, so it is always
## perfectly aligned to the roads (no image-fitting needed). Trades the
## painted-art detail of the image background for guaranteed alignment;
## see CityGrid.BackgroundMode to switch between the two.
##
## Approach: tile the network's bounding box into cells, skip any cell
## whose center is too close to a road (so buildings/parks never overlap
## the street), and draw a building or a small park in the rest. Which one,
## and its color/size, comes from a deterministic hash of the cell's grid
## indices — not the shared seeded RNG — so this never disturbs simulated
## resident determinism and looks identical every run.

const CELL_SIZE: float = 46.0
const ROAD_CLEARANCE: float = 22.0   # keep clear of ROAD_WIDTH/2 (12) + margin
const MARGIN: float = 60.0           # how far past the node bounds to tile

const BUILDING_COLORS: Array = [
	Color(0.80, 0.72, 0.60),
	Color(0.70, 0.74, 0.68),
	Color(0.76, 0.68, 0.70),
	Color(0.70, 0.73, 0.80),
	Color(0.82, 0.78, 0.64),
]
const PARK_COLOR      := Color(0.74, 0.82, 0.68)
const PARK_TREE_COLOR := Color(0.47, 0.60, 0.42)
const PARK_CHANCE: float  = 0.22
const SKIP_CHANCE: float  = 0.15   # empty lot, so blocks don't feel too dense

var _segments: Array = []   # Array[PackedVector2Array of 2 points] — road lines to avoid
var _cells: Array = []      # cached draw data, built once in setup()


func setup(net: CityNetwork) -> void:
	_segments.clear()
	var drawn: Dictionary = {}
	for link_id: String in net.links:
		var link: CityNetwork.Link = net.links[link_id]
		var canonical := CityNetwork.canonical_link_id(link.from_node, link.to_node)
		if drawn.has(canonical):
			continue
		drawn[canonical] = true
		_segments.append([net.node_positions[link.from_node], net.node_positions[link.to_node]])

	_build_cells(net.get_bounds())
	queue_redraw()


func _build_cells(bounds: Rect2) -> void:
	_cells.clear()
	var start := bounds.position - Vector2(MARGIN, MARGIN)
	var end   := bounds.position + bounds.size + Vector2(MARGIN, MARGIN)
	var cols := int(ceil((end.x - start.x) / CELL_SIZE))
	var rows := int(ceil((end.y - start.y) / CELL_SIZE))

	for row in range(rows):
		for col in range(cols):
			var center := start + Vector2((col + 0.5) * CELL_SIZE, (row + 0.5) * CELL_SIZE)
			if _too_close_to_road(center):
				continue
			var h := _hash2(col, row)
			if h < SKIP_CHANCE:
				continue
			var is_park := h < SKIP_CHANCE + PARK_CHANCE
			var jitter := Vector2(_hash2(col * 3 + 1, row) - 0.5, _hash2(col, row * 3 + 1) - 0.5) * (CELL_SIZE * 0.2)
			var size := CELL_SIZE * (0.55 + _hash2(col * 7, row * 5) * 0.25)
			_cells.append({
				"center": center + jitter,
				"size": size,
				"is_park": is_park,
				"color_index": int(_hash2(col * 11, row * 13) * BUILDING_COLORS.size()) % BUILDING_COLORS.size(),
			})


func _too_close_to_road(point: Vector2) -> bool:
	var min_clear: float = ROAD_CLEARANCE + CELL_SIZE * 0.4
	for seg in _segments:
		if _dist_to_segment(point, seg[0], seg[1]) < min_clear:
			return true
	return false


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.dot(ab)
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Classic sine-hash pseudo-random — deterministic per (i, j), not tied to
## the shared seeded RNG, so resident/route determinism is untouched.
func _hash2(i: int, j: int) -> float:
	var v := sin(float(i) * 127.1 + float(j) * 311.7) * 43758.5453
	return v - floor(v)


func _draw() -> void:
	for cell in _cells:
		if cell["is_park"]:
			_draw_park(cell["center"], cell["size"])
		else:
			_draw_building(cell["center"], cell["size"], cell["color_index"])


func _draw_building(center: Vector2, size: float, color_index: int) -> void:
	var col: Color = BUILDING_COLORS[color_index]
	var half := size * 0.5
	draw_rect(Rect2(center - Vector2(half, half), Vector2(size, size)), col)
	draw_rect(Rect2(center - Vector2(half, half), Vector2(size, size * 0.2)), col.darkened(0.18))


func _draw_park(center: Vector2, size: float) -> void:
	var half := size * 0.5
	draw_rect(Rect2(center - Vector2(half, half), Vector2(size, size)), PARK_COLOR)
	var tree_count := 3
	for i in range(tree_count):
		var offset := Vector2(
			(_hash2(i * 17, int(center.x)) - 0.5) * size * 0.6,
			(_hash2(i * 19, int(center.y)) - 0.5) * size * 0.6
		)
		draw_circle(center + offset, size * 0.14, PARK_TREE_COLOR)
