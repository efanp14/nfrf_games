class_name LinkSegment
extends Node2D

signal clicked(link_id: String)

var link_id: String = ""
var _upgrade_level: int = 0
var _pending_level: int = -1
var _route_players: Array[int] = []
var _is_hovered: bool = false
var _path_points: PackedVector2Array = []
var _draw_points: PackedVector2Array = []
var _stress_score: float = 0.5

# Legacy Line2D children are hidden — all rendering is via _draw().
@onready var stress_outline: Line2D  = $StressOutline
@onready var road: Line2D            = $Road
@onready var bike_lane: Line2D       = $BikeLane
@onready var route_highlight: Line2D = $RouteHighlight
@onready var hover_highlight: Line2D = $HoverHighlight

const ROAD_FILL         := Color("#494949")
const ROAD_EDGE         := Color("#1a1a1a")
const YELLOW_CENTER     := Color(0.85, 0.75, 0.20)
const WHITE_MARKING     := Color(0.95, 0.95, 0.90)
const BIKE_PAINT        := Color(0.22, 0.62, 0.28)
const PROTECTED_ASPHALT := Color("#9E948A")
const ROUTE_COLORS: Array = [
	Color(0.42, 0.64, 0.84, 0.45),
	Color(0.88, 0.47, 0.32, 0.45),
	Color(0.35, 0.72, 0.40, 0.45),
	Color(0.62, 0.42, 0.78, 0.45),
	Color(0.85, 0.68, 0.25, 0.45),
]
const HOVER_GLOW      := Color(0.95, 0.75, 0.25, 0.45)
const CAR_BODY        := Color(0.82, 0.35, 0.30)
const CAR_WINDOW      := Color(0.65, 0.82, 0.92)

const ROAD_WIDTH     := 24.0
const EDGE_BORDER    := 1.5
const LANE_W         := 6.0
const ROUTE_WIDTH    := 32.0
const HOVER_WIDTH    := 36.0
const CENTER_LINE_W  := 1.5
const LANE_DIV_W     := 1.0
const BIKE_PAINT_W   := 4.0
const DIVIDER_W      := 1.5
const HIT_RADIUS     := 18.0
const NODE_RADIUS    := 8.5   # roads extend to this depth inside the node circle (18.0 radius) so ends are hidden

const DASH_LEN       := 5.0
const DASH_GAP       := 5.0
const BARRIER_SPACE  := 10.0
const BARRIER_MARK   := 3.0
const CAR_LENGTH     := 6.0
const CAR_WIDTH_HALF := 1.8


func setup(id: String, points: PackedVector2Array, upgrade_level: int = 0, stress: float = 0.5) -> void:
	link_id = id
	_stress_score = stress
	_upgrade_level = upgrade_level
	set_points(points)


func set_points(points: PackedVector2Array) -> void:
	_path_points = points
	_compute_draw_points()
	queue_redraw()


func _compute_draw_points() -> void:
	if _path_points.size() < 2:
		_draw_points = PackedVector2Array(_path_points)
		return
	_draw_points = PackedVector2Array(_path_points)
	var dir_s := (_draw_points[1] - _draw_points[0]).normalized()
	_draw_points[0] = _draw_points[0] + dir_s * NODE_RADIUS
	var last := _draw_points.size() - 1
	var dir_e := (_draw_points[last] - _draw_points[last - 1]).normalized()
	_draw_points[last] = _draw_points[last] - dir_e * NODE_RADIUS


func set_upgrade_level(level: int) -> void:
	_upgrade_level = level
	_pending_level = -1
	queue_redraw()


func set_pending_level(level: int) -> void:
	_pending_level = level
	queue_redraw()


func set_on_route(on_route: bool, player_index: int = 0) -> void:
	if on_route:
		if not _route_players.has(player_index):
			_route_players.append(player_index)
	else:
		_route_players.erase(player_index)
	queue_redraw()


func clear_routes() -> void:
	_route_players.clear()
	queue_redraw()



func _ready() -> void:
	for child in get_children():
		if child is Line2D:
			child.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var was := _is_hovered
		_is_hovered = _is_mouse_near()
		if was != _is_hovered:
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _is_mouse_near():
			clicked.emit(link_id)
			get_viewport().set_input_as_handled()


# =======================================================================
#  DRAWING — layered from back to front
# =======================================================================

func _draw() -> void:
	if _draw_points.size() < 2:
		return

	if _is_hovered:
		_draw_thick_line(HOVER_GLOW, HOVER_WIDTH)

	if _route_players.size() == 1:
		var col: Color = ROUTE_COLORS[_route_players[0] % ROUTE_COLORS.size()]
		_draw_thick_line(col, ROUTE_WIDTH)
	elif _route_players.size() > 1:
		_draw_striped_route()

	_draw_thick_line(ROAD_EDGE, ROAD_WIDTH + EDGE_BORDER * 2.0)
	_draw_thick_line(ROAD_FILL, ROAD_WIDTH)
	_draw_road_markings()
	_draw_cars()


func _draw_thick_line(color: Color, width: float) -> void:
	draw_polyline(_draw_points, color, width, true)


func _draw_striped_route() -> void:
	var count := _route_players.size()
	var stripe_len := 10.0 / count
	for i in range(_draw_points.size() - 1):
		var a := _draw_points[i]
		var b := _draw_points[i + 1]
		var dir := (b - a).normalized()
		var length := a.distance_to(b)
		var pos := 0.0
		var ci := 0
		while pos < length:
			var pi: int = _route_players[ci % count]
			var col: Color = ROUTE_COLORS[pi % ROUTE_COLORS.size()]
			var end_pos := minf(pos + stripe_len, length)
			var p1 := a + dir * pos
			var p2 := a + dir * end_pos
			draw_line(p1, p2, col, ROUTE_WIDTH, true)
			pos = end_pos
			ci += 1


# --- Center / lane dashes ---

func _draw_dashes(offset_dist: float, color: Color, width: float, dash: float, gap: float) -> void:
	for i in range(_draw_points.size() - 1):
		var a := _draw_points[i]
		var b := _draw_points[i + 1]
		var dir := (b - a).normalized()
		var perp := dir.rotated(PI / 2.0)
		var oa := a + perp * offset_dist
		var length := a.distance_to(b)
		var pos := gap / 2.0
		while pos < length:
			var end_pos := minf(pos + dash, length)
			draw_line(oa + dir * pos, oa + dir * end_pos, color, width, true)
			pos += dash + gap


# --- Upgrade visuals (painted lanes / protected barriers) ---

func _draw_road_markings() -> void:
	var display_level := _upgrade_level
	var alpha_mult := 1.0
	if _pending_level > _upgrade_level:
		display_level = _pending_level
		alpha_mult = 0.5
	elif _pending_level == 0 and _upgrade_level > 0:
		alpha_mult = 0.25

	_draw_offset_line(0.0, YELLOW_CENTER, CENTER_LINE_W)

	if display_level <= 0:
		_draw_dashes(LANE_W, WHITE_MARKING, LANE_DIV_W, DASH_LEN, DASH_GAP)
		_draw_dashes(-LANE_W, WHITE_MARKING, LANE_DIV_W, DASH_LEN, DASH_GAP)
	elif display_level == 1:
		var pc := Color(BIKE_PAINT, alpha_mult)
		var po := ROAD_WIDTH / 2.0 - BIKE_PAINT_W / 2.0
		_draw_offset_line(po, pc, BIKE_PAINT_W)
		_draw_offset_line(-po, pc, BIKE_PAINT_W)
	else:
		# Protected: grey strips same width as painted, white divider just inside
		var po := ROAD_WIDTH / 2.0 - BIKE_PAINT_W / 2.0
		var ac := Color(PROTECTED_ASPHALT, alpha_mult)
		_draw_offset_line(po, ac, BIKE_PAINT_W)
		_draw_offset_line(-po, ac, BIKE_PAINT_W)
		var dc := Color(WHITE_MARKING, alpha_mult)
		var div_off := ROAD_WIDTH / 2.0 - BIKE_PAINT_W - DIVIDER_W / 2.0
		_draw_offset_line(div_off, dc, DIVIDER_W)
		_draw_offset_line(-div_off, dc, DIVIDER_W)


func _draw_offset_line(offset_dist: float, color: Color, width: float) -> void:
	for i in range(_draw_points.size() - 1):
		var a := _draw_points[i]
		var b := _draw_points[i + 1]
		var perp := (b - a).normalized().rotated(PI / 2.0)
		draw_line(a + perp * offset_dist, b + perp * offset_dist, color, width, true)


func _draw_barrier_marks(offset_dist: float, color: Color) -> void:
	for i in range(_draw_points.size() - 1):
		var a := _draw_points[i]
		var b := _draw_points[i + 1]
		var dir := (b - a).normalized()
		var perp := dir.rotated(PI / 2.0)
		var length := a.distance_to(b)
		var pos := BARRIER_SPACE / 2.0
		while pos < length - 2.0:
			var center := a + dir * pos + perp * offset_dist
			draw_line(
				center - perp * BARRIER_MARK,
				center + perp * (BARRIER_MARK * 0.5),
				color, 1.5, true
			)
			pos += BARRIER_SPACE


# --- Stress cars (car count reflects effective road stress, decreases when upgraded) ---

func _draw_cars() -> void:
	var beta_est: float = [1.0, 0.65, 0.3][clampi(_upgrade_level, 0, 2)]
	var num_cars := int(_stress_score * beta_est * 6.0)
	if num_cars == 0:
		return
	for i in range(_draw_points.size() - 1):
		var a := _draw_points[i]
		var b := _draw_points[i + 1]
		var dir := (b - a).normalized()
		var perp := dir.rotated(PI / 2.0)
		var length := a.distance_to(b)
		if length < CAR_LENGTH * 2.0:
			continue
		var spacing := length / float(num_cars + 1)
		var angle := dir.angle()
		for j in range(num_cars):
			var pos := spacing * (j + 1)
			var center := a + dir * pos
			# Alternate cars slightly left/right of center
			var side := LANE_W * 0.5 if j % 2 == 0 else -(LANE_W * 0.5)
			center += perp * side
			_draw_car(center, angle)


func _draw_car(center: Vector2, angle: float) -> void:
	var half_l := CAR_LENGTH / 2.0
	var hw := CAR_WIDTH_HALF
	# Car body
	var body_corners := PackedVector2Array([
		center + Vector2(-half_l, -hw).rotated(angle),
		center + Vector2(half_l, -hw).rotated(angle),
		center + Vector2(half_l, hw).rotated(angle),
		center + Vector2(-half_l, hw).rotated(angle),
	])
	draw_colored_polygon(body_corners, CAR_BODY)
	# Windshield stripe
	var ws_off := half_l * 0.3
	var ws_hw := hw * 0.6
	var ws_corners := PackedVector2Array([
		center + Vector2(ws_off - 1.0, -ws_hw).rotated(angle),
		center + Vector2(ws_off + 1.0, -ws_hw).rotated(angle),
		center + Vector2(ws_off + 1.0, ws_hw).rotated(angle),
		center + Vector2(ws_off - 1.0, ws_hw).rotated(angle),
	])
	draw_colored_polygon(ws_corners, CAR_WINDOW)


# --- Hit detection ---

func _is_mouse_near() -> bool:
	if _path_points.size() < 2:
		return false
	var local_mouse := to_local(get_global_mouse_position())
	for i: int in range(_path_points.size() - 1):
		if _dist_to_segment(local_mouse, _path_points[i], _path_points[i + 1]) < HIT_RADIUS:
			return true
	return false


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.dot(ab)
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
