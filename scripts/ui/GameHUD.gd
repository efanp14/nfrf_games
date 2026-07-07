class_name GameHUD
extends CanvasLayer

signal end_round_pressed

@onready var round_label: Label         = %RoundLabel
@onready var budget_label: Label        = %BudgetLabel
@onready var time_label: Label          = %TimeLabel
@onready var safety_label: Label        = %SafetyLabel
@onready var city_panel: VBoxContainer  = %CityPanel
@onready var city_time_label: Label     = %CityTimeLabel
@onready var coverage_label: Label      = %CoverageLabel
@onready var end_round_button: Button   = %EndRoundButton


func _ready() -> void:
	end_round_button.pressed.connect(func(): end_round_pressed.emit())
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.city_metrics_updated.connect(_on_city_metrics_updated)
	GameManager.game_over.connect(_on_game_over)
	_sync_initial_state()


func _sync_initial_state() -> void:
	if not GameManager.game_running:
		return
	round_label.text  = "Round %d / %d" % [GameManager.current_round, GameManager.total_rounds]
	budget_label.text = "Budget: $%d"   % GameManager.human_player.credits_per_round
	city_panel.visible = GameManager.treatment != GameManager.Treatment.INDIVIDUAL


func _on_round_started(round_num: int, budget: int) -> void:
	round_label.text       = "Round %d / %d" % [round_num, GameManager.total_rounds]
	budget_label.text      = "Budget: $%d"   % budget
	city_panel.visible     = GameManager.treatment != GameManager.Treatment.INDIVIDUAL
	end_round_button.disabled = false


func _on_round_ended(_round_num: int, results: Dictionary) -> void:
	var players_data: Array = results.get("players", [])
	if players_data.size() <= 1:
		time_label.text   = "Time: %.1f min" % results.get("personal_time", 0.0)
		safety_label.text = "Safety: %d"     % int(results.get("personal_safety", 0.0))
	else:
		var time_parts: PackedStringArray = []
		var safety_parts: PackedStringArray = []
		for i in range(players_data.size()):
			var pd: Dictionary = players_data[i]
			time_parts.append("P%d: %.1f" % [i + 1, pd.get("time", 0.0)])
			safety_parts.append("P%d: %d" % [i + 1, int(pd.get("safety", 0.0))])
		time_label.text   = "Time  " + "  ".join(time_parts)
		safety_label.text = "Safety  " + "  ".join(safety_parts)
	end_round_button.disabled = true


func _on_city_metrics_updated(metrics: Dictionary) -> void:
	city_time_label.text = "City: %.1f min" % metrics.get("avg_time",  0.0)
	coverage_label.text  = "Cover: %d%%"    % int(metrics.get("coverage", 0.0))


func _on_game_over(_final: Dictionary) -> void:
	end_round_button.text     = "Game Over"
	end_round_button.disabled = true


func update_budget(credits_remaining: int) -> void:
	budget_label.text = "Budget: $%d" % credits_remaining
