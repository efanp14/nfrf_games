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
##
## It grows LEFTWARDS (grow_horizontal = BEGIN in the scene) and its long labels
## autowrap. Neither was true before: the panel was pinned 380px from the right
## edge growing right, and CityTimeLabel is an 18pt Label whose text in T2/T3
## ("City average commute:   28.6 min   (up 1.2 min better)") measures about
## 470px. A Label reports its longest line as its minimum width, a PanelContainer
## must honour that, and the surplus went off the side of the screen -- which is
## what playtesters saw as the panel being cut off with information missing. T1
## escaped it only because CitySection is hidden there.

signal next_round_pressed

## Shown for a rider whose route moved this round.
##
## Dijkstra minimises IMPEDANCE, not time, so calming a road can pull a rider
## onto a longer but quieter one: their travel time goes UP while their stress
## goes down. That is the detour behaviour the whole model exists to produce
## (design doc 3.1), and without a word of explanation it reads as the game
## having got the arithmetic backwards. `route_changed` was already on every
## per-player record and was simply never shown.
const ROUTE_CHANGED_LINE: String = "Your route changed this round"

@onready var title_label: Label          = %TitleLabel
@onready var time_label: Label           = %TimeLabel
@onready var delta_label: Label          = %DeltaLabel
@onready var safety_label: RichTextLabel = %SafetyLabel
@onready var city_section: VBoxContainer = %CitySection
@onready var city_time_label: Label      = %CityTimeLabel
@onready var city_safety_label: RichTextLabel = %CitySafetyLabel
@onready var coverage_label: Label       = %CoverageLabel
@onready var benefit_label: Label        = %BenefitLabel
@onready var next_button: Button         = %NextButton

var _players_box: VBoxContainer


func _ready() -> void:
	visible = false
	next_button.pressed.connect(func(): next_round_pressed.emit(); hide())
	_players_box = PlayerRow.make_box()
	var vbox := title_label.get_parent()
	vbox.add_child(_players_box)
	vbox.move_child(_players_box, safety_label.get_index() + 1)


## Fills the panel and shows it. Three separable jobs: the solo player's own
## figures, the per-seat rows that replace them in a group, and the city block.
func show_results(results: Dictionary, treatment: int, is_last_round: bool) -> void:
	var players_data: Array = results.get("players", [])

	title_label.text = "Round %d of %d Complete" % [
			results.get("round", 0), GameManager.total_rounds]

	PlayerRow.clear(_players_box)
	var solo := players_data.size() <= 1
	time_label.visible   = solo
	delta_label.visible  = solo
	safety_label.visible = solo
	_players_box.visible = not solo
	if solo:
		_show_solo(results)
	else:
		_show_player_rows(players_data)

	city_section.visible = treatment != GameManager.Treatment.INDIVIDUAL
	if city_section.visible:
		_show_city(results)

	next_button.text = "See Final Results" if is_last_round else "Next Round  →"
	visible = true


## The single player's own commute. Wording reflects the STATIC reference
## point: every round is compared to the player's original commute, not to the
## previous round (design doc 3.7).
func _show_solo(results: Dictionary) -> void:
	var time: float   = results.get("personal_time", 0.0)
	var delta: float  = results.get("time_delta", 0.0)
	var safety: float = results.get("personal_safety", 0.0)

	time_label.text = "Commute time:   %.1f min" % time

	# `time_delta` is already signed so positive means faster, so it is an
	# improvement figure and goes to Valence as-is.
	delta_label.text = Valence.phrase(delta,
			"%.1f min faster than your original commute" % delta,
			"%.1f min slower than your original commute" % absf(delta),
			"Same as your original commute")
	Valence.paint(delta_label, delta)
	if results.get("route_changed", false):
		delta_label.text += "
" + ROUTE_CHANGED_LINE

	safety_label.text = "Safety: " + SafetyDisplay.format_route_bb(
			safety, results.get("alpha", PersonalityConfig.ALPHA_AVERAGE))


## One row per seat in a group session, in seat order and seat colour.
func _show_player_rows(players_data: Array) -> void:
	for i in range(players_data.size()):
		var pd: Dictionary = players_data[i]
		var delta: float = pd.get("time_delta", 0.0)
		var delta_str := ""
		var g := Valence.glyph(delta)
		if not g.is_empty():
			delta_str = " (%s%.1f)" % [g, absf(delta)]
		var text := "P%d:  %.1f min  Safety: %s%s" % [
				i + 1, pd.get("time", 0.0),
				SafetyDisplay.format_route_bb(pd.get("safety", 0.0),
						pd.get("alpha", PersonalityConfig.ALPHA_AVERAGE)),
				delta_str]
		if pd.get("route_changed", false):
			text += "
    " + ROUTE_CHANGED_LINE
		_players_box.add_child(PlayerRow.make(i, text))


## City-wide outcomes, shown to participants in T2/T3 with the change against
## this round's starting values -- the round summary is where before/after
## belongs. Same CityFeedback source as the HUD and the research log, so all
## three always agree.
func _show_city(results: Dictionary) -> void:
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

	# The collective-impact sentences. `results` already carries the residents_*
	# fields verbatim, so this hands CityFeedback the same values the log
	# records rather than a re-derived copy.
	var benefit := CityFeedback.benefit_lines(results)
	benefit_label.visible = not benefit.is_empty()
	benefit_label.text    = "
".join(benefit)
