class_name EndScreen
extends CanvasLayer
## EndScreen.gd
##
## Final screen shown after the last round and immediately before
## the post-survey.
##
## T1 shows:
##   - final personal commute time
##   - final personal safety
##
## T2/T3 additionally show:
##   - city average commute time
##   - city safety
##   - resident safety-benefit icons
##
## Other research variables are still calculated and logged in the backend,
## but are intentionally not shown here.
##
## The screen deliberately does not evaluate or label the participant's
## strategy, because the post-survey asks about self-interest, fairness,
## collective benefit, and related attitudes.

signal finished


@onready var final_time_label: Label = %FinalTimeLabel
@onready var saved_label: Label = %SavedLabel
@onready var safety_label: RichTextLabel = %SafetyLabel
@onready var coverage_label: Label = %CoverageLabel
@onready var finish_button: Button = %FinishButton


var _players_box: VBoxContainer

var _city_box: VBoxContainer
var _city_title: Label
var _city_time_label: Label
var _city_safety_label: RichTextLabel
var _resident_icons: ResidentIcons


func _ready() -> void:
	visible = false

	# Dark background behind the final popup.
	($Overlay as ColorRect).color = Palette.OVERLAY_HEAVY

	finish_button.pressed.connect(
		func():
			finished.emit()
			hide()
	)

	var vbox := final_time_label.get_parent() as VBoxContainer

	# ---------------------------------------------------------
	# T3 player rows
	# ---------------------------------------------------------
	_players_box = PlayerRow.make_box()
	vbox.add_child(_players_box)
	vbox.move_child(
		_players_box,
		safety_label.get_index() + 1
	)

	# ---------------------------------------------------------
	# Citywide section for T2/T3
	# ---------------------------------------------------------
	_city_box = VBoxContainer.new()
	_city_box.add_theme_constant_override("separation", 8)

	_city_title = Label.new()
	_city_title.text = "Citywide"
	_city_title.add_theme_font_size_override("font_size", 18)
	_city_box.add_child(_city_title)

	_city_time_label = Label.new()
	_city_box.add_child(_city_time_label)

	_city_safety_label = RichTextLabel.new()
	_city_safety_label.bbcode_enabled = true
	_city_safety_label.fit_content = true
	_city_safety_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_city_box.add_child(_city_safety_label)

	_resident_icons = ResidentIcons.new()
	_city_box.add_child(_resident_icons)

	vbox.add_child(_city_box)

	# Put the citywide section where the old coverage line was.
	vbox.move_child(
		_city_box,
		coverage_label.get_index()
	)

	# These are backend metrics now and should not be shown.
	saved_label.visible = false
	coverage_label.visible = false


## Fill and show the final screen.
func show_results(final_results: Dictionary) -> void:
	var players_data: Array = final_results.get("players", [])

	PlayerRow.clear(_players_box)

	var solo: bool = players_data.size() <= 1

	# ---------------------------------------------------------
	# Personal results
	# ---------------------------------------------------------
	final_time_label.visible = solo
	safety_label.visible = solo
	_players_box.visible = not solo

	saved_label.visible = false
	coverage_label.visible = false

	if solo:
		_show_solo(final_results)
	else:
		_show_player_rows(players_data)

	# ---------------------------------------------------------
	# Citywide results
	# T1 = hidden
	# T2/T3 = shown
	# ---------------------------------------------------------
	var treatment_value: int = int(
		final_results.get(
			"treatment",
			GameManager.Treatment.INDIVIDUAL
		)
	)

	var show_citywide: bool = (
		treatment_value != GameManager.Treatment.INDIVIDUAL
	)

	_city_box.visible = show_citywide

	if show_citywide:
		_show_citywide(final_results)

	visible = true


## Final personal result for T1/T2.
func _show_solo(final_results: Dictionary) -> void:
	var final_time: float = final_results.get(
		"final_time",
		0.0
	)

	var safety: float = final_results.get(
		"final_safety",
		0.0
	)

	final_time_label.text = (
		"Final commute:   %.1f min"
		% final_time
	)

	safety_label.text = (
		"Final safety: "
		+ SafetyDisplay.format_route_bb(
			safety,
			final_results.get(
				"alpha",
				PersonalityConfig.ALPHA_AVERAGE
			)
		)
	)


## Final personal results for all T3 group members.
func _show_player_rows(players_data: Array) -> void:
	for i in range(players_data.size()):
		var pd: Dictionary = players_data[i]

		var row_text := (
			"P%d:  %.1f min  Safety: %s"
			% [
				i + 1,
				pd.get("final_time", 0.0),
				SafetyDisplay.format_route_bb(
					pd.get("final_safety", 0.0),
					pd.get(
						"alpha",
						PersonalityConfig.ALPHA_AVERAGE
					)
				)
			]
		)

		_players_box.add_child(
			PlayerRow.make(
				i,
				row_text
			)
		)


## Final citywide results shown only in T2 and T3.
func _show_citywide(final_results: Dictionary) -> void:
	var metrics := {
		"avg_time":
			final_results.get(
				"city_avg_time",
				0.0
			),

		"avg_safety":
			final_results.get(
				"city_avg_safety",
				0.0
			),

		"residents_total":
			final_results.get(
				"residents_total",
				0
			),

		"residents_safety_improved_pct":
			final_results.get(
				"residents_safety_improved_pct",
				0.0
			),
	}

	var city_lines: PackedStringArray = (
		CityFeedback.lines(metrics)
	)

	_city_time_label.text = city_lines[0]
	_city_safety_label.text = city_lines[1]

	_resident_icons.show_metrics(metrics)
