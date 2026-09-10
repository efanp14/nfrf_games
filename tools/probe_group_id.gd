extends Node
## Checks group ID assignment and the menu row that shows it. Run as a scene.
##
##   godot --headless res://tools/probe_group_id.tscn

var _failures: int = 0
var _had_roster: bool = false
var _roster_backup: String = ""


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL  %s" % what)


func _ready() -> void:
	_had_roster = FileAccess.file_exists(GroupId.ROSTER_PATH)
	if _had_roster:
		var r := FileAccess.open(GroupId.ROSTER_PATH, FileAccess.READ)
		if r != null:
			_roster_backup = r.get_as_text()
			r.close()

	_counts_up()
	_header_is_not_read_back()
	_old_style_ids_ignored()
	_played_group_survives_a_lost_roster()
	await _menu_shows_it()

	_restore()
	print("")
	print("FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## next() must advance only when a group is actually issued, and never repeat.
func _counts_up() -> void:
	var letter := ParticipantId.machine_letter()
	var first := GroupId.next()
	print("Next group: %s" % first)
	if not first.begins_with(letter + GroupId.MARKER):
		_fail("%s does not lead with this machine's letter" % first)

	# Reading it twice must not move it: browsing the menu cannot burn numbers.
	if GroupId.next() != first:
		_fail("next() advanced without a session starting")

	var seen := {}
	var previous := ""
	for _i in range(12):
		var id := GroupId.next()
		if seen.has(id):
			_fail("%s was handed out twice" % id)
		seen[id] = true
		previous = id
		GroupId.issue(id)
	print("Issued 12 in sequence, last was %s" % previous)
	if seen.size() != 12:
		_fail("expected 12 distinct group IDs, got %d" % seen.size())

	# The count is taken from the highest, not from the number of lines, so a
	# line removed from the MIDDLE must not shift everything after it down.
	var expected := GroupId.next()
	var text := ""
	var f := FileAccess.open(GroupId.ROSTER_PATH, FileAccess.READ)
	if f != null:
		text = f.get_as_text()
		f.close()
	var middle: String = "%sG05" % ParticipantId.machine_letter()
	var w := FileAccess.open(GroupId.ROSTER_PATH, FileAccess.WRITE)
	if w != null:
		w.store_string(text.replace(middle + "\n", ""))
		w.close()
	if GroupId.next() != expected:
		_fail("deleting %s from the middle moved the next group to %s"
				% [middle, GroupId.next()])
	else:
		print("Deleting %s from the middle leaves the next group at %s" % [middle, expected])


func _header_is_not_read_back() -> void:
	var ids := GroupId.roster_ids()
	for id: String in ids:
		if not GroupId.has_scheme_shape(id):
			_fail("'%s' was read out of the roster as a group ID" % id)
	print("Roster read back: %d IDs, no header or timestamp lines among them" % ids.size())


func _old_style_ids_ignored() -> void:
	# Groups typed by hand under the old scheme must not hold the counter back
	# or be mistaken for part of this sequence.
	for old: String in ["g001", "123", "group-1", ""]:
		if GroupId.has_scheme_shape(old):
			_fail("'%s' was treated as a generated group ID" % old)
	print("Old hand-typed groups (g001, 123, group-1) correctly not in the sequence")


## The claim that matters: a group that actually played keeps its number even if
## the roster is lost entirely, because the session recorded it in
## parameters.json. Stands in for a wiped or hand-deleted roster mid-study.
func _played_group_survives_a_lost_roster() -> void:
	var letter := ParticipantId.machine_letter()
	var played := "%sG42" % letter
	var folder: String = DataLogger.SESSIONS_ROOT.path_join("PROBE-group-id-delete-me")
	DirAccess.make_dir_recursive_absolute(folder)
	var params := FileAccess.open(folder.path_join("parameters.json"), FileAccess.WRITE)
	if params == null:
		_fail("could not stage a session folder")
		return
	params.store_string(JSON.stringify({"group_id": played}))
	params.close()

	# Roster gone completely.
	var saved := ""
	var f := FileAccess.open(GroupId.ROSTER_PATH, FileAccess.READ)
	if f != null:
		saved = f.get_as_text()
		f.close()
	DirAccess.remove_absolute(GroupId.ROSTER_PATH)

	var after := GroupId.next()
	if after == played:
		_fail("%s was handed out again after the roster was lost" % played)
	elif after != "%sG43" % letter:
		_fail("expected %sG43 from the session record alone, got %s" % [letter, after])
	else:
		print("With no roster at all, a played %s still forces the next to %s" % [played, after])

	var w := FileAccess.open(GroupId.ROSTER_PATH, FileAccess.WRITE)
	if w != null:
		w.store_string(saved)
		w.close()
	DirAccess.remove_absolute(folder.path_join("parameters.json"))
	DirAccess.remove_absolute(folder)


func _menu_shows_it() -> void:
	var menu: MainMenu = preload("res://scenes/ui/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame

	if menu._group_row.visible:
		_fail("the group row is showing on T1")

	menu.treatment_option.selected = 2
	menu._on_treatment_changed(2)
	await get_tree().process_frame
	if not menu._group_row.visible:
		_fail("the group row is hidden in T3")
	var shown: String = menu._group_value.text
	print("Menu shows for T3: %s" % shown)
	if shown != GroupId.next():
		_fail("the menu shows %s but the next group is %s" % [shown, GroupId.next()])
	if not menu._entered_group_id() == shown:
		_fail("what the session records differs from what the menu shows")

	# There is no field to type into any more.
	for child in menu._group_row.get_children():
		if child is LineEdit:
			_fail("the group is still an editable field")

	# Switching away must not carry the group into a session that has none.
	menu.treatment_option.selected = 0
	menu._on_treatment_changed(0)
	if not menu._entered_group_id().is_empty():
		_fail("a group was carried into T1")
	else:
		print("Switching to T1 drops the group, and the row hides")

	# And browsing back and forth must not have spent it.
	menu.treatment_option.selected = 2
	menu._on_treatment_changed(2)
	if menu._group_value.text != shown:
		_fail("browsing away and back moved the group from %s to %s"
				% [shown, menu._group_value.text])
	else:
		print("Browsing away and back still offers %s" % shown)


func _restore() -> void:
	if _had_roster:
		var w := FileAccess.open(GroupId.ROSTER_PATH, FileAccess.WRITE)
		if w != null:
			w.store_string(_roster_backup)
			w.close()
	else:
		DirAccess.remove_absolute(GroupId.ROSTER_PATH)
