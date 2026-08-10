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

const QUESTION_COLUMN_WIDTH: float = 320.0

var _responses: Dictionary = {}
var _required_keys: Array[String] = []
var _treatment: int = 0
var _player_num: int = 1
var _total_players: int = 1
var _player_label: Label

@onready var questions_box: VBoxContainer = %QuestionsBox
@onready var submit_button: Button        = %SubmitButton


func _ready() -> void:
	visible = false
	submit_button.disabled = true
	submit_button.pressed.connect(_on_submit)

	_player_label = Label.new()
	_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_label.add_theme_font_size_override("font_size", 14)
	_player_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_player_label.visible = false
	var vbox := questions_box.get_parent()
	vbox.add_child(_player_label)
	vbox.move_child(_player_label, questions_box.get_index())


func show_survey(treatment: int, player_num: int = 1, total_players: int = 1) -> void:
	_treatment = treatment
	_player_num = player_num
	_total_players = total_players
	_responses.clear()
	for child in questions_box.get_children():
		questions_box.remove_child(child)
		child.queue_free()
	_build_questions()

	submit_button.disabled = true
	if total_players > 1:
		_player_label.text = "Player %d of %d" % [player_num, total_players]
		_player_label.visible = true
		submit_button.text = "Next" if player_num < total_players else "Submit & Finish"
	else:
		_player_label.visible = false
		submit_button.text = "Submit & Finish"
	visible = true


func _build_questions() -> void:
	_required_keys.clear()
	# Wrapped the same way as the rows below it, so the headers sit squarely
	# above their own column of bubbles.
	questions_box.add_child(SurveyScale.banded_row(
		SurveyScale.build_header_row(QUESTION_COLUMN_WIDTH), 0))

	for q: Dictionary in SurveyQuestions.POST:
		if q.get("group_only", false) and _treatment != GROUP_TREATMENT:
			continue
		_add_scale_row(q, _required_keys.size())
		_required_keys.append(q["key"])


func _add_scale_row(q: Dictionary, row_index: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.text = q["text"]
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(QUESTION_COLUMN_WIDTH, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)

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


func _on_submit() -> void:
	survey_completed.emit(_player_num, _responses.duplicate())
	hide()
