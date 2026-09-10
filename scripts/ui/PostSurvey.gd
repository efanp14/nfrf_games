class_name PostSurvey
extends CanvasLayer
## The survey shown after play. Content comes from SurveyQuestions.POST and the
## response scale from SurveyScale, so this script only renders and collects.
##
## Nothing here feeds the game logic; these responses exist purely for analysis.

signal survey_completed(player_num: int, responses: Dictionary)

## Treatment index for the group condition. The three discussion items are shown
## only here, since they ask about something T1 and T2 participants never did.
const GROUP_TREATMENT: int = 2


var _responses: Dictionary = {}
var _required_keys: Array[String] = []
var _treatment: int = 0
var _player_num: int = 1
var _total_players: int = 1
## Says whose turn it is: seat colour, seat number and participant ID. In the
## group treatment three people share one screen and answer in turn, and this is
## what tells them which of them is up.
var _player_banner: SurveyIdentityBanner

@onready var questions_box: VBoxContainer = %QuestionsBox
@onready var submit_button: Button        = %SubmitButton


func _ready() -> void:
	visible = false
	# The scrim comes from Palette rather than from the scene, so every
	# screen's backdrop is set in the one place colours are declared.
	($Overlay as ColorRect).color = Palette.OVERLAY_FULL
	submit_button.disabled = true
	submit_button.pressed.connect(_on_submit)

	_player_banner = SurveyIdentityBanner.new()
	_player_banner.visible = false
	var vbox := questions_box.get_parent()
	vbox.add_child(_player_banner)
	vbox.move_child(_player_banner, questions_box.get_index())


## `participant_id` is shown, not stored: the caller still passes the ID
## separately to the logger. It is here so a group can tell whose turn it is.
func show_survey(treatment: int, player_num: int = 1, total_players: int = 1,
		participant_id: String = "") -> void:
	_treatment = treatment
	_player_num = player_num
	_total_players = total_players
	_responses.clear()
	for child in questions_box.get_children():
		questions_box.remove_child(child)
		child.queue_free()
	_build_questions()

	submit_button.disabled = true
	_player_banner.set_player(player_num, total_players, participant_id)
	if total_players > 1:
		submit_button.text = "Next" if player_num < total_players else "Submit & Finish"
	else:
		submit_button.text = "Submit & Finish"
	visible = true


func _build_questions() -> void:
	_required_keys.clear()
	# Wrapped the same way as the rows below it, so the headers sit squarely
	# above their own column of bubbles.
	questions_box.add_child(SurveyScale.banded_row(
		SurveyScale.build_header_row(SurveyScale.QUESTION_COLUMN_WIDTH), 0))

	for q: Dictionary in SurveyQuestions.POST:
		if q.get("group_only", false) and _treatment != GROUP_TREATMENT:
			continue
		_add_scale_row(q, _required_keys.size())
		_required_keys.append(q["key"])


func _add_scale_row(q: Dictionary, row_index: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	row.add_child(SurveyScale.question_label(q["text"]))

	var key: String = q["key"]
	row.add_child(SurveyScale.build_response_row(
		func(value: Variant) -> void: _on_scale_pick(key, value)))
	questions_box.add_child(SurveyScale.banded_row(row, row_index))


func _on_scale_pick(key: String, value: Variant) -> void:
	_responses[key] = value
	for k: String in _required_keys:
		if not _responses.has(k):
			submit_button.disabled = true
			return
	submit_button.disabled = false


## Emits without hiding, and the caller decides what happens next — the same
## division of labour PreSurvey uses.
##
## This must not hide itself. Emission is synchronous, so in the group treatment
## the handler has already called show_survey() for the next player by the time
## this returns; hiding here wiped that survey off the screen and left the
## session with nothing to click on after the first member submitted.
func _on_submit() -> void:
	survey_completed.emit(_player_num, _responses.duplicate())
