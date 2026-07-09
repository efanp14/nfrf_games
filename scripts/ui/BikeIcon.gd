class_name BikeIcon
extends Node2D
## BikeIcon.gd
## Lightweight top-down bike glyph, tweened along a route's waypoints for
## the round-end "moving bikes" animation — cosmetic only, purely
## presentational, never touches routing/model state.

var bike_color: Color = Color.WHITE


func _draw() -> void:
	var r := 4.0
	draw_arc(Vector2(-5, 0), r, 0, TAU, 16, bike_color, 1.5, true)
	draw_arc(Vector2(5, 0), r, 0, TAU, 16, bike_color, 1.5, true)
	draw_line(Vector2(-5, 0), Vector2(0, -6), bike_color, 1.5, true)
	draw_line(Vector2(0, -6), Vector2(5, 0), bike_color, 1.5, true)
	draw_line(Vector2(-5, 0), Vector2(5, 0), bike_color, 1.5, true)
	draw_circle(Vector2(0, -6), 2.2, bike_color)
