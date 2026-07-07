class_name PostSurvey
extends CanvasLayer

signal survey_completed(responses: Dictionary)

# Four construct blocks. DQI (index 3) is T3-only.
const SECTIONS: Array = [
	{
		"title": "Outcome Perception",
		"questions": [
			["op_1", "My commute improved over the course of the game"],
			["op_2", "The infrastructure upgrades I chose were effective"],
			["op_3", "The game outcome matched my initial expectations"],
		]
	},
	{
		"title": "Distributional Fairness",
		"questions": [
			["df_1", "Cycling infrastructure was invested in fairly across the city"],
			["df_2", "I tried to invest in roads that would benefit the most commuters"],
			["df_3", "I considered other commuters' needs when deciding where to invest"],
		]
	},
	{
		"title": "Collective Investment Willingness",
		"questions": [
			["cw_1", "I would support greater public spending on cycling infrastructure"],
			["cw_2", "Upgrades that help everyone are more valuable than upgrades only for my own route"],
			["cw_3", "People should contribute to cycling infrastructure even if they do not cycle"],
		]
	},
	{
		"title": "Group Discussion Quality",
		"questions": [
			["dqi_1", "The group discussion helped us make better investment decisions"],
			["dqi_2", "All group members had equal opportunity to speak and contribute"],
			["dqi_3", "Our investment decisions were reached through reasoned argument"],
			["dqi_4", "The group considered the needs of all commuters, not just our own route"],
		]
	}
]

var _responses: Dictionary = {}
var _all_keys: Array[String] = []
var _treatment: int = 0

@onready var questions_box: VBoxContainer = %QuestionsBox
@onready var submit_button: Button        = %SubmitButton


func _ready() -> void:
	visible = false
	submit_button.disabled = true
	submit_button.pressed.connect(_on_submit)


func show_survey(treatment: int) -> void:
	_treatment = treatment
	_responses.clear()
	_all_keys.clear()
	for child in questions_box.get_children():
		child.queue_free()
	_build_questions()
	submit_button.disabled = true
	visible = true


func _build_questions() -> void:
	for section_idx in range(SECTIONS.size()):
		var section: Dictionary = SECTIONS[section_idx]
		if section_idx == 3 and _treatment != 2:   # DQI only for T3
			continue

		var header := Label.new()
		header.text = section["title"]
		header.add_theme_font_size_override("font_size", 14)
		questions_box.add_child(header)

		for item: Array in section["questions"]:
			_all_keys.append(item[0] as String)
			_add_question_row(item[0] as String, item[1] as String)

		questions_box.add_child(HSeparator.new())


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
		btn.text    = str(i)
		btn.toggle_mode          = true
		btn.button_group         = bg
		btn.custom_minimum_size  = Vector2(36, 36)
		btn_box.add_child(btn)
		buttons.append(btn)

	# Capture key + buttons array per-row in the closure.
	bg.pressed.connect(func(_b: BaseButton): _on_response(key, buttons))
	questions_box.add_child(row)


func _on_response(key: String, buttons: Array[Button]) -> void:
	for i in range(buttons.size()):
		if buttons[i].button_pressed:
			_responses[key] = i + 1
			break
	submit_button.disabled = _responses.size() < _all_keys.size()


func _on_submit() -> void:
	survey_completed.emit(_responses.duplicate())
	hide()
