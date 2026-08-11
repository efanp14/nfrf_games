class_name NodeMarker
extends Node2D

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

const PLAYER_COLORS: Array = [
	Color(0.42, 0.64, 0.84),   # blue
	Color(0.88, 0.47, 0.32),   # coral
	Color(0.35, 0.72, 0.40),   # green
	Color(0.62, 0.42, 0.78),   # purple
	Color(0.85, 0.68, 0.25),   # amber
]
## Shrunk from the original flat-circle design (was 18.0) now that real
## icons sit on top — a smaller "manhole" reads as an intersection cap
## instead of a big black dot competing with the icon for attention, and
## keeps icons (see ICON_PX below) from overhanging it.
const RADII := {
	MarkerType.NORMAL:   14.0,
	MarkerType.HOME:     12.0,
	MarkerType.WORK:     12.0,
	MarkerType.NPC_HOME: 6.0,
	MarkerType.NPC_WORK: 6.0,
}
## Simulated-resident markers: muted (desaturated, not translucent) so they
## read as background texture without competing with the player's own
## HOME/WORK markers.
const NPC_HOME_COLOR := Color(0.58, 0.61, 0.54, 1.0)
const NPC_WORK_COLOR := Color(0.46, 0.52, 0.58, 1.0)

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
## reads as one consistent icon set. Kept at or under the node circle's own
## diameter (2 * RADII[NORMAL] = 28px): an icon scaled up past its anchor
## circle reads as swallowing the intersection and the roads through it,
## which is what "the icons are off" was (icons used to size up to 48px
## against a then-36px circle).
const ICON_PX: float = 20.0

## Soft shadow shared by every node/building — kept as one flat translucent
## color (no blur/gradient) to match LinkSegment's road shadow treatment.
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.16)
const SHADOW_OFFSET := Vector2(2.0, 2.5)
## Thin, subtle rim so the intersection reads as a paved circle with an
## edge — kept low-contrast on purpose. At this map's on-screen scale
## (nodes render ~50px across), a strong dark rim plus a full-radius
## shadow reads as a heavy ink blot rather than a clean intersection.
const NODE_RIM_COLOR := Color(0.20, 0.19, 0.20, 0.55)
const NODE_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.10)


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
	_name_label.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
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
		return LinkSegment.ROAD_FILL
	return PLAYER_COLORS[_player_index % PLAYER_COLORS.size()]


func _apply_type() -> void:
	var is_player_marker := marker_type == MarkerType.HOME or marker_type == MarkerType.WORK
	if not is_player_marker or _num_players <= 1:
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
	var r: float = RADII[MarkerType.NORMAL]

	# Soft shadow first (furthest back), then a thin low-contrast rim, then
	# the road fill on top — depth without the intersection reading as a
	# heavy ink blot (this map renders nodes ~50px across on screen, so a
	# strong rim/shadow combo gets very heavy very fast).
	# antialiased:true matters here beyond edge smoothing — Godot's default
	# (non-AA) filled draw_circle triangle-fans from a shared center vertex,
	# which can rasterize as a single stray off-color pixel dead in the
	# middle of the circle on some GPU/driver combos. The AA path uses a
	# different draw method that doesn't have that seam.
	draw_circle(SHADOW_OFFSET, r, NODE_SHADOW_COLOR, true, -1.0, true)
	draw_circle(Vector2.ZERO, r + 1.0, NODE_RIM_COLOR, true, -1.0, true)
	draw_circle(Vector2.ZERO, r, LinkSegment.ROAD_FILL, true, -1.0, true)

	if icon_hidden:
		# Road node only. The circle above is the intersection and always
		# stands; what is dropped is the icon and the shadow it casts.
		return

	if marker_type == MarkerType.HOME or marker_type == MarkerType.WORK \
			or marker_type == MarkerType.NPC_HOME or marker_type == MarkerType.NPC_WORK:
		_draw_shadow_blob(Vector2.ZERO, _icon_shadow_radius)
	elif marker_type != MarkerType.NORMAL:
		draw_circle(Vector2.ZERO, r, _get_color(), true, -1.0, true)


## Shows or hides this marker's icon, leaving the road node itself drawn.
func set_icon_hidden(hidden: bool) -> void:
	if icon_hidden == hidden:
		return
	icon_hidden = hidden
	_update_icon()
	queue_redraw()


## Small ground shadow under the icon so it reads as standing on the
## intersection rather than floating on top of it.
func _draw_shadow_blob(offset: Vector2, radius: float) -> void:
	draw_circle(offset + SHADOW_OFFSET * 0.6, radius, SHADOW_COLOR, true, -1.0, true)


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
			_set_icon(ICON_HOME, ICON_PX, _get_color())
		MarkerType.WORK:
			_set_icon(ICON_BRIEFCASE, ICON_PX, _get_color())
		MarkerType.NPC_HOME:
			_set_icon(ICON_NEIGHBOURHOOD, ICON_PX, NPC_HOME_COLOR)
		MarkerType.NPC_WORK:
			var tex: Texture2D = WORK_ICONS.get(work_icon_key, ICON_WORK_DEFAULT)
			_set_icon(tex, ICON_PX, NPC_WORK_COLOR)
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
