class_name EndScreen
extends CanvasLayer

signal finished

@onready var final_time_label: Label = %FinalTimeLabel
@onready var saved_label: Label      = %SavedLabel
@onready var safety_label: Label     = %SafetyLabel
@onready var coverage_label: Label   = %CoverageLabel
@onready var strategy_label: Label   = %StrategyLabel
@onready var finish_button: Button   = %FinishButton

var _players_box: VBoxContainer


func _ready() -> void:
	visible = false
	finish_button.pressed.connect(func(): finished.emit(); hide())
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	_players_box.visible = false
	var vbox := final_time_label.get_parent()
	vbox.add_child(_players_box)
	vbox.move_child(_players_box, safety_label.get_index() + 1)


func show_results(final_results: Dictionary) -> void:
	var players_data: Array = final_results.get("players", [])
	var coverage: float     = final_results.get("city_coverage", 0.0)

	for child in _players_box.get_children():
		_players_box.remove_child(child)
		child.queue_free()

	if players_data.size() <= 1:
		final_time_label.visible = true
		saved_label.visible = true
		safety_label.visible = true
		_players_box.visible = false

		var final_time: float = final_results.get("final_time", 0.0)
		var baseline: float   = final_results.get("baseline_time", 0.0)
		var saved: float      = final_results.get("total_time_saved", 0.0)
		var safety: float     = final_results.get("final_safety", 0.0)

		final_time_label.text = "Final commute:   %.1f min" % final_time

		if saved > 0.05:
			saved_label.text = "▼  %.1f min saved vs. your first commute (%.1f min)" % [saved, baseline]
			saved_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		elif saved < -0.05:
			saved_label.text = "▲  %.1f min longer vs. your first commute (%.1f min)" % [absf(saved), baseline]
			saved_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
		else:
			saved_label.text = "Same time as your first commute (%.1f min)" % baseline
			saved_label.remove_theme_color_override("font_color")

		safety_label.text = "Final safety: " + SafetyDisplay.format(safety)
	else:
		final_time_label.visible = false
		saved_label.visible = false
		safety_label.visible = false
		_players_box.visible = true

		for i in range(players_data.size()):
			var pd: Dictionary = players_data[i]
			var ft: float = pd.get("final_time", 0.0)
			var saved: float = pd.get("total_time_saved", 0.0)
			var safety: float = pd.get("final_safety", 0.0)
			var player_lbl := Label.new()
			player_lbl.add_theme_font_size_override("font_size", 12)
			var saved_str := ""
			if saved > 0.05:
				saved_str = "saved %.1f min" % saved
			elif saved < -0.05:
				saved_str = "+%.1f min slower" % absf(saved)
			else:
				saved_str = "no change"
			player_lbl.text = "P%d:  %.1f min  Safety: %s  (%s)" % [i + 1, ft, SafetyDisplay.format(safety), saved_str]
			var col: Color = GameManager.PLAYER_COLORS[i % GameManager.PLAYER_COLORS.size()]
			player_lbl.add_theme_color_override("font_color", col)
			_players_box.add_child(player_lbl)

	# Network coverage is a backend metric — debug-only.
	coverage_label.text = "[debug] Network coverage:   %.0f%%" % coverage if SafetyDisplay.debug_mode else ""
	strategy_label.text = _strategy_flavour(coverage, final_results.get("total_time_saved", 0.0))

	visible = true


func _strategy_flavour(coverage: float, saved: float) -> String:
	if coverage >= 40.0 and saved >= 2.0:
		return "Civic Champion — you built for the whole city and your commute improved."
	elif coverage >= 25.0:
		return "Collective Builder — your investments helped the whole network."
	elif saved >= 3.0:
		return "Personal Optimizer — you focused on your own route, and it paid off."
	else:
		return "Mixed Planner — a varied strategy across the city."
