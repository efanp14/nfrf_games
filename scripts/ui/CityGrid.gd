class_name CityGrid
extends Node2D
## CityGrid.gd
## The map: background, roads and node markers, built from CityNetwork.
##
## _build() runs once when a round first starts and again after a scene reload,
## and is written back-to-front in draw order. Segments are keyed by the
## CANONICAL link id, which matters beyond tidiness: that id is what reaches
## upgrades.csv and decisions.csv, and network_links.csv is canonical, so a
## non-canonical id would silently fail to join at analysis time.
##
## This is one of the places the "UI reads nothing directly" guardrail is not
## literally held (README, guardrail 2). It pulls GameManager.network,
## .human_players and .ai_commuters at build time because it has to ask what to
## draw. Those are reads, never writes, and every per-round update still arrives
## by signal.
##
## The view toggles (resident visuals, player routes) are STATIC, so they
## survive the scene reload between chained sessions; _build() re-applies them
## at the end for that reason.

signal link_clicked(link_id: String)

@onready var links_container: Node2D = $Links
@onready var nodes_container: Node2D = $Nodes

var _segments: Dictionary = {}
## from_node of each canonical segment, so a route step can be told apart from
## the same road travelled the other way. Filled in alongside _segments.
var _segment_from_node: Dictionary = {}
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

## Hides the simulated residents' presence on the map: their neighbourhood and
## workplace markers, and the bikes they ride at round end. Playtest feedback
## was that the map is visually busy, and the residents are the largest single
## contributor — 12 neighbourhood markers, 15 workplace markers, and 99 bikes
## crossing the city in one burst after every round.
##
## A toggle rather than a removal, because whether they go for good is the
## owner's call and has not been made. Nothing about the model changes: the
## residents are still simulated, still routed, still counted in every city
## metric and still written to the logs. This hides them, it does not switch
## them off, so a session recorded with the toggle on produces exactly the same
## data as one with it off.
##
## Static so it survives the scene reload between a chained T1 and T2, which
## would otherwise reset it mid-sitting.
static var hide_resident_visuals: bool = false

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

## Drawn width of the river, if a topology has one. This one does not.
const RIVER_WIDTH := 32.0

## Aligns the decorative background image with our actual node/road layout.
##
## ⚠️ This describes BackgroundMode.IMAGE, which is NOT the selected mode: the
## build ships PROCEDURAL, so nothing below runs as things stand. Kept because
## the fit is expensive to recover and the mode is a one-line switch away, but
## do not read it as documentation of what you see on screen.
##
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


## Builds the whole map from the network: background, roads, node markers.
## Called once when a round first starts, and again after a scene reload.
##
## Split into one function per layer, back to front, because that order is the
## draw order and reading it is how you find out what sits on top of what.
func _build() -> void:
	var net := GameManager.network
	_build_background(net)
	_build_river(net)
	_build_segments(net)
	_build_markers(net)
	# The toggles are static and survive a scene reload, so a map built after
	# either was switched on must come up already hiding what it hides.
	_apply_resident_visibility()
	_apply_player_route_visibility()


## Furthest back, behind roads, nodes and everything else.
func _build_background(net: CityNetwork) -> void:
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


## A no-op on this topology, which has no river. Kept because the network
## format still carries river_points and a future board may use them.
func _build_river(net: CityNetwork) -> void:
	if net.river_points.size() <= 1:
		return
	var river := Line2D.new()
	river.points          = net.river_points
	river.default_color   = Palette.RIVER
	river.width           = RIVER_WIDTH
	river.begin_cap_mode  = Line2D.LINE_CAP_ROUND
	river.end_cap_mode    = Line2D.LINE_CAP_ROUND
	add_child(river)
	move_child(river, 0)


## One segment per undirected edge. net.links holds both directions, so the
## second one met is skipped.
func _build_segments(net: CityNetwork) -> void:
	var rider_alpha: float = (GameManager.human_player.alpha
			if GameManager.human_player != null else PersonalityConfig.ALPHA_AVERAGE)
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
		# The CANONICAL id, not `link_id`. `net.links` holds both directions and
		# this loop takes whichever it meets first, which for 16 of the 69 edges is
		# the high-node-first one. That id is what clicked() emits and what ends up
		# in upgrades.csv and decisions.csv, while network_links.csv and every
		# route_links column are canonical -- so a join between them would silently
		# drop those links. Both directions exist in net.links, so every lookup
		# downstream of here still resolves.
		# The rider's alpha goes in too: the stress colour, the cars and their speed
		# all describe how the road feels, and how it feels depends on who is riding.
		seg.setup(canonical, pts, link.upgrade_level, link.stress_score, rider_alpha)
		seg.clicked.connect(_on_segment_clicked)
		_segments[canonical] = seg
		# Segments are stored under one canonical id for an undirected edge, so
		# the node its points start from is recorded here. The route flow arrows
		# need it to tell which way along the road a given rider is going.
		_segment_from_node[canonical] = link.from_node


## Which nodes the simulated residents start and finish at. Purely a visual cue
## for where the city-wide averages come from; never read by routing or metric
## logic.
func _resident_endpoints() -> Array[Dictionary]:
	var homes: Dictionary = {}
	var works: Dictionary = {}
	for commuter: Dictionary in GameManager.ai_commuters:
		homes[commuter["start"]] = true
		works[commuter["goal"]] = true
	return [homes, works]


## Which kind of marker a node gets, and for which seat. The player's own
## HOME/WORK wins over a resident endpoint wherever the two coincide.
func _marker_kind_for(node_vec: Vector2i, net: CityNetwork,
		npc_homes: Dictionary, npc_works: Dictionary) -> Dictionary:
	for i in range(GameManager.human_players.size()):
		var p: Player = GameManager.human_players[i]
		if node_vec == p.home:
			return {"type": NodeMarker.MarkerType.HOME, "seat": i, "icon": ""}
		if node_vec == p.work:
			return {"type": NodeMarker.MarkerType.WORK, "seat": i, "icon": ""}
	if npc_homes.has(node_vec):
		return {"type": NodeMarker.MarkerType.NPC_HOME, "seat": 0, "icon": ""}
	if npc_works.has(node_vec):
		return {"type": NodeMarker.MarkerType.NPC_WORK, "seat": 0,
				"icon": net.WORK_NODE_ICONS.get(node_vec, "")}
	return {"type": NodeMarker.MarkerType.NORMAL, "seat": 0, "icon": ""}


## All markers render at the same fixed icon size (NodeMarker.ICON_PX) -- no
## population-based scaling.
func _build_markers(net: CityNetwork) -> void:
	var num_players: int = GameManager.human_players.size()
	var endpoints := _resident_endpoints()
	var npc_homes: Dictionary = endpoints[0]
	var npc_works: Dictionary = endpoints[1]

	for node_vec: Vector2i in net.adjacency.keys():
		var node_id := _vec_to_id(node_vec)
		var marker: NodeMarker = NodeMarkerScene.instantiate()
		nodes_container.add_child(marker)
		marker.position = net.node_positions[node_vec]

		var kind := _marker_kind_for(node_vec, net, npc_homes, npc_works)
		# Deliberately blank: the fictional-city rule means no node ever shows a
		# participant-facing name, so nothing is passed for the label.
		var display_label: String = ""
		marker.setup(node_id, kind["type"], display_label, kind["seat"],
				num_players, kind["icon"])
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


## Marks one road as the one the upgrade popup is about, clearing any previous.
## Pass "" to clear. Display only.
func set_selected_link(link_id: String) -> void:
	var canonical := ""
	if not link_id.is_empty():
		var parts := link_id.split("-")
		if parts.size() == 2:
			canonical = _canonical(_id_to_vec(parts[0]), _id_to_vec(parts[1]))
	for key: String in _segments:
		_segments[key].set_selected(key == canonical)


func clear_all_previews() -> void:
	for seg: LinkSegment in _segments.values():
		seg.set_pending_level(-1)


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
		var col: Color = Palette.seat_color(i)
		var t := _spawn_bike(path, col)
		if t:
			last_tween = t
	if last_tween:
		await last_tween.finished

	# The residents' commute is the busiest moment on screen, so it is the first
	# thing the hide toggle drops. The player's own bike above always rides:
	# there is one of it, and it is how they see what their upgrade did.
	if hide_resident_visuals:
		return

	var npc_last_tween: Tween = null
	for commuter in GameManager.ai_commuters:
		var route: Dictionary = GameManager.network.find_route(
				commuter["start"], commuter["goal"], commuter["alpha"])
		var path: Array = route.get("path", [])
		var t := _spawn_bike(path, Palette.NPC_HOME)
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
			var forward: bool = _segment_from_node.get(canonical) == path[i]
			_segments[canonical].set_on_route(true, player_index, forward)
	# NPC routes are recalculated the same round the player's are, so a
	# heatmap left open needs refreshing here too, not just on toggle.
	if _view_mode == ViewMode.NPC_HEATMAP:
		_show_npc_heatmap()


## Hides the players' own route bands and their flow arrows.
##
## Separate from ViewMode, which decides what the CENTRE LINE carries and whose
## options are mutually exclusive. This is the band drawn behind the road, it is
## independent of all three view modes, and it is personal rather than
## collective information, so it is available in every treatment.
##
## Static for the same reason hide_resident_visuals is: the legend needs to know
## which rows to draw without holding a reference to the grid.
static var hide_player_routes: bool = false


## Called by main.gd, wired to GameHUD's player-routes button. Applies to the
## segments already on the map, so it takes effect without rebuilding the grid.
func set_player_routes_hidden(is_hidden: bool) -> void:
	hide_player_routes = is_hidden
	_apply_player_route_visibility()


func _apply_player_route_visibility() -> void:
	for seg: LinkSegment in _segments.values():
		seg.set_routes_hidden(hide_player_routes)


## Called by main.gd, wired to GameHUD's resident-visuals button. Applies to
## markers already on the map, so it takes effect without rebuilding the grid.
func set_resident_visuals_hidden(is_hidden: bool) -> void:
	hide_resident_visuals = is_hidden
	_apply_resident_visibility()


## Hides the ICON only, never the marker. Every marker draws the road node's
## own intersection circle and the icon sits on top of it, so hiding the node
## would delete a junction from the map and leave a visible gap where roads
## meet.
func _apply_resident_visibility() -> void:
	for marker: NodeMarker in _markers.values():
		if marker.marker_type == NodeMarker.MarkerType.NPC_HOME \
				or marker.marker_type == NodeMarker.MarkerType.NPC_WORK:
			marker.set_icon_hidden(hide_resident_visuals)


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
