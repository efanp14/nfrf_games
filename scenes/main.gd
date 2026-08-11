extends Node2D
## Scene coordinator — thin glue between CityGrid, GameHUD, UpgradePopup, and GameManager.

@onready var city_grid: CityGrid = $CityGrid
@onready var game_hud            = $GameHUD as GameHUD
@onready var upgrade_popup       = $UpgradePopup as UpgradePopup
@onready var round_summary       = $RoundSummary as RoundSummary
@onready var end_screen          = $EndScreen as EndScreen
@onready var post_survey         = $PostSurvey as PostSurvey
@onready var chat_panel          = $ChatPanel as ChatPanel
@onready var pre_survey          = $PreSurvey as PreSurvey
@onready var main_menu           = $MainMenu as MainMenu
@onready var narrative_intro     = $NarrativeIntro as NarrativeIntro

var _pending_upgrades: Array = []
var _logger: DataLogger = null
var _pending_treatment: int = 0
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

## Layout of the map area. The HUD occupies a fixed strip down the left, so the
## map is fitted into what is left rather than into the whole window.
const HUD_LEFT: float = 240.0
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

## Temporarily disabled at the user's request — flip to true to bring the
## T3 "Planner Chat" panel back. ChatPanel defaults to hidden on its own
## (ChatPanel.gd:_ready), so leaving this false is enough to fully turn it
## off: it never becomes visible and never receives messages.
const CHAT_PANEL_ENABLED := false


func _enter_tree() -> void:
	RenderingServer.set_default_clear_color(Color(0.965, 0.945, 0.90))
	_logger = DataLogger.new()
	GameManager.add_child(_logger)
	GameManager.round_ended.connect(_logger.on_round_ended)
	GameManager.game_over.connect(_logger.on_game_over)


func _ready() -> void:
	get_tree().root.size_changed.connect(_on_viewport_resized)
	city_grid.link_clicked.connect(_on_link_clicked)
	game_hud.end_round_pressed.connect(_on_end_round)
	game_hud.view_mode_changed.connect(_on_view_mode_changed)
	game_hud.resident_visuals_toggled.connect(city_grid.set_resident_visuals_hidden)
	upgrade_popup.upgrade_chosen.connect(_on_upgrade_chosen)
	upgrade_popup.downgrade_requested.connect(_on_downgrade_requested)
	upgrade_popup.cancelled.connect(upgrade_popup.hide)
	round_summary.next_round_pressed.connect(_on_next_round)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.game_over.connect(_on_game_over)
	end_screen.finished.connect(_on_end_screen_finished)
	post_survey.survey_completed.connect(_on_post_survey_completed)
	pre_survey.survey_completed.connect(_on_survey_completed)
	main_menu.game_starting.connect(_on_game_starting)
	narrative_intro.narrative_finished.connect(_on_narrative_finished)


func _on_game_starting(treatment: int, num_players: int, participant_ids: Array, group_id: String) -> void:
	_pending_treatment = treatment
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
			and _pending_treatment == int(GameManager.Treatment.COLLECTIVE_CHAT)


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
			pre_survey.show_for_player(_current_survey_player, _num_players)
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
	_logger.on_consent_external()
	_logger.set_participant_identity(_participant_ids, _group_id, _treatment_ordinals)
	for i in range(_player_alphas.size()):
		_logger.on_pre_survey_completed(i + 1, _player_survey_responses[i], _player_alphas[i],
				_participant_ids[i], _alpha_sources[i])
		# Marks this treatment as played only once the game actually begins, so
		# a session abandoned at the menu does not consume a participant's slot
		# in the fixed treatment order.
		ParticipantStore.record_treatment(_participant_ids[i], int(GameManager.treatment))
	# Every session opens on the whole city, whatever the previous one left.
	_zoom_level = 1.0
	_center_grid()
	if CHAT_PANEL_ENABLED and GameManager.treatment == GameManager.Treatment.COLLECTIVE_CHAT:
		chat_panel.visible = true
		GameManager.chat_message_received.connect(chat_panel.add_message)


func _on_view_mode_changed(mode: int) -> void:
	city_grid.set_view_mode(mode)


func _on_link_clicked(link_id: String) -> void:
	if _round_summary_active:
		return
	upgrade_popup.show_for_link(link_id, _credits_remaining(), GameManager.human_player.alpha, _get_pending_level(link_id))


## Every branch below reports the action to GameManager.record_interaction()
## before returning: the confirmed upgrade list only captures the end state, so
## this is what preserves the ORDER links were picked in and any choice that
## was changed or withdrawn before the round was confirmed.
func _on_upgrade_chosen(link_id: String, level: int) -> void:
	for i: int in range(_pending_upgrades.size()):
		if _pending_upgrades[i]["link_id"] == link_id:
			GameManager.record_interaction(GameManager.ACTION_CHANGE_LEVEL, link_id, level)
			_pending_upgrades[i]["level"] = level
			city_grid.preview_link(link_id, level)
			game_hud.update_budget(_credits_remaining())
			return
	GameManager.record_interaction(GameManager.ACTION_SELECT, link_id, level)
	_pending_upgrades.append({ "link_id": link_id, "level": level })
	city_grid.preview_link(link_id, level)
	game_hud.update_budget(_credits_remaining())


func _on_downgrade_requested(link_id: String) -> void:
	for i: int in range(_pending_upgrades.size()):
		if _pending_upgrades[i]["link_id"] == link_id:
			GameManager.record_interaction(
				GameManager.ACTION_UNSTAGE, link_id, _pending_upgrades[i]["level"])
			_pending_upgrades.remove_at(i)
			city_grid.preview_link(link_id, -1)
			game_hud.update_budget(_credits_remaining())
			return
	GameManager.record_interaction(GameManager.ACTION_STAGE_REMOVAL, link_id, 0)
	_pending_upgrades.append({ "link_id": link_id, "level": 0 })
	city_grid.preview_link(link_id, 0)
	game_hud.update_budget(_credits_remaining())


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
	post_survey.show_survey(int(GameManager.treatment), 1, _num_players)


## In T3, each group member completes their own post-survey in turn (same
## pattern as the pre-survey loop) so DQI responses stay attributable to an
## individual rather than one shared submission for the whole group.
func _on_post_survey_completed(player_num: int, responses: Dictionary) -> void:
	var pid: String = _participant_ids[player_num - 1] if player_num - 1 < _participant_ids.size() else ""
	_logger.on_post_survey_completed(player_num, _num_players, pid, responses)
	if player_num < _num_players:
		post_survey.show_survey(int(GameManager.treatment), player_num + 1, _num_players)
	else:
		get_tree().reload_current_scene()


func _on_end_round() -> void:
	if not GameManager.game_running:
		return
	GameManager.submit_upgrades(_pending_upgrades)
	_pending_upgrades.clear()
	city_grid.refresh_all()


func _credits_remaining() -> int:
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
		GameManager.human_player.credits_per_round,
		GameManager.human_player.credits_per_round - net_spent
	)


## The map's extent in city_grid's own local space. The background image is a
## child of city_grid, so it scales and moves in lockstep and needs no separate
## handling.
func _map_bounds() -> Rect2:
	return GameManager.network.get_bounds().grow(VISUAL_MARGIN)


## The area of the window the map is allowed to occupy.
##
## The sidebar's real width is measured rather than assumed. HUD_LEFT is only a
## floor: the sidebar is a PanelContainer, so it grows past its 240px offset
## whenever its contents demand more, and the group treatment is where that is
## most likely, since the legend gains a row per player. A hardcoded 240 would
## then leave the map running underneath it with roads hidden behind the panel.
func _map_viewport() -> Rect2:
	var vp: Vector2 = get_viewport_rect().size
	# HUD_LEFT until the HUD exists, which is only during the first frames.
	var left: float = HUD_LEFT
	if game_hud != null:
		left = maxf(HUD_LEFT, game_hud.sidebar_width())
	return Rect2(
		Vector2(left + PAD, PAD),
		Vector2(vp.x - left - PAD * 2.0, vp.y - PAD * 2.0)
	)


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


func _on_viewport_resized() -> void:
	if GameManager.game_running:
		_center_grid()


func _get_pending_level(link_id: String) -> int:
	for req: Dictionary in _pending_upgrades:
		if req["link_id"] == link_id:
			return req["level"]
	return -1
