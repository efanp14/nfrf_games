class_name EndScreen
extends CanvasLayer

signal finished

@onready var final_time_label: Label = %FinalTimeLabel
@onready var saved_label: Label      = %SavedLabel
@onready var safety_label: RichTextLabel = %SafetyLabel
@onready var coverage_label: Label   = %CoverageLabel
@onready var finish_button: Button   = %FinishButton

var _players_box: VBoxContainer


func _ready() -> void:
	visible = false
	# The scrim comes from Palette rather than from the scene, so every
	# screen's backdrop is set in the one place colours are declared.
	($Overlay as ColorRect).color = Palette.OVERLAY_HEAVY
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
			saved_label.add_theme_color_override("font_color", Palette.DELTA_GAIN)
		elif saved < -0.05:
			saved_label.text = "▲  %.1f min longer vs. your first commute (%.1f min)" % [absf(saved), baseline]
			saved_label.add_theme_color_override("font_color", Palette.DELTA_LOSS)
		else:
			saved_label.text = "Same time as your first commute (%.1f min)" % baseline
			saved_label.remove_theme_color_override("font_color")

		safety_label.text = "Final safety: " + SafetyDisplay.format_bb(safety)
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
			# Rich text, so the stars in this row are gold like every other
			# rating. The seat colour moves to default_color for the same reason.
			var player_lbl := RichTextLabel.new()
			player_lbl.bbcode_enabled = true
			player_lbl.fit_content = true
			player_lbl.add_theme_font_size_override("normal_font_size", 12)
			var saved_str := ""
			if saved > 0.05:
				saved_str = "saved %.1f min" % saved
			elif saved < -0.05:
				saved_str = "+%.1f min slower" % absf(saved)
			else:
				saved_str = "no change"
			player_lbl.text = "P%d:  %.1f min  Safety: %s  (%s)" % [i + 1, ft, SafetyDisplay.format_bb(safety), saved_str]
			var col: Color = Palette.PLAYER_COLORS[i % Palette.PLAYER_COLORS.size()]
			player_lbl.add_theme_color_override("default_color", col)
			_players_box.add_child(player_lbl)

	# Network coverage is a backend metric — debug-only.
	coverage_label.text = "[debug] Network coverage:   %.0f%%" % coverage if SafetyDisplay.debug_mode else ""

	# NOTE: this screen deliberately shows NO summary label characterising the
	# player's strategy. It previously ended the session by labelling the
	# player "Civic Champion" / "Collective Builder" / "Personal Optimizer"
	# based on how much of the network they upgraded. Removed (owner, 3 Aug
	# 2026): the end screen is shown immediately before the post-survey, whose
	# items ask about fairness, prioritising oneself, and willingness to
	# sacrifice for citywide benefit — praising or labelling a strategy right
	# before asking those questions risks steering the answers. Self- vs.
	# collective-oriented investment IS the dependent variable, so the game
	# must not evaluate it back to the participant. Do not reintroduce.

	visible = true
