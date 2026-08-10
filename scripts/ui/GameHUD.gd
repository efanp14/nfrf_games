class_name GameHUD
extends CanvasLayer

signal end_round_pressed
signal city_view_toggled(show_npc_heatmap: bool)

@onready var round_label: Label         = %RoundLabel
@onready var budget_label: Label        = %BudgetLabel
@onready var time_label: Label          = %TimeLabel
@onready var safety_label: Label        = %SafetyLabel
@onready var city_panel: VBoxContainer  = %CityPanel
@onready var city_time_label: Label     = %CityTimeLabel
@onready var city_safety_label: Label   = %CitySafetyLabel
@onready var coverage_label: Label      = %CoverageLabel
@onready var benefit_label: Label       = %BenefitLabel
@onready var city_view_button: Button   = %CityViewButton
@onready var end_round_button: Button   = %EndRoundButton
@onready var debug_button: Button       = %DebugButton

## Cached so toggling debug mode can re-render immediately without waiting
## for the next GameManager signal.
var _last_round_results: Dictionary = {}
var _last_city_metrics: Dictionary = {}

## T2/T3 only — lets a player switch the map between their own highlighted
## route (default) and a green→red heatmap of how heavily the simulated
## residents use each street, so "the collective" is visible as a single
## clean picture instead of dozens of overlapping individual paths.
var _showing_npc_heatmap: bool = false


func _ready() -> void:
	end_round_button.pressed.connect(func(): end_round_pressed.emit())
	debug_button.pressed.connect(_on_debug_pressed)
	city_view_button.pressed.connect(_on_city_view_pressed)
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.city_metrics_updated.connect(_on_city_metrics_updated)
	GameManager.game_over.connect(_on_game_over)
	_sync_initial_state()


func _on_city_view_pressed() -> void:
	_showing_npc_heatmap = not _showing_npc_heatmap
	city_view_button.text = "View: My Route" if _showing_npc_heatmap else "View: City Routes"
	city_view_toggled.emit(_showing_npc_heatmap)


func _on_debug_pressed() -> void:
	SafetyDisplay.debug_mode = not SafetyDisplay.debug_mode
	debug_button.text = "Debug: ON" if SafetyDisplay.debug_mode else "Debug: OFF"
	if not _last_round_results.is_empty():
		_render_personal(_last_round_results)
	if not _last_city_metrics.is_empty():
		_render_city(_last_city_metrics)


func _sync_initial_state() -> void:
	if not GameManager.game_running:
		return
	round_label.text  = "Round %d / %d" % [GameManager.current_round, GameManager.total_rounds]
	budget_label.text = "Budget: " + Player.format_dollars(GameManager.human_player.credits_per_round)
	city_panel.visible = GameManager.treatment != GameManager.Treatment.INDIVIDUAL


func _on_round_started(round_num: int, budget: int) -> void:
	round_label.text       = "Round %d / %d" % [round_num, GameManager.total_rounds]
	budget_label.text      = "Budget: " + Player.format_dollars(budget)
	city_panel.visible     = GameManager.treatment != GameManager.Treatment.INDIVIDUAL
	end_round_button.disabled = false


func _on_round_ended(_round_num: int, results: Dictionary) -> void:
	_last_round_results = results
	_render_personal(results)
	end_round_button.disabled = true


## Time stays a raw number (travel time + money are the only raw numbers
## shown to participants); safety is star-rating-only unless debug mode is
## on (SafetyDisplay.format handles that).
func _render_personal(results: Dictionary) -> void:
	var players_data: Array = results.get("players", [])
	if players_data.size() <= 1:
		time_label.text   = "Time: %.1f min" % results.get("personal_time", 0.0)
		safety_label.text = "Safety: " + SafetyDisplay.format(results.get("personal_safety", 0.0))
	else:
		var time_parts: PackedStringArray = []
		var safety_parts: PackedStringArray = []
		for i in range(players_data.size()):
			var pd: Dictionary = players_data[i]
			time_parts.append("P%d: %.1f" % [i + 1, pd.get("time", 0.0)])
			safety_parts.append("P%d: %s" % [i + 1, SafetyDisplay.format(pd.get("safety", 0.0))])
		time_label.text   = "Time  " + "  ".join(time_parts)
		safety_label.text = "Safety  " + "  ".join(safety_parts)


func _on_city_metrics_updated(metrics: Dictionary) -> void:
	_last_city_metrics = metrics
	_render_city(metrics)


## City-wide outcomes ARE shown to participants in T2/T3 (the whole point of
## those conditions); the panel itself is hidden in T1 by city_panel.visible.
## Text comes from CityFeedback so it matches what the log records verbatim.
func _render_city(metrics: Dictionary) -> void:
	var text := CityFeedback.lines(metrics)
	city_time_label.text   = text[0]
	city_safety_label.text = text[1]
	coverage_label.text    = text[2]

	# How many residents are better off than on the original network. Absent
	# until the first round is confirmed, so the label hides rather than
	# showing a placeholder "0%" that would read as a real result.
	var benefit := CityFeedback.benefit_lines(metrics)
	benefit_label.visible = not benefit.is_empty()
	benefit_label.text    = "\n".join(benefit)


func _on_game_over(_final: Dictionary) -> void:
	end_round_button.text     = "Game Over"
	end_round_button.disabled = true


func update_budget(credits_remaining: int) -> void:
	budget_label.text = "Budget: " + Player.format_dollars(credits_remaining)
