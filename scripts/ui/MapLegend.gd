class_name MapLegend
extends Control
## MapLegend.gd
## The key to the map, behind a rail toggle and rebuilt each time it opens.
##
## Every colour here comes from Palette, and specifically from the same
## constants the map itself draws with, so a legend entry cannot end up
## describing a colour the roads stopped using. The legend previously kept its
## own copies and they had already drifted apart by a little.

const SWATCH_W := 60.0
const SWATCH_H := 14.0
const ROW_H    := SWATCH_H + 10.0
## The lane strip's height in a swatch, derived from the map rather than chosen.
## A swatch is SWATCH_H tall where the road is LinkSegment.ROAD_WIDTH, so the
## strip has to be scaled by that ratio to sit at the same proportion of the
## road's width. This was a hardcoded 2.5 with a comment claiming it was the
## same width as the map's painted strip; the map's is 4.0, so the comment was
## the only thing making the drift look deliberate.
const LANE_STRIP_H := LinkSegment.BIKE_PAINT_W / LinkSegment.ROAD_WIDTH * SWATCH_H
## Marker rows get their own height, because the icons grew and the swatches did
## not. One shared row height would have padded every road swatch to suit the
## icons and pushed the bottom of the legend out of the sidebar.
const ICON_ROW_H := 40.0
const LABEL_X  := SWATCH_W + 8.0
## Raised from 11 on 24 Aug 2026. The legend is read by participants across a
## table, on a laptop or a tablet, and 11px was set when it lived in a fixed
## sidebar that could not afford anything larger. The panel measures its own
## text now (see _content_width), so this can be changed on its own.
const FS       := 15

## Every label in one place, because two things need them: _draw() writes them
## and _content_width() measures them. A legend narrower than its own text is
## the failure mode, and it would only appear after a reword.
const L_NO_LANE       := "No Bike Lane"
const L_PAINTED       := "Painted lane"
const L_PROTECTED     := "Protected track"
## "stressful to cycle", not "more stress". Playtesters read road stress as
## traffic congestion, which is exactly what it is not: the cars are decoration
## and never touch routing (guardrail 8). Every stress label now says whose
## stress it means.
const L_QUIET         := "Quiet street (calm to cycle)"
const L_BUSY          := "Busy road (stressful to cycle)"
const L_TRAFFIC       := "Traffic (more cars = more stress)"
const L_STRESS_RAMP   := "Cycling stress, calm to stressful"
const L_STRESS_NOTE   := "shown by Cycling stress / City routes"
const L_YOUR_ROUTE    := "Your route"
const L_PLAYER_ROUTE  := "Player %d route"
const L_HOME          := "Home"
const L_WORK          := "Work destination"
const L_HOME_MULTI    := "Home (one per player)"
const L_WORK_MULTI    := "Work destination (one per player)"
const L_NEIGHBOURHOOD := "Neighbourhood"
const L_WORKPLACE     := "Workplace"

## Legend marker icons match the actual in-game ones (NodeMarker.gd) instead
## of separate hand-drawn glyphs, so this stays accurate as those icons
## change. Workplaces show the generic building — the real map varies that
## icon per cluster (school, cafe, ...; see CityNetwork.WORK_NODE_ICONS).
const ICON_TINT_SHADER   := preload("res://assets/shaders/icon_tint.gdshader")
const ICON_HOME          := preload("res://assets/images/home.svg")
const ICON_BRIEFCASE     := preload("res://assets/images/briefcase.svg")
const ICON_NEIGHBOURHOOD := preload("res://assets/images/threepeoplehome.svg")
const ICON_WORK_DEFAULT  := preload("res://assets/images/workbuildings.svg")
## Bigger, in step with the map's icons, but not the full 40px those use: the
## legend lives in a fixed-width sidebar with a fixed height to spend, and four
## marker rows at 40px each pushed the last of them off the bottom.
const ICON_PX: float = 32.0
## In a group session the home row carries one icon per seat, side by side in the
## same 60px column rather than one row per seat, so the legend does not grow a
## pair of rows every time a player is added.
const ICON_PX_MULTI: float = 20.0

var _home_icons: Array[Sprite2D] = []
var _work_icons: Array[Sprite2D] = []
## Set while _total_height() walks the layout. Every drawing helper checks it
## and returns without painting, which is what lets the measure pass run outside
## NOTIFICATION_DRAW, where any draw_* call would error.
var _measure_only: bool = false

var _neighbourhood_icon: Sprite2D
var _workplace_icon: Sprite2D


func _ready() -> void:
	_neighbourhood_icon = _sized(_make_icon(ICON_NEIGHBOURHOOD, Palette.NPC_HOME), ICON_PX)
	_workplace_icon     = _sized(_make_icon(ICON_WORK_DEFAULT, Palette.NPC_WORK), ICON_PX)
	_rebuild_player_icons()

	_refresh_size()
	GameManager.round_started.connect(func(_r, _b): refresh())


func _make_icon(tex: Texture2D, tint: Color) -> Sprite2D:
	var icon := Sprite2D.new()
	icon.texture = tex
	icon.centered = true
	var mat := ShaderMaterial.new()
	mat.shader = ICON_TINT_SHADER
	mat.set_shader_parameter("tint_color", tint)
	icon.material = mat
	add_child(icon)
	return icon


func _sized(icon: Sprite2D, px: float) -> Sprite2D:
	icon.scale = Vector2.ONE * (px / maxf(icon.texture.get_width(), 1.0))
	return icon


func _num_players() -> int:
	return GameManager.human_players.size() if GameManager.game_running else 1


## One home and one work icon per seat, each in that seat's own colour.
##
## They used to be a single pair tinted PLAYER_COLORS[0] unconditionally, so in a
## group session the legend stated that home and work were blue while two of the
## three players' markers on the map were not. A legend describing a colour
## nobody has is worse than one describing nothing.
func _rebuild_player_icons() -> void:
	for icon in _home_icons:
		icon.queue_free()
	for icon in _work_icons:
		icon.queue_free()
	_home_icons.clear()
	_work_icons.clear()
	var n := _num_players()
	var px: float = ICON_PX if n <= 1 else ICON_PX_MULTI
	for i in range(n):
		var col: Color = Palette.seat_color(i)
		_home_icons.append(_sized(_make_icon(ICON_HOME, col), px))
		_work_icons.append(_sized(_make_icon(ICON_BRIEFCASE, col), px))


## Re-measure and repaint. Called when the resident markers are toggled, which
## changes the legend's height as well as its contents, so a plain queue_redraw()
## would leave a gap where the removed rows used to be. Also on round start,
## which is the first moment the player count is known.
func refresh() -> void:
	_rebuild_player_icons()
	_refresh_size()
	queue_redraw()


func _refresh_size() -> void:
	custom_minimum_size = Vector2(_content_width(ThemeDB.fallback_font), _total_height())


## Width of the widest row, measured with the font actually used to draw it.
##
## The popover used to be a fixed 230px, which fitted the labels at 11px with
## nothing to spare. Measuring means the font size is a single number to change
## rather than a number plus a guess at how wide it makes the panel.
func _content_width(font: Font) -> float:
	var n := _num_players()
	var labels := PackedStringArray([L_NO_LANE, L_PAINTED, L_PROTECTED, L_QUIET,
			L_BUSY, L_TRAFFIC, L_STRESS_RAMP, L_STRESS_NOTE, L_NEIGHBOURHOOD,
			L_WORKPLACE])
	labels.append(L_HOME if n <= 1 else L_HOME_MULTI)
	labels.append(L_WORK if n <= 1 else L_WORK_MULTI)
	if not CityGrid.hide_player_routes:
		if n == 1:
			labels.append(L_YOUR_ROUTE)
		else:
			for i in range(n):
				labels.append(L_PLAYER_ROUTE % (i + 1))
	var widest := 0.0
	for text: String in labels:
		widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x)
	return LABEL_X + widest


## The legend's height, measured by running the SAME layout that draws it.
##
## This used to be a hand-written copy of every `y +=` in _draw(), in the same
## order, kept in step by nothing at all: the popover clipped its own last row
## whenever the two drifted, and the only thing linking them was a column of
## trailing comments. Now there is one layout and two modes.
func _total_height() -> float:
	_measure_only = true
	var h := _layout(ThemeDB.fallback_font)
	_measure_only = false
	return h


func _draw() -> void:
	_layout(ThemeDB.fallback_font)


## Walks the legend top to bottom and returns the height it consumed. Every
## drawing helper below returns early while _measure_only is set, so this same
## walk can be run outside NOTIFICATION_DRAW to measure without painting.
func _layout(font: Font) -> float:
	var y := 0.0
	var n    := _num_players()

	# ── Header ──────────────────────────────────────────────────────────────
	if not _measure_only:
		draw_string(font, Vector2(0, y + FS + 1), "LEGEND",
				HORIZONTAL_ALIGNMENT_LEFT, -1, FS + 1, Palette.TEXT_HEADING)
	y += FS + 8
	_sep(y); y += 8

	# ── Road types ──────────────────────────────────────────────────────────
	_road_swatch(0, y)
	_label(L_NO_LANE, y, font); y += ROW_H

	_road_swatch(1, y)
	_label(L_PAINTED, y, font); y += ROW_H

	_road_swatch(2, y)
	_label(L_PROTECTED, y, font); y += ROW_H + 4
	_sep(y); y += 8

	# ── Stress ──────────────────────────────────────────────────────────────
	# Road width is the always-on stress cue (LinkSegment.ROAD_WIDTH), so it is
	# listed first and given both ends of its range; the cars below are the
	# secondary cue that also responds to upgrades.
	_width_swatch(0.22, y)
	_label(L_QUIET, y, font); y += ROW_H

	_width_swatch(0.82, y)
	_label(L_BUSY, y, font); y += ROW_H

	_car_swatch(y)
	_label(L_TRAFFIC, y, font); y += ROW_H + 4

	# The green-to-red centre line. It had no entry at all, in either of the two
	# views that paint it, which left the map's loudest colour unexplained.
	_stress_ramp_swatch(y)
	_label(L_STRESS_RAMP, y, font); y += ROW_H
	if not _measure_only:
		draw_string(font, Vector2(LABEL_X, y + FS * 0.4), L_STRESS_NOTE,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FS - 2, Palette.TEXT_MUTED)
	y += FS + 6
	_sep(y); y += 8

	# ── Routes ──────────────────────────────────────────────────────────────
	# Shown with one player too, where it used to be skipped. The whole point of
	# the widened band and the flow arrows is that a participant can find their
	# own commute at a glance, and the legend is where they are told that the
	# coloured road with arrows on it is theirs.
	# Dropped when the route toggle is off, for the same reason the resident
	# rows are: the legend never explains something that is not on the map.
	if not CityGrid.hide_player_routes:
		for i in range(n):
			_route_swatch(i, y)
			_label(L_YOUR_ROUTE if n == 1 else L_PLAYER_ROUTE % (i + 1), y, font)
			y += ROW_H - 4
		y += 8
		_sep(y); y += 8

	# ── Markers ─────────────────────────────────────────────────────────────
	_place_icon_row(_home_icons, y)
	_label(L_HOME if n <= 1 else L_HOME_MULTI, y, font); y += ICON_ROW_H

	_place_icon_row(_work_icons, y)
	_label(L_WORK if n <= 1 else L_WORK_MULTI, y, font); y += ICON_ROW_H

	# Dropped along with the markers themselves, so the legend never explains a
	# symbol that is not on the map.
	#
	# The icons are persistent Sprite2D children, not something _draw() paints,
	# so skipping the _place_icon() calls alone would only remove the TEXT and
	# leave the two glyphs sitting wherever they were last positioned. They have
	# to be hidden explicitly.
	var show_residents := not CityGrid.hide_resident_visuals
	if not _measure_only:
		_neighbourhood_icon.visible = show_residents
		_workplace_icon.visible = show_residents
	if show_residents:
		_place_icon(_neighbourhood_icon, y)
		_label(L_NEIGHBOURHOOD, y, font); y += ICON_ROW_H

		_place_icon(_workplace_icon, y)
		_label(L_WORKPLACE, y, font)
		# Advances y even though nothing is drawn after it: the return value is
		# the panel's height, so the last row has to be counted like every
		# other. Leaving it out clipped the bottom row by ICON_ROW_H.
		y += ICON_ROW_H
	return y


# ── Drawing helpers ──────────────────────────────────────────────────────────

## Baseline placed so the text centres on the swatch beside it whatever FS is.
## It used to be y + FS + 1, which happened to centre at 11px and drifts down as
## the font grows.
func _label(text: String, y: float, font: Font) -> void:
	if _measure_only:
		return
	draw_string(font, Vector2(LABEL_X, y + SWATCH_H * 0.5 + FS * 0.36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Palette.TEXT_PRIMARY)


## Spans the panel rather than a fixed 156px, which was shorter than the labels
## it was meant to divide once they grew.
func _sep(y: float) -> void:
	if _measure_only:
		return
	draw_line(Vector2(0, y), Vector2(size.x, y), Palette.TEXT_MUTED, 1)


## What the three UPGRADE LEVELS look like. Deliberately carries no centre line:
## the line means "arterial" on the map now rather than merely "road", and
## putting one on all three of these rows would say that every upgraded street
## is a main road.
func _road_swatch(level: int, y: float) -> void:
	if _measure_only:
		return
	var w  := SWATCH_W
	var h  := SWATCH_H

	draw_rect(Rect2(0, y, w, h), Palette.ROAD_FILL)
	# Only upgraded roads get a curb, matching LinkSegment._draw(): a No Bike
	# Lane road is deliberately drawn without one, and outlining all three here
	# said the opposite.
	if level > 0:
		draw_rect(Rect2(0, y, w, h), Palette.ROAD_EDGE, false, 1.0)

	var strip := LANE_STRIP_H
	match level:
		1:
			# Green painted strips on the outer edges, as on the map.
			draw_rect(Rect2(0, y,             w, strip), Palette.BIKE_PAINT)
			draw_rect(Rect2(0, y + h - strip, w, strip), Palette.BIKE_PAINT)
		2:
			# Grey strips in the same place, white divider just inside them.
			draw_rect(Rect2(0, y,             w, strip), Palette.PROTECTED_ASPHALT)
			draw_rect(Rect2(0, y + h - strip, w, strip), Palette.PROTECTED_ASPHALT)
			draw_line(Vector2(0, y + strip),     Vector2(w, y + strip),
					Palette.WHITE_MARKING, LinkSegment.DIVIDER_W)
			draw_line(Vector2(0, y + h - strip), Vector2(w, y + h - strip),
					Palette.WHITE_MARKING, LinkSegment.DIVIDER_W)
		_:
			pass  # No Bike Lane: plain road, no lane dividers (matches LinkSegment.gd)


## Same road drawn at the width a given base stress would give it on the map,
## so the legend's two rows bracket the real on-screen range rather than being
## an arbitrary thick/thin pair. Scaled to the legend's own swatch height.
##
## The two stress values are the network's ACTUAL clusters (backstreets ~0.22,
## arterials ~0.82) rather than 0.15 and 0.90, so these rows show the difference
## a participant can really see rather than a wider one they cannot.
func _width_swatch(stress: float, y: float) -> void:
	if _measure_only:
		return
	var full := LinkSegment.ROAD_WIDTH + LinkSegment.STRESS_WIDTH_BONUS
	var frac: float = (LinkSegment.ROAD_WIDTH + LinkSegment.STRESS_WIDTH_BONUS * stress) / full
	var h := SWATCH_H * frac
	var top := y + (SWATCH_H - h) * 0.5
	draw_rect(Rect2(0, top, SWATCH_W, h), Palette.ROAD_FILL)
	draw_rect(Rect2(0, top, SWATCH_W, h), Palette.ROAD_EDGE, false, 1.0)
	# Dashed, and only above the same threshold the map uses, so this row carries
	# both halves of the cue: an arterial is wide AND lined, a backstreet is
	# narrow and bare. It used to draw a solid line on both, which described
	# neither.
	if stress >= LinkSegment.CENTER_LINE_MIN_STRESS:
		_dashed_center(top + h * 0.5)


## The map's centre line is dashed (LinkSegment.CENTER_DASH_LEN / _GAP) and this
## drew it solid, which playtesters spotted directly. Scaled to the legend's
## shorter swatch so the pattern still reads as a dash rather than one long mark.
func _dashed_center(cy: float) -> void:
	var scale_f: float = 0.55
	var period: float = (LinkSegment.CENTER_DASH_LEN + LinkSegment.CENTER_DASH_GAP) * scale_f
	var on: float = LinkSegment.CENTER_DASH_LEN * scale_f
	var pos := 0.0
	while pos < SWATCH_W:
		var seg_end: float = minf(pos + on, SWATCH_W)
		draw_line(Vector2(pos, cy), Vector2(seg_end, cy),
				Palette.YELLOW_CENTER, LinkSegment.CENTER_LINE_W, true)
		pos += period


## The green-to-red ramp the stress view and the city-routes heatmap paint down
## the centre of a road. Sampled from LinkSegment's own colour function so the
## key cannot drift from the thing it describes.
func _stress_ramp_swatch(y: float) -> void:
	if _measure_only:
		return
	var cy: float = y + SWATCH_H * 0.5
	var steps := 24
	draw_rect(Rect2(0, y + 1.0, SWATCH_W, SWATCH_H - 2.0), Palette.ROAD_FILL)
	for i in range(steps):
		var t: float = float(i) / float(steps - 1)
		var x0: float = SWATCH_W * float(i) / float(steps)
		var x1: float = SWATCH_W * float(i + 1) / float(steps)
		draw_line(Vector2(x0, cy), Vector2(x1, cy),
				LinkSegment.stress_ramp_color(t), LinkSegment.CENTER_HEATMAP_W)


## Casing, band and a chevron, in the same order and proportions the map draws
## them, so the legend keeps describing what is actually on screen.
func _route_swatch(player_index: int, y: float) -> void:
	if _measure_only:
		return
	var mid: float = y + SWATCH_H * 0.5
	var col: Color = Palette.seat_color(player_index)
	draw_line(Vector2(0, mid), Vector2(SWATCH_W, mid), Palette.ROAD_EDGE, SWATCH_H)
	draw_line(Vector2(0, mid), Vector2(SWATCH_W, mid), col, SWATCH_H - 4.0)
	draw_line(Vector2(0, mid), Vector2(SWATCH_W, mid), Palette.ROAD_FILL, SWATCH_H - 9.0)
	var arrow: Color = LinkSegment.route_arrow_color(player_index)
	var tip := Vector2(SWATCH_W * 0.62, mid)
	draw_line(tip - Vector2(5, 3.5), tip, arrow, 2.0, true)
	draw_line(tip - Vector2(5, -3.5), tip, arrow, 2.0, true)


func _car_swatch(y: float) -> void:
	if _measure_only:
		return
	_road_swatch(0, y)
	var h := SWATCH_H
	var car_x: Array[float] = [8.0, 28.0, 48.0]
	var car_side: Array[int] = [1, -1, 1]
	for i in range(car_x.size()):
		var cx: float = car_x[i]
		var cy: float = y + h * 0.5 + car_side[i] * h * 0.20
		draw_rect(Rect2(cx - 4, cy - 2, 8, 4), Palette.CAR_COLORS[0])
		draw_rect(Rect2(cx - 0.5, cy - 1.5, 2.5, 3), Color(Palette.CAR_WINDOW, 0.85))


func _place_icon(icon: Sprite2D, y: float) -> void:
	if _measure_only:
		return
	icon.position = Vector2(SWATCH_W * 0.5, y + SWATCH_H * 0.5)
	icon.visible = true


## One seat's icon, or all of them side by side across the same column, so the
## legend does not grow two rows per additional player.
func _place_icon_row(icons: Array[Sprite2D], y: float) -> void:
	if _measure_only:
		return
	var count := icons.size()
	if count == 0:
		return
	if count == 1:
		_place_icon(icons[0], y)
		return
	for i in range(count):
		icons[i].position = Vector2(
				SWATCH_W * (float(i) + 0.5) / float(count), y + SWATCH_H * 0.5)
		icons[i].visible = true
