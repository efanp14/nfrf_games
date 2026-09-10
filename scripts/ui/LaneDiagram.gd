class_name LaneDiagram
extends Control
## LaneDiagram.gd
## The three infrastructure levels drawn as cross-sections of a street, with a
## plain-language caption each. Used on the orientation screens.
##
## Playtesters asked for pictures of painted versus protected lanes, and for
## them to be explained for people who have never ridden either. The obvious
## answer was to commission artwork; the better one is to draw the roads with
## the same constants LinkSegment paints the map with, because then the picture
## in the briefing cannot end up showing something the map does not. Change
## BIKE_PAINT_W or the palette and this follows on its own.
##
## Purely presentational: it reads constants, never model state, and nothing
## here can affect routing (guardrail 8).

## Height of one drawn road. Larger than the map's own 24-42px because this is
## a diagram meant to be read once, not a map to be scanned.
const ROAD_H: float = 46.0
const ROAD_W: float = 210.0
const ROW_GAP: float = 22.0
const TEXT_X: float = ROAD_W + 24.0
const TITLE_FS: int = 18
const BODY_FS: int = 15

## What each level is, in words a participant who has never used either can act
## on. Deliberately flat: it says what the thing is and what it costs relative
## to the other, and stops there. Nothing here should read as advice about where
## to spend, since where people choose to spend is the measurement.
const ROWS: Array = [
	{
		"level": 0,
		"title": "No Bike Lane",
		"body": "You ride in the traffic lane, alongside the cars.\nNothing separates you from them.",
	},
	{
		"level": 1,
		"title": "Painted Lane",
		"body": "A painted strip marks space for bikes at the edge\nof the road. Cheaper. Cars can still cross it.",
	},
	{
		"level": 2,
		"title": "Protected Lane",
		"body": "A raised kerb separates bikes from the traffic.\nCosts more. The calmest of the three to ride.",
	},
]


func _ready() -> void:
	var font := ThemeDB.fallback_font
	var widest := 0.0
	for row: Dictionary in ROWS:
		for line in str(row["body"]).split("\n"):
			widest = maxf(widest, font.get_string_size(
					line, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_FS).x)
	custom_minimum_size = Vector2(TEXT_X + widest,
			(ROAD_H + ROW_GAP) * ROWS.size() - ROW_GAP)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var y := 0.0
	for row: Dictionary in ROWS:
		_road(int(row["level"]), y)
		draw_string(font, Vector2(TEXT_X, y + TITLE_FS),
				str(row["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				TITLE_FS, Palette.TEXT_HEADING)
		var line_y := y + TITLE_FS + 20.0
		for line in str(row["body"]).split("\n"):
			draw_string(font, Vector2(TEXT_X, line_y), line,
					HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_FS, Palette.TEXT_PRIMARY)
			line_y += BODY_FS + 4.0
		y += ROAD_H + ROW_GAP


## One road, at the proportions LinkSegment draws it, scaled up to ROAD_H.
##
## Everything is expressed as a fraction of LinkSegment.ROAD_WIDTH so the
## diagram keeps matching the map at whatever size it is drawn.
func _road(level: int, y: float) -> void:
	var k: float = ROAD_H / LinkSegment.ROAD_WIDTH
	var strip: float = LinkSegment.BIKE_PAINT_W * k
	var divider: float = LinkSegment.DIVIDER_W * k

	# Only an upgraded road has a curb, exactly as on the map.
	if level > 0:
		draw_rect(Rect2(-LinkSegment.EDGE_BORDER * k, y - LinkSegment.EDGE_BORDER * k,
				ROAD_W + LinkSegment.EDGE_BORDER * k * 2.0,
				ROAD_H + LinkSegment.EDGE_BORDER * k * 2.0), Palette.ROAD_EDGE)
	draw_rect(Rect2(0, y, ROAD_W, ROAD_H), Palette.ROAD_FILL)

	match level:
		1:
			draw_rect(Rect2(0, y, ROAD_W, strip), Palette.BIKE_PAINT)
			draw_rect(Rect2(0, y + ROAD_H - strip, ROAD_W, strip), Palette.BIKE_PAINT)
		2:
			draw_rect(Rect2(0, y, ROAD_W, strip), Palette.PROTECTED_ASPHALT)
			draw_rect(Rect2(0, y + ROAD_H - strip, ROAD_W, strip), Palette.PROTECTED_ASPHALT)
			draw_rect(Rect2(0, y + strip, ROAD_W, divider), Palette.WHITE_MARKING)
			draw_rect(Rect2(0, y + ROAD_H - strip - divider, ROAD_W, divider),
					Palette.WHITE_MARKING)

	# A car in the traffic lane on every level, since the point of the three
	# pictures is what stands between a rider and it.
	var car_w: float = LinkSegment.CAR_LENGTH * k * 0.9
	var car_h: float = LinkSegment.CAR_WIDTH_HALF * 2.0 * k
	var car_y: float = y + ROAD_H * 0.5 - car_h * 0.5
	draw_rect(Rect2(ROAD_W * 0.62, car_y, car_w, car_h), Palette.CAR_COLORS[0])
	draw_rect(Rect2(ROAD_W * 0.62 + car_w * 0.55, car_y + car_h * 0.2,
			car_w * 0.28, car_h * 0.6), Color(Palette.CAR_WINDOW, 0.85))

	# And a bike where a rider would actually be: out in the lane with no
	# infrastructure, tucked into the strip once there is one.
	var bike_cy: float = y + ROAD_H * 0.5 if level == 0 else y + strip * 0.5 + strip
	draw_circle(Vector2(ROAD_W * 0.24, bike_cy), 4.5 * k * 0.9,
			Palette.seat_color(0), true, -1.0, true)
