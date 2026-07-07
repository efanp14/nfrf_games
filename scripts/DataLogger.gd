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
		"time_delta_from_baseline": results.get("time_delta", 0.0),
		"personal_safety":        results.get("personal_safety", 0.0),
		"safety_before":          results.get("safety_before", null),
		"safety_delta":           results.get("safety_delta", null),
		# -- budget --
		"credits_spent":          results.get("credits_spent", 0),
		"credits_remaining":      results.get("credits_remaining", 0),
		# -- upgrades: array of {link, level, cost} --
		"upgrades":               results.get("upgrades", []),
		# -- city (null in T1) --
		"city_avg_time":          results.get("city_avg_time", null),
		"city_avg_time_before":   results.get("city_avg_time_before", null),
		"city_avg_time_delta":    results.get("city_avg_time_delta", null),
		"city_coverage_pct":      results.get("city_coverage", null),
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
	}
	log_entries.append(summary)
	_write_to_disk()


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
