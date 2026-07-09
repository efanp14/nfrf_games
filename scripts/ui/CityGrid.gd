class_name CityGrid
extends Node2D

signal link_clicked(link_id: String)

@onready var links_container: Node2D = $Links
@onready var nodes_container: Node2D = $Nodes

var _segments: Dictionary = {}
var _markers: Dictionary = {}

const LinkSegmentScene := preload("res://scenes/components/LinkSegment.tscn")
const NodeMarkerScene  := preload("res://scenes/components/NodeMarker.tscn")

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

	# --- Draw the Bow River behind everything ---
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

	# --- Node markers ---
	for node_vec: Vector2i in net.adjacency.keys():
		var node_id := _vec_to_id(node_vec)
		var marker: NodeMarker = NodeMarkerScene.instantiate()
		nodes_container.add_child(marker)
		marker.position = net.node_positions[node_vec]

		var mtype := NodeMarker.MarkerType.NORMAL
		var pidx := 0
		for i in range(num_players):
			var p: Player = GameManager.human_players[i]
			if node_vec == p.home:
				mtype = NodeMarker.MarkerType.HOME
				pidx = i
				break
			elif node_vec == p.work:
				mtype = NodeMarker.MarkerType.WORK
				pidx = i
				break

		var display_label: String = ""
		marker.setup(node_id, mtype, display_label, pidx, num_players)
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
## upgrade before reading the numbers.
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
