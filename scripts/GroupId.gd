class_name GroupId
## GroupId.gd
## Names the set of people who play the group treatment together.
##
## The value is opaque: nothing anywhere parses it. It has three jobs, and each
## only needs the label to be distinct and stable.
##
##   - it is the `decision_maker_id` on group decision rows, since in that
##     treatment the group decides rather than a person (DataLogger);
##   - the aggregator recovers who was grouped with whom from it, filling the
##     group into those people's individual sessions and marking those rows
##     `group_id_derived` (tools/aggregate_logs.py, derive_groups);
##   - it goes into `audio_manifest.json`, which is how a discussion recorded on
##     a separate device is tied back to the rounds it covers.
##
## It used to be typed by the researcher. That was a field that could be
## mistyped at the one moment nobody has attention to spare, and a mistyped
## group is worse than a mistyped participant: it splits one group across two
## labels or merges two groups under one, and derive_groups then propagates that
## error into every member's individual rows. It is assigned here instead and
## shown on the menu read-only.
##
## SEQUENTIAL, NOT RANDOM, and deliberately unlike ParticipantId. A participant
## ID is carried between two machines on a slip of paper and typed back in, so
## it is drawn at random and carries a check character. A group ID never leaves
## this machine and is never typed back in; what it does have to do is get
## written on a voice recorder and said out loud. PG03 wins on both counts, and
## the properties the participant scheme pays for would buy nothing here.

## Machine letter, the marker, then the count on this machine: PG01, PG02.
## The machine letter leads for the same reason it does on a participant ID: two
## machines running group sessions would otherwise both start at 01, and two
## different groups sharing a label is the one failure that corrupts silently,
## since derive_groups would merge them.
const MARKER: String = "G"

## Where issued group IDs are recorded, beside the participant roster and for
## the same reasons: not session data, so not inside a session folder.
const ROSTER_PATH: String = DataLogger.SESSIONS_ROOT + "group_ids.txt"

const ROSTER_HEADER: String = """CycleCity: group IDs used on this machine, newest last.
Each entry is the ID on one line and the moment it was issued on the next.

DO NOT DELETE OR EDIT THIS FILE WHILE THE STUDY IS RUNNING.
The game reads it back to decide the next group number, so losing it would
start the count again and give two different groups the same name.

"""


## What the next group session will be recorded as.
##
## Read, not reserved: the menu shows this while the researcher is still
## choosing a treatment, and browsing the menu must not burn numbers. It is
## committed by issue() when a session actually starts.
static func next() -> String:
	return "%s%s%02d" % [ParticipantId.machine_letter(), MARKER, _highest_used() + 1]


## Records that a group ID has been used. Called when the session starts, which
## is the first moment the label is real.
static func issue(group_id: String) -> void:
	var clean := group_id.strip_edges().to_upper()
	if clean.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(DataLogger.SESSIONS_ROOT)
	var file: FileAccess
	if FileAccess.file_exists(ROSTER_PATH):
		file = FileAccess.open(ROSTER_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(ROSTER_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(ROSTER_HEADER)
	if file == null:
		push_warning("GroupId: could not write the roster at %s" % ROSTER_PATH)
		return
	file.store_string("%s\n%sZ\n\n" % [clean,
			Time.get_datetime_string_from_system(true)])
	file.close()


## The highest group number already used on this machine, or 0 if none.
##
## Two sources, because the roster alone would restart the count if it were
## deleted, and two groups sharing a label corrupts silently. The sessions
## themselves are the durable record: every session writes its group into
## parameters.json (DataLogger), so a group that was actually played still holds
## its number with the roster gone entirely. That is the case worth protecting,
## and it is the one that survives.
##
## The highest is taken rather than the count, so a line removed from the middle
## of the roster does not shift everything after it down.
##
## What this does NOT survive: deleting the LAST line of the roster for a group
## that never played a session. Nothing else recorded that number, so it comes
## back round. Hence the roster header telling people not to edit the file; the
## number is only truly spent once a session has written it.
static func _highest_used() -> int:
	var letter := ParticipantId.machine_letter()
	var highest := 0
	for id in _known_ids():
		var n := _number_in(id, letter)
		if n > highest:
			highest = n
	return highest


## Every group ID this machine can still see, from the roster and from the
## sessions already written.
static func _known_ids() -> PackedStringArray:
	var found := PackedStringArray()
	found.append_array(roster_ids())

	var sessions := DirAccess.open(DataLogger.SESSIONS_ROOT)
	if sessions == null:
		return found
	for folder in sessions.get_directories():
		var path := DataLogger.SESSIONS_ROOT.path_join(folder).path_join("parameters.json")
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var recorded := str((parsed as Dictionary).get("group_id", "")).strip_edges().to_upper()
		if not recorded.is_empty():
			found.append(recorded)
	return found


## The number in an ID belonging to this machine, or 0 for anything else. Group
## IDs typed by hand under the old scheme (g001) return 0 and so never hold the
## counter back, which is right: they are not part of this sequence.
static func _number_in(group_id: String, letter: String) -> int:
	var prefix := letter + MARKER
	if not group_id.begins_with(prefix):
		return 0
	var digits := group_id.substr(prefix.length())
	return int(digits) if digits.is_valid_int() else 0


## The IDs recorded in the roster. Prose in the header is skipped, since a line
## is only read as an ID when it is one.
static func roster_ids() -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(ROSTER_PATH):
		return out
	var file := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	if file == null:
		return out
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var trimmed := line.strip_edges().to_upper()
		if has_scheme_shape(trimmed):
			out.append(trimmed)
	return out


## A letter, the marker, then digits. Tight enough that no line of the header
## and no timestamp can be read back as a group ID.
static func has_scheme_shape(text: String) -> bool:
	var t := text.strip_edges().to_upper()
	if t.length() < 3 or t[1] != MARKER:
		return false
	if not ParticipantId.LETTERS.contains(t[0]):
		return false
	return t.substr(2).is_valid_int()
