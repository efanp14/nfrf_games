class_name MapLegend
extends Control

const SWATCH_W := 60.0
const SWATCH_H := 14.0
const ROW_H    := SWATCH_H + 10.0
const LABEL_X  := SWATCH_W + 8.0
const FS       := 11

const ROAD_FILL         := Color("#494949")
const ROAD_EDGE         := Color("#1a1a1a")
const YELLOW_CENTER     := Color(0.85, 0.75, 0.20)
const WHITE_MARKING     := Color(0.95, 0.95, 0.90)
const BIKE_PAINT        := Color(0.22, 0.62, 0.28)
const PROTECTED_ASPHALT := Color("#9E948A")
const CAR_BODY          := Color(0.82, 0.35, 0.30)
const CAR_WINDOW        := Color(0.65, 0.82, 0.92, 0.85)
const TEXT_COL          := Color(0.28, 0.26, 0.24)
const HEAD_COL          := Color(0.50, 0.48, 0.45)
const SEP_COL           := Color(0.60, 0.58, 0.55, 0.35)
const PLAYER_COLORS     := [
	Color(0.42, 0.64, 0.84),
	Color(0.88, 0.47, 0.32),
	Color(0.35, 0.72, 0.40),
	Color(0.62, 0.42, 0.78),
	Color(0.85, 0.68, 0.25),
]


func _ready() -> void:
	_refresh_size()
	GameManager.round_started.connect(func(_r, _b): _refresh_size(); queue_redraw())


func _refresh_size() -> void:
	custom_minimum_size = Vector2(0, _total_height())


func _total_height() -> float:
	var n := GameManager.human_players.size() if GameManager.game_running else 1
	var h := float(FS + 8 + 8)   # header + sep
	h += ROW_H * 3 + 4           # 3 road types
	h += 8 + ROW_H + 4           # sep + cars row
	h += 8                        # sep before markers
	if n > 1:
		h += (ROW_H - 4) * n + 16
	h += ROW_H * 2               # home + work
	return h


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var y    := 0.0

	# ── Header ──────────────────────────────────────────────────────────────
	draw_string(font, Vector2(0, y + FS + 1), "LEGEND",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS + 1, HEAD_COL)
	y += FS + 8
	_sep(y); y += 8

	# ── Road types ──────────────────────────────────────────────────────────
	_road_swatch(0, y)
	_label("Unimproved road", y, font); y += ROW_H

	_road_swatch(1, y)
	_label("Painted lane", y, font); y += ROW_H

	_road_swatch(2, y)
	_label("Protected track", y, font); y += ROW_H + 4
	_sep(y); y += 8

	# ── Traffic / stress ────────────────────────────────────────────────────
	_car_swatch(y)
	_label("Traffic stress", y, font); y += ROW_H + 4
	_sep(y); y += 8

	# ── Player routes (multi-player only) ───────────────────────────────────
	var num := GameManager.human_players.size() if GameManager.game_running else 1
	if num > 1:
		for i in range(num):
			var col: Color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
			draw_rect(Rect2(0, y + 3, SWATCH_W, 8), Color(col, 0.50))
			_label("Player %d route" % (i + 1), y, font)
			y += ROW_H - 4
		y += 8
		_sep(y); y += 8

	# ── Markers ─────────────────────────────────────────────────────────────
	_house_mini(y, PLAYER_COLORS[0])
	_label("Home", y, font); y += ROW_H

	_briefcase_mini(y, PLAYER_COLORS[0])
	_label("Work destination", y, font)


# ── Drawing helpers ──────────────────────────────────────────────────────────

func _label(text: String, y: float, font: Font) -> void:
	draw_string(font, Vector2(LABEL_X, y + FS + 1),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, TEXT_COL)


func _sep(y: float) -> void:
	draw_line(Vector2(0, y), Vector2(SWATCH_W + 96, y), SEP_COL, 1)


func _road_swatch(level: int, y: float) -> void:
	var w  := SWATCH_W
	var h  := SWATCH_H
	var cy := y + h * 0.5
	var q  := h * 0.25  # one lane = quarter of road height

	draw_rect(Rect2(0, y, w, h), ROAD_FILL)
	draw_rect(Rect2(0, y, w, h), ROAD_EDGE, false, 1.0)

	match level:
		1:
			# Green painted strips on outer edges
			draw_rect(Rect2(0, y,           w, 2.5), BIKE_PAINT)
			draw_rect(Rect2(0, y + h - 2.5, w, 2.5), BIKE_PAINT)
		2:
			# Grey strips same width as painted (2.5px), white divider just inside
			draw_rect(Rect2(0, y,             w, 2.5), PROTECTED_ASPHALT)
			draw_rect(Rect2(0, y + h - 2.5,   w, 2.5), PROTECTED_ASPHALT)
			draw_line(Vector2(0, y + 2.5),     Vector2(w, y + 2.5),     WHITE_MARKING, 1.0)
			draw_line(Vector2(0, y + h - 2.5), Vector2(w, y + h - 2.5), WHITE_MARKING, 1.0)
		_:
			# Unimproved: white dashed lane dividers
			_swatch_dashes(y + q, w)
			_swatch_dashes(y + h - q, w)

	# Yellow centre line (all levels)
	draw_line(Vector2(0, cy), Vector2(w, cy), YELLOW_CENTER, 1.5)


func _swatch_dashes(dy: float, w: float) -> void:
	var x := 2.0
	while x < w - 2:
		draw_line(Vector2(x, dy), Vector2(minf(x + 5.0, w - 2), dy), WHITE_MARKING, 1.0)
		x += 9.0


func _car_swatch(y: float) -> void:
	_road_swatch(0, y)
	var h := SWATCH_H
	var car_x: Array[float] = [8.0, 28.0, 48.0]
	var car_side: Array[int] = [1, -1, 1]
	for i in range(car_x.size()):
		var cx: float = car_x[i]
		var cy: float = y + h * 0.5 + car_side[i] * h * 0.20
		draw_rect(Rect2(cx - 4, cy - 2, 8, 4), CAR_BODY)
		draw_rect(Rect2(cx - 0.5, cy - 1.5, 2.5, 3), CAR_WINDOW)


func _house_mini(y: float, col: Color) -> void:
	var cx := SWATCH_W * 0.5
	var s  := 7.0
	var by := y + SWATCH_H * 0.15
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, by),
		Vector2(cx - s * 0.85, by + s * 0.75),
		Vector2(cx + s * 0.85, by + s * 0.75),
	]), col)
	draw_rect(Rect2(cx - s * 0.6, by + s * 0.7, s * 1.2, s * 0.9), col)


func _briefcase_mini(y: float, col: Color) -> void:
	var cx := SWATCH_W * 0.5
	var s  := 7.0
	var by := y + SWATCH_H * 0.2
	draw_rect(Rect2(cx - s * 0.75, by + s * 0.3, s * 1.5, s * 1.0), col)
	draw_line(Vector2(cx - s * 0.28, by + s * 0.3), Vector2(cx - s * 0.28, by), col, 1.5)
	draw_line(Vector2(cx - s * 0.28, by), Vector2(cx + s * 0.28, by), col, 1.5)
	draw_line(Vector2(cx + s * 0.28, by), Vector2(cx + s * 0.28, by + s * 0.3), col, 1.5)
