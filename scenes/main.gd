extends Node2D
## Scene coordinator: runs a session on main.tscn. The menu and survey flow,
## chaining T1 into T2, staging upgrades before they are bought, and the map
## camera (zoom, pan, pinch) all live here, alongside the wiring between
## CityGrid, GameHUD, UpgradePopup and GameManager.

# `= $X as T` leaves the variable Variant; the annotation has to be on the
# left to get a checked type. All nine were `as`-cast except city_grid.
@onready var city_grid: CityGrid            = $CityGrid
@onready var game_hud: GameHUD              = $GameHUD
@onready var upgrade_popup: UpgradePopup    = $UpgradePopup
@onready var round_summary: RoundSummary    = $RoundSummary
@onready var end_screen: EndScreen          = $EndScreen
@onready var post_survey: PostSurvey        = $PostSurvey
@onready var pre_survey: PreSurvey          = $PreSurvey
@onready var main_menu: MainMenu            = $MainMenu
@onready var narrative_intro: NarrativeIntro = $NarrativeIntro

var _pending_upgrades: Array = []
var _logger: DataLogger = null
var _pending_treatment: int = 0
## Study, pilot or test: chosen at the menu and carried into the log, so a
## development run can be filtered out of the data afterwards.
var _session_kind: String = ResearchConfig.DEFAULT_SESSION_KIND
## Latched once the end-of-session reload is under way, so a dialog that emits
## more than one dismissal signal cannot trigger it twice.
var _reloading: bool = false

## Fingers currently down, by touch index, for the two-finger map gestures.
var _touch_points: Dictionary = {}
var _pinch_distance: float = 0.0
var _pinch_midpoint: Vector2 = Vector2.ZERO
var _pinch_zoom: float = 1.0
## How long roads stay deaf to taps after a gesture touches them. Long enough
## to cover two fingers lifting a moment apart, short enough that a deliberate
## tap straight after a pinch still lands.
const GESTURE_LOCKOUT_MS: int = 220
var _num_players: int = 1
var _player_alphas: Array[float] = []
var _player_survey_responses: Array = []
## The IDs the researcher typed, one per player, exactly as entered.
var _participant_ids: Array[String] = []
## The group they were entered under. Recorded on every row, and what links a
## group discussion recorded on a separate device back to these rounds.
var _group_id: String = ""
## Where each player's personality value came from this session: answered here,
## or reused from an earlier session on this machine. Logged so analysis never
## has to infer it.
var _alpha_sources: Array[String] = []
## Whether this is each participant's first, second or third treatment.
var _treatment_ordinals: Array[int] = []
var _current_survey_player: int = 0
var _round_summary_active: bool = false
## Set when the researcher picked the chained menu entry. T2 is queued only
## after T1's post-survey is submitted, so an abandoned T1 leaves nothing behind.
var _chain_to_t2: bool = false
## The session this one follows on from, empty unless this IS the follow-on half
## of a chained sitting. Recorded so "these two folders were one sitting" is a
## fact in the data rather than something inferred from adjacent timestamps.
var _chained_from_session_id: String = ""

## Layout of the map area. The HUD floats over the board rather than taking a
## strip of it, so the map is fitted to the whole window less a margin and the
## cards sit on top.
const PAD: float      = 20.0
## get_bounds() only spans node CENTER positions. Roads (half-width), node
## shadows and rims, and especially the building icons (towers rise up to ~45px
## above their node) all draw beyond that, so the bounds are grown before
## fitting. Without it the outermost roads and buildings sit flush against the
## viewport edge and read as cropped.
const VISUAL_MARGIN: float = 50.0

## How far the map can be magnified past the fitted view. 1.0 is the whole city
## on screen, which is where every round starts; scrolling back down to 1.0 is
## the reset, so no separate reset control is needed.
const ZOOM_MIN:  float = 1.0
const ZOOM_MAX:  float = 2.5
const ZOOM_STEP: float = 1.12

var _zoom_level: float = 1.0


func _enter_tree() -> void:
	RenderingServer.set_default_clear_color(Palette.MAP_BACKGROUND)
	_logger = DataLogger.new()
	# Parented to THIS scene, not to the GameManager autoload. One logger is one
	# session, and a session is one scene: the logger is last used by
	# on_post_survey_completed, which runs before the reload. Parenting it to the
	# autoload instead left it alive after reload_current_scene(), still
	# connected to round_ended, so a second session's rounds were appended to the
	# FIRST session's files while a fresh logger wrote them again to its own.
	# Chaining T1 into T2 reloads every time, so this has to be right.
	add_child(_logger)
	GameManager.round_ended.connect(_logger.on_round_ended)
	GameManager.game_over.connect(_logger.on_game_over)


## Two things a tablet does by default that would end a session.
##
## A tablet dims and sleeps on its own, and a round can sit untouched for
## minutes while a group argues about it. Keeping the screen on for the whole
## app rather than only during play, because a researcher setting up at the menu
## should not have it go dark either.
##
## The back gesture quits a Godot app outright. Mid-session that ends the
## session, and on a touch screen it is a swipe from the edge, which is to say
## an accident waiting to happen with three people reaching across one tablet.
## Turning off quit-on-back makes the gesture do nothing at all; there is no
## screen in this game that a participant should be navigating backwards out of.
##
## Both are no-ops on desktop, so this runs unconditionally rather than behind a
## platform check that would go stale.
func _configure_for_device() -> void:
	DisplayServer.screen_set_keep_on(true)
	get_tree().set_quit_on_go_back(false)


func _ready() -> void:
	_configure_for_device()
	get_tree().root.size_changed.connect(_on_viewport_resized)
	city_grid.link_clicked.connect(_on_link_clicked)
	game_hud.end_round_pressed.connect(_on_end_round)
	game_hud.view_mode_changed.connect(_on_view_mode_changed)
	game_hud.resident_visuals_toggled.connect(city_grid.set_resident_visuals_hidden)
	game_hud.player_routes_toggled.connect(city_grid.set_player_routes_hidden)
	game_hud.display_toggled.connect(_logger.on_display_toggled)
	game_hud.instructions_pressed.connect(
			func(): narrative_intro.reopen(int(GameManager.treatment)))
	upgrade_popup.upgrade_chosen.connect(_on_upgrade_chosen)
	upgrade_popup.downgrade_requested.connect(_on_downgrade_requested)
	upgrade_popup.cancelled.connect(_on_upgrade_cancelled)
	round_summary.next_round_pressed.connect(_on_next_round)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.game_over.connect(_on_game_over)
	end_screen.finished.connect(_on_end_screen_finished)
	post_survey.survey_completed.connect(_on_post_survey_completed)
	pre_survey.survey_completed.connect(_on_survey_completed)
	main_menu.game_starting.connect(_on_game_starting)
	narrative_intro.narrative_finished.connect(_on_narrative_finished)
	_start_queued_treatment_if_any()


## A chained session reloads the scene between treatments (see SessionQueue for
## why a reload rather than an in-place reset), so the follow-on treatment picks
## up here instead of at the menu, with the identity the researcher already
## entered. Runs after every child's _ready(), which is what lets it override
## MainMenu._ready() having just made itself visible.
func _start_queued_treatment_if_any() -> void:
	if not SessionQueue.has_pending():
		return
	var queued: Dictionary = SessionQueue.take()
	main_menu.hide()
	# chain_to_t2 false: this IS the follow-on, so it queues nothing further.
	_on_game_starting(queued["treatment"], queued["num_players"],
			queued["participant_ids"], queued["group_id"], false,
			str(queued.get("session_kind", ResearchConfig.DEFAULT_SESSION_KIND)),
			str(queued.get("from_session_id", "")))


func _on_game_starting(treatment: int, num_players: int, participant_ids: Array,
		group_id: String, chain_to_t2: bool = false,
		session_kind: String = ResearchConfig.DEFAULT_SESSION_KIND,
		from_session_id: String = "") -> void:
	_pending_treatment = treatment
	_session_kind = ResearchConfig.session_kind_or_default(session_kind)
	_chain_to_t2 = chain_to_t2
	_chained_from_session_id = from_session_id
	_num_players = num_players
	_player_alphas.clear()
	_player_survey_responses.clear()
	_alpha_sources.clear()
	_treatment_ordinals.clear()
	_group_id = group_id
	# Participant IDs are ENTERED, not generated. The session ID still
	# identifies this run, but it cannot identify a person: someone playing
	# their second treatment starts a new session, and previously the two had
	# nothing in common, so their sessions could not be joined afterwards.
	_participant_ids.clear()
	for id in participant_ids:
		var pid := str(id)
		_participant_ids.append(pid)
		# Read before the treatment is recorded, so it counts what came before.
		_treatment_ordinals.append(ParticipantStore.next_treatment_ordinal(pid))
	_current_survey_player = 1
	# Consent is collected outside the game, in person, so the session opens
	# straight onto the first survey. The log still records that consent was
	# handled externally rather than dropping the field entirely.
	_advance_survey_queue()


## True when this session assigns the average personality instead of measuring
## it. The single treatment branch that touches a routing input; see
## ResearchConfig.GROUP_TREATMENT_USES_DEFAULT_ALPHA for why it is allowed.
func _uses_default_alpha() -> bool:
	return ResearchConfig.GROUP_TREATMENT_USES_DEFAULT_ALPHA \
			and _pending_treatment == int(GameManager.Treatment.GROUP_DISCUSSION)


## Walks the players in order, asking the opening survey only of those this
## machine has no record for.
##
## The rule is deliberately "do we already know this participant", not "is this
## treatment 1". A person returning for their second treatment on their own
## machine is recognised and skipped; the shared group-session machine has never
## seen them, so it asks. That is the intended behaviour in both cases today,
## and it needs no branch on treatment to get there.
func _advance_survey_queue() -> void:
	# The group treatment skips the survey outright and assigns everyone the
	# average personality (owner, 5 Aug 2026). Applied to every player rather
	# than only to those with no record, so the whole group runs at the same
	# sensitivity instead of one member differing because they happened to play
	# an earlier treatment on this particular machine.
	if _uses_default_alpha():
		while _player_alphas.size() < _num_players:
			_player_alphas.append(PersonalityConfig.ALPHA_AVERAGE)
			_player_survey_responses.append({})
			_alpha_sources.append(ParticipantStore.SOURCE_DEFAULT)
		pre_survey.hide()
		narrative_intro.show_narrative(_pending_treatment)
		return

	while _player_alphas.size() < _num_players:
		var idx: int = _player_alphas.size()
		var record: Dictionary = ParticipantStore.load_record(_participant_ids[idx])
		if record.is_empty():
			_current_survey_player = idx + 1
			pre_survey.show_for_player(_current_survey_player, _num_players,
					_participant_id_for(_current_survey_player))
			return
		# Known participant: reuse the value measured the first time. Asking
		# again risks a different answer pushing them across a personality
		# threshold, which would leave their two sessions incomparable.
		_player_alphas.append(float(record["alpha"]))
		_player_survey_responses.append(record.get("responses", {}))
		_alpha_sources.append(ParticipantStore.SOURCE_STORED)

	pre_survey.hide()
	narrative_intro.show_narrative(_pending_treatment)


func _on_survey_completed(alpha: float, responses: Dictionary) -> void:
	var idx: int = _player_alphas.size()
	_player_alphas.append(alpha)
	_player_survey_responses.append(responses)
	_alpha_sources.append(ParticipantStore.SOURCE_SURVEY)
	# Persist immediately rather than at the end of the session: a session
	# abandoned midway should not cost a participant their survey.
	ParticipantStore.save_survey(_participant_ids[idx], alpha, responses)
	_advance_survey_queue()


## Fires once the player(s) have clicked through the welcome + treatment
## orientation screens (NarrativeIntro) — only then does the game itself
## actually start, so round_started/city_grid build behind a screen the
## player has already dismissed rather than behind one still covering it.
func _on_narrative_finished() -> void:
	GameManager.start_game(_player_alphas, _pending_treatment)
	_logger.treatment = int(GameManager.treatment)
	# Set before the identity, which is what composes the folder name: a
	# non-study session is named so it can be spotted without opening it.
	_logger.session_kind = _session_kind
	# Taken after start_game(), so the network exists and its fingerprint can be
	# recorded along with the rest of the settings this session ran under.
	_logger.game_parameters = GameManager.session_parameters()
	_logger.network_tables  = GameManager.network_tables()
	_logger.on_consent_external()
	_logger.set_participant_identity(_participant_ids, _group_id, _treatment_ordinals,
			_chained_from_session_id)
	for i in range(_player_alphas.size()):
		_logger.on_pre_survey_completed(i + 1, _player_survey_responses[i], _player_alphas[i],
				_participant_ids[i], _alpha_sources[i])
		# Marks this treatment as played only once the game actually begins, so
		# a session abandoned at the menu does not consume a participant's slot
		# in the fixed treatment order.
		ParticipantStore.record_treatment(_participant_ids[i], int(GameManager.treatment))
	# The session folder appears on disk here, before round 1 rather than after
	# the closing survey, so a session that ends unexpectedly still leaves the
	# settings it ran under and every round it completed.
	_logger.begin_session()
	# Every session opens on the whole city, whatever the previous one left.
	_zoom_level = 1.0
	_center_grid()


func _on_view_mode_changed(mode: int) -> void:
	city_grid.set_view_mode(mode)


func _on_link_clicked(link_id: String) -> void:
	if _round_summary_active:
		return
	# Mark the road before the popup covers it. Hover cannot do this job: it is
	# driven by mouse motion, so on the tablet there was no indication at all of
	# which road the open panel belonged to.
	game_hud.dismiss_hint()
	city_grid.set_selected_link(link_id)
	upgrade_popup.show_for_link(link_id, _budget_remaining(), GameManager.human_player.alpha, _get_pending_level(link_id))


## Every branch below reports the action to GameManager.record_interaction()
## before returning: the confirmed upgrade list only captures the end state, so
## this is what preserves the ORDER links were picked in and any choice that
## was changed or withdrawn before the round was confirmed.
## Every route out of the popup clears the selection, so a road can never be
## left marked with nothing open about it.
func _on_upgrade_cancelled() -> void:
	upgrade_popup.hide()
	city_grid.set_selected_link("")


func _on_upgrade_chosen(link_id: String, level: int) -> void:
	city_grid.set_selected_link("")
	for i: int in range(_pending_upgrades.size()):
		if _pending_upgrades[i]["link_id"] == link_id:
			GameManager.record_interaction(GameManager.ACTION_CHANGE_LEVEL, link_id, level)
			_pending_upgrades[i]["level"] = level
			city_grid.preview_link(link_id, level)
			game_hud.update_budget(_budget_remaining())
			return
	GameManager.record_interaction(GameManager.ACTION_SELECT, link_id, level)
	_pending_upgrades.append({ "link_id": link_id, "level": level })
	city_grid.preview_link(link_id, level)
	game_hud.update_budget(_budget_remaining())


func _on_downgrade_requested(link_id: String) -> void:
	city_grid.set_selected_link("")
	for i: int in range(_pending_upgrades.size()):
		if _pending_upgrades[i]["link_id"] == link_id:
			GameManager.record_interaction(
				GameManager.ACTION_UNSTAGE, link_id, _pending_upgrades[i]["level"])
			_pending_upgrades.remove_at(i)
			city_grid.preview_link(link_id, -1)
			game_hud.update_budget(_budget_remaining())
			return
	GameManager.record_interaction(GameManager.ACTION_STAGE_REMOVAL, link_id, 0)
	_pending_upgrades.append({ "link_id": link_id, "level": 0 })
	city_grid.preview_link(link_id, 0)
	game_hud.update_budget(_budget_remaining())


func _on_round_ended(round_num: int, results: Dictionary) -> void:
	_round_summary_active = true
	var is_last := round_num >= GameManager.total_rounds
	await city_grid.play_round_end_animation()
	round_summary.show_results(results, int(GameManager.treatment), is_last)


func _on_next_round() -> void:
	_round_summary_active = false
	city_grid.clear_all_previews()
	GameManager.advance_round()


func _on_game_over(final_results: Dictionary) -> void:
	end_screen.show_results(final_results)


func _on_end_screen_finished() -> void:
	post_survey.show_survey(int(GameManager.treatment), 1, _num_players,
			_participant_id_for(1))


## The ID to SHOW on a survey, so a group sharing one screen can tell whose turn
## it is. Empty for a session run without IDs, which the banner handles by naming
## the seat alone. Deliberately separate from the ID passed to the logger: this
## one is display, and it must never be the reason a row is attributed.
func _participant_id_for(player_num: int) -> String:
	var idx: int = player_num - 1
	return _participant_ids[idx] if idx >= 0 and idx < _participant_ids.size() else ""


## In T3, each group member completes their own post-survey in turn (same
## pattern as the pre-survey loop) so DQI responses stay attributable to an
## individual rather than one shared submission for the whole group.
func _on_post_survey_completed(player_num: int, responses: Dictionary) -> void:
	var pid: String = _participant_ids[player_num - 1] if player_num - 1 < _participant_ids.size() else ""
	_logger.on_post_survey_completed(player_num, _num_players, pid, responses)
	if player_num < _num_players:
		post_survey.show_survey(int(GameManager.treatment), player_num + 1, _num_players,
				_participant_id_for(player_num + 1))
		return
	# Everyone has answered, so the survey comes down here rather than inside
	# PostSurvey itself: it is still needed right up to this point, once per
	# group member.
	post_survey.hide()
	# Queued here rather than at the menu so the follow-on treatment exists only
	# once the first one is genuinely finished and its survey recorded. T2 gets
	# its own session ID, folder and summary row; the two are joined afterwards
	# by participant ID, which keeps the one-row-per-session schema intact.
	if _chain_to_t2:
		SessionQueue.queue_next(int(GameManager.Treatment.COLLECTIVE_INFO),
				_participant_ids, _group_id, _num_players, _logger.session_id,
				_session_kind)
	# Everything is on disk by now: on_post_survey_completed writes the events,
	# the analysis tables and the summary before returning. So this is the first
	# moment the folder can be reported honestly, and the last moment anyone is
	# looking at this session.
	_confirm_session_saved_then_reload()


## Shows the researcher what the session wrote, and moves on only once they have
## seen it.
##
## The reload is deferred behind the dialog rather than run alongside it: a
## chained sitting would otherwise start the second treatment over the top of
## the confirmation for the first, which is the case where losing the data
## quietly would cost the most.
func _confirm_session_saved_then_reload() -> void:
	var dialog := SessionSavedDialog.new()
	add_child(dialog)
	dialog.confirmed.connect(_reload_after_confirmation)
	dialog.canceled.connect(_reload_after_confirmation)
	dialog.show_for(_logger.session_report())


## Guarded because AcceptDialog can emit both confirmed and canceled for one
## dismissal depending on how it is closed, and reloading twice would restart a
## session that had already begun.
func _reload_after_confirmation() -> void:
	if _reloading:
		return
	_reloading = true
	get_tree().reload_current_scene()


func _on_end_round() -> void:
	if not GameManager.game_running:
		return
	GameManager.submit_upgrades(_pending_upgrades)
	_pending_upgrades.clear()
	city_grid.refresh_all()


func _budget_remaining() -> int:
	var net_spent: int = 0
	for req: Dictionary in _pending_upgrades:
		var link: CityNetwork.Link = GameManager.network.links.get(req["link_id"])
		if link == null:
			continue
		if req["level"] == 0:
			if link.upgrade_level > 0:
				net_spent -= Player.cost_for_link(link, link.upgrade_level)
		elif req["level"] > link.upgrade_level:
			net_spent += Player.cost_for_link(link, req["level"])
	return mini(
		GameManager.human_player.budget_per_round,
		GameManager.human_player.budget_per_round - net_spent
	)


## The map's extent in city_grid's own local space. The background image is a
## child of city_grid, so it scales and moves in lockstep and needs no separate
## handling.
func _map_bounds() -> Rect2:
	return GameManager.network.get_bounds().grow(VISUAL_MARGIN)


## The area of the window the map is allowed to occupy: all of it, less a margin.
##
## This used to subtract the sidebar's measured width so the map sat beside the
## HUD. The HUD is now floating cards in the corners, and letting the board run
## underneath them is the point of that change: the map is the game, and it was
## permanently confined to about 87% of the window, less in the group treatment
## where the sidebar grew a legend row per seat.
##
## The cards are small and cornered, and _map_bounds() grows the network by
## VISUAL_MARGIN before fitting, so what actually ends up beneath a card is
## margin rather than road.
func _map_viewport() -> Rect2:
	var vp: Vector2 = get_viewport_rect().size
	return Rect2(Vector2(PAD, PAD), vp - Vector2(PAD, PAD) * 2.0)


## Scale at which the whole city just fits. Zoom multiplies this rather than
## replacing it, so a zoom level means the same thing at any window size.
func _fit_scale() -> float:
	var bounds: Rect2 = _map_bounds()
	var avail: Rect2 = _map_viewport()
	return minf(avail.size.x / bounds.size.x, avail.size.y / bounds.size.y)


## Keeps the map covering the visible area so it can never be scrolled off into
## empty space. Anything smaller than the area is centred in it instead, which
## is what produces the fitted view at zoom 1.0.
func _clamped_position(pos: Vector2, scale_factor: float) -> Vector2:
	var bounds: Rect2 = _map_bounds()
	var avail: Rect2 = _map_viewport()
	var map_size: Vector2 = bounds.size * scale_factor
	var out: Vector2 = pos
	for axis in 2:
		# Where the map's top-left corner lands on screen for this position.
		var origin: float = pos[axis] + bounds.position[axis] * scale_factor
		if map_size[axis] <= avail.size[axis]:
			origin = avail.position[axis] + (avail.size[axis] - map_size[axis]) / 2.0
		else:
			origin = clampf(origin,
				avail.position[axis] + avail.size[axis] - map_size[axis],
				avail.position[axis])
		out[axis] = origin - bounds.position[axis] * scale_factor
	return out


## Fits the city to the window at the current zoom level. Called at game start
## and on resize; zoom is preserved across both, only the framing is redone.
func _center_grid() -> void:
	var scale_factor: float = _fit_scale() * _zoom_level
	city_grid.scale = Vector2(scale_factor, scale_factor)
	city_grid.position = _clamped_position(city_grid.position, scale_factor)


## Zooms about `focus` (the pointer), so whatever is under the cursor stays put
## while the rest of the city grows outward from it. Without pan support this
## doubles as the way to navigate: point at a district and scroll in.
func _zoom_at(new_zoom: float, focus: Vector2) -> void:
	new_zoom = clampf(new_zoom, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, _zoom_level):
		return
	var old_scale: float = city_grid.scale.x
	var new_scale: float = _fit_scale() * new_zoom
	_zoom_level = new_zoom
	city_grid.scale = Vector2(new_scale, new_scale)
	city_grid.position = _clamped_position(
		focus - (focus - city_grid.position) * (new_scale / old_scale), new_scale)


func _unhandled_input(event: InputEvent) -> void:
	if not GameManager.game_running:
		return
	if _handle_touch(event):
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	# Events over the HUD or an open dialog are consumed by those Controls
	# before reaching here, so scrolling only ever zooms the map itself.
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(_zoom_level * ZOOM_STEP, mb.position)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(_zoom_level / ZOOM_STEP, mb.position)
		get_viewport().set_input_as_handled()


## Two-finger pinch to zoom and two-finger drag to pan.
##
## Returns true when the event was a touch the map has taken responsibility for.
##
## One finger is deliberately left alone: it selects a road, which is the game's
## only action, and a map where a stray finger slides the city under you while
## you are trying to press a street is worse than one that cannot be panned.
## Two fingers is the gesture nobody performs by accident.
##
## Android sends no magnify gesture, so the pinch is measured by hand from the
## two touch points. Zoom is anchored to the midpoint between the fingers, the
## same way the mouse wheel anchors to the pointer, so the city grows out of
## the place being pinched rather than out of the middle of the screen.
func _handle_touch(event: InputEvent) -> bool:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_touch_points[touch.index] = touch.position
		else:
			_touch_points.erase(touch.index)
		if _touch_points.size() >= 2:
			_begin_pinch()
		elif _touch_points.size() < 2:
			_pinch_distance = 0.0
			# Held briefly after the fingers leave, because they lift a few
			# milliseconds apart and the last one would otherwise register as a
			# tap on whatever road it happened to be over.
			if not touch.pressed:
				MapGestures.lock(GESTURE_LOCKOUT_MS)
		return _touch_points.size() >= 2

	var drag := event as InputEventScreenDrag
	if drag == null:
		return false
	if not _touch_points.has(drag.index):
		return false
	_touch_points[drag.index] = drag.position
	if _touch_points.size() < 2:
		return false

	var keys: Array = _touch_points.keys()
	keys.sort()
	var a: Vector2 = _touch_points[keys[0]]
	var b: Vector2 = _touch_points[keys[1]]
	var midpoint: Vector2 = (a + b) * 0.5
	var distance: float = a.distance_to(b)

	if _pinch_distance > 0.0 and distance > 0.0:
		# Pan first, then zoom about the new midpoint, so a gesture that both
		# spreads and slides does both rather than fighting itself.
		var pan: Vector2 = midpoint - _pinch_midpoint
		if pan.length_squared() > 0.0:
			city_grid.position = _clamped_position(city_grid.position + pan,
					city_grid.scale.x)
		_zoom_at(_pinch_zoom * (distance / _pinch_distance), midpoint)

	_pinch_midpoint = midpoint
	MapGestures.lock(GESTURE_LOCKOUT_MS)
	get_viewport().set_input_as_handled()
	return true


## Records where a pinch started, so the zoom is measured against the moment the
## second finger landed rather than accumulating rounding drift frame by frame.
func _begin_pinch() -> void:
	var keys: Array = _touch_points.keys()
	keys.sort()
	var a: Vector2 = _touch_points[keys[0]]
	var b: Vector2 = _touch_points[keys[1]]
	_pinch_distance = maxf(a.distance_to(b), 1.0)
	_pinch_midpoint = (a + b) * 0.5
	_pinch_zoom = _zoom_level
	MapGestures.lock(GESTURE_LOCKOUT_MS)


func _on_viewport_resized() -> void:
	if GameManager.game_running:
		_center_grid()


func _get_pending_level(link_id: String) -> int:
	for req: Dictionary in _pending_upgrades:
		if req["link_id"] == link_id:
			return req["level"]
	return -1
