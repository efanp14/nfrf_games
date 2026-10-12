class_name ResidentIcons
extends VBoxContainer
## ResidentIcons.gd
## Five person figures showing what share of the city's residents travel more
## safely than on the original network, with a one-line caption beneath. Shown
## in T2 and T3 on the city card and the round summary.
##
## Five figures rather than ten, and figures may be half filled, split down the
## middle, so the picture still moves in tenths (owner, Oct 2026). Five full
## figures alone would move in fifths: 9% would show nobody, and 30% would look
## the same as 49%.
##
## Display only. How many halves to fill and the caption both come from
## CityFeedback, which the research log also reads, so the picture, the words
## and the log cannot disagree.

const FIGURES: int = 5
const FIGURE_SIZE := Vector2(30, 56)
const FIGURE_GAP: int = 8
const CAPTION_FONT_SIZE: int = 16

var _figures: Array[_Figure] = []
var _caption: Label


func _init() -> void:
	add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FIGURE_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	for i in range(FIGURES):
		var f := _Figure.new()
		row.add_child(f)
		_figures.append(f)

	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", CAPTION_FONT_SIZE)
	# Never wraps, so its height cannot depend on a width the container has not
	# settled yet (the round summary rule; see probe_round_summary).
	_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_caption)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Hidden until there is a result, like the benefit text beside it.
func show_metrics(metrics: Dictionary) -> void:
	visible = metrics.has("residents_total")
	if not visible:
		return
	var halves := CityFeedback.safety_icon_halves(metrics)
	for i in range(FIGURES):
		_figures[i].set_fill(clampf((halves - 2 * i) / 2.0, 0.0, 1.0))
	_caption.text = CityFeedback.safety_caption(metrics)


## Half figures currently filled, so a probe can check the picture against the
## caption without walking the tree.
func filled_halves() -> int:
	var total := 0
	for f in _figures:
		total += int(round(f.fill * 2.0))
	return total


## One figure: drawn empty, then drawn again filled inside a child that clips it
## to the filled share of its width, so half a figure is its left half.
class _Figure extends Control:
	var fill: float = 0.0
	var _clip: Control
	var _filled: _Shape

	func _init() -> void:
		custom_minimum_size = ResidentIcons.FIGURE_SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var empty := _Shape.new(Palette.RESIDENT_ICON_EMPTY)
		add_child(empty)
		_clip = Control.new()
		_clip.clip_contents = true
		_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_clip)
		_filled = _Shape.new(Palette.RESIDENT_ICON_FILLED)
		_clip.add_child(_filled)
		set_fill(0.0)

	func set_fill(value: float) -> void:
		fill = value
		_clip.size = Vector2(ResidentIcons.FIGURE_SIZE.x * fill, ResidentIcons.FIGURE_SIZE.y)
		_clip.visible = fill > 0.0


## The person silhouette: head, shoulders and arms, two legs. Proportions after
## the owner's reference image.
class _Shape extends Control:
	var _color: Color

	func _init(color: Color) -> void:
		_color = color
		size = ResidentIcons.FIGURE_SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := ResidentIcons.FIGURE_SIZE.x
		var h := ResidentIcons.FIGURE_SIZE.y
		var cx := w / 2.0
		# Head
		draw_circle(Vector2(cx, h * 0.10), w * 0.20, _color, true, -1.0, true)
		# Torso: shoulders wider than the waist
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - w * 0.30, h * 0.24), Vector2(cx + w * 0.30, h * 0.24),
			Vector2(cx + w * 0.22, h * 0.56), Vector2(cx - w * 0.22, h * 0.56),
		]), _color)
		# Arms
		var arm_w := w * 0.15
		draw_line(Vector2(cx - w * 0.30, h * 0.27), Vector2(cx - w * 0.42, h * 0.52), _color, arm_w, true)
		draw_line(Vector2(cx + w * 0.30, h * 0.27), Vector2(cx + w * 0.42, h * 0.52), _color, arm_w, true)
		# Legs
		var leg_w := w * 0.19
		draw_line(Vector2(cx - w * 0.12, h * 0.55), Vector2(cx - w * 0.16, h * 0.97), _color, leg_w, true)
		draw_line(Vector2(cx + w * 0.12, h * 0.55), Vector2(cx + w * 0.16, h * 0.97), _color, leg_w, true)
