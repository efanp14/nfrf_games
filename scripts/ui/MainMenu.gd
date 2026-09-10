class_name MainMenu
extends CanvasLayer
## MainMenu.gd
## The researcher's setup screen: treatment, session kind, participant IDs,
## group ID, player count. Emits `game_starting` once and hides.
##
## This screen is operated by the researcher with a participant sitting there,
## which drives most of its design. IDs are ISSUED rather than typed where
## possible (ParticipantId, GroupId), the group ID is shown read-only because
## the voice recorder has to be labelled with it before the session starts, and
## _refresh_validity() separates problems that BLOCK a start from warnings that
## do not -- only certain corruption is worth refusing a session over when
## someone is waiting.
##
## The seat colours appear beside the ID fields because the game identifies a
## group only as P1/P2/P3 in colour and never by ID; this is the one moment the
## two are visibly connected, and it is deliberately here rather than in-game.
##
## The player-count row is shown only for T3. T1 and T2 are single-player.

signal game_starting(treatment: int, num_players: int, participant_ids: Array, group_id: String, chain_to_t2: bool, session_kind: String)

@onready var treatment_option: OptionButton = %TreatmentOption
@onready var start_button: Button           = %StartButton
@onready var data_folder_button: Button     = %DataFolderButton
@onready var export_data_button: Button     = %ExportDataButton
@onready var quit_button: Button            = %QuitButton

var _player_count_row: HBoxContainer
var _player_count_spin: SpinBox

## What this session counts as: study data, a pilot, or a development test.
## First control on the menu, above the treatment, because it decides whether
## anything that follows is data at all. See ResearchConfig for why it defaults
## to test.
var _kind_option: OptionButton
var _kind_note: Label

## One text field per participant, rebuilt whenever the player count changes.
## The ID is what joins that person's separate treatment sessions together
## afterwards. It can be typed, since the research team may have a scheme of its
## own and the older p001 IDs are still in the data, or issued by the Generate
## button beside the field (see ParticipantId).
var _participant_box: VBoxContainer
var _participant_fields: Array[LineEdit] = []

## Said under the fields after an ID is issued, so the researcher is told to
## write it down at the one moment it matters. Held rather than written straight
## to the status label because _refresh_validity() owns that label and would
## overwrite it on the next keystroke.
var _issued_note: String = ""

## The letter this computer's issued IDs begin with. An install-level setting,
## not a per-session one, which is why it lives at the bottom of the menu with
## the data folder rather than in the session setup.
var _machine_option: OptionButton
var _machine_note: Label

## The group these participants belong to. Shown ONLY in the group treatment,
## where it ties a discussion recorded on a separate device back to the rounds
## it covers; an individual session has no group decision and no recording.
## Which group a solo participant belonged to is recovered afterwards from the
## group session that names them (tools/aggregate_logs.py).
##
## Assigned by GroupId, not typed. Nothing anywhere parses the value, so there
## was never a decision for the researcher to make here, only a field to get
## wrong; and a wrong group is worse than a wrong participant, because the
## aggregator propagates it into every member's individual rows.
##
## An even earlier version tried to derive it from the participant numbers,
## which only worked for bare integers and so never fired for the prefixed IDs
## actually in use.
var _group_value: Label
## Worked out when the group treatment is selected, not on every refresh, since
## it reads the roster and every session's parameters.json. Held so that what
## the researcher writes on the recorder is exactly what the session records.
var _pending_group_id: String = ""
## Shown only in the group treatment; see _on_treatment_changed().
var _group_row: HBoxContainer
var _status_label: Label


func _ready() -> void:
	visible = true
	# The scrim comes from Palette rather than from the scene, so every
	# screen's backdrop is set in the one place colours are declared.
	($Overlay as ColorRect).color = Palette.OVERLAY_FULL
	# No subtitle, tagline or framing paragraph here any more. This screen is the
	# researcher's setup, not the participant's opening: NarrativeIntro gives the
	# player the framing once the session starts, and stating the budget twice is
	# how the figure came to disagree with itself before.
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
	group_lbl.text = "Group"
	group_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_lbl.add_theme_font_size_override("font_size", 12)
	group_row.add_child(group_lbl)
	# Shown, not asked for. The value is opaque and nothing parses it, so there
	# was nothing for the researcher to decide, only something to mistype at the
	# one moment they have no attention to spare. It stays visible because the
	# voice recorder has to be labelled with it before the session starts.
	_group_value = Label.new()
	_group_value.add_theme_font_size_override("font_size", 12)
	_group_value.add_theme_color_override("font_color", Palette.BRAND_GOLD)
	group_row.add_child(_group_value)
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

	_build_machine_row()

	data_folder_button.pressed.connect(_on_data_folder_pressed)
	export_data_button.pressed.connect(_on_export_data_pressed)
	# A browser build has no folder to open: there, user:// is storage inside
	# the browser rather than a path on disk.
	data_folder_button.visible = not OS.has_feature("web")
	_refresh_data_folder_button()

	quit_button.pressed.connect(_on_quit_pressed)
	# A browser tab cannot be closed by the page it shows, and iOS does not let
	# an app quit itself, so on both the button would do nothing and read as broken.
	quit_button.visible = not (OS.has_feature("web") or OS.has_feature("ios"))


## The letter every ID issued on this computer begins with.
##
## Sits at the bottom with the other machine-level controls rather than in the
## session setup above, because it is set once per install and then never
## touched. Putting it in the flow would mean the researcher's eye passing over
## it before every session for a setting they change once.
##
## Worth setting deliberately on each computer that issues IDs. The derived
## default is a hash of the device with nothing coordinating the two machines,
## so they share a letter about one time in twenty-two, and a shared letter is
## the only route by which two machines could ever issue the same ID. Different
## letters rule it out by construction.
func _build_machine_row() -> void:
	var vbox := data_folder_button.get_parent()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = "This machine"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(lbl)

	_machine_option = OptionButton.new()
	_machine_option.tooltip_text = ("The letter participant IDs issued here begin with. Give "
			+ "each computer that issues IDs a different letter. IDs already issued keep the "
			+ "letter they were made with.")
	var current := ParticipantId.machine_letter()
	for i in range(ParticipantId.LETTERS.length()):
		var letter := ParticipantId.LETTERS[i]
		_machine_option.add_item(letter, i)
		if letter == current:
			_machine_option.selected = i
	_machine_option.item_selected.connect(_on_machine_letter_selected)
	row.add_child(_machine_option)

	vbox.add_child(row)
	vbox.move_child(row, data_folder_button.get_index())

	_machine_note = Label.new()
	_machine_note.add_theme_font_size_override("font_size", 11)
	_machine_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_machine_note.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	vbox.add_child(_machine_note)
	vbox.move_child(_machine_note, row.get_index() + 1)
	_refresh_machine_note()


func _on_machine_letter_selected(index: int) -> void:
	if index < 0 or index >= ParticipantId.LETTERS.length():
		return
	ParticipantId.set_machine_letter(ParticipantId.LETTERS[index])
	_refresh_machine_note()


## Says what the letter does, and how many IDs are already spoken for, since
## that is what decides whether changing it now matters.
func _refresh_machine_note() -> void:
	var issued := ParticipantId.roster_ids().size()
	var text := "IDs issued here start with %s." % ParticipantId.machine_letter()
	if issued > 0:
		text += "  %d already issued, unaffected by a change." % issued
	_machine_note.text = text


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


## Asks before quitting, then quits the way closing the window does.
##
## The confirmation is there for the tablet: this button sits directly under
## Export in a column of small buttons, and a tap that lands one row low would
## otherwise close the app with a participant sitting there.
##
## The close request is propagated before quitting rather than calling quit()
## alone, because a bare quit() skips NOTIFICATION_WM_CLOSE_REQUEST and that
## notification is what DataLogger flushes on. Nothing is normally unwritten at
## the menu, but this keeps a single way out of the app, so anything that ever
## saves on close gets its chance from here too.
func _on_quit_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	add_child(dialog)
	dialog.exclusive = true
	dialog.title = "Quit CycleCity"
	dialog.dialog_text = "Close the game?"
	dialog.ok_button_text = "Quit"
	dialog.confirmed.connect(_quit)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _quit() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()


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
	# Worked out once here rather than on every keystroke: it reads the roster
	# and every session's parameters.json. Read, not reserved, so switching back
	# and forth on the menu cannot burn group numbers.
	if treatment_id == 2:
		_pending_group_id = GroupId.next()
		_group_value.text = _pending_group_id
	else:
		_pending_group_id = ""
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

		# The seat colour this ID will be playing as, shown at the one moment the
		# researcher is looking at the IDs and can say it out loud.
		#
		# In the group treatment three people share one screen and the game
		# identifies them only as P1, P2 and P3 in their seat colours: the map
		# markers, the route bands, the HUD rows and both summary screens all use
		# colour and never the ID. Nothing anywhere connected the two, so
		# afterwards nobody could say which participant the pink commute belonged
		# to. Shown here rather than in-game deliberately, since a research
		# identifier on screen for three hours is a participant's business, not
		# something they should be reading.
		row.add_child(_seat_swatch(i))

		var lbl := Label.new()
		lbl.text = "Participant ID" if count == 1 else "Participant ID  (Player %d)" % (i + 1)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 12)
		if count > 1:
			lbl.add_theme_color_override("font_color",
					Palette.seat_color(i))
		row.add_child(lbl)

		var field := LineEdit.new()
		field.custom_minimum_size = Vector2(140, 0)
		field.placeholder_text = "Generate, or type"
		field.text = previous[i] if i < previous.size() else ""
		# Typing by hand answers the "was this just issued" note, so it clears.
		field.text_changed.connect(func(_t): _on_participant_field_edited())
		row.add_child(field)
		_participant_fields.append(field)

		var generate := Button.new()
		generate.text = "Generate"
		generate.tooltip_text = ("Issue a new participant ID that has not been used on "
				+ "this machine. Write it on the participant's card: they need it again "
				+ "for the group session.")
		generate.visible = _generation_offered()
		# bind() rather than a lambda closing over i, which is the shape that has
		# silently captured the wrong value elsewhere in this project.
		generate.pressed.connect(_on_generate_pressed.bind(i))
		row.add_child(generate)

		_participant_box.add_child(row)

	_refresh_validity()


## A filled disc in one seat's colour, drawn rather than themed so it matches
## Palette.PLAYER_COLORS exactly and cannot drift from the map.
func _seat_swatch(player_index: int) -> Control:
	var swatch := ColorRect.new()
	swatch.color = Palette.seat_color(player_index)
	swatch.custom_minimum_size = Vector2(16, 16)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.tooltip_text = "This participant plays as Player %d, in this colour." % (player_index + 1)
	return swatch


## Whether the Generate button is offered for the treatment now selected.
##
## Not in the group treatment. An ID is issued once, at the participant's first
## session, and carried to the group machine on a card; a Generate button there
## invites issuing a second one, which would leave that person's individual
## sessions joined to nothing. Typing is unaffected, so a participant whose
## first session really is a group one can still be given an ID by hand.
func _generation_offered() -> bool:
	return treatment_option.get_selected_id() != 2


func _on_participant_field_edited() -> void:
	_issued_note = ""
	_refresh_validity()


## Issues an ID into one field and records it as spent.
##
## Recorded at the moment it is issued rather than when the session starts,
## because a card can be written out for someone who then never plays, and
## handing the same ID to the next participant would merge two people.
func _on_generate_pressed(index: int) -> void:
	if index < 0 or index >= _participant_fields.size():
		return
	var issued := ParticipantId.generate()
	if issued.is_empty():
		_issued_note = ""
		_refresh_validity()
		_status_label.text = "Could not issue an ID. Enter one by hand and tell the study lead."
		_status_label.add_theme_color_override("font_color", Palette.ERROR_TEXT)
		return
	ParticipantId.issue(issued)
	var shown := ParticipantId.format_for_display(issued)
	_participant_fields[index].text = shown
	_issued_note = "Issued %s. Write it on the participant's card; they need it for T3." % shown
	_refresh_validity()
	_refresh_machine_note()


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

	# The group is assigned rather than typed, so this can only fire if
	# GroupId.next() somehow produced nothing. Kept as a backstop: a group
	# session recorded without a group cannot be tied to its own audio.
	var group := _entered_group_id()
	if _group_required() and not ResearchConfig.is_valid_id(group):
		problems.append("No group could be assigned. Check the data folder is writable.")

	start_button.disabled = not problems.is_empty()
	if not problems.is_empty():
		_status_label.text = problems[0]
		_status_label.add_theme_color_override("font_color", Palette.ERROR_TEXT)
		return

	# Warnings do NOT block. A re-run after a false start is legitimate and
	# happens, so this says what the machine already knows and leaves the
	# decision where it belongs.
	#
	# The mistyped ID goes first of the two. A repeat is visible in the data and
	# recoverable from the paper session log; an ID typed one character wrong is
	# neither, since it records as a valid session belonging to a person who does
	# not exist, and the individual sessions it should have joined stay orphaned.
	var mistyped := _failing_check_character(ids)
	if not mistyped.is_empty():
		_status_label.text = "%s is not a valid issued ID. Check it against the participant's card." % ", ".join(mistyped)
		_status_label.add_theme_color_override("font_color", Palette.BRAND_GOLD)
		return

	var repeats := _already_played(ids)
	if not repeats.is_empty():
		_status_label.text = "Already played this treatment here: %s. Starting again will produce a second session for them." % ", ".join(repeats)
		_status_label.add_theme_color_override("font_color", Palette.BRAND_GOLD)
		return

	if not _issued_note.is_empty():
		_status_label.text = _issued_note
		_status_label.add_theme_color_override("font_color", Palette.BRAND_GOLD)
		return

	var who := "%d participant%s" % [ids.size(), "" if ids.size() == 1 else "s"]
	_status_label.text = ("Group %s  ·  %s" % [group, who]) if _group_required() else who
	_status_label.remove_theme_color_override("font_color")


## Entered IDs that have the shape of an issued one but fail its check
## character, which is what a single mistyped or transposed character looks
## like.
##
## Deliberately a warning rather than a block, matching how this file treats
## everything that is not certain corruption. An ID that is not from the
## generator is not judged at all: the older p001 IDs are still in the data and
## the research team may bring a scheme of its own.
func _failing_check_character(ids: Array) -> PackedStringArray:
	var suspect := PackedStringArray()
	for id in ids:
		var typed := str(id).strip_edges()
		if typed.is_empty():
			continue
		if ParticipantId.has_scheme_shape(typed) and not ParticipantId.looks_generated(typed):
			suspect.append(typed)
	return suspect


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


## The assigned group, or empty outside the group treatment. Read through this
## rather than off the held value directly, so a group worked out and then left
## behind by switching treatment cannot be sent with a session that has none.
func _entered_group_id() -> String:
	if not _group_required():
		return ""
	return _pending_group_id


## The entered IDs, with issued ones reduced to their canonical form.
##
## Canonicalising here rather than in the field means one spelling reaches the
## participant store, the folder name and the log however the card was written:
## a7k-2q9, A7K2Q9 and A7K-2Q9 are one participant, not three. Anything that
## does not verify as an issued ID is passed through exactly as typed, since
## uppercasing an existing p001 would orphan the sessions already recorded
## under it.
func _participant_ids() -> Array:
	var out: Array = []
	for field in _participant_fields:
		out.append(ParticipantId.canonical_or_verbatim(field.text))
	return out


func _on_start_pressed() -> void:
	var selected := treatment_option.get_selected_id()
	var chained := selected == CHAINED_T1_T2
	# The chained entry starts T1; the follow-on treatment is queued only once
	# T1's post-survey is in, so an abandoned T1 never leaves a T2 waiting.
	var treatment := int(GameManager.Treatment.INDIVIDUAL) if chained else selected
	var group := _entered_group_id()
	# Committed here rather than when it was worked out, so that a group number
	# is spent by a session actually starting and not by looking at the menu.
	if not group.is_empty():
		GroupId.issue(group)
	game_starting.emit(treatment, _current_player_count(),
			_participant_ids(), group, chained, selected_session_kind())
	hide()
