class_name PreSurvey
extends CanvasLayer

signal survey_completed(alpha: float, responses: Dictionary)

const QUESTIONS: Array = [
	["q1", "When cycling, I am willing to use busy roads even without a bike lane",  false],
	["q2", "I actively avoid roads that feel unsafe when cycling",                    true],
	["q3", "I would choose a faster cycling route even if it felt less comfortable",  false],
	["q4", "I feel confident cycling alongside moving motor traffic",                 false],
]

var _responses: Dictionary = {}
var _player_label: Label

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
		_player_label.text = "— Player %d of %d —" % [player_num, total]
		_player_label.visible = true
		begin_button.text = "Next" if player_num < total else "Begin Game"
	else:
		_player_label.visible = false
		begin_button.text = "Begin Game"
	visible = true


func _reset() -> void:
	_responses.clear()
	begin_button.disabled = true
	for child in questions_box.get_children():
		questions_box.remove_child(child)
		child.queue_free()
	_build_questions()


func _build_questions() -> void:
	for item: Array in QUESTIONS:
		_add_question_row(item[0] as String, item[1] as String)


func _add_question_row(key: String, question_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var lbl := Label.new()
	lbl.text = question_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 4)
	row.add_child(btn_box)

	var bg := ButtonGroup.new()
	var buttons: Array[Button] = []
	for i in range(1, 6):
		var btn := Button.new()
		btn.text                = str(i)
		btn.toggle_mode         = true
		btn.button_group        = bg
		btn.custom_minimum_size = Vector2(36, 36)
		btn_box.add_child(btn)
		buttons.append(btn)

	bg.pressed.connect(func(_b: BaseButton): _on_response(key, buttons))
	questions_box.add_child(row)


func _on_response(key: String, buttons: Array[Button]) -> void:
	for i in range(buttons.size()):
		if buttons[i].button_pressed:
			_responses[key] = i + 1
			break
	begin_button.disabled = _responses.size() < QUESTIONS.size()


func _on_begin_pressed() -> void:
	survey_completed.emit(_calculate_alpha(), _responses.duplicate())


func _calculate_alpha() -> float:
	var total: float = 0.0
	for item: Array in QUESTIONS:
		var key: String   = item[0]
		var reverse: bool = item[2]
		var score: int    = _responses.get(key, 3)
		total += (6 - score) if reverse else score
	var avg: float = total / float(QUESTIONS.size())
	return PersonalityConfig.alpha_for_survey_mean(avg)
