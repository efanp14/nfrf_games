class_name MainMenu
extends CanvasLayer

signal game_starting(treatment: int, num_players: int, participant_ids: Array, group_id: String, chain_to_t2: bool)

@onready var treatment_option: OptionButton = %TreatmentOption
@onready var start_button: Button           = %StartButton
@onready var intro_label: Label             = %IntroLabel

var _player_count_row: HBoxContainer
var _player_count_spin: SpinBox

## One text field per participant, rebuilt whenever the player count changes.
## The researcher types the ID each person was assigned; it is what joins that
## person's separate treatment sessions together afterwards, so it is entered
## rather than generated. Free text, because the ID scheme is the research
## team's to choose and may not be a plain number.
var _participant_box: VBoxContainer
var _participant_fields: Array[LineEdit] = []

## The group these participants belong to, typed by the researcher exactly as
## the participant IDs are. Asked for ONLY in the group treatment, where it ties
## a discussion recorded on a separate device back to the rounds it covers; an
## individual session has no group decision and no recording. Which group a solo
## participant belonged to is recovered afterwards from the group session that
## names them (tools/aggregate_logs.py).
##
## Nothing pre-fills it. An earlier version derived a guess from the participant
## numbers, which only worked for bare integers and so never fired for the
## prefixed IDs actually in use.
var _group_field: LineEdit
## Shown only in the group treatment; see _on_treatment_changed().
var _group_row: HBoxContainer
var _status_label: Label


func _ready() -> void:
	visible = true
	# Quoted from the one place the budget is defined, so this line cannot go
	# stale the next time the figure is re-derived.
	intro_label.text = ("You are a citizen-planner with %s per round to upgrade roads with "
			+ "painted bike lanes or protected cycle tracks — longer roads cost more. "
			+ "Help shape a city that works for everyone.") % Player.format_dollars(
					Player.DEFAULT_CREDITS_PER_ROUND)
	treatment_option.add_item("T1 — Individual  (personal stats only)", 0)
	treatment_option.add_item("T2 — Collective Info  (city averages shown)", 1)
	treatment_option.add_item("T3 — Coordination  (city averages + chat)", 2)
	# The chained option, and the one a real session normally uses: the protocol
	# has each person play T1 and then T2 individually, so the two belong in one
	# uninterrupted sitting rather than as two runs the researcher sets up by
	# hand. T3 is deliberately not chainable, being a group session on a shared
	# machine. The single-treatment entries above stay for re-runs and testing.
	treatment_option.add_item("T1 then T2  (back to back, one participant)", CHAINED_T1_T2)
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
	_player_count_spin.value_changed.connect(func(_v): _rebuild_participant_rows())

	_participant_box = VBoxContainer.new()
	_participant_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_participant_box)
	vbox.move_child(_participant_box, _player_count_row.get_index() + 1)

	_group_row = HBoxContainer.new()
	var group_row := _group_row
	group_row.add_theme_constant_override("separation", 10)
	var group_lbl := Label.new()
	group_lbl.text = "Group ID"
	group_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_lbl.add_theme_font_size_override("font_size", 12)
	group_row.add_child(group_lbl)
	_group_field = LineEdit.new()
	_group_field.custom_minimum_size = Vector2(140, 0)
	_group_field.placeholder_text = "e.g. g001"
	_group_field.text_changed.connect(func(_t): _refresh_validity())
	group_row.add_child(_group_field)
	vbox.add_child(group_row)
	vbox.move_child(group_row, _participant_box.get_index() + 1)
	# Hidden until the group treatment is chosen; the menu opens on T1.
	group_row.visible = false

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)
	vbox.move_child(_status_label, group_row.get_index() + 1)

	_rebuild_participant_rows()


## Item id for the chained option. Not a treatment in its own right: it starts
## T1 and queues T2, so everything downstream still sees one treatment at a time.
const CHAINED_T1_T2: int = 3


func _on_treatment_changed(index: int) -> void:
	var treatment_id := treatment_option.get_item_id(index)
	# Adjustable player count is T3-only. T1 and T2 are strictly
	# single-player — this control must not appear for T2.
	_player_count_row.visible = treatment_id == 2
	# The group is only asked for where it is load-bearing: it is what ties a
	# discussion recorded on a separate device back to the rounds it covers.
	# An individual session has no group decision and no recording, so asking
	# there was one more thing to type and one more thing to mistype, with a
	# wrong group linking a person to the wrong people and nothing able to catch
	# it. Who belongs to which group is recovered from the group session itself
	# at analysis time (see tools/aggregate_logs.py).
	_group_row.visible = treatment_id == 2
	_rebuild_participant_rows()


func _group_required() -> bool:
	return treatment_option.get_selected_id() == 2


func _current_player_count() -> int:
	if treatment_option.get_selected_id() == 2:
		return int(_player_count_spin.value)
	return 1


## Rebuilds the ID fields from scratch on any change to the player count,
## keeping whatever was already typed so switching treatment does not make the
## researcher re-enter it.
func _rebuild_participant_rows() -> void:
	var previous: Array[String] = []
	for field in _participant_fields:
		previous.append(field.text)

	for child in _participant_box.get_children():
		_participant_box.remove_child(child)
		child.queue_free()
	_participant_fields.clear()

	var count := _current_player_count()
	for i in range(count):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lbl := Label.new()
		lbl.text = "Participant ID" if count == 1 else "Participant ID  (Player %d)" % (i + 1)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl)

		var field := LineEdit.new()
		field.custom_minimum_size = Vector2(140, 0)
		field.placeholder_text = "e.g. %d" % (i + 1)
		field.text = previous[i] if i < previous.size() else ""
		field.text_changed.connect(func(_t): _refresh_validity())
		row.add_child(field)
		_participant_fields.append(field)
		_participant_box.add_child(row)

	_refresh_validity()


## Blocks Start on anything that would corrupt the record, and says why.
##
## The checks are not cosmetic. A blank or duplicate ID cannot be un-merged
## after sessions have been run, and an ID with a slash or colon in it becomes
## a filename in the participant store, so it would either fail to write or
## write somewhere unintended.
func _refresh_validity() -> void:
	var ids := _participant_ids()
	var problems: Array[String] = []

	var blank := false
	var illegal := false
	for id in ids:
		if str(id).strip_edges().is_empty():
			blank = true
		elif not ResearchConfig.is_valid_id(str(id)):
			illegal = true
	if blank:
		problems.append("Enter an ID for every participant")
	if illegal:
		problems.append("IDs may use letters, digits, hyphen and underscore only")

	var seen := {}
	for id in ids:
		var key := str(id).strip_edges()
		if not key.is_empty() and seen.has(key):
			problems.append("Participant IDs must all be different")
			break
		seen[key] = true

	var group := _entered_group_id()
	if _group_required():
		if group.is_empty():
			problems.append("Enter a group ID")
		elif not ResearchConfig.is_valid_id(group):
			problems.append("Group ID may use letters, digits, hyphen and underscore only")

	start_button.disabled = not problems.is_empty()
	if problems.is_empty():
		var who := "%d participant%s" % [ids.size(), "" if ids.size() == 1 else "s"]
		_status_label.text = ("Group %s  ·  %s" % [group, who]) if _group_required() else who
		_status_label.remove_theme_color_override("font_color")
	else:
		_status_label.text = problems[0]
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))


## The typed group, or empty outside the group treatment. Read through this
## rather than off the field directly, so a value left over from switching
## treatment on the menu cannot be sent with a session that never asked for one.
func _entered_group_id() -> String:
	if not _group_required():
		return ""
	return _group_field.text.strip_edges()


func _participant_ids() -> Array:
	var out: Array = []
	for field in _participant_fields:
		out.append(field.text.strip_edges())
	return out


func _on_start_pressed() -> void:
	var selected := treatment_option.get_selected_id()
	var chained := selected == CHAINED_T1_T2
	# The chained entry starts T1; the follow-on treatment is queued only once
	# T1's post-survey is in, so an abandoned T1 never leaves a T2 waiting.
	var treatment := int(GameManager.Treatment.INDIVIDUAL) if chained else selected
	game_starting.emit(treatment, _current_player_count(),
			_participant_ids(), _entered_group_id(), chained)
	hide()
