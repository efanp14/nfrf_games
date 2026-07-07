class_name MainMenu
extends CanvasLayer

signal game_starting(treatment: int, num_players: int)

@onready var treatment_option: OptionButton = %TreatmentOption
@onready var start_button: Button           = %StartButton

var _player_count_row: HBoxContainer
var _player_count_spin: SpinBox


func _ready() -> void:
	visible = true
	treatment_option.add_item("T1 — Individual  (personal stats only)", 0)
	treatment_option.add_item("T2 — Collective Info  (city averages shown)", 1)
	treatment_option.add_item("T3 — Coordination  (city averages + chat)", 2)
	treatment_option.selected = 0
	treatment_option.item_selected.connect(_on_treatment_changed)
	start_button.pressed.connect(_on_start_pressed)

	_player_count_row = HBoxContainer.new()
	_player_count_row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = "Number of Players"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_count_row.add_child(lbl)
	_player_count_spin = SpinBox.new()
	_player_count_spin.min_value = 2
	_player_count_spin.max_value = 5
	_player_count_spin.value = 3
	_player_count_spin.step = 1
	_player_count_row.add_child(_player_count_spin)
	var vbox := treatment_option.get_parent()
	vbox.add_child(_player_count_row)
	vbox.move_child(_player_count_row, treatment_option.get_index() + 1)
	_player_count_row.visible = false


func _on_treatment_changed(index: int) -> void:
	var treatment_id := treatment_option.get_item_id(index)
	_player_count_row.visible = treatment_id != 0


func _on_start_pressed() -> void:
	var treatment := treatment_option.get_selected_id()
	var num_players := 1
	if treatment != 0:
		num_players = int(_player_count_spin.value)
	game_starting.emit(treatment, num_players)
	hide()
