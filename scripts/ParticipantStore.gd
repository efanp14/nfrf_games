class_name ParticipantStore
## ParticipantStore.gd
## Remembers what is already known about a participant, across sessions on this
## machine: their opening-survey answers, the personality value derived from
## them, and which treatments they have already played.
##
## Why this exists: the study asks each person to complete the opening survey
## once, not once per treatment. Without somewhere to keep the answers, a person
## returning for their second treatment would be asked again, and a slightly
## different set of answers can push them across a personality threshold. Their
## two sessions would then run at different stress sensitivities, and any change
## in their behaviour could no longer be attributed to the treatment.
##
## Deliberately separate from DataLogger. That writes the research record, which
## is append-only and never read back. This is working state the game reads at
## the start of a session, and the two must not be confused: nothing here is a
## substitute for the logged data.
##
## Scope is one machine. A participant who plays their second treatment on a
## different computer has no record here, so they are asked again. That is the
## correct behaviour today for the shared group-session machine, and the point
## where a decision is still outstanding about whether their value should
## instead be carried across.

const STORE_DIR: String = "user://participants/"

## Where a personality value came from. Logged alongside it so that analysis
## can tell a measured value from a reused or assumed one, without having to
## infer it from the survey rows.
const SOURCE_SURVEY: String = "survey"    # answered the survey in this session
const SOURCE_STORED: String = "stored"    # reused from an earlier session here
## Assigned, not measured — the group treatment gives everyone the average
## personality rather than surveying them (see ResearchConfig). Rows marked this
## way carry no personality measurement at all, and must not be pooled with
## surveyed rows in any analysis that treats personality as an observed value.
const SOURCE_DEFAULT: String = "default"


static func _path_for(participant_id: String) -> String:
	return STORE_DIR + participant_id + ".json"


## True when this participant has already completed the opening survey on this
## machine, so it should not be asked again.
static func has_record(participant_id: String) -> bool:
	return FileAccess.file_exists(_path_for(participant_id))


## The stored record, or an empty dictionary if there is none. An unreadable or
## malformed file is treated as absent rather than as an error: the cost of
## re-asking the survey is small, while refusing to start a session because a
## cache file is corrupt would strand a participant who is sitting there ready
## to play.
static func load_record(participant_id: String) -> Dictionary:
	var path := _path_for(participant_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	# A record with no alpha is unusable for the thing this store exists to do,
	# so treat it as absent rather than handing back a partial record that a
	# caller would then have to re-check.
	if not (parsed as Dictionary).has("alpha"):
		return {}
	return parsed


## Writes the opening-survey outcome for a participant. Only called the first
## time they complete it; a later session reads this back instead.
static func save_survey(participant_id: String, alpha: float, responses: Dictionary) -> void:
	var record := load_record(participant_id)
	record["participant_id"] = participant_id
	record["alpha"]          = alpha
	record["responses"]      = responses
	record["survey_taken_utc"] = Time.get_datetime_string_from_system(true, true)
	if not record.has("treatments_played"):
		record["treatments_played"] = []
	_write(participant_id, record)


## Notes that this participant has now played `treatment`, so the next session
## can tell whether it is their first, second or third. Appended rather than
## counted, so a repeat of the same treatment stays visible instead of being
## silently folded into a total.
static func record_treatment(participant_id: String, treatment: int) -> void:
	var record := load_record(participant_id)
	if record.is_empty():
		return
	var played: Array = record.get("treatments_played", [])
	played.append({
		"treatment": treatment,
		"played_utc": Time.get_datetime_string_from_system(true, true),
	})
	record["treatments_played"] = played
	_write(participant_id, record)


## Which session this is for the participant: 1 for their first treatment, 2
## for their second, and so on. Call BEFORE record_treatment for the current
## session, since it counts what has already been played.
static func next_treatment_ordinal(participant_id: String) -> int:
	var record := load_record(participant_id)
	if record.is_empty():
		return 1
	return (record.get("treatments_played", []) as Array).size() + 1


static func _write(participant_id: String, record: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(STORE_DIR)
	var file := FileAccess.open(_path_for(participant_id), FileAccess.WRITE)
	if file == null:
		push_warning("ParticipantStore: could not write record for %s" % participant_id)
		return
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
