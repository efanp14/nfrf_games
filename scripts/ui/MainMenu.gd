class_name MainMenu
extends CanvasLayer

signal game_starting(treatment: int, num_players: int, participant_ids: Array, group_id: String, chain_to_t2: bool, session_kind: String)

@onready var treatment_option: OptionButton = %TreatmentOption
@onready var start_button: Button           = %StartButton
@onready var intro_label: Label             = %IntroLabel
@onready var data_folder_button: Button     = %DataFolderButton
@onready var export_data_button: Button     = %ExportDataButton

var _player_count_row: HBoxContainer
var _player_count_spin: SpinBox

## What this session counts as: study data, a pilot, or a development test.
## First control on the menu, above the treatment, because it decides whether
## anything that follows is data at all. See ResearchConfig for why it defaults
## to test.
var _kind_option: OptionButton
var _kind_note: Label

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
	# The scrim comes from Palette rather than from the scene, so every
	# screen's backdrop is set in the one place colours are declared.
	($Overlay as ColorRect).color = Palette.OVERLAY_FULL
	# Quoted from the one place the budget is defined, so this line cannot go
	# stale the next time the figure is re-derived.
	intro_label.text = ("You are a citizen-planner with %s per round to upgrade roads with "
			+ "painted bike lanes or protected cycle tracks — longer roads cost more. "
			+ "Help shape a city that works for everyone.") % Player.format_dollars(
					Player.DEFAULT_CREDITS_PER_ROUND)
	treatment_option.add_item("T1 — Individual  (personal stats only)", 0)
	treatment_option.add_item("T2 — Collective Info  (city averages shown)", 1)
	treatment_option.add_item("T3 — Coordination  (city averages + group discussion)", 2)
	# The chained option, and the one a real session normally uses: the protocol
	# has each person play T1 and then T2 individually, so the two belong in one
	# uninterrupted sitting rather than as two runs the researcher sets up by
	# hand. T3 is deliberately not chainable, being a group session on a shared
	# machine. The single-treatment entries above stay for re-runs and testing.
	treatment_option.add_item("T1 then T2  (back to back, one participant)", CHAINED_T1_T2)
	treatment_option.selected = 0
	treatment_option.item_selected.connect(_on_treatment_changed)
	start_button.pressed.connect(_on_start_pressed)

	_build_session_kind_row()

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

	data_folder_button.pressed.connect(_on_data_folder_pressed)
	export_data_button.pressed.connect(_on_export_data_pressed)
	# A browser build has no folder to open: there, user:// is storage inside
	# the browser rather than a path on disk.
	data_folder_button.visible = not OS.has_feature("web")
	_refresh_data_folder_button()


## Sits above the treatment selector, since it decides whether this session is
## data at all, and carries a plain-words note underneath rather than relying on
## the researcher reading a dropdown entry back to themselves.
func _build_session_kind_row() -> void:
	var vbox := treatment_option.get_parent()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = "Session type"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	_kind_option = OptionButton.new()
	_kind_option.custom_minimum_size = Vector2(280, 0)
	for i in range(ResearchConfig.SESSION_KINDS.size()):
		var kind: String = ResearchConfig.SESSION_KINDS[i]
		_kind_option.add_item(ResearchConfig.SESSION_KIND_LABELS[kind], i)
	_kind_option.selected = ResearchConfig.SESSION_KINDS.find(
			ResearchConfig.DEFAULT_SESSION_KIND)
	_kind_option.item_selected.connect(func(_i): _refresh_kind_note())
	row.add_child(_kind_option)

	vbox.add_child(row)
	vbox.move_child(row, treatment_option.get_index())

	_kind_note = Label.new()
	_kind_note.add_theme_font_size_override("font_size", 12)
	_kind_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_kind_note)
	vbox.move_child(_kind_note, row.get_index() + 1)
	_refresh_kind_note()


## Study sessions are stated in the emphasis colour and the other two in the
## muted one, so "this is being recorded as real data" is the line that catches
## the eye rather than one of three similar sentences.
func _refresh_kind_note() -> void:
	var kind := selected_session_kind()
	_kind_note.text = ResearchConfig.SESSION_KIND_NOTES[kind]
	_kind_note.add_theme_color_override("font_color",
			Palette.TEXT_HEADING if ResearchConfig.is_study_session(kind)
			else Palette.TEXT_MUTED)


func selected_session_kind() -> String:
	var idx := _kind_option.selected
	if idx < 0 or idx >= ResearchConfig.SESSION_KINDS.size():
		return ResearchConfig.DEFAULT_SESSION_KIND
	return ResearchConfig.SESSION_KINDS[idx]


## Packs every session into one zip and says where it went.
##
## The button exists mainly for the tablet, where the data is otherwise
## unreachable: app storage on Android is not browsable over USB, so "open the
## folder and copy it" has no meaning there. It earns its place on the desktop
## too, since one file per machine is easier to collect than a folder of
## folders.
##
## The result is reported in full rather than as "done". Where the file landed
## is the part that matters, and on Android it is also the part that decides
## whether the researcher can plug in a cable or has to share it off the device.
func _on_export_data_pressed() -> void:
	export_data_button.disabled = true
	export_data_button.text = "Exporting..."
	# Let the label paint before the zip blocks the frame.
	await get_tree().process_frame

	var report: Dictionary = SessionExporter.export_all()
	export_data_button.disabled = false
	export_data_button.text = "Export All Sessions (zip)"

	var dialog := AcceptDialog.new()
	add_child(dialog)
	dialog.exclusive = true
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

	if not bool(report.get("ok", false)):
		dialog.title = "Export failed"
		dialog.dialog_text = str(report.get("error", "Unknown error."))
		dialog.popup_centered()
		return

	var lines := PackedStringArray()
	lines.append("%d session%s, %d files" % [int(report.get("sessions", 0)),
			"" if int(report.get("sessions", 0)) == 1 else "s",
			int(report.get("files", 0))])
	lines.append(SessionSavedDialog._format_size(int(report.get("bytes", 0))))
	lines.append("")
	lines.append(str(report.get("path", "")))
	if not bool(report.get("reachable", true)):
		lines.append("")
		lines.append("This folder is inside the app's own storage, which a")
		lines.append("computer cannot see over USB. Share the file from the")
		lines.append("device to get it off.")
	dialog.title = "Sessions exported"
	dialog.dialog_text = "
".join(lines)
	dialog.popup_centered()


## Opens the folder every session is written into.
##
## The folder is created first, so the button does the same thing before the
## first session as after it. An empty folder is the honest answer to "where
## does the data go"; a button that silently does nothing reads as broken, and
## the first press is exactly when nothing has been written yet.
func _on_data_folder_pressed() -> void:
	DirAccess.make_dir_recursive_absolute(DataLogger.SESSIONS_ROOT)
	var absolute := ProjectSettings.globalize_path(DataLogger.SESSIONS_ROOT)
	if OS.shell_open(absolute) != OK:
		# Nothing further can be done from in here, so surface the path itself:
		# it can still be pasted into a file manager by hand.
		_status_label.text = absolute
		_status_label.remove_theme_color_override("font_color")


## Counts the sessions already on disk and says so on the button, so the data
## can be confirmed present before a testing machine is wiped or handed back.
## Sessions written earlier in this sitting are included, the chained T1-into-T2
## flow reloading the scene between its halves.
func _refresh_data_folder_button() -> void:
	var count := _session_count()
	if count == 0:
		data_folder_button.text = "Open Data Folder"
	else:
		data_folder_button.text = "Open Data Folder  (%d session%s)" % [
				count, "" if count == 1 else "s"]


func _session_count() -> int:
	var dir := DirAccess.open(DataLogger.SESSIONS_ROOT)
	if dir == null:
		return 0
	return dir.get_directories().size()


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
	if not problems.is_empty():
		_status_label.text = problems[0]
		_status_label.add_theme_color_override("font_color", Palette.ERROR_TEXT)
		return

	# Warnings do NOT block. A re-run after a false start is legitimate and
	# happens, so this says what the machine already knows and leaves the
	# decision where it belongs.
	var repeats := _already_played(ids)
	if not repeats.is_empty():
		_status_label.text = "Already played this treatment here: %s. Starting again will produce a second session for them." % ", ".join(repeats)
		_status_label.add_theme_color_override("font_color", Palette.BRAND_GOLD)
		return

	var who := "%d participant%s" % [ids.size(), "" if ids.size() == 1 else "s"]
	_status_label.text = ("Group %s  ·  %s" % [group, who]) if _group_required() else who
	_status_label.remove_theme_color_override("font_color")


## Which of the entered participants have already played the treatment about to
## be started, according to this machine's participant store.
##
## Reuse used to surface only at analysis time, as a DUPLICATE line in the
## aggregate report, possibly weeks after the session that caused it. By then
## one of the two sessions has to be discarded, and the participant's time with
## it. Two seconds at the menu is a better place to find out.
##
## The chained entry starts T1 and queues T2, so both count as about to be
## played. The store is local, so a treatment played on another machine is
## invisible here; the warning can miss, but it cannot cry wolf.
func _already_played(ids: Array) -> PackedStringArray:
	var selected := treatment_option.get_selected_id()
	var about_to_play: Array = [int(GameManager.Treatment.INDIVIDUAL),
			int(GameManager.Treatment.COLLECTIVE_INFO)] if selected == CHAINED_T1_T2 else [selected]
	var repeats := PackedStringArray()
	for id in ids:
		var pid := str(id).strip_edges()
		if pid.is_empty():
			continue
		for t: int in about_to_play:
			if ParticipantStore.has_played_treatment(pid, t):
				repeats.append(pid)
				break
	return repeats


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
			_participant_ids(), _entered_group_id(), chained, selected_session_kind())
	hide()
