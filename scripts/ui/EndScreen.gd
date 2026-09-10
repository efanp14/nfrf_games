class_name EndScreen
extends CanvasLayer
## EndScreen.gd
## The closing screen, shown once after the last round and immediately before
## the post-survey.
##
## Same solo/group shape as RoundSummary and sharing its row builder
## (PlayerRow) and its better/worse rule (Valence).
##
## It deliberately says NOTHING evaluative about how the player played -- see
## the note in show_results(). That is a research constraint, not a style
## choice, because the survey that follows asks about exactly what a summary
## label would be praising.

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
	_players_box = PlayerRow.make_box()
	var vbox := final_time_label.get_parent()
	vbox.add_child(_players_box)
	vbox.move_child(_players_box, safety_label.get_index() + 1)


## Fills the closing screen and shows it. Same solo/group split as
## RoundSummary, and the same shared row builder.
func show_results(final_results: Dictionary) -> void:
	var players_data: Array = final_results.get("players", [])

	PlayerRow.clear(_players_box)
	var solo := players_data.size() <= 1
	final_time_label.visible = solo
	saved_label.visible      = solo
	safety_label.visible     = solo
	_players_box.visible     = not solo
	if solo:
		_show_solo(final_results)
	else:
		_show_player_rows(players_data)

	var coverage: float = final_results.get("city_coverage", 0.0)
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


## The single player's whole session, against their first commute.
func _show_solo(final_results: Dictionary) -> void:
	var final_time: float = final_results.get("final_time", 0.0)
	var baseline: float   = final_results.get("baseline_time", 0.0)
	var saved: float      = final_results.get("total_time_saved", 0.0)
	var safety: float     = final_results.get("final_safety", 0.0)

	final_time_label.text = "Final commute:   %.1f min" % final_time
	# `total_time_saved` is signed so positive means saved, i.e. already an
	# improvement figure.
	saved_label.text = Valence.phrase(saved,
			"%.1f min saved vs. your first commute (%.1f min)" % [saved, baseline],
			"%.1f min longer vs. your first commute (%.1f min)" % [absf(saved), baseline],
			"Same time as your first commute (%.1f min)" % baseline)
	Valence.paint(saved_label, saved)

	safety_label.text = "Final safety: " + SafetyDisplay.format_route_bb(
			safety, final_results.get("alpha", PersonalityConfig.ALPHA_AVERAGE))


## One row per seat, matching the round summary's rows.
##
## These used to carry no glyph at all, unlike the other three places the
## better/worse rule is shown, so the final screen of the session was the one
## that stated it least clearly. They go through Valence now like the rest.
func _show_player_rows(players_data: Array) -> void:
	for i in range(players_data.size()):
		var pd: Dictionary = players_data[i]
		var saved: float = pd.get("total_time_saved", 0.0)
		var saved_str := Valence.phrase(saved,
				"saved %.1f min" % saved,
				"%.1f min slower" % absf(saved),
				"no change")
		_players_box.add_child(PlayerRow.make(i, "P%d:  %.1f min  Safety: %s  (%s)" % [
				i + 1, pd.get("final_time", 0.0),
				SafetyDisplay.format_route_bb(pd.get("final_safety", 0.0),
						pd.get("alpha", PersonalityConfig.ALPHA_AVERAGE)),
				saved_str]))
