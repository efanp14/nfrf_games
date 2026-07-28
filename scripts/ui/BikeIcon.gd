class_name BikeIcon
extends Node2D
## BikeIcon.gd
## Bike glyph tweened along a route's waypoints for the round-end "moving
## bikes" animation — cosmetic only, purely presentational, never touches
## routing/model state. Uses bike.svg (flat solid-black, like the other node
## icons) recolored via icon_tint.gdshader so it can match each player's
## route color.

var bike_color: Color = Color.WHITE

const ICON_BIKE         := preload("res://assets/images/bike.svg")
const ICON_TINT_SHADER  := preload("res://assets/shaders/icon_tint.gdshader")
const ICON_PX: float = 22.0


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = ICON_BIKE
	sprite.centered = true
	# Read the texture's own imported size rather than assuming a fixed
	# native size — see NodeMarker._set_icon for why (one of these SVG icons
	# imported at 24x24 instead of 512x512, and assuming 512 for it made it
	# render at ~1px, effectively invisible).
	sprite.scale = Vector2.ONE * (ICON_PX / maxf(ICON_BIKE.get_width(), 1.0))
	var mat := ShaderMaterial.new()
	mat.shader = ICON_TINT_SHADER
	mat.set_shader_parameter("tint_color", bike_color)
	sprite.material = mat
	add_child(sprite)
