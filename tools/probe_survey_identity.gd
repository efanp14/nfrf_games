extends Node
## Checks that a survey says whose turn it is.
##
##   godot --headless res://tools/probe_survey_identity.tscn
##
## The group treatment runs the closing survey one member at a time on a single
## shared screen. It used to announce only "Player 2 of 3", and nothing on that
## screen said which of the three people at the table player 2 was: the seat is a
## colour everywhere else in the game and an ID on a card in their pocket, and
## the survey named neither. Getting it wrong attaches one person's attitudes to
## another person's decisions, silently and unrecoverably.
##
## Also guards the 17 Aug 2026 fix, which is easy to undo by accident: PostSurvey
## must emit `survey_completed` and leave itself visible, because the handler
## synchronously puts the next member's survey up and a self-hide would wipe it
## off a screen with nothing else on it.

var _failures: int = 0

const IDS: Array[String] = ["PCYXA6", "PCYK92", "PCY7T4"]


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL  %s" % what)


func _ready() -> void:
	await _each_seat_is_named()
	await _solo_session_shows_nothing()
	await _missing_id_still_names_the_seat()
	await _survey_does_not_hide_itself_on_submit()

	print("")
	print("FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _banner(survey: PostSurvey) -> SurveyIdentityBanner:
	return survey._player_banner


func _each_seat_is_named() -> void:
	var survey: PostSurvey = load("res://scenes/ui/PostSurvey.tscn").instantiate()
	add_child(survey)
	await get_tree().process_frame

	for seat in range(1, 4):
		survey.show_survey(int(GameManager.Treatment.GROUP_DISCUSSION), seat, 3, IDS[seat - 1])
		await get_tree().process_frame
		var b := _banner(survey)
		var expected: Color = Palette.PLAYER_COLORS[seat - 1]
		var shown_id := ParticipantId.format_for_display(IDS[seat - 1])
		if not b.visible:
			_fail("seat %d: the banner is hidden in a three-player session" % seat)
			continue
		if b._swatch.color != expected:
			_fail("seat %d: swatch is %s, the map draws that seat %s"
					% [seat, b._swatch.color.to_html(false), expected.to_html(false)])
		if not b._seat_label.text.begins_with("Player %d of 3" % seat):
			_fail("seat %d: says '%s'" % [seat, b._seat_label.text])
		if b._id_label.text != shown_id:
			_fail("seat %d: shows ID '%s', expected '%s'" % [seat, b._id_label.text, shown_id])
		else:
			print("Seat %d: %s  %s  swatch %s" % [seat, b._seat_label.text,
					b._id_label.text, b._swatch.color.to_html(false)])
	survey.queue_free()
	await get_tree().process_frame


## A solo participant has nobody to be confused with, and a research identifier
## on screen for no reason is not something they should be reading.
func _solo_session_shows_nothing() -> void:
	var survey: PostSurvey = load("res://scenes/ui/PostSurvey.tscn").instantiate()
	add_child(survey)
	await get_tree().process_frame
	survey.show_survey(int(GameManager.Treatment.INDIVIDUAL), 1, 1, IDS[0])
	await get_tree().process_frame
	if _banner(survey).visible:
		_fail("a single-player survey is showing the participant's ID on screen")
	else:
		print("Solo session shows no identity banner")
	survey.queue_free()
	await get_tree().process_frame


## Sessions run before IDs were issued, or with the field left blank, still have
## to name the seat rather than showing a blank line.
func _missing_id_still_names_the_seat() -> void:
	var survey: PostSurvey = load("res://scenes/ui/PostSurvey.tscn").instantiate()
	add_child(survey)
	await get_tree().process_frame
	survey.show_survey(int(GameManager.Treatment.GROUP_DISCUSSION), 2, 3, "")
	await get_tree().process_frame
	var b := _banner(survey)
	if not b.visible:
		_fail("the banner vanished when the ID was blank")
	elif b._id_label.visible:
		_fail("a blank ID is being drawn as an empty gold label")
	elif not b._seat_label.text.begins_with("Player 2 of 3"):
		_fail("seat not named when the ID is blank: '%s'" % b._seat_label.text)
	else:
		print("A blank ID still names the seat, and draws no empty ID label")
	survey.queue_free()
	await get_tree().process_frame


## The 17 Aug 2026 fix. Emission is synchronous, so main.gd has already put the
## next member's survey up by the time control returns here; a self-hide would
## take that survey down with it and strand the session.
func _survey_does_not_hide_itself_on_submit() -> void:
	var survey: PostSurvey = load("res://scenes/ui/PostSurvey.tscn").instantiate()
	add_child(survey)
	await get_tree().process_frame
	survey.show_survey(int(GameManager.Treatment.GROUP_DISCUSSION), 1, 3, IDS[0])
	await get_tree().process_frame

	var visible_when_handled := [true]
	survey.survey_completed.connect(
			func(_n, _r): visible_when_handled[0] = survey.visible)
	for key: String in survey._required_keys:
		survey._responses[key] = 4
	survey._on_submit()

	if not visible_when_handled[0]:
		_fail("PostSurvey hid itself before the handler ran (the 17 Aug bug is back)")
	elif not survey.visible:
		_fail("PostSurvey hid itself on submit; main.gd owns closing it")
	else:
		print("PostSurvey stays up on submit, leaving the caller to close it")
	survey.queue_free()
	await get_tree().process_frame
