class_name LinkSegment
extends Node2D

signal clicked(link_id: String)

var link_id: String = ""
var _upgrade_level: int = 0
var _pending_level: int = -1
var _route_players: Array[int] = []
## Which way each rider in _route_players travels along this link: true means
## from _draw_points[0] towards the far end, matching the order CityGrid built
## the points in. Needed only by the flow arrows; a link is stored under one
## canonical id and does not otherwise care which direction anyone crosses it.
var _route_forward: Dictionary = {}
## -1 = not in heatmap mode (draw the normal per-player route highlight
## instead); 0..1 = NPC-heatmap mode, set by CityGrid._show_npc_heatmap().
var _heatmap_intensity: float = -1.0
## Stress view: the centre line carries this road's EFFECTIVE stress (post-beta)
## on the same green to red ramp the usage heatmap uses. Separate from
## _heatmap_intensity rather than folded into it because it must not be cached:
## effective stress changes the moment a link is upgraded, and reading it at
## draw time means the colour updates itself with no explicit refresh.
##
## Deliberately paired with road WIDTH, which encodes base stress and never
## moves. Width says what kind of road this is, this view says how it feels now.
var _stress_view: bool = false
var _is_hovered: bool = false
## Set from CityGrid when the player-routes toggle is off. The route itself is
## still recorded in _route_players, so turning it back on redraws what was
## already there rather than waiting for the next round to recompute it.
var _routes_hidden: bool = false
var _path_points: PackedVector2Array = []
var _draw_points: PackedVector2Array = []
var _stress_score: float = 0.5
## Drawn width of this road, derived once from base stress in setup(). Never
## changes at runtime. See the ROAD_WIDTH comment.
var _road_width: float = ROAD_WIDTH
var _anim_t: float = 0.0
var _total_length: float = 0.0

# Legacy Line2D children are hidden — all rendering is via _draw().
@onready var stress_outline: Line2D  = $StressOutline
@onready var road: Line2D            = $Road
@onready var bike_lane: Line2D       = $BikeLane
@onready var route_highlight: Line2D = $RouteHighlight
@onready var hover_highlight: Line2D = $HoverHighlight

## Colours all come from Palette. The route band is the player's own colour at
## a fixed transparency, derived rather than listed a second time, so a seat's
## route can never disagree with its markers or its legend entry.
##
## Nearly opaque. It used to be 0.45, which on a 1280x720 laptop left the route
## as a faint tint four pixels wider than the road, and participants lost track
## of their own commute. Transparency was buying nothing: the band sits behind
## the road, so the only thing showing through it is the background art.
const ROUTE_ALPHA: float = 0.92

## Soft offset shadow drawn under every road for a touch of depth — still
## flat-shaded (a single translucent color, no blur/gradient), just enough
## to lift the road off the background.
const ROAD_SHADOW_OFFSET := Vector2(2.5, 3.0)


static func route_color(player_index: int) -> Color:
	var base: Color = Palette.PLAYER_COLORS[player_index % Palette.PLAYER_COLORS.size()]
	return Color(base, ROUTE_ALPHA)


## The arrow colour for a seat: its own colour lifted towards white, so the
## arrows stay legible against the band they sit on without introducing a sixth
## hue that would have to be kept distinct from everything else on the map.
static func route_arrow_color(player_index: int) -> Color:
	var base: Color = Palette.PLAYER_COLORS[player_index % Palette.PLAYER_COLORS.size()]
	return base.lerp(Color.WHITE, 0.72)

## Road width encodes BASE stress: the wider the road, the more inherently
## stressful it is (10 Aug 2026). This is the always-on stress cue, added
## because upgrade level had three visual cues (a curb appears, bike strips,
## colour) and stress had only one, the cars, which is the weakest channel on
## the road.
##
## Width rather than colour, because colour is already spoken for three times
## over (per-player route highlight, the NPC usage heatmap, upgrade level),
## because width is pre-attentive so the arterial network's shape reads in a
## single glance, and because it survives red-green colour deficiency, which
## affects roughly 8% of men and so matters with real lab participants.
##
## Width reads BASE stress and therefore never changes at runtime: a road does
## not narrow because someone painted a lane on it. It is the road's permanent
## character. How stressful a road feels RIGHT NOW, after upgrades, is carried
## by the cars and the centre-line stress view, both of which read effective
## (post-beta) stress. Two cues, two meanings, mirroring the model's own split
## between an immutable base_stress and an upgradeable beta.
##
## ROAD_WIDTH is the FLOOR, not the average: arterials grow from it and no road
## is ever drawn narrower than it used to be. Narrowing is not an option: see
## the CAR_LANE_OFFSET note below, where the drivable band on a painted or
## protected road is already only 8px and cars need 6.5 of it. Anything under
## ~21px would push cars out onto the bike lane.
const ROAD_WIDTH         := 24.0
const STRESS_WIDTH_BONUS := 12.0
const EDGE_BORDER    := 1.5
## Margins ADDED to the road's own width, not absolute widths. These are drawn
## behind the road, so a fixed 32/36 would disappear underneath a wide arterial.
##
## ROUTE_MARGIN was 8, leaving four pixels of colour each side of the road,
## which is close to invisible once the map is scaled down to the laptops the
## game is run on. It went to 20 on 17 Aug to fix that, and back to 10 on
## 24 Aug (owner request) because 20 read as heavy: the band was competing with
## the road it sits under rather than marking it.
##
## Five pixels a side is thinner than the 17 Aug version but wider than the
## original, and the flow chevrons carry the rest. Motion survives shrinking in
## a way that a few pixels of colour does not, which is why they exist.
const ROUTE_MARGIN   := 10.0
const HOVER_MARGIN   := 12.0
## The route band gets a dark outline of its own. Without it the band relies on
## contrasting with whatever is behind the map, and the background art is not
## something this code controls.
## Kept in proportion to ROUTE_MARGIN: a 5px casing around a 5px band would be
## more outline than route.
const ROUTE_CASING   := 3.0

## Flow arrows: chevrons that drift along the route in the direction the rider
## travels. They do two jobs that the band alone cannot: they say which way the
## commute runs, and motion is the one channel that survives any amount of
## shrinking, so the route stays findable on a small screen.
const ARROW_SPACING  := 34.0
const ARROW_LENGTH   := 7.0
const ARROW_HALF_W   := 6.0
const ARROW_WIDTH    := 2.6
const ARROW_SPEED    := 26.0   # pixels per second along the road
## Riders sharing a link get their arrows side by side rather than overlapping,
## up to this many; beyond it the stripes on the band carry the information and
## more lanes of arrows would not fit inside the road.
const ARROW_MAX_LANES := 3
const CENTER_LINE_W  := 1.8
## Width of the centre line when it is carrying the NPC heatmap colour.
const CENTER_HEATMAP_W := 4.0
const CENTER_DASH_LEN := 11.0
const CENTER_DASH_GAP := 8.0
const BIKE_PAINT_W   := 4.0
const DIVIDER_W      := 1.5
const HIT_RADIUS     := 18.0
const NODE_RADIUS    := 6.5   # roads extend to this depth inside the node circle (28.0 radius, NodeMarker.RADII.NORMAL) so ends are hidden

const BARRIER_SPACE  := 10.0
const BARRIER_MARK   := 3.0
# Cars must stay within the plain road fill (the "black") on every upgrade
# level. On painted/protected roads the outer BIKE_PAINT_W strip on each
# side narrows that to ROAD_WIDTH/2 - BIKE_PAINT_W = 8.0, so
# CAR_LANE_OFFSET + CAR_WIDTH_HALF must stay comfortably under 8.0.
# CAR_LANE_OFFSET is scaled by the road's own width at draw time (see
# _car_lane_offset), so a wide arterial spreads its cars across the extra
# space instead of bunching them down the centre line. That scaling only ever
# increases the offset, since ROAD_WIDTH is the minimum width.
const CAR_LENGTH      := 10.0
const CAR_WIDTH_HALF  := 2.5
const CAR_LANE_OFFSET := 4.0
## Cars drift along their lane over time — cosmetic only (stress/routing
## still comes purely from the model), just enough motion that the street
## reads as alive rather than a static illustration. Speed scales with the
## road's effective stress (owner request, 4 Aug 2026: "high stress roads
## have faster cars"; widened: "increase the speed difference... by making
## the stressful cars drive even faster"; then tuned down: "slow the
## calmest by 3 and the fastest by 7" — measured against the network's
## actual endpoints, the calmest protected road at ~13.94px/s -> ~10.94,
## the fastest unimproved road at ~47.6px/s -> ~40.6). Solving for a new
## floor/scale that hits both those exact targets gives the values below —
## not independently chosen, derived from the two requested numbers.
const CAR_SPEED_MIN          := 5.71
const CAR_SPEED_STRESS_SCALE := 39.65


func setup(id: String, points: PackedVector2Array, upgrade_level: int = 0, stress: float = 0.5) -> void:
	link_id = id
	_stress_score = stress
	_road_width = ROAD_WIDTH + STRESS_WIDTH_BONUS * clampf(stress, 0.0, 1.0)
	_upgrade_level = upgrade_level
	set_points(points)


## Cars sit proportionally further out on a wider road, so an arterial's extra
## width reads as more room rather than a wider empty margin.
func _car_lane_offset() -> float:
	return CAR_LANE_OFFSET * (_road_width / ROAD_WIDTH)


func set_points(points: PackedVector2Array) -> void:
	_path_points = points
	_compute_draw_points()
	queue_redraw()


func _compute_draw_points() -> void:
	if _path_points.size() < 2:
		_draw_points = PackedVector2Array(_path_points)
		_total_length = 0.0
		return
	_draw_points = PackedVector2Array(_path_points)
	var dir_s := (_draw_points[1] - _draw_points[0]).normalized()
	_draw_points[0] = _draw_points[0] + dir_s * NODE_RADIUS
	var last := _draw_points.size() - 1
	var dir_e := (_draw_points[last] - _draw_points[last - 1]).normalized()
	_draw_points[last] = _draw_points[last] - dir_e * NODE_RADIUS
	_total_length = 0.0
	for i in range(_draw_points.size() - 1):
		_total_length += _draw_points[i].distance_to(_draw_points[i + 1])


func set_upgrade_level(level: int) -> void:
	_upgrade_level = level
	_pending_level = -1
	queue_redraw()


func set_pending_level(level: int) -> void:
	_pending_level = level
	queue_redraw()


## `forward` is true when the rider travels from this segment's first drawn point
## towards its last, which is the from_node to to_node order CityGrid built the
## points in. It only steers the flow arrows.
func set_on_route(on_route: bool, player_index: int = 0, forward: bool = true) -> void:
	if on_route:
		if not _route_players.has(player_index):
			_route_players.append(player_index)
		_route_forward[player_index] = forward
	else:
		_route_players.erase(player_index)
		_route_forward.erase(player_index)
	queue_redraw()


func clear_routes() -> void:
	_route_players.clear()
	_route_forward.clear()
	queue_redraw()


## intensity: 0.0 (least-used street this round) to 1.0 (most-used) — CityGrid
## already normalizes by the busiest link before calling this.
func set_heatmap(intensity: float) -> void:
	_heatmap_intensity = clampf(intensity, 0.0, 1.0)
	queue_redraw()


func clear_heatmap() -> void:
	_heatmap_intensity = -1.0
	queue_redraw()


func set_stress_view(on: bool) -> void:
	if _stress_view == on:
		return
	_stress_view = on
	queue_redraw()


## Green (least-used) → yellow → red (most-used), constant saturation/value
## so the gradient reads clearly at every step rather than washing out.
##
## Fully opaque and at full value, unlike the translucent band this replaced:
## it now paints a thin centre line over dark asphalt rather than a wide wash
## behind the road, and at that size any transparency muddies the hue.
func _heatmap_color(intensity: float) -> Color:
	var hue: float = lerpf(0.33, 0.0, intensity)
	return Color.from_hsv(hue, 0.85, 1.0, 1.0)



func _ready() -> void:
	for child in get_children():
		if child is Line2D:
			child.visible = false


## Advances the cosmetic traffic/route-pulse animation. Purely visual —
## nothing here feeds back into stress, impedance, or routing.
func _process(delta: float) -> void:
	_anim_t += delta
	if _num_cars() > 0 or not _route_players.is_empty():
		queue_redraw()


## Hides or shows this segment's route band and its flow arrows. Display only:
## nothing about the route, the model or the logs changes.
func set_routes_hidden(hidden: bool) -> void:
	if _routes_hidden == hidden:
		return
	_routes_hidden = hidden
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var was := _is_hovered
		_is_hovered = _is_mouse_near()
		if was != _is_hovered:
			# On the entering edge only. Roads are Node2D rather than Control,
			# so they sit outside the button wiring in Audio.gd and say so
			# themselves. Audio applies its own cooldown, which matters here:
			# dragging across the map crosses several roads in a few frames.
			if _is_hovered:
				Audio.play_hover()
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _is_mouse_near():
			# Clicking a road opens the upgrade popup, so this is an ordinary
			# click. The upgrade sound belongs to the buttons inside that popup.
			Audio.play_click()
			clicked.emit(link_id)
			get_viewport().set_input_as_handled()


# =======================================================================
#  DRAWING — layered from back to front
# =======================================================================

func _draw() -> void:
	if _draw_points.size() < 2:
		return

	_draw_shadow()

	if _is_hovered:
		_draw_thick_line(Palette.HOVER_GLOW, _road_width + HOVER_MARGIN)

	# Route highlight breathes gently (± a couple px) instead of sitting
	# perfectly static, so an active route reads as "selected" at a glance.
	# In heatmap mode the usage colour is carried by the centre line instead of
	# a wide band behind the road, so nothing is drawn out here and the player
	# route highlight stays hidden, keeping the two views distinct.
	var pulse: float = sin(_anim_t * 2.0) * 2.0
	var show_route: bool = not _routes_hidden 			and _heatmap_intensity < 0.0 and not _route_players.is_empty()
	if show_route:
		# Dark casing first, so the band separates from the background rather
		# than relying on whatever art happens to be underneath it.
		_draw_thick_line(Palette.ROAD_EDGE,
				_road_width + ROUTE_MARGIN + ROUTE_CASING + pulse)
		if _route_players.size() == 1:
			_draw_thick_line(route_color(_route_players[0]),
					_road_width + ROUTE_MARGIN + pulse)
		else:
			_draw_striped_route()

	# No Bike Lane roads have no curb — a plain, informal street; upgraded
	# (painted/protected) roads get a defined edge to read as "built".
	if _display_level() > 0:
		_draw_thick_line(Palette.ROAD_EDGE, _road_width + EDGE_BORDER * 2.0)
	_draw_thick_line(Palette.ROAD_FILL, _road_width)
	_draw_road_markings()
	_draw_cars()
	# Arrows go on last, over the road surface and over the cars: they are the
	# thing a participant is meant to find first.
	if show_route:
		_draw_flow_arrows()


## The level to visually render as — the pending upgrade if one is staged
## and higher than the current level, otherwise the current level.
func _display_level() -> int:
	return _pending_level if _pending_level > _upgrade_level else _upgrade_level


func _draw_thick_line(color: Color, width: float) -> void:
	draw_polyline(_draw_points, color, width, true)


## Soft offset shadow under the whole road, drawn first (furthest back) so
## the road reads as slightly raised off the background.
func _draw_shadow() -> void:
	var shifted := PackedVector2Array()
	for p in _draw_points:
		shifted.append(p + ROAD_SHADOW_OFFSET)
	draw_polyline(shifted, Palette.ROAD_SHADOW, _road_width + 3.0, true)


## Chevrons drifting along the route. Riders sharing a link are given their own
## lane across the road's width so two commutes read as two streams rather than
## one flickering line.
func _draw_flow_arrows() -> void:
	var lanes: int = mini(_route_players.size(), ARROW_MAX_LANES)
	# Lanes have to stay inside the plain road fill. On painted and protected
	# roads the outer BIKE_PAINT_W strip on each side is lane paint, so the
	# usable band is narrower than the road.
	var usable: float = _road_width - BIKE_PAINT_W * 2.0
	var lane_gap: float = 0.0 if lanes < 2 else minf(usable / float(lanes), 9.0)
	for i in range(lanes):
		var player_index: int = _route_players[i]
		var offset: float = (float(i) - (lanes - 1) * 0.5) * lane_gap
		_draw_arrow_lane(player_index, offset)


func _draw_arrow_lane(player_index: int, lateral: float) -> void:
	var forward: bool = _route_forward.get(player_index, true)
	var color: Color = route_arrow_color(player_index)
	# Phase runs the same way the rider does, so the arrows travel with them.
	var phase: float = fposmod(_anim_t * ARROW_SPEED, ARROW_SPACING)
	if not forward:
		phase = ARROW_SPACING - phase
	var travelled: float = 0.0
	for i in range(_draw_points.size() - 1):
		var a: Vector2 = _draw_points[i]
		var b: Vector2 = _draw_points[i + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len < 0.001:
			continue
		var dir: Vector2 = (b - a) / seg_len
		var normal := Vector2(-dir.y, dir.x)
		var point: Vector2 = dir if forward else -dir
		# First arrow position at or after the start of this segment.
		var first: float = ceilf((travelled - phase) / ARROW_SPACING) * ARROW_SPACING + phase
		var d: float = first - travelled
		while d < seg_len:
			# Skipped near the ends so arrows do not run under the node circles.
			if travelled + d > NODE_RADIUS and travelled + d < _total_length - NODE_RADIUS:
				var tip: Vector2 = a + dir * d + normal * lateral
				var back: Vector2 = tip - point * ARROW_LENGTH
				draw_line(back + normal * ARROW_HALF_W, tip, color, ARROW_WIDTH, true)
				draw_line(back - normal * ARROW_HALF_W, tip, color, ARROW_WIDTH, true)
			d += ARROW_SPACING
		travelled += seg_len


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
			var col: Color = route_color(pi)
			var end_pos := minf(pos + stripe_len, length)
			var p1 := a + dir * pos
			var p2 := a + dir * end_pos
			draw_line(p1, p2, col, _road_width + ROUTE_MARGIN, true)
			pos = end_pos
			ci += 1




# --- Upgrade visuals (painted lanes / protected barriers) ---

func _draw_road_markings() -> void:
	var display_level := _display_level()
	var alpha_mult := 1.0
	if _pending_level > _upgrade_level:
		alpha_mult = 0.5
	elif _pending_level == 0 and _upgrade_level > 0:
		alpha_mult = 0.25

	_draw_dashed_center_line()

	if display_level == 0:
		# No Bike Lane: a single clean street line, no lane dividers or
		# other clutter.
		pass
	elif display_level == 1:
		var pc := Color(Palette.BIKE_PAINT, alpha_mult)
		var po := _road_width / 2.0 - BIKE_PAINT_W / 2.0
		_draw_offset_line(po, pc, BIKE_PAINT_W)
		_draw_offset_line(-po, pc, BIKE_PAINT_W)
	else:
		# Protected: grey strips same width as painted, white divider just inside
		var po := _road_width / 2.0 - BIKE_PAINT_W / 2.0
		var ac := Color(Palette.PROTECTED_ASPHALT, alpha_mult)
		_draw_offset_line(po, ac, BIKE_PAINT_W)
		_draw_offset_line(-po, ac, BIKE_PAINT_W)
		var dc := Color(Palette.WHITE_MARKING, alpha_mult)
		var div_off := _road_width / 2.0 - BIKE_PAINT_W - DIVIDER_W / 2.0
		_draw_offset_line(div_off, dc, DIVIDER_W)
		_draw_offset_line(-div_off, dc, DIVIDER_W)


## Static dashed centre line (small dash + gap) instead of a solid ruled
## line — reads more like an actual street marking than a wiring-diagram
## line. Not animated: a scrolling dash was tried and turned out distracting
## rather than lively, so the dash positions are fixed per-road.
func _draw_dashed_center_line() -> void:
	# Heatmap mode repaints this same line with the link's usage colour, drawn
	# solid and a little thicker. A 1.8px dash carries too little pixel area to
	# read a green-to-red gradient off, so the dash pattern is dropped here
	# rather than tinted.
	# Stress view reads effective stress live rather than a stored intensity, so
	# an upgrade recolours the line on the same redraw that redraws the lanes.
	# Absolute 0-1, NOT normalised against the network's current worst road the
	# way the usage heatmap is: a city where every street had been calmed should
	# read as green everywhere, not re-stretch its own scale back to red.
	if _stress_view:
		_draw_thick_line(_heatmap_color(clampf(_effective_stress(), 0.0, 1.0)), CENTER_HEATMAP_W)
		return

	if _heatmap_intensity >= 0.0:
		_draw_thick_line(_heatmap_color(_heatmap_intensity), CENTER_HEATMAP_W)
		return

	for i in range(_draw_points.size() - 1):
		var a := _draw_points[i]
		var b := _draw_points[i + 1]
		var dir := (b - a).normalized()
		var length := a.distance_to(b)
		var pos := 0.0
		while pos < length:
			var seg_end := minf(pos + CENTER_DASH_LEN, length)
			draw_line(a + dir * pos, a + dir * seg_end, Palette.YELLOW_CENTER, CENTER_LINE_W, true)
			pos += CENTER_DASH_LEN + CENTER_DASH_GAP


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


# --- Stress cars (count + speed both reflect effective road stress, both
#     decrease when upgraded) ---

## Raw stress reduced by however much this road's current infrastructure
## relieves it — a cheap per-level estimate (not the real personality-
## dependent beta_protected from CityNetwork.gd, which needs a rider alpha
## this purely-visual layer doesn't have and shouldn't need). Shared by both
## car count and car speed so the two cues move together as a road is
## upgraded, instead of drifting independently.
func _effective_stress() -> float:
	var beta_est: float = [1.0, 0.65, 0.3][clampi(_upgrade_level, 0, 2)]
	return _stress_score * beta_est

## Cars per 100px of road, before the effective-stress multiplier. Car count
## used to be a flat function of stress alone (stress * beta * 6), so a
## short and a long road at the same stress showed the SAME number of cars
## — packed much tighter on the short one, reading as "way busier" even
## though the underlying stress was identical (owner report, 4 Aug 2026).
## Fixed by scaling with the road's actual on-screen length instead, so cars
## reflect a consistent per-100px DENSITY: num_cars = density * length/100.
## Lowered from 2.5 to 1.5 (owner, 4 Aug 2026 — "reduce the amount of cars
## overall... with so many cars the screen looks too cluttery") — a flat
## 40% cut applied after the length fix above, so the relative pattern
## (short roads still show fewer cars than long ones at the same stress)
## is unchanged, just the whole network reads less busy.
const CARS_PER_100PX := 1.5

func _num_cars() -> int:
	var density: float = _effective_stress() * CARS_PER_100PX
	# Every road gets at least one car — zero cars reads as "broken/empty
	# map" rather than "calm street." Count above that floor still scales
	# with stress and length, so upgrading a road (or a road simply being
	# short) visibly thins its traffic.
	return maxi(1, int(round(density * _total_length / 100.0)))


func _car_speed() -> float:
	return CAR_SPEED_MIN + _effective_stress() * CAR_SPEED_STRESS_SCALE


func _draw_cars() -> void:
	var num_cars := _num_cars()
	if num_cars == 0:
		return
	var speed := _car_speed()
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
			var base_pos := spacing * (j + 1)
			# Alternate cars slightly left/right of center, one per direction of
			# travel — and each lane drifts along its own direction over time,
			# looping back to the start. Cosmetic only; never read by routing.
			var lane_off := _car_lane_offset()
			var side: float = lane_off if j % 2 == 0 else -lane_off
			var travel_dir: float = 1.0 if j % 2 == 0 else -1.0
			var pos: float = fposmod(base_pos + _anim_t * speed * travel_dir, length)
			var car_angle: float = angle if travel_dir > 0.0 else angle + PI
			var center := a + dir * pos + perp * side
			_draw_car(center, car_angle, i + j)


func _draw_car(center: Vector2, angle: float, color_index: int = 0) -> void:
	var half_l := CAR_LENGTH / 2.0
	var hw := CAR_WIDTH_HALF
	draw_circle(center + Vector2(0.6, 1.0), hw * 1.3, Palette.CAR_SHADOW)
	var body_color: Color = Palette.CAR_COLORS[color_index % Palette.CAR_COLORS.size()]
	# Chamfered corners give a car-like silhouette instead of a plain rectangle.
	var cl := half_l * 0.55
	var cw := hw * 0.65
	var body_corners := PackedVector2Array([
		center + Vector2(-half_l, -cw).rotated(angle),
		center + Vector2(-cl, -hw).rotated(angle),
		center + Vector2(cl, -hw).rotated(angle),
		center + Vector2(half_l, -cw).rotated(angle),
		center + Vector2(half_l, cw).rotated(angle),
		center + Vector2(cl, hw).rotated(angle),
		center + Vector2(-cl, hw).rotated(angle),
		center + Vector2(-half_l, cw).rotated(angle),
	])
	draw_colored_polygon(body_corners, body_color)
	# Windshield, biased toward the front so travel direction reads at a glance
	var ws_off := half_l * 0.35
	var ws_hw := hw * 0.55
	var ws_corners := PackedVector2Array([
		center + Vector2(ws_off - 2.0, -ws_hw).rotated(angle),
		center + Vector2(ws_off + 2.0, -ws_hw).rotated(angle),
		center + Vector2(ws_off + 2.0, ws_hw).rotated(angle),
		center + Vector2(ws_off - 2.0, ws_hw).rotated(angle),
	])
	draw_colored_polygon(ws_corners, Palette.CAR_WINDOW)


# --- Hit detection ---

## A wide arterial is drawn past the fixed HIT_RADIUS, so its visual edge
## would not be clickable. Track the drawn width, never shrinking below the
## original radius on a narrow road.
func _hit_radius() -> float:
	return maxf(HIT_RADIUS, _road_width / 2.0)


func _is_mouse_near() -> bool:
	if _path_points.size() < 2:
		return false
	var local_mouse := to_local(get_global_mouse_position())
	for i: int in range(_path_points.size() - 1):
		if _dist_to_segment(local_mouse, _path_points[i], _path_points[i + 1]) < _hit_radius():
			return true
	return false


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.dot(ab)
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
