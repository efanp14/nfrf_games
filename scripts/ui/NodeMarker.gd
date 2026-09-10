class_name NodeMarker
extends Node2D
## NodeMarker.gd
## One junction on the map, drawn as a cap with an optional icon on top.
##
## Five kinds (see MarkerType): the player's own HOME and WORK, a simulated
## resident's NPC_HOME and NPC_WORK, and a plain NORMAL junction. In a group
## session each seat's own two markers carry that seat's colour as a ring and a
## numeral, which is the only thing on the map telling a player which pins are
## theirs.
##
## The rule that keeps this looking right: an icon must not overhang its own
## cap. ICON_PX is a diameter and RADII holds radii, so the comparison is
## against 2 x the radius. Change one and check the other.
##
## Nodes carry no participant-facing name. The fictional-city rule means no
## real-world label is ever shown, so the label is always blank in practice.

enum MarkerType { NORMAL, HOME, WORK, NPC_HOME, NPC_WORK }

var node_id: String = ""
var marker_type: MarkerType = MarkerType.NORMAL
var _location_name: String = ""
var _player_index: int = 0
var _num_players: int = 1
## Which amenity icon to show for an NPC_WORK node (see
## CityNetwork.WORK_NODE_ICONS) — "" falls back to the generic building.
var work_icon_key: String = ""

@onready var label: Label = $Label
var _name_label: Label
var _icon: Sprite2D
var _icon_shadow_radius: float = 0.0

## Suppresses the amenity icon and its ground shadow while leaving the marker
## itself alone. Used to hide the simulated residents' neighbourhoods and
## workplaces without taking the ROAD NODE with them: every marker draws the
## intersection circle, and the icon merely sits on top of it, so hiding the
## whole node would delete a junction from the map rather than an icon from it.
var icon_hidden: bool = false

## The cap a marker is drawn on, per type.
##
## Every type is the same size today, which is deliberate: one cap for every node
## means the map reads as a single set of places rather than as several. Kept as
## a per-type table anyway, because _draw() and the name-label offset both read
## it, and because differentiating one type later should not mean restructuring
## anything.
##
## These were declared per type and then ignored for a long time: _draw() read
## RADII[NORMAL] for every marker, so the only thing the other four entries
## affected was where the name label sat. They are honoured now.
##
## Change a radius here and check it against ICON_PX below: an icon must not
## overhang its own cap.
const RADII := {
	MarkerType.NORMAL:   28.0,
	MarkerType.HOME:     34.0,
	MarkerType.WORK:     34.0,
	MarkerType.NPC_HOME: 28.0,
	MarkerType.NPC_WORK: 28.0,
}
# --- Icons ---
# All source SVGs are flat solid-black glyphs rasterized at 512x512 (viewBox
# 0 0 24 24) — see assets/images/. Recolored per-instance via
# icon_tint.gdshader (plain `modulate` can't hue-shift solid black), sized by
# scaling a 512px-native Sprite2D down to the target on-screen pixel size.
const ICON_TINT_SHADER   := preload("res://assets/shaders/icon_tint.gdshader")
const ICON_HOME          := preload("res://assets/images/home.svg")
const ICON_BRIEFCASE     := preload("res://assets/images/briefcase.svg")
const ICON_NEIGHBOURHOOD := preload("res://assets/images/threepeoplehome.svg")
const ICON_WORK_DEFAULT  := preload("res://assets/images/workbuildings.svg")
## Extra amenity icons, keyed to match CityNetwork.WORK_NODE_ICONS values —
## lets different NPC workplace clusters read as visually distinct
## destinations instead of one repeated generic building.
const WORK_ICONS: Dictionary = {
	"school":       preload("res://assets/images/school.svg"),
	"coffee":       preload("res://assets/images/coffee.svg"),
	"bank":         preload("res://assets/images/bank.svg"),
	"gym":          preload("res://assets/images/gym.svg"),
	"market":       preload("res://assets/images/market.svg"),
	"shopping":     preload("res://assets/images/shopping.svg"),
	"shopping_bag": preload("res://assets/images/shopping bag.svg"),
}

## Every marker icon (player HOME/WORK and NPC neighbourhood/workplace) is
## the same fixed size — no population- or role-based scaling — so the map
## reads as one consistent icon set.
##
## Doubled from 20px for legibility: at 20 the amenity icons were hard to tell
## apart at a glance, and telling them apart is the point of having seven of
## them. The rule that keeps this safe is that an icon stays inside its own
## anchor circle. An icon scaled past its anchor reads as swallowing the
## intersection and the roads running through it, which is what "the icons are
## off" was the first time round, when icons reached 48px against a 36px circle.
## ICON_PX is a DIAMETER, so the comparison is against 2 x RADII: 40 inside the
## 56px resident cap, 48 inside the 68px player cap. Change one and the other has
## to move with it.
const ICON_PX: float = 40.0

## The player's own home and workplace, which are the two markers a participant
## has to find on a map carrying 99 other people's. Bigger than the residents'
## rather than the same size, together with the seat-coloured ring in _draw().
const ICON_PX_PLAYER: float = 48.0

## Thickness of the seat-coloured ring around the player's own two markers.
const PLAYER_RING_W: float = 4.0

## Offset of the soft shadow shared by every node and building. The colour
## itself, like every other colour here, comes from Palette.
const SHADOW_OFFSET := Vector2(2.0, 2.5)


func setup(id: String, type: MarkerType = MarkerType.NORMAL, location_name: String = "", player_index: int = 0, num_players: int = 1, icon_key: String = "") -> void:
	node_id = id
	marker_type = type
	_location_name = location_name
	_player_index = player_index
	_num_players = num_players
	work_icon_key = icon_key
	if is_node_ready():
		_apply_type()
		_apply_name()
		_update_icon()
	queue_redraw()


func _ready() -> void:
	z_index = 1
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Palette.NODE_NAME_TEXT)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name_label)

	_icon = Sprite2D.new()
	_icon.centered = true
	var mat := ShaderMaterial.new()
	mat.shader = ICON_TINT_SHADER
	_icon.material = mat
	add_child(_icon)

	_apply_type()
	_apply_name()
	_update_icon()


func _get_color() -> Color:
	if marker_type == MarkerType.NORMAL:
		return Palette.ROAD_FILL
	return Palette.seat_color(_player_index)


func _apply_type() -> void:
	var is_player_marker := marker_type == MarkerType.HOME or marker_type == MarkerType.WORK
	if not is_player_marker or _num_players <= 1:
		label.text = ""
		label.visible = false
		return
	# Font 9 up to 20. This numeral answers "which of these is mine" in the group
	# treatment and it was the smallest text in the game, then scaled down again
	# by the map fit. Dark ink on an outline in the seat colour, so it holds up
	# over roads, buildings and route bands alike.
	label.text = str(_player_index + 1)
	label.visible = true
	label.add_theme_color_override("font_color", Palette.SEAT_NUMBER_TEXT)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", _get_color())
	label.add_theme_constant_override("outline_size", 10)
	label.position = Vector2(RADII[marker_type] - 2.0, -14.0)


func _apply_name() -> void:
	if _name_label == null:
		return
	_name_label.text = _location_name
	_name_label.visible = not _location_name.is_empty()
	_name_label.position = Vector2(-42.0, RADII[marker_type] + 2.0)
	_name_label.custom_minimum_size = Vector2(84.0, 0.0)


func _draw() -> void:
	var r: float = RADII[marker_type]

	# Soft shadow first (furthest back), then a thin low-contrast rim, then
	# the road fill on top — depth without the intersection reading as a
	# heavy ink blot (this map renders nodes ~50px across on screen, so a
	# strong rim/shadow combo gets very heavy very fast).
	# antialiased:true matters here beyond edge smoothing — Godot's default
	# (non-AA) filled draw_circle triangle-fans from a shared center vertex,
	# which can rasterize as a single stray off-color pixel dead in the
	# middle of the circle on some GPU/driver combos. The AA path uses a
	# different draw method that doesn't have that seam.
	draw_circle(SHADOW_OFFSET, r, Palette.NODE_SHADOW, true, -1.0, true)
	draw_circle(Vector2.ZERO, r + 1.0, Palette.NODE_RIM, true, -1.0, true)
	draw_circle(Vector2.ZERO, r, Palette.ROAD_FILL, true, -1.0, true)

	if icon_hidden:
		# Road node only. The circle above is the intersection and always
		# stands; what is dropped is the icon and the shadow it casts.
		return

	if marker_type == MarkerType.HOME or marker_type == MarkerType.WORK \
			or marker_type == MarkerType.NPC_HOME or marker_type == MarkerType.NPC_WORK:
		_draw_shadow_blob(Vector2.ZERO, _icon_shadow_radius)

	# The player's own two markers get a ring in their seat colour.
	#
	# This replaces a branch that could never run: it was written
	# `elif marker_type != MarkerType.NORMAL`, under an `if` that had already
	# caught all four non-NORMAL types, so every cap in the game drew as plain
	# ROAD_FILL and the seat colour survived only in the icon tint and a font-9
	# numeral. In the group treatment that numeral is the only thing answering
	# whose home is whose, and it is scaled down again when the city is fitted
	# to the window.
	#
	# A ring rather than a filled cap, because the icon is tinted the same seat
	# colour and would vanish into it.
	if marker_type == MarkerType.HOME or marker_type == MarkerType.WORK:
		draw_arc(Vector2.ZERO, r + PLAYER_RING_W * 0.5, 0.0, TAU, 48,
				_get_color(), PLAYER_RING_W, true)


## Shows or hides this marker's icon, leaving the road node itself drawn.
func set_icon_hidden(is_hidden: bool) -> void:
	if icon_hidden == is_hidden:
		return
	icon_hidden = is_hidden
	_update_icon()
	queue_redraw()


## Small ground shadow under the icon so it reads as standing on the
## intersection rather than floating on top of it.
func _draw_shadow_blob(offset: Vector2, radius: float) -> void:
	draw_circle(offset + SHADOW_OFFSET * 0.6, radius, Palette.ICON_SHADOW, true, -1.0, true)


## Swaps in the right texture/color/size for the current marker_type and
## repositions the icon sprite. Called whenever setup() changes anything
## that affects how the icon should look.
func _update_icon() -> void:
	if _icon == null:
		return
	_icon.position = Vector2.ZERO

	if icon_hidden:
		_icon.visible = false
		_icon_shadow_radius = 0.0
		return

	match marker_type:
		MarkerType.HOME:
			_set_icon(ICON_HOME, ICON_PX_PLAYER, _get_color())
		MarkerType.WORK:
			_set_icon(ICON_BRIEFCASE, ICON_PX_PLAYER, _get_color())
		MarkerType.NPC_HOME:
			_set_icon(ICON_NEIGHBOURHOOD, ICON_PX, Palette.NPC_HOME)
		MarkerType.NPC_WORK:
			var tex: Texture2D = WORK_ICONS.get(work_icon_key, ICON_WORK_DEFAULT)
			_set_icon(tex, ICON_PX, Palette.NPC_WORK)
		_:
			_icon.visible = false
			_icon_shadow_radius = 0.0
			return
	_icon.visible = true


func _set_icon(tex: Texture2D, target_px: float, color: Color) -> void:
	_icon.texture = tex
	# Read the texture's own imported size rather than assuming 512px for
	# every icon — threepeoplehome.svg imports at 24x24 (Godot's SVG importer
	# fell back to its viewBox instead of its width/height attributes) while
	# every other icon here imports at 512x512. Assuming 512 for all of them
	# silently scaled that one icon down to ~1px — invisible, not just small.
	var native_px: float = maxf(tex.get_width(), 1.0)
	_icon.scale = Vector2.ONE * (target_px / native_px)
	_icon_shadow_radius = target_px * 0.42
	(_icon.material as ShaderMaterial).set_shader_parameter("tint_color", color)
