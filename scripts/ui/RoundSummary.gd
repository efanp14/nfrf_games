class_name RoundSummary
extends CanvasLayer

signal next_round_pressed

@onready var title_label: Label          = %TitleLabel
@onready var time_label: Label           = %TimeLabel
@onready var delta_label: Label          = %DeltaLabel
@onready var safety_label: Label         = %SafetyLabel
@onready var city_section: VBoxContainer = %CitySection
@onready var city_time_label: Label      = %CityTimeLabel
@onready var coverage_label: Label       = %CoverageLabel
@onready var next_button: Button         = %NextButton

var _players_box: VBoxContainer


func _ready() -> void:
	visible = false
	next_button.pressed.connect(func(): next_round_pressed.emit(); hide())
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	_players_box.visible = false
	var vbox := title_label.get_parent()
	vbox.add_child(_players_box)
	vbox.move_child(_players_box, safety_label.get_index() + 1)


func show_results(results: Dictionary, treatment: int, is_last_round: bool) -> void:
	var round_num: int = results.get("round", 0)
	var players_data: Array = results.get("players", [])

	title_label.text = "Round %d of %d Complete" % [round_num, GameManager.total_rounds]

	# Clear previous player rows
	for child in _players_box.get_children():
		_players_box.remove_child(child)
		child.queue_free()

	if players_data.size() <= 1:
		time_label.visible = true
		delta_label.visible = true
		safety_label.visible = true
		_players_box.visible = false

		var time: float    = results.get("personal_time", 0.0)
		var delta: float   = results.get("time_delta", 0.0)
		var safety: float  = results.get("personal_safety", 0.0)

		time_label.text  = "Commute time:   %.1f min" % time
		if delta > 0.05:
			delta_label.text = "▼  %.1f min faster than last round" % delta
			delta_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		elif delta < -0.05:
			delta_label.text = "▲  %.1f min slower than last round" % absf(delta)
			delta_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
		else:
			delta_label.text = "No change from last round"
			delta_label.remove_theme_color_override("font_color")
		safety_label.text = "Safety score:   %.0f / 100" % safety
	else:
		time_label.visible = false
		delta_label.visible = false
		safety_label.visible = false
		_players_box.visible = true

		for i in range(players_data.size()):
			var pd: Dictionary = players_data[i]
			var time_val: float = pd.get("time", 0.0)
			var safety_val: float = pd.get("safety", 0.0)
			var delta_val: float = pd.get("time_delta", 0.0)
			var delta_str := ""
			if delta_val > 0.05:
				delta_str = " (▼%.1f)" % delta_val
			elif delta_val < -0.05:
				delta_str = " (▲%.1f)" % absf(delta_val)
			var player_lbl := Label.new()
			player_lbl.add_theme_font_size_override("font_size", 16)
			player_lbl.text = "P%d:  %.1f min  Safety: %d%s" % [i + 1, time_val, int(safety_val), delta_str]
			var col: Color = GameManager.PLAYER_COLORS[i % GameManager.PLAYER_COLORS.size()]
			player_lbl.add_theme_color_override("font_color", col)
			_players_box.add_child(player_lbl)

	city_section.visible = treatment != GameManager.Treatment.INDIVIDUAL
	if city_section.visible:
		city_time_label.text = "City avg time:   %.1f min" % results.get("city_avg_time", 0.0)
		coverage_label.text  = "Network coverage:   %.0f%%" % results.get("city_coverage", 0.0)

	next_button.text = "See Final Results" if is_last_round else "Next Round  →"
	visible = true
