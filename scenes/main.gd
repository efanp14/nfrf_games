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
@onready var consent_screen      = $ConsentScreen as ConsentScreen

var _pending_upgrades: Array = []
var _logger: DataLogger = null
var _pending_treatment: int = 0
var _num_players: int = 1
var _player_alphas: Array[float] = []
var _player_survey_responses: Array = []
var _current_survey_player: int = 0
var _round_summary_active: bool = false
var _consent_timestamp_s: float = -1.0

## Temporarily disabled at the user's request — flip to true to bring the
## T3 "Planner Chat" panel back. ChatPanel defaults to hidden on its own
## (ChatPanel.gd:_ready), so leaving this false is enough to fully turn it
## off: it never becomes visible and never receives messages.
const CHAT_PANEL_ENABLED := false


func _enter_tree() -> void:
	RenderingServer.set_default_clear_color(Color(0.96, 0.94, 0.91))
	_logger = DataLogger.new()
	GameManager.add_child(_logger)
	GameManager.round_ended.connect(_logger.on_round_ended)
	GameManager.game_over.connect(_logger.on_game_over)


func _ready() -> void:
	get_tree().root.size_changed.connect(_on_viewport_resized)
	city_grid.link_clicked.connect(_on_link_clicked)
	game_hud.end_round_pressed.connect(_on_end_round)
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
	consent_screen.consent_given.connect(_on_consent_given)
	consent_screen.consent_declined.connect(_on_consent_declined)


func _on_game_starting(treatment: int, num_players: int) -> void:
	_pending_treatment = treatment
	_num_players = num_players
	_player_alphas.clear()
	_player_survey_responses.clear()
	_current_survey_player = 1
	consent_screen.show_consent()


func _on_consent_given() -> void:
	# Treatment isn't known to the logger yet (set below, once pre-surveys
	# finish), so the timestamp is captured now and the actual log entry is
	# written later — same deferral pattern as pre-survey responses.
	_consent_timestamp_s = Time.get_ticks_msec() / 1000.0
	pre_survey.show_for_player(1, _num_players)


func _on_consent_declined() -> void:
	main_menu.show()


func _on_survey_completed(alpha: float, responses: Dictionary) -> void:
	_player_alphas.append(alpha)
	_player_survey_responses.append(responses)
	if _player_alphas.size() < _num_players:
		_current_survey_player += 1
		pre_survey.show_for_player(_current_survey_player, _num_players)
		return

	pre_survey.hide()
	GameManager.start_game(_player_alphas, _pending_treatment)
	_logger.treatment = int(GameManager.treatment)
	_logger.on_consent_given(_consent_timestamp_s)
	for i in range(_player_alphas.size()):
		_logger.on_pre_survey_completed(i + 1, _player_survey_responses[i], _player_alphas[i])
	_center_grid()
	if CHAT_PANEL_ENABLED and GameManager.treatment == GameManager.Treatment.COLLECTIVE_CHAT:
		chat_panel.visible = true
		GameManager.chat_message_received.connect(chat_panel.add_message)


func _on_link_clicked(link_id: String) -> void:
	if _round_summary_active:
		return
	upgrade_popup.show_for_link(link_id, _credits_remaining(), GameManager.human_player.alpha, _get_pending_level(link_id))


func _on_upgrade_chosen(link_id: String, level: int) -> void:
	for i: int in range(_pending_upgrades.size()):
		if _pending_upgrades[i]["link_id"] == link_id:
			_pending_upgrades[i]["level"] = level
			city_grid.preview_link(link_id, level)
			game_hud.update_budget(_credits_remaining())
			return
	_pending_upgrades.append({ "link_id": link_id, "level": level })
	city_grid.preview_link(link_id, level)
	game_hud.update_budget(_credits_remaining())


func _on_downgrade_requested(link_id: String) -> void:
	for i: int in range(_pending_upgrades.size()):
		if _pending_upgrades[i]["link_id"] == link_id:
			_pending_upgrades.remove_at(i)
			city_grid.preview_link(link_id, -1)
			game_hud.update_budget(_credits_remaining())
			return
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
	post_survey.show_survey(int(GameManager.treatment))


func _on_post_survey_completed(responses: Dictionary) -> void:
	_logger.on_post_survey_completed(responses)
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
				net_spent -= Player.COST_PAINTED_LANE if link.upgrade_level == 1 \
						else Player.COST_PROTECTED_TRACK
		elif req["level"] > link.upgrade_level:
			net_spent += Player.COST_PAINTED_LANE if req["level"] == 1 \
					else Player.COST_PROTECTED_TRACK
	return mini(
		GameManager.human_player.credits_per_round,
		GameManager.human_player.credits_per_round - net_spent
	)


func _center_grid() -> void:
	const HUD_LEFT: float = 240.0
	const PAD: float      = 20.0
	var vp: Vector2 = get_viewport_rect().size
	var bounds: Rect2 = GameManager.network.get_bounds()
	var map_w: float = bounds.size.x
	var map_h: float = bounds.size.y
	var avail_w: float = vp.x - HUD_LEFT - PAD * 2.0
	var avail_h: float = vp.y - PAD * 2.0
	var scale_factor: float = minf(avail_w / map_w, avail_h / map_h)
	city_grid.scale = Vector2(scale_factor, scale_factor)
	var scaled_w: float = map_w * scale_factor
	var scaled_h: float = map_h * scale_factor
	city_grid.position = Vector2(
		HUD_LEFT + PAD + (avail_w - scaled_w) / 2.0 - bounds.position.x * scale_factor,
		PAD + (avail_h - scaled_h) / 2.0 - bounds.position.y * scale_factor
	)


func _on_viewport_resized() -> void:
	if GameManager.game_running:
		_center_grid()


func _get_pending_level(link_id: String) -> int:
	for req: Dictionary in _pending_upgrades:
		if req["link_id"] == link_id:
			return req["level"]
	return -1
