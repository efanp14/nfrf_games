class_name NodeMarker
extends Node2D

enum MarkerType { NORMAL, HOME, WORK }

var node_id: String = ""
var marker_type: MarkerType = MarkerType.NORMAL
var _location_name: String = ""
var _player_index: int = 0
var _num_players: int = 1

@onready var label: Label = $Label
var _name_label: Label

const PLAYER_COLORS: Array = [
	Color(0.42, 0.64, 0.84),   # blue
	Color(0.88, 0.47, 0.32),   # coral
	Color(0.35, 0.72, 0.40),   # green
	Color(0.62, 0.42, 0.78),   # purple
	Color(0.85, 0.68, 0.25),   # amber
]
const RADII := {
	MarkerType.NORMAL: 18.0,
	MarkerType.HOME:   16.0,
	MarkerType.WORK:   16.0,
}


func setup(id: String, type: MarkerType = MarkerType.NORMAL, location_name: String = "", player_index: int = 0, num_players: int = 1) -> void:
	node_id = id
	marker_type = type
	_location_name = location_name
	_player_index = player_index
	_num_players = num_players
	if is_node_ready():
		_apply_type()
		_apply_name()
	queue_redraw()


func _ready() -> void:
	z_index = 1
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name_label)
	_apply_type()
	_apply_name()


func _get_color() -> Color:
	if marker_type == MarkerType.NORMAL:
		return LinkSegment.ROAD_FILL
	return PLAYER_COLORS[_player_index % PLAYER_COLORS.size()]


func _apply_type() -> void:
	if marker_type == MarkerType.NORMAL or _num_players <= 1:
		label.text = ""
		label.visible = false
		return
	label.text = str(_player_index + 1)
	label.visible = true
	label.add_theme_color_override("font_color", _get_color())
	label.add_theme_font_size_override("font_size", 9)
	label.position = Vector2(RADII[marker_type] + 1.0, -6.0)


func _apply_name() -> void:
	if _name_label == null:
		return
	_name_label.text = _location_name
	_name_label.visible = not _location_name.is_empty()
	_name_label.position = Vector2(-42.0, RADII[marker_type] + 2.0)
	_name_label.custom_minimum_size = Vector2(84.0, 0.0)


func _draw() -> void:
	var col: Color = _get_color()
	if marker_type == MarkerType.HOME:
		draw_circle(Vector2.ZERO, RADII[MarkerType.NORMAL], LinkSegment.ROAD_FILL)
		_draw_house(col)
	elif marker_type == MarkerType.WORK:
		draw_circle(Vector2.ZERO, RADII[MarkerType.NORMAL], LinkSegment.ROAD_FILL)
		_draw_briefcase(col)
	else:
		draw_circle(Vector2.ZERO, RADII[MarkerType.NORMAL], col)


func _draw_house(col: Color) -> void:
	var s := 16.0
	# Body
	draw_rect(Rect2(-s * 0.7, -s * 0.15, s * 1.4, s * 1.05), col)
	# Roof (triangle)
	var roof := PackedVector2Array([
		Vector2(0.0, -s * 0.95),
		Vector2(-s * 0.9, -s * 0.15),
		Vector2(s * 0.9, -s * 0.15),
	])
	draw_colored_polygon(roof, col)
	# Door
	draw_rect(Rect2(-s * 0.2, s * 0.3, s * 0.4, s * 0.6), col.darkened(0.25))
	# Window
	draw_rect(Rect2(s * 0.2, s * 0.0, s * 0.3, s * 0.25), col.lightened(0.35))


func _draw_briefcase(col: Color) -> void:
	var s := 16.0
	# Body
	draw_rect(Rect2(-s * 0.85, -s * 0.35, s * 1.7, s * 1.15), col)
	# Handle
	var hw := s * 0.3
	var ht := 1.5
	draw_line(Vector2(-hw, -s * 0.35), Vector2(-hw, -s * 0.6), col, ht, true)
	draw_line(Vector2(-hw, -s * 0.6), Vector2(hw, -s * 0.6), col, ht, true)
	draw_line(Vector2(hw, -s * 0.6), Vector2(hw, -s * 0.35), col, ht, true)
	# Clasp line
	draw_line(Vector2(-s * 0.85, s * 0.05), Vector2(s * 0.85, s * 0.05), col.darkened(0.2), 1.5)
	# Latch
	draw_rect(Rect2(-s * 0.12, -s * 0.05, s * 0.24, s * 0.2), col.darkened(0.15))
