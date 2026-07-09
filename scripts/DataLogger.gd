class_name DataLogger
extends Node
## DataLogger.gd
## Records every player decision and round outcome to a structured log.
## Outputs JSON that maps directly to the data columns the research team needs.
##
## Attach this as a child of GameManager and connect the signals.

var session_id: String
var treatment: int
var log_entries: Array = []
var start_time: float


func _ready() -> void:
	# Generate a unique session ID per run (timestamp-based for easy sorting)
	session_id = "session_%d" % int(Time.get_unix_time_from_system())
	start_time = Time.get_ticks_msec() / 1000.0


## Connect this to GameManager.round_ended
func on_round_ended(round_num: int, results: Dictionary) -> void:
	var entry: Dictionary = {
		# -- identity --
		"session_id":             session_id,
		"treatment":              treatment,   # 0=T1, 1=T2, 2=T3
		"round":                  round_num,
		"timestamp_s":            (Time.get_ticks_msec() / 1000.0) - start_time,
		"alpha":                  results.get("alpha", null),
		"group_mode":             results.get("group_mode", false),
		# -- personal commute --
		"personal_time":          results.get("personal_time", 0.0),
		"personal_time_before":   results.get("personal_time_before", null),
		"time_delta_from_baseline": results.get("time_delta", 0.0),
		"personal_safety":        results.get("personal_safety", 0.0),
		"safety_before":          results.get("safety_before", null),
		"safety_delta":           results.get("safety_delta", null),
		# -- budget --
		"credits_spent":          results.get("credits_spent", 0),
		"credits_remaining":      results.get("credits_remaining", 0),
		# -- upgrades: array of {link, level, cost, own_route} --
		"upgrades":               results.get("upgrades", []),
		# -- behavioral: selfish vs. community-minded investment (research question) --
		"own_route_upgrade_share":            results.get("own_route_upgrade_share", null),
		"cumulative_own_route_upgrade_share": results.get("cumulative_own_route_upgrade_share", null),
		# -- other players (T3 group mode; empty in T1/T2) --
		"players":                results.get("players", []),
		# -- city (null in T1) --
		"city_avg_time":          results.get("city_avg_time", null),
		"city_avg_time_before":   results.get("city_avg_time_before", null),
		"city_avg_time_delta":    results.get("city_avg_time_delta", null),
		"city_avg_safety":        results.get("city_avg_safety", null),
		"city_avg_safety_before": results.get("city_avg_safety_before", null),
		"city_avg_safety_delta":  results.get("city_avg_safety_delta", null),
		"city_coverage_pct":      results.get("city_coverage", null),
		"city_coverage_pct_before": results.get("city_coverage_before", null),
	}
	log_entries.append(entry)


## Connect this to GameManager.game_over
func on_game_over(final_results: Dictionary) -> void:
	var summary: Dictionary = {
		"session_id":       session_id,
		"treatment":        treatment,
		"round":            "FINAL",
		"alpha":            final_results.get("alpha", null),
		"baseline_time":    final_results.get("baseline_time", 0.0),
		"final_time":       final_results.get("final_time", 0.0),
		"total_time_saved": final_results.get("total_time_saved", 0.0),
		"final_safety":     final_results.get("final_safety", 0.0),
		"city_coverage_pct": final_results.get("city_coverage", 0.0),
		"cumulative_own_route_upgrade_share": final_results.get("cumulative_own_route_upgrade_share", null),
	}
	log_entries.append(summary)
	_write_to_disk()


## Connect this to ConsentScreen.consent_given. main.gd captures the moment
## consent was actually given and passes it here later (once treatment is
## known), the same way pre-survey responses are deferred — see
## on_pre_survey_completed below.
func on_consent_given(timestamp_s: float) -> void:
	log_entries.append({
		"session_id": session_id,
		"treatment":  treatment,
		"round":      "CONSENT",
		"timestamp_s": timestamp_s - start_time,
	})


## Connect this to PreSurvey.survey_completed (once per player, called from
## main.gd after treatment is known so the entry is tagged correctly).
func on_pre_survey_completed(player_num: int, responses: Dictionary, alpha: float) -> void:
	log_entries.append({
		"session_id": session_id,
		"treatment":  treatment,
		"round":      "PRE_SURVEY",
		"player_num": player_num,
		"responses":  responses,
		"alpha":      alpha,
	})


## Connect this to PostSurvey.survey_completed.
## Appends post-survey responses then rewrites the file with complete session data.
func on_post_survey_completed(responses: Dictionary) -> void:
	log_entries.append({
		"session_id": session_id,
		"treatment":  treatment,
		"round":      "POST_SURVEY",
		"responses":  responses,
	})
	_write_to_disk()
	_write_session_summary()


## Rolls up the per-round/pre-survey/post-survey/final entries already in
## log_entries into one flat, research-usable row for the whole session,
## instead of leaving researchers to parse the per-round JSON array. Called
## once, after the post-survey, since that's the true end of a session and
## every piece of data is available by then.
func _build_session_summary() -> Dictionary:
	var final_entry: Dictionary = {}
	var post_survey_entry: Dictionary = {}
	var pre_survey_entries: Array = []
	var round_entries: Array = []
	var consent_timestamp_s: Variant = null

	for entry: Dictionary in log_entries:
		var round_val: Variant = entry.get("round")
		# Check the int case first — GDScript errors (not just false) when
		# comparing an int to a String with `==`, and per-round entries store
		# an int while the special markers below store a String.
		if round_val is int:
			round_entries.append(entry)
		elif round_val == "FINAL":
			final_entry = entry
		elif round_val == "POST_SURVEY":
			post_survey_entry = entry
		elif round_val == "PRE_SURVEY":
			pre_survey_entries.append(entry)
		elif round_val == "CONSENT":
			consent_timestamp_s = entry.get("timestamp_s")

	var total_credits_spent: int = 0
	for r: Dictionary in round_entries:
		total_credits_spent += int(r.get("credits_spent", 0))

	var round1_safety_before: Variant = null
	var group_mode: bool = false
	if not round_entries.is_empty():
		round1_safety_before = round_entries[0].get("safety_before")
		group_mode = round_entries[0].get("group_mode", false)

	return {
		"session_id":            session_id,
		"treatment":             treatment,
		"group_mode":            group_mode,
		"num_players":           pre_survey_entries.size(),
		"consent_given_at_s":    consent_timestamp_s,
		"alpha":                 final_entry.get("alpha"),
		"rounds_played":         round_entries.size(),
		"total_credits_spent":   total_credits_spent,
		"baseline_time":         final_entry.get("baseline_time"),
		"final_time":            final_entry.get("final_time"),
		"total_time_saved":      final_entry.get("total_time_saved"),
		"safety_round1_before":  round1_safety_before,
		"final_safety":          final_entry.get("final_safety"),
		"city_coverage_pct":     final_entry.get("city_coverage_pct"),
		"cumulative_own_route_upgrade_share": final_entry.get("cumulative_own_route_upgrade_share"),
		"post_survey_responses": post_survey_entry.get("responses", {}),
	}


func _write_session_summary() -> void:
	var summary := _build_session_summary()
	DirAccess.make_dir_recursive_absolute("user://logs/")

	var json_path: String = "user://logs/%s_summary.json" % session_id
	var json_file: FileAccess = FileAccess.open(json_path, FileAccess.WRITE)
	if json_file:
		json_file.store_string(JSON.stringify(summary, "\t"))
		json_file.close()
	else:
		push_error("[DataLogger] Could not write session summary to %s" % json_path)
		return

	# CSV alongside the JSON — one header row + one data row, so a
	# researcher can drop it straight into a spreadsheet without parsing
	# JSON. Nested values (e.g. post_survey_responses) are JSON-encoded
	# into a single quoted cell so the row still parses as one line.
	var csv_path: String = "user://logs/%s_summary.csv" % session_id
	var csv_file: FileAccess = FileAccess.open(csv_path, FileAccess.WRITE)
	if csv_file:
		var header: PackedStringArray = []
		var values: PackedStringArray = []
		for key in summary.keys():
			header.append(str(key))
			values.append(_csv_cell(summary[key]))
		csv_file.store_line(",".join(header))
		csv_file.store_line(",".join(values))
		csv_file.close()
		print("[DataLogger] Session summary saved to %s and .csv" % json_path)
	else:
		push_error("[DataLogger] Could not write session summary to %s" % csv_path)


func _csv_cell(value: Variant) -> String:
	var s: String
	if value is Dictionary or value is Array:
		s = JSON.stringify(value)
	else:
		s = str(value)
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		s = "\"%s\"" % s.replace("\"", "\"\"")
	return s


func _write_to_disk() -> void:
	var path: String = "user://logs/%s.json" % session_id
	DirAccess.make_dir_recursive_absolute("user://logs/")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(log_entries, "\t"))
		file.close()
		print("[DataLogger] Session saved to %s" % path)
	else:
		push_error("[DataLogger] Could not write to %s" % path)
