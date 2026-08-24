class_name MapLegend
extends Control

const SWATCH_W := 60.0
const SWATCH_H := 14.0
const ROW_H    := SWATCH_H + 10.0
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
const L_QUIET         := "Quiet street"
const L_BUSY          := "Busy road (more stress)"
const L_TRAFFIC       := "Traffic"
const L_YOUR_ROUTE    := "Your route"
const L_PLAYER_ROUTE  := "Player %d route"
const L_HOME          := "Home"
const L_WORK          := "Work destination"
const L_NEIGHBOURHOOD := "Neighbourhood"
const L_WORKPLACE     := "Workplace"

## Every colour here comes from Palette, and specifically from the same
## constants the map itself draws with, so a legend entry cannot end up
## describing a colour the roads stopped using. The legend previously kept its
## own copies and they had already drifted apart by a little.
##
## Simulated-resident swatches are the marker colour at reduced alpha, matching
## how faint those markers read against the map.
const NPC_SWATCH_ALPHA: float = 0.55

## Legend marker icons match the actual in-game ones (NodeMarker.gd) instead
## of separate hand-drawn glyphs, so this stays accurate as those icons
## change. Workplaces show the generic building — the real map varies that
## icon per cluster (school, café, ...; see CityNetwork.WORK_NODE_ICONS).
## All markers render at the same fixed size (see NodeMarker.ICON_PX).
const ICON_TINT_SHADER   := preload("res://assets/shaders/icon_tint.gdshader")
const ICON_HOME          := preload("res://assets/images/home.svg")
const ICON_BRIEFCASE     := preload("res://assets/images/briefcase.svg")
const ICON_NEIGHBOURHOOD := preload("res://assets/images/threepeoplehome.svg")
const ICON_WORK_DEFAULT  := preload("res://assets/images/workbuildings.svg")
## Bigger, in step with the map's icons, but not the full 40px those use: the
## legend lives in a fixed-width sidebar with a fixed height to spend, and four
## marker rows at 40px each pushed the last of them off the bottom.
const ICON_PX: float = 32.0

var _home_icon: Sprite2D
var _work_icon: Sprite2D
var _neighbourhood_icon: Sprite2D
var _workplace_icon: Sprite2D


func _ready() -> void:
	_home_icon          = _make_icon(ICON_HOME, Palette.PLAYER_COLORS[0])
	_work_icon          = _make_icon(ICON_BRIEFCASE, Palette.PLAYER_COLORS[0])
	_neighbourhood_icon = _make_icon(ICON_NEIGHBOURHOOD, Palette.NPC_HOME)
	_workplace_icon     = _make_icon(ICON_WORK_DEFAULT, Palette.NPC_WORK)

	_refresh_size()
	GameManager.round_started.connect(func(_r, _b): _refresh_size(); queue_redraw())


func _make_icon(tex: Texture2D, tint: Color) -> Sprite2D:
	var icon := Sprite2D.new()
	icon.texture = tex
	icon.centered = true
	icon.scale = Vector2.ONE * (ICON_PX / maxf(tex.get_width(), 1.0))
	var mat := ShaderMaterial.new()
	mat.shader = ICON_TINT_SHADER
	mat.set_shader_parameter("tint_color", tint)
	icon.material = mat
	add_child(icon)
	return icon


## Re-measure and repaint. Called when the resident markers are toggled, which
## changes the legend's height as well as its contents, so a plain queue_redraw()
## would leave a gap where the removed rows used to be.
func refresh() -> void:
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
	var labels := PackedStringArray([L_NO_LANE, L_PAINTED, L_PROTECTED, L_QUIET,
			L_BUSY, L_TRAFFIC, L_HOME, L_WORK, L_NEIGHBOURHOOD, L_WORKPLACE])
	if not CityGrid.hide_player_routes:
		var n := GameManager.human_players.size() if GameManager.game_running else 1
		if n == 1:
			labels.append(L_YOUR_ROUTE)
		else:
			for i in range(n):
				labels.append(L_PLAYER_ROUTE % (i + 1))
	var widest := 0.0
	for text: String in labels:
		widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x)
	return LABEL_X + widest


func _total_height() -> float:
	var n := GameManager.human_players.size() if GameManager.game_running else 1
	var h := float(FS + 8 + 8)   # header + sep
	h += ROW_H * 3 + 4           # 3 road types
	h += 8 + ROW_H * 2 + 4       # sep + road-width rows (quiet / busy)
	h += ROW_H + 4               # cars row
	h += 8                        # sep before markers
	if not CityGrid.hide_player_routes:
		h += (ROW_H - 4) * n + 16
	h += ICON_ROW_H * 2          # home + work
	if not CityGrid.hide_resident_visuals:
		h += ICON_ROW_H * 2      # neighbourhood + workplace
	return h


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var y    := 0.0

	# ── Header ──────────────────────────────────────────────────────────────
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
	_width_swatch(0.15, y)
	_label(L_QUIET, y, font); y += ROW_H

	_width_swatch(0.90, y)
	_label(L_BUSY, y, font); y += ROW_H

	_car_swatch(y)
	_label(L_TRAFFIC, y, font); y += ROW_H + 4
	_sep(y); y += 8

	# ── Routes ──────────────────────────────────────────────────────────────
	# Shown with one player too, where it used to be skipped. The whole point of
	# the widened band and the flow arrows is that a participant can find their
	# own commute at a glance, and the legend is where they are told that the
	# coloured road with arrows on it is theirs.
	# Dropped when the route toggle is off, for the same reason the resident
	# rows are: the legend never explains something that is not on the map.
	if not CityGrid.hide_player_routes:
		var num := GameManager.human_players.size() if GameManager.game_running else 1
		for i in range(num):
			_route_swatch(i, y)
			_label(L_YOUR_ROUTE if num == 1 else L_PLAYER_ROUTE % (i + 1), y, font)
			y += ROW_H - 4
		y += 8
		_sep(y); y += 8

	# ── Markers ─────────────────────────────────────────────────────────────
	_place_icon(_home_icon, y)
	_label(L_HOME, y, font); y += ICON_ROW_H

	_place_icon(_work_icon, y)
	_label(L_WORK, y, font); y += ICON_ROW_H

	# Dropped along with the markers themselves, so the legend never explains a
	# symbol that is not on the map.
	#
	# The icons are persistent Sprite2D children, not something _draw() paints,
	# so skipping the _place_icon() calls alone would only remove the TEXT and
	# leave the two glyphs sitting wherever they were last positioned. They have
	# to be hidden explicitly.
	var show_residents := not CityGrid.hide_resident_visuals
	_neighbourhood_icon.visible = show_residents
	_workplace_icon.visible = show_residents
	if show_residents:
		_place_icon(_neighbourhood_icon, y)
		_label(L_NEIGHBOURHOOD, y, font); y += ICON_ROW_H

		_place_icon(_workplace_icon, y)
		_label(L_WORKPLACE, y, font)


# ── Drawing helpers ──────────────────────────────────────────────────────────

## Baseline placed so the text centres on the swatch beside it whatever FS is.
## It used to be y + FS + 1, which happened to centre at 11px and drifts down as
## the font grows.
func _label(text: String, y: float, font: Font) -> void:
	draw_string(font, Vector2(LABEL_X, y + SWATCH_H * 0.5 + FS * 0.36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Palette.TEXT_PRIMARY)


## Spans the panel rather than a fixed 156px, which was shorter than the labels
## it was meant to divide once they grew.
func _sep(y: float) -> void:
	draw_line(Vector2(0, y), Vector2(size.x, y), Palette.TEXT_MUTED, 1)


func _road_swatch(level: int, y: float) -> void:
	var w  := SWATCH_W
	var h  := SWATCH_H
	var cy := y + h * 0.5

	draw_rect(Rect2(0, y, w, h), Palette.ROAD_FILL)
	draw_rect(Rect2(0, y, w, h), Palette.ROAD_EDGE, false, 1.0)

	match level:
		1:
			# Green painted strips on outer edges
			draw_rect(Rect2(0, y,           w, 2.5), Palette.BIKE_PAINT)
			draw_rect(Rect2(0, y + h - 2.5, w, 2.5), Palette.BIKE_PAINT)
		2:
			# Grey strips same width as painted (2.5px), white divider just inside
			draw_rect(Rect2(0, y,             w, 2.5), Palette.PROTECTED_ASPHALT)
			draw_rect(Rect2(0, y + h - 2.5,   w, 2.5), Palette.PROTECTED_ASPHALT)
			draw_line(Vector2(0, y + 2.5),     Vector2(w, y + 2.5),     Palette.WHITE_MARKING, 1.0)
			draw_line(Vector2(0, y + h - 2.5), Vector2(w, y + h - 2.5), Palette.WHITE_MARKING, 1.0)
		_:
			pass  # No Bike Lane: plain road, no lane dividers (matches LinkSegment.gd)

	# Yellow centre line (all levels)
	draw_line(Vector2(0, cy), Vector2(w, cy), Palette.YELLOW_CENTER, 1.5)


## Same road drawn at the width a given base stress would give it on the map,
## so the legend's two rows bracket the real on-screen range rather than being
## an arbitrary thick/thin pair. Scaled to the legend's own swatch height.
func _width_swatch(stress: float, y: float) -> void:
	var full := LinkSegment.ROAD_WIDTH + LinkSegment.STRESS_WIDTH_BONUS
	var frac: float = (LinkSegment.ROAD_WIDTH + LinkSegment.STRESS_WIDTH_BONUS * stress) / full
	var h := SWATCH_H * frac
	var top := y + (SWATCH_H - h) * 0.5
	draw_rect(Rect2(0, top, SWATCH_W, h), Palette.ROAD_FILL)
	draw_rect(Rect2(0, top, SWATCH_W, h), Palette.ROAD_EDGE, false, 1.0)
	draw_line(Vector2(0, top + h * 0.5), Vector2(SWATCH_W, top + h * 0.5), Palette.YELLOW_CENTER, 1.5)


## Casing, band and a chevron, in the same order and proportions the map draws
## them, so the legend keeps describing what is actually on screen.
func _route_swatch(player_index: int, y: float) -> void:
	var mid: float = y + SWATCH_H * 0.5
	var col: Color = Palette.PLAYER_COLORS[player_index % Palette.PLAYER_COLORS.size()]
	draw_line(Vector2(0, mid), Vector2(SWATCH_W, mid), Palette.ROAD_EDGE, SWATCH_H)
	draw_line(Vector2(0, mid), Vector2(SWATCH_W, mid), col, SWATCH_H - 4.0)
	draw_line(Vector2(0, mid), Vector2(SWATCH_W, mid), Palette.ROAD_FILL, SWATCH_H - 9.0)
	var arrow: Color = LinkSegment.route_arrow_color(player_index)
	var tip := Vector2(SWATCH_W * 0.62, mid)
	draw_line(tip - Vector2(5, 3.5), tip, arrow, 2.0, true)
	draw_line(tip - Vector2(5, -3.5), tip, arrow, 2.0, true)


func _car_swatch(y: float) -> void:
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
	icon.position = Vector2(SWATCH_W * 0.5, y + SWATCH_H * 0.5)
	icon.visible = true
