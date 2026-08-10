class_name CityGrid
extends Node2D

signal link_clicked(link_id: String)

@onready var links_container: Node2D = $Links
@onready var nodes_container: Node2D = $Nodes

var _segments: Dictionary = {}
var _markers: Dictionary = {}

## PLAYER_ROUTES (default): each human player's current route highlighted in
## their own color, as before. NPC_HEATMAP (T2/T3 toggle, see GameHUD's
## CityViewButton): every street recolored green→red by how many of the
## simulated residents' current routes cross it, so "what the collective
## relies on" reads as one clean picture instead of ~48 overlapping paths.
## STRESS (all treatments, see GameHUD's StressViewButton): every street's
## centre line recolored green→red by its current effective stress, so a player
## can read how dangerous each road feels and watch an upgrade calm it. Unlike
## the other two this is available in T1 as well, because road stress is
## personal information every treatment needs, not a collective view.
##
## All three are mutually exclusive: NPC_HEATMAP and STRESS both take over the
## centre line, so they cannot both be on. One view mode, not a set of flags.
enum ViewMode { PLAYER_ROUTES, NPC_HEATMAP, STRESS }
var _view_mode: int = ViewMode.PLAYER_ROUTES

const LinkSegmentScene := preload("res://scenes/components/LinkSegment.tscn")
const NodeMarkerScene  := preload("res://scenes/components/NodeMarker.tscn")
const BackgroundTexture := preload("res://assets/images/background new.png")
const ProceduralBackgroundScript := preload("res://scripts/ui/ProceduralBackground.gd")

## Two interchangeable backgrounds:
##  - IMAGE: the illustrated art (background new.png), aligned via BG_TRANSFORM
##    below. More detail/atmosphere, but it's hand/AI-drawn art fit to our
##    grid after the fact, so alignment is close but not mathematically exact.
##  - PROCEDURAL: flat-vector buildings/parks generated directly from the
##    network's own node/link positions (see ProceduralBackground.gd) — always
##    perfectly aligned since it's built from the same coordinates as the
##    roads, but plainer/less detailed.
## Switch by changing BACKGROUND_MODE; nothing else needs to change.
enum BackgroundMode { NONE, IMAGE, PROCEDURAL }
const BACKGROUND_MODE := BackgroundMode.PROCEDURAL

## Aligns the decorative background image with our actual node/road layout.
## A 2-point (home/work icon) fit left visible drift in the upper-right of
## the map — the image isn't a mathematically precise scaled copy of our
## grid, so anchoring only two far-apart points let error accumulate
## elsewhere. Fixed by least-squares fitting a full affine transform (scale
## + shear + translation, solved for via numpy) against 23 correspondences:
## the image's own house/briefcase icons (nodes 1/20) plus its "school"
## grad-cap icon (node 15), plus 20 more found by detecting the image's own
## intersection-circle blobs (dark-pixel erosion + connected components)
## and matching them to nodes via a rough preliminary fit. Residuals after
## the full fit are ~1–14px on a 24px-wide road — much tighter than the old
## 2-point version, especially away from the home/work diagonal.
## (The image's coffee-cup icon was tried as a 4th anchor but its predicted
## position was ~200px off any real node — it's decorative filler between
## nodes 5 and 6, not meant to mark node 4 — so it's excluded.)
## Recompute this transform (see git history for the fitting script) if the
## background image or node layout changes.
const BG_TRANSFORM := Transform2D(
	Vector2(0.559452, -0.006345),
	Vector2(-0.001913, 0.550042),
	Vector2(141.406, 104.130)
)

## Manual fine-tune on top of the fitted transform above, in case it still
## needs a small nudge. Positive X = image moves right, negative Y = image
## moves up.
const BG_MANUAL_OFFSET := Vector2.ZERO

## Round-end "moving bikes" animation — one bike per human player, traced
## along their newly-recalculated route. Cosmetic only.
const ROUND_END_ANIM_DURATION := 3.3


func _ready() -> void:
	GameManager.round_started.connect(_on_game_ready, CONNECT_ONE_SHOT)


func _on_game_ready(_round_num: int, _budget: int) -> void:
	_build()
	GameManager.route_updated.connect(_on_route_updated)
	for p: Player in GameManager.human_players:
		_on_route_updated(p.player_id, p.current_route)


func _build() -> void:
	var net    := GameManager.network
	var num_players: int = GameManager.human_players.size()

	# --- Background (furthest back, behind roads/nodes/everything) ---
	match BACKGROUND_MODE:
		BackgroundMode.IMAGE:
			if net.node_positions.has(Vector2i(1, 0)):
				var bg := Sprite2D.new()
				bg.texture = BackgroundTexture
				bg.centered = false
				bg.transform = BG_TRANSFORM
				bg.position += BG_MANUAL_OFFSET
				add_child(bg)
				move_child(bg, 0)
		BackgroundMode.PROCEDURAL:
			var proc_bg: Node2D = ProceduralBackgroundScript.new()
			proc_bg.setup(net)
			add_child(proc_bg)
			move_child(proc_bg, 0)
		BackgroundMode.NONE:
			pass

	# --- Draw the river behind everything (no-op: this topology has none) ---
	if net.river_points.size() > 1:
		var river := Line2D.new()
		river.points        = net.river_points
		river.default_color = Color(0.60, 0.80, 0.92, 0.35)
		river.width         = 32.0
		river.begin_cap_mode = Line2D.LINE_CAP_ROUND
		river.end_cap_mode   = Line2D.LINE_CAP_ROUND
		add_child(river)
		move_child(river, 0)


	# --- Link segments (one per undirected edge) ---
	var drawn: Dictionary = {}
	for link_id: String in net.links:
		var link: CityNetwork.Link = net.links[link_id]
		var canonical := _canonical(link.from_node, link.to_node)
		if drawn.has(canonical):
			continue
		drawn[canonical] = true

		var pts := PackedVector2Array([
			net.node_positions[link.from_node],
			net.node_positions[link.to_node],
		])
		var seg: LinkSegment = LinkSegmentScene.instantiate()
		links_container.add_child(seg)
		seg.setup(link_id, pts, link.upgrade_level, link.stress_score)
		seg.clicked.connect(_on_segment_clicked)
		_segments[canonical] = seg

	# --- Simulated-resident home/work nodes ---
	# Purely a visual cue for where the city-wide averages come from; never
	# read by routing or metric logic, and drawn beneath the player's own
	# HOME/WORK markers wherever the two coincide. All markers render at the
	# same fixed icon size (NodeMarker.ICON_PX) — no population-based scaling.
	var npc_home_nodes: Dictionary = {}
	var npc_work_nodes: Dictionary = {}
	for commuter in GameManager.ai_commuters:
		npc_home_nodes[commuter["start"]] = true
		npc_work_nodes[commuter["goal"]] = true

	# --- Node markers ---
	for node_vec: Vector2i in net.adjacency.keys():
		var node_id := _vec_to_id(node_vec)
		var marker: NodeMarker = NodeMarkerScene.instantiate()
		nodes_container.add_child(marker)
		marker.position = net.node_positions[node_vec]

		var mtype := NodeMarker.MarkerType.NORMAL
		var pidx := 0
		var is_player_marker := false
		for i in range(num_players):
			var p: Player = GameManager.human_players[i]
			if node_vec == p.home:
				mtype = NodeMarker.MarkerType.HOME
				pidx = i
				is_player_marker = true
				break
			elif node_vec == p.work:
				mtype = NodeMarker.MarkerType.WORK
				pidx = i
				is_player_marker = true
				break

		var work_icon_key := ""
		if not is_player_marker:
			if npc_home_nodes.has(node_vec):
				mtype = NodeMarker.MarkerType.NPC_HOME
			elif npc_work_nodes.has(node_vec):
				mtype = NodeMarker.MarkerType.NPC_WORK
				work_icon_key = net.WORK_NODE_ICONS.get(node_vec, "")

		var display_label: String = ""
		marker.setup(node_id, mtype, display_label, pidx, num_players, work_icon_key)
		_markers[node_id] = marker


func refresh_link(link_id: String) -> void:
	var parts := link_id.split("-")
	if parts.size() != 2:
		return
	var a := _id_to_vec(parts[0])
	var b := _id_to_vec(parts[1])
	var canonical := _canonical(a, b)
	if _segments.has(canonical):
		var link: CityNetwork.Link = GameManager.network.links[link_id]
		_segments[canonical].set_upgrade_level(link.upgrade_level)


func refresh_all() -> void:
	for link_id: String in GameManager.network.links:
		refresh_link(link_id)


func preview_link(link_id: String, level: int) -> void:
	var parts := link_id.split("-")
	if parts.size() != 2:
		return
	var canonical := _canonical(_id_to_vec(parts[0]), _id_to_vec(parts[1]))
	if _segments.has(canonical):
		_segments[canonical].set_pending_level(level)


func clear_all_previews() -> void:
	for seg: LinkSegment in _segments.values():
		seg.set_pending_level(-1)


func set_link_points(link_id: String, points: PackedVector2Array) -> void:
	var parts := link_id.split("-")
	if parts.size() != 2:
		return
	var canonical := _canonical(_id_to_vec(parts[0]), _id_to_vec(parts[1]))
	if _segments.has(canonical):
		_segments[canonical].set_points(points)



func _on_segment_clicked(link_id: String) -> void:
	link_clicked.emit(link_id)


## Spawns a bike per human player and tweens it along their current route,
## then resolves once the longest one finishes. Called by main.gd right
## before the round summary is shown, so players see the effect of their
## upgrade before reading the numbers. Once the player(s) arrive, the
## simulated residents make their own commute (home → work) on bikes too —
## sequenced after, not simultaneous, so it reads as two distinct beats
## instead of one crowded blur of every bike on the map at once.
func play_round_end_animation() -> void:
	var last_tween: Tween = null
	for i in range(GameManager.human_players.size()):
		var p: Player = GameManager.human_players[i]
		var path: Array = p.current_route.get("path", [])
		var col: Color = GameManager.PLAYER_COLORS[i % GameManager.PLAYER_COLORS.size()]
		var t := _spawn_bike(path, col)
		if t:
			last_tween = t
	if last_tween:
		await last_tween.finished

	var npc_last_tween: Tween = null
	for commuter in GameManager.ai_commuters:
		var route: Dictionary = GameManager.network.find_route(
				commuter["start"], commuter["goal"], commuter["alpha"])
		var path: Array = route.get("path", [])
		var t := _spawn_bike(path, NodeMarker.NPC_HOME_COLOR)
		if t:
			npc_last_tween = t
	if npc_last_tween:
		await npc_last_tween.finished


func _spawn_bike(path: Array, bike_color: Color) -> Tween:
	if path.size() < 2:
		return null
	var points: Array = []
	for node_vec in path:
		points.append(GameManager.network.node_positions.get(node_vec, Vector2.ZERO))

	var icon := BikeIcon.new()
	icon.bike_color = bike_color
	icon.position = points[0]
	# NodeMarker (the home/work/intersection circles) sets z_index = 1, which
	# overrides normal tree-order drawing — the bike needs a higher z_index
	# or it renders underneath every node circle it passes through.
	icon.z_index = 2
	add_child(icon)

	var tween := create_tween()
	var seg_count := points.size() - 1
	var seg_dur := ROUND_END_ANIM_DURATION / float(seg_count)
	for i in range(seg_count):
		tween.tween_property(icon, "position", points[i + 1], seg_dur)
	tween.finished.connect(icon.queue_free)
	return tween


func _on_route_updated(player_id: String, route: Dictionary) -> void:
	var player_index := _player_id_to_index(player_id)
	if player_index < 0:
		return
	for seg: LinkSegment in _segments.values():
		seg.set_on_route(false, player_index)
	var path: Array = route.get("path", [])
	for i in range(path.size() - 1):
		var canonical := _canonical(path[i], path[i + 1])
		if _segments.has(canonical):
			_segments[canonical].set_on_route(true, player_index)
	# NPC routes are recalculated the same round the player's are, so a
	# heatmap left open needs refreshing here too, not just on toggle.
	if _view_mode == ViewMode.NPC_HEATMAP:
		_show_npc_heatmap()


## Called by main.gd, wired to GameHUD's CityViewButton (T2/T3 only).
func set_view_mode(mode: int) -> void:
	_view_mode = mode
	# Clear both centre-line views first, so switching between them can never
	# leave a segment carrying the previous one.
	for seg: LinkSegment in _segments.values():
		seg.set_stress_view(false)
	if mode != ViewMode.NPC_HEATMAP:
		for seg: LinkSegment in _segments.values():
			seg.clear_heatmap()
	match mode:
		ViewMode.NPC_HEATMAP:
			_show_npc_heatmap()
		ViewMode.STRESS:
			# No per-link value passed in: each segment already knows its own
			# base stress and upgrade level, so it derives effective stress
			# itself. Keeps this out of the "UI reads core state" pattern that
			# _show_npc_heatmap() below is already stuck with.
			for seg: LinkSegment in _segments.values():
				seg.set_stress_view(true)


## Tallies how many simulated residents' current shortest routes use each
## link, then recolors every segment green→red by that count relative to the
## busiest link this round. Recomputes via find_route rather than caching,
## same pattern already used by play_round_end_animation() above.
func _show_npc_heatmap() -> void:
	var usage: Dictionary = {}
	var max_count: int = 0
	for commuter in GameManager.ai_commuters:
		var route: Dictionary = GameManager.network.find_route(
				commuter["start"], commuter["goal"], commuter["alpha"])
		var path: Array = route.get("path", [])
		for i in range(path.size() - 1):
			var canonical := _canonical(path[i], path[i + 1])
			var count: int = usage.get(canonical, 0) + 1
			usage[canonical] = count
			max_count = maxi(max_count, count)

	for canonical: String in _segments:
		var count: int = usage.get(canonical, 0)
		var intensity: float = float(count) / float(max_count) if max_count > 0 else 0.0
		_segments[canonical].set_heatmap(intensity)


func _player_id_to_index(player_id: String) -> int:
	if player_id == "human":
		return 0
	if player_id.begins_with("player_"):
		return int(player_id.substr(7))
	return -1


# --- Coordinate helpers ---

func _vec_to_id(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]

func _id_to_vec(id: String) -> Vector2i:
	var p := id.split(",")
	return Vector2i(int(p[0]), int(p[1]))

func _canonical(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d-%d,%d" % [b.x, b.y, a.x, a.y]
