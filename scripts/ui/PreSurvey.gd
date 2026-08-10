class_name PreSurvey
extends CanvasLayer
## The survey shown before play. Content comes from SurveyQuestions.PRE and the
## response scale from SurveyScale, so this script only renders and collects.
##
## The four attitude items are scored into alpha, which sets the cyclist's
## stress sensitivity and therefore drives routing for the whole session. The
## demographic and behaviour answers are recorded for analysis and take no part
## in the game logic.

signal survey_completed(alpha: float, responses: Dictionary)

## Sits at index 0 of every dropdown so nothing is preselected. Without it the
## first real option would stand as an unnoticed default answer.
const SELECT_PROMPT: String = "Select…"

## Keeps question text in a fixed column so the scale buttons line up with their
## headers across every row.
const QUESTION_COLUMN_WIDTH: float = 320.0

var _responses: Dictionary = {}
var _required_keys: Array[String] = []
var _player_label: Label
var _gender_free_text: LineEdit

@onready var questions_box: VBoxContainer = %QuestionsBox
@onready var begin_button: Button         = %BeginButton


func _ready() -> void:
	visible = false
	begin_button.disabled = true
	begin_button.pressed.connect(_on_begin_pressed)

	_player_label = Label.new()
	_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_label.add_theme_font_size_override("font_size", 14)
	_player_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_player_label.visible = false
	var vbox := questions_box.get_parent()
	vbox.add_child(_player_label)
	vbox.move_child(_player_label, questions_box.get_index())

	_build_questions()


func show_for_player(player_num: int, total: int) -> void:
	_reset()
	if total > 1:
		_player_label.text = "Player %d of %d" % [player_num, total]
		_player_label.visible = true
		begin_button.text = "Next" if player_num < total else "Begin Game"
	else:
		_player_label.visible = false
		begin_button.text = "Begin Game"
	visible = true


func _reset() -> void:
	_responses.clear()
	_gender_free_text = null
	begin_button.disabled = true
	for child in questions_box.get_children():
		questions_box.remove_child(child)
		child.queue_free()
	_build_questions()


func _build_questions() -> void:
	_required_keys.clear()
	var current_section: String = ""
	var scale_header_shown: bool = false
	# Restarts at each section so the banding always begins unshaded under a
	# heading rather than depending on how many questions came before it.
	var row_index: int = 0

	for q: Dictionary in SurveyQuestions.PRE:
		var section: String = q.get("section", "")
		if section != current_section:
			current_section = section
			_add_section_header(section)
			# Each section gets its own copy of the column headers, since a
			# section break puts distance between a row and the headers above.
			scale_header_shown = false
			row_index = 0

		if q["kind"] == SurveyQuestions.Kind.LIKERT and not scale_header_shown:
			# Wrapped the same way as the rows below it, so the headers sit
			# squarely above their own column of bubbles.
			questions_box.add_child(SurveyScale.banded_row(
				SurveyScale.build_header_row(QUESTION_COLUMN_WIDTH), 0))
			scale_header_shown = true
			row_index = 0

		_required_keys.append(q["key"])
		if q["kind"] == SurveyQuestions.Kind.CHOICE:
			_add_choice_row(q, row_index)
		else:
			_add_scale_row(q, row_index)
		row_index += 1


func _add_section_header(title: String) -> void:
	if title.is_empty():
		return
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.72, 0.85, 1.0))
	questions_box.add_child(lbl)


func _add_choice_row(q: Dictionary, row_index: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_question_label(q["text"]))

	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(260, 0)
	picker.add_item(SELECT_PROMPT, 0)
	var options: Array = q["options"]
	for i in range(options.size()):
		picker.add_item(options[i], i + 1)
	picker.select(0)

	var key: String = q["key"]
	picker.item_selected.connect(func(idx: int) -> void: _on_choice(key, options, idx))
	row.add_child(picker)
	questions_box.add_child(SurveyScale.banded_row(row, row_index))

	if key == SurveyQuestions.GENDER_KEY:
		_gender_free_text = LineEdit.new()
		_gender_free_text.placeholder_text = "I identify as…"
		_gender_free_text.visible = false
		_gender_free_text.text_changed.connect(_on_gender_text_changed)
		questions_box.add_child(_gender_free_text)


func _add_scale_row(q: Dictionary, row_index: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_question_label(q["text"]))

	var key: String = q["key"]
	row.add_child(SurveyScale.build_response_row(
		func(value: Variant) -> void: _on_scale_pick(key, value)))
	questions_box.add_child(SurveyScale.banded_row(row, row_index))


func _question_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(QUESTION_COLUMN_WIDTH, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 12)
	return lbl


func _on_choice(key: String, options: Array, idx: int) -> void:
	if idx <= 0:
		_responses.erase(key)
	else:
		_responses[key] = options[idx - 1]

	if key == SurveyQuestions.GENDER_KEY and _gender_free_text != null:
		var self_described: bool = \
			_responses.get(key, "") == SurveyQuestions.GENDER_SELF_DESCRIBED_OPTION
		_gender_free_text.visible = self_described
		if not self_described:
			# Clear any text typed before the participant changed their mind,
			# so a stale write-in cannot survive next to a fixed option.
			_gender_free_text.text = ""
			_responses.erase(SurveyQuestions.GENDER_SELF_DESCRIBED_KEY)

	_refresh_begin_button()


## The written gender answer is optional: selecting "I identify as" is enough to
## submit, so nobody is trapped by a field they would rather leave blank.
func _on_gender_text_changed(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		_responses.erase(SurveyQuestions.GENDER_SELF_DESCRIBED_KEY)
	else:
		_responses[SurveyQuestions.GENDER_SELF_DESCRIBED_KEY] = trimmed


func _on_scale_pick(key: String, value: Variant) -> void:
	_responses[key] = value
	_refresh_begin_button()


func _refresh_begin_button() -> void:
	for key: String in _required_keys:
		if not _responses.has(key):
			begin_button.disabled = true
			return
	begin_button.disabled = false


func _on_begin_pressed() -> void:
	var mean: float = SurveyQuestions.alpha_mean(_responses)
	survey_completed.emit(PersonalityConfig.alpha_for_survey_mean(mean), _responses.duplicate())
