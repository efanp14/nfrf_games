class_name RoundSummary
extends CanvasLayer
## The end-of-round panel down the right-hand edge.
##
## Its background (SidePanel's panel style, set in the scene) is FULLY OPAQUE
## and uses the same colour as the left sidebar, so the two read as one
## interface framing the map rather than two different surfaces. The panel
## carried no style override at all until 11 Aug 2026 and fell back to the
## default theme's translucent one, which left the city network showing through
## the round's numbers and made them hard to read against a busy map. A light
## hairline down the left edge keeps it reading as sitting ON the map rather
## than being cut out of it.

signal next_round_pressed

@onready var title_label: Label          = %TitleLabel
@onready var time_label: Label           = %TimeLabel
@onready var delta_label: Label          = %DeltaLabel
@onready var safety_label: Label         = %SafetyLabel
@onready var city_section: VBoxContainer = %CitySection
@onready var city_time_label: Label      = %CityTimeLabel
@onready var city_safety_label: Label    = %CitySafetyLabel
@onready var coverage_label: Label       = %CoverageLabel
@onready var benefit_label: Label        = %BenefitLabel
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
		# Wording reflects the STATIC reference point: every round is compared
		# to the player's original commute, not to the previous round.
		if delta > 0.05:
			delta_label.text = "▼  %.1f min faster than your original commute" % delta
			delta_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		elif delta < -0.05:
			delta_label.text = "▲  %.1f min slower than your original commute" % absf(delta)
			delta_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
		else:
			delta_label.text = "Same as your original commute"
			delta_label.remove_theme_color_override("font_color")
		safety_label.text = "Safety: " + SafetyDisplay.format(safety)
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
			player_lbl.text = "P%d:  %.1f min  Safety: %s%s" % [i + 1, time_val, SafetyDisplay.format(safety_val), delta_str]
			var col: Color = GameManager.PLAYER_COLORS[i % GameManager.PLAYER_COLORS.size()]
			player_lbl.add_theme_color_override("font_color", col)
			_players_box.add_child(player_lbl)

	city_section.visible = treatment != GameManager.Treatment.INDIVIDUAL
	if city_section.visible:
		# City-wide outcomes are shown to participants in T2/T3, with the
		# change against this round's starting values — the round summary is
		# where before/after belongs. Same CityFeedback source as the HUD and
		# the research log, so all three always agree.
		var text := CityFeedback.lines_with_change(
			{
				"avg_time":   results.get("city_avg_time", 0.0),
				"avg_safety": results.get("city_avg_safety", 0.0),
				"coverage":   results.get("city_coverage", 0.0),
			},
			{
				"avg_time":   results.get("city_avg_time_baseline", 0.0),
				"avg_safety": results.get("city_avg_safety_baseline", 0.0),
				"coverage":   results.get("city_coverage_baseline", 0.0),
			})
		city_time_label.text   = text[0]
		city_safety_label.text = text[1]
		coverage_label.text    = text[2]

		# The collective-impact sentences. `results` already carries the
		# residents_* fields verbatim, so this hands CityFeedback the same
		# values the log records rather than a re-derived copy.
		var benefit := CityFeedback.benefit_lines(results)
		benefit_label.visible = not benefit.is_empty()
		benefit_label.text    = "\n".join(benefit)

	next_button.text = "See Final Results" if is_last_round else "Next Round  →"
	visible = true
