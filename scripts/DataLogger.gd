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

## Identifies the set of people playing together. One group per session here
## (T3 seats its whole group at one screen; T1/T2 are single-player, so their
## "group" is one person), but it is recorded as its own field on every entry
## because the T3 audio recording and transcript are linked back to the game
## data by group ID + session ID + round number.
var group_id: String

## Per-simulated-resident before/after detail, one block per round. Kept out
## of log_entries and written to its own file: at ~99 residents x 2 snapshots
## x N rounds it would bury the participant-level rows in events.json, and
## researchers generally want the two at different times.
var resident_rows: Array = []

## Absolute clock time the session began, and one row per round marking when
## that round opened and was confirmed. Written out as audio_manifest.json so
## a T3 discussion recorded on a separate device can be split into per-round
## segments and joined back to the decisions made in each one.
var session_start_unix: float = 0.0
var round_timings: Array = []

## One participant_id per human player, index-aligned with GameManager's
## human_players / results["players"] (i.e. participant_ids[0] is the
## primary player, "player_0"). Set once via set_participant_identity() once
## every player's survey position is settled — see main.gd.
##
## These are the numbers the researcher ENTERED, not values generated here. A
## generated ID identifies a run; only an entered one identifies a person, and
## joining someone's separate treatment sessions is the whole reason the field
## exists.
var participant_ids: Array[String] = []

## Which treatment in the fixed order this is for each participant (1 = their
## first). Index-aligned with participant_ids.
var treatment_ordinals: Array = []


func _ready() -> void:
	_ensure_session_identity()


## Assigns the session/group identity exactly once (timestamp-based, so runs
## sort naturally). Called from _ready(), but also defensively before anything
## is recorded or written: were these ever left empty, _session_dir() would
## collapse to "research_sessions//" and every session would silently
## overwrite the same files. Cheap insurance on write-once research data.
func _ensure_session_identity() -> void:
	if not session_id.is_empty():
		return
	session_start_unix = Time.get_unix_time_from_system()
	var stamp: int = int(session_start_unix)
	session_id = "session_%d" % stamp
	group_id   = "group_%d" % stamp
	start_time = Time.get_ticks_msec() / 1000.0


## Called once, after every player's survey position is settled, with one entry
## per player in human_players order.
##
## This also replaces the placeholder group identity minted in
## _ensure_session_identity() with the group the researcher entered. The
## timestamp form remains as the fallback for a blank entry, so the field is
## never empty and the session folder can never collapse.
##
## IDs carry no personally identifying information: they are whatever the
## research team assigned, and the mapping from an ID back to a person lives
## outside the game.
func set_participant_identity(ids: Array, entered_group_id: String, ordinals: Array) -> void:
	_ensure_session_identity()
	participant_ids = []
	for id in ids:
		participant_ids.append(str(id))
	treatment_ordinals = ordinals.duplicate()

	if not entered_group_id.strip_edges().is_empty():
		group_id = entered_group_id.strip_edges()


## Connect this to GameManager.round_ended
func on_round_ended(round_num: int, results: Dictionary) -> void:
	_ensure_session_identity()
	# Stamp each per-player row with its participant_id (index-aligned with
	# participant_ids) without mutating the shared results dict other
	# listeners (round summary UI) also read from.
	var players_raw: Array = results.get("players", [])
	var players_enriched: Array = []
	for i in range(players_raw.size()):
		var pd: Dictionary = (players_raw[i] as Dictionary).duplicate()
		if i < participant_ids.size():
			pd["participant_id"] = participant_ids[i]
		players_enriched.append(pd)

	round_timings.append({
		"round":            round_num,
		"started_unix":     results.get("round_started_unix", null),
		"confirmed_unix":   results.get("round_confirmed_unix", null),
		"decision_time_s":  results.get("decision_time_s", null),
	})

	# Simulated-resident detail goes to its own file (see resident_rows).
	# Computed in every treatment, including T1 where it is never displayed.
	resident_rows.append({
		"session_id": session_id,
		"group_id":   group_id,
		"treatment":  treatment,
		"round":      round_num,
		"residents_before": results.get("residents_before", []),
		"residents_after":  results.get("residents_after", []),
	})

	var entry: Dictionary = {
		# -- identity --
		"session_id":             session_id,
		"group_id":               group_id,
		"participant_id":         (participant_ids[0] as Variant) if participant_ids.size() > 0 else null,
		# This person's position in the fixed treatment order (1 = first).
		"treatment_ordinal":      (treatment_ordinals[0] as Variant) if treatment_ordinals.size() > 0 else null,
		"treatment":              treatment,   # 0=T1, 1=T2, 2=T3
		"round":                  round_num,
		"timestamp_s":            (Time.get_ticks_msec() / 1000.0) - start_time,
		# Round start -> confirm. In T3 this is the group's deliberation time.
		"decision_time_s":        results.get("decision_time_s", null),
		"alpha":                  results.get("alpha", null),
		"group_mode":             results.get("group_mode", false),
		# -- personal commute --
		# Three comparisons per metric, do not conflate them:
		#   *_before   = this round's starting value (the before/after pair)
		#   *_baseline = the Round-1 value
		#   *_delta    = Prospect Theory gain/loss vs *_baseline (STATIC
		#                reference), signed positive = improvement
		"personal_time":          results.get("personal_time", 0.0),
		"personal_time_before":   results.get("personal_time_before", null),
		"personal_time_baseline": results.get("time_baseline", null),
		"time_delta_from_baseline": results.get("time_delta", 0.0),
		"personal_safety":        results.get("personal_safety", 0.0),
		"safety_before":          results.get("safety_before", null),
		"safety_baseline":        results.get("safety_baseline", null),
		"safety_delta":           results.get("safety_delta", null),
		# Raw route stress, alongside the normalized 0-100 safety score above.
		"personal_stress":        results.get("personal_stress", null),
		"personal_stress_before": results.get("personal_stress_before", null),
		"personal_stress_baseline": results.get("personal_stress_baseline", null),
		"stress_delta":           results.get("stress_delta", null),
		# Impedance = what Dijkstra actually minimised (time weighted by
		# stress and infrastructure), so it moves even when neither raw time
		# nor raw stress alone tells the whole story.
		"personal_impedance":        results.get("personal_impedance", null),
		"personal_impedance_before": results.get("personal_impedance_before", null),
		"personal_impedance_baseline": results.get("personal_impedance_baseline", null),
		"impedance_delta":           results.get("impedance_delta", null),
		# -- routes: node IDs ridden, plus the same route as link IDs (which
		# join directly against the upgrade records below) --
		"final_route":            results.get("final_route", []),
		"route_before":           results.get("route_before", []),
		"route_links":            results.get("route_links", []),
		"route_links_before":     results.get("route_links_before", []),
		"route_changed":          results.get("route_changed", null),
		# Which links bought this round ended up on the player's NEW route
		# (each upgrade's own_route flag below is the pre-purchase answer).
		"upgraded_links_on_new_route": results.get("upgraded_links_on_new_route", []),
		# -- budget --
		"budget_available":       results.get("budget_available", null),
		"credits_spent":          results.get("credits_spent", 0),
		"credits_remaining":      results.get("credits_remaining", 0),
		# -- upgrades: {link, level, cost, own_route, on_new_route, length_m,
		# base_time_min}; removals: upgrades taken back off the network --
		"upgrades":               results.get("upgrades", []),
		"removals":               results.get("removals", []),
		# Ordered staging actions before confirmation — selection order, level
		# changes, and withdrawals. {seq, round, t_s, action, link, level}
		"interaction_events":     results.get("interaction_events", []),
		# -- behavioral: selfish vs. community-minded investment (research question) --
		"own_route_upgrade_share":            results.get("own_route_upgrade_share", null),
		"cumulative_own_route_upgrade_share": results.get("cumulative_own_route_upgrade_share", null),
		# -- other players (T3 group mode; empty in T1/T2) — each item now
		# also carries participant_id and its own "route" (see GameManager) --
		"players":                players_enriched,
		# -- city (null in T1) --
		"city_avg_time":          results.get("city_avg_time", null),
		"city_avg_time_before":   results.get("city_avg_time_before", null),
		"city_avg_time_baseline": results.get("city_avg_time_baseline", null),
		"city_avg_time_delta":    results.get("city_avg_time_delta", null),
		"city_avg_safety":        results.get("city_avg_safety", null),
		"city_avg_safety_before": results.get("city_avg_safety_before", null),
		"city_avg_safety_baseline": results.get("city_avg_safety_baseline", null),
		"city_avg_safety_delta":  results.get("city_avg_safety_delta", null),
		"city_avg_stress":        results.get("city_avg_stress", null),
		"city_avg_stress_before": results.get("city_avg_stress_before", null),
		"city_avg_stress_baseline": results.get("city_avg_stress_baseline", null),
		"city_avg_stress_delta":  results.get("city_avg_stress_delta", null),
		"city_coverage_pct":      results.get("city_coverage", null),
		"city_coverage_pct_before": results.get("city_coverage_before", null),
		"city_coverage_pct_baseline": results.get("city_coverage_baseline", null),
		# -- collective impact: how many residents are better off than on the
		# untouched Round-1 network. Time and safety are counted SEPARATELY and
		# are never combined into one weighted score. "No benefit" is the
		# complement of "improved", so it includes the worsened, which are also
		# broken out on their own. The means are over the improved subset only.
		# The two totals exclude the human player(s) structurally: they are sums
		# over the simulated residents, who are a different population.
		"residents_total":                    results.get("residents_total", null),
		"residents_time_improved":            results.get("residents_time_improved", null),
		"residents_time_improved_pct":        results.get("residents_time_improved_pct", null),
		"residents_time_worsened":            results.get("residents_time_worsened", null),
		"residents_time_no_benefit":          results.get("residents_time_no_benefit", null),
		"residents_time_no_benefit_pct":      results.get("residents_time_no_benefit_pct", null),
		"residents_time_improvement_mean":    results.get("residents_time_improvement_mean", null),
		"residents_safety_improved":          results.get("residents_safety_improved", null),
		"residents_safety_improved_pct":      results.get("residents_safety_improved_pct", null),
		"residents_safety_worsened":          results.get("residents_safety_worsened", null),
		"residents_safety_no_benefit":        results.get("residents_safety_no_benefit", null),
		"residents_safety_no_benefit_pct":    results.get("residents_safety_no_benefit_pct", null),
		"residents_safety_improvement_mean":  results.get("residents_safety_improvement_mean", null),
		"residents_total_time_saved_min":     results.get("residents_total_time_saved_min", null),
		"residents_total_safety_gained":      results.get("residents_total_safety_gained", null),
		# The exact city-wide feedback text the participant read this round,
		# verbatim (empty in T1, which is shown none). Built from the same
		# source the UI renders, so it cannot drift from what was on screen.
		"city_feedback_shown":    results.get("city_feedback_shown", []),
	}
	log_entries.append(entry)


## Connect this to GameManager.game_over
func on_game_over(final_results: Dictionary) -> void:
	var summary: Dictionary = {
		"session_id":       session_id,
		"group_id":         group_id,
		"participant_id":   (participant_ids[0] as Variant) if participant_ids.size() > 0 else null,
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


## Records that consent for this session was obtained outside the game, on
## paper or by signature, which is how the study now runs.
##
## The CONSENT entry is kept rather than removed. Dropping it would break the
## log schema, and more importantly a missing entry is ambiguous: it cannot be
## told apart from a session where consent was never recorded at all. An
## explicit `consent_process` marker says which process was used. There is no
## in-game timestamp to report, so `timestamp_s` stays present but null,
## keeping the field shape stable for anything already reading it.
func on_consent_external() -> void:
	log_entries.append({
		"session_id": session_id,
		"group_id":   group_id,
		"treatment":  treatment,
		"round":      "CONSENT",
		"timestamp_s": null,
		"consent_process": "external",
	})


## Connect this to PreSurvey.survey_completed (once per player, called from
## main.gd after treatment is known so the entry is tagged correctly).
func on_pre_survey_completed(player_num: int, responses: Dictionary, alpha: float,
		participant_id: String = "", alpha_source: String = "") -> void:
	var idx: int = player_num - 1
	log_entries.append({
		"session_id": session_id,
		"group_id":   group_id,
		"participant_id": participant_id,
		# Which treatment in the fixed order this is for this person: 1 for
		# their first, 2 for their second. The order is deliberately not
		# counterbalanced, so this is a position in a sequence, not a condition.
		"treatment_ordinal": (treatment_ordinals[idx] as Variant) if idx < treatment_ordinals.size() else null,
		"treatment":  treatment,
		"round":      "PRE_SURVEY",
		"player_num": player_num,
		"responses":  responses,
		"alpha":      alpha,
		# "survey" when answered in this session, "stored" when reused from an
		# earlier session on this machine. A reused value means these responses
		# are a copy of the original, not a fresh set — analysis must not treat
		# them as an independent second measurement.
		"alpha_source": alpha_source,
		# The scoring behind alpha, recorded so analysis can reproduce the
		# personality assignment without re-implementing the scale. Derived from
		# the same helpers the survey itself used, so the log cannot disagree
		# with what drove routing. "Don't know" answers stay as `dk` inside
		# `responses` and count as the neutral middle here.
		"alpha_mean":  SurveyQuestions.alpha_mean(responses),
		"personality": PersonalityConfig.personality_name_for_alpha(alpha),
	})


## Connect this to PostSurvey.survey_completed. Called once per player in the
## session (T3 groups complete one each); only the last player's call
## triggers the file write, since that's when the session is truly done.
func on_post_survey_completed(player_num: int, total_players: int, participant_id: String, responses: Dictionary) -> void:
	log_entries.append({
		"session_id": session_id,
		"group_id":   group_id,
		"participant_id": participant_id,
		"treatment":  treatment,
		"round":      "POST_SURVEY",
		"player_num": player_num,
		"responses":  responses,
	})
	if player_num >= total_players:
		_write_to_disk()
		_write_session_summary()


## Rolls up the per-round/pre-survey/post-survey/final entries already in
## log_entries into one flat, research-usable row for the whole session,
## instead of leaving researchers to parse the per-round JSON array. Called
## once, after the post-survey, since that's the true end of a session and
## every piece of data is available by then.
func _build_session_summary() -> Dictionary:
	var final_entry: Dictionary = {}
	var post_survey_entries: Array = []
	var pre_survey_entries: Array = []
	var round_entries: Array = []
	var consent_timestamp_s: Variant = null
	var consent_process: Variant = null

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
			post_survey_entries.append(entry)
		elif round_val == "PRE_SURVEY":
			pre_survey_entries.append(entry)
		elif round_val == "CONSENT":
			consent_timestamp_s = entry.get("timestamp_s")
			consent_process = entry.get("consent_process")

	var total_credits_spent: int = 0
	var total_decision_time_s: float = 0.0
	for r: Dictionary in round_entries:
		total_credits_spent += int(r.get("credits_spent", 0))
		total_decision_time_s += float(r.get("decision_time_s", 0.0))

	var round1_safety_before: Variant = null
	var group_mode: bool = false
	# Collective impact at the END of the session. Taken from the last round
	# rather than the FINAL marker entry, which carries no resident figures.
	# These are already cumulative (measured against the Round-1 network), so
	# the last round's values are the whole session's outcome, not just that
	# round's — no summing required, and summing them would double-count.
	var last_round: Dictionary = {}
	if not round_entries.is_empty():
		round1_safety_before = round_entries[0].get("safety_before")
		group_mode = round_entries[0].get("group_mode", false)
		last_round = round_entries[round_entries.size() - 1]

	var post_survey_by_player: Array = []
	for e: Dictionary in post_survey_entries:
		post_survey_by_player.append({
			"player_num":     e.get("player_num"),
			"participant_id": e.get("participant_id"),
			"responses":      e.get("responses", {}),
		})

	return {
		"session_id":            session_id,
		"group_id":              group_id,
		"participant_ids":       participant_ids,
		"treatment_ordinals":    treatment_ordinals,
		"treatment":             treatment,
		"group_mode":            group_mode,
		"num_players":           pre_survey_entries.size(),
		# Null now that consent is collected outside the game. Kept so the
		# summary's field shape does not change; `consent_process` says why.
		"consent_given_at_s":    consent_timestamp_s,
		"consent_process":       consent_process,
		"alpha":                 final_entry.get("alpha"),
		"rounds_played":         round_entries.size(),
		"total_decision_time_s": total_decision_time_s,
		"total_credits_spent":   total_credits_spent,
		"baseline_time":         final_entry.get("baseline_time"),
		"final_time":            final_entry.get("final_time"),
		"total_time_saved":      final_entry.get("total_time_saved"),
		"safety_round1_before":  round1_safety_before,
		"final_safety":          final_entry.get("final_safety"),
		"city_coverage_pct":     final_entry.get("city_coverage_pct"),
		"cumulative_own_route_upgrade_share": final_entry.get("cumulative_own_route_upgrade_share"),
		"final_residents_total":                   last_round.get("residents_total"),
		"final_residents_time_improved_pct":       last_round.get("residents_time_improved_pct"),
		"final_residents_time_improvement_mean":   last_round.get("residents_time_improvement_mean"),
		"final_residents_safety_improved_pct":     last_round.get("residents_safety_improved_pct"),
		"final_residents_safety_improvement_mean": last_round.get("residents_safety_improvement_mean"),
		"final_residents_total_time_saved_min":    last_round.get("residents_total_time_saved_min"),
		"final_residents_total_safety_gained":     last_round.get("residents_total_safety_gained"),
		"post_survey_responses": post_survey_by_player,
	}


## One subfolder per session, under a top-level directory of our own
## (distinct from Godot's own user://logs/, which the engine uses for its
## own log files — sharing that folder made it easy to mistake engine logs
## for research data). All 3 files for a session live together here, so a
## researcher can just zip/copy one folder per participant/group.
func _session_dir() -> String:
	_ensure_session_identity()
	return "user://research_sessions/%s/" % session_id


func _write_session_summary() -> void:
	var summary := _build_session_summary()
	DirAccess.make_dir_recursive_absolute(_session_dir())

	var json_path: String = _session_dir() + "summary.json"
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
	var csv_path: String = _session_dir() + "summary.csv"
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
	var path: String = _session_dir() + "events.json"
	DirAccess.make_dir_recursive_absolute(_session_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(log_entries, "\t"))
		file.close()
		print("[DataLogger] Session saved to %s" % path)
	else:
		push_error("[DataLogger] Could not write to %s" % path)
	_write_residents()
	_write_audio_manifest()


## Absolute clock bounds for the session and each round, so a discussion
## recorded on a separate device (T3) can be cut into per-round segments and
## each segment joined to the decisions made during it via group_id + round.
##
## The game deliberately does NOT record audio — the recording and
## speaker-diarization pipeline live outside it. This file is the join key.
##
## Times are UTC. Unix values are kept alongside the readable strings because
## they are what alignment arithmetic actually needs, and they carry
## sub-second precision the formatted string drops.
func _write_audio_manifest() -> void:
	if round_timings.is_empty():
		return

	# Anchor offsets to the EARLIEST known moment in the session, not blindly
	# to session_start_unix. Normally they are the same thing, but if the
	# logger's identity were ever assigned late its "start" could fall after
	# round 1 began, which would emit negative offsets and make this file
	# useless as an alignment anchor. Taking the minimum guarantees offsets
	# are always non-negative and always measured from the true earliest point.
	var anchor_unix: float = session_start_unix
	for t: Dictionary in round_timings:
		var s: Variant = t.get("started_unix")
		if s != null and (anchor_unix <= 0.0 or float(s) < anchor_unix):
			anchor_unix = float(s)

	var rounds: Array = []
	for t: Dictionary in round_timings:
		var started: Variant = t.get("started_unix")
		var confirmed: Variant = t.get("confirmed_unix")
		rounds.append({
			"round":                t.get("round"),
			"started_utc":          _iso_utc(started),
			"confirmed_utc":        _iso_utc(confirmed),
			"started_unix":         started,
			"confirmed_unix":       confirmed,
			# Seconds from session start — usable directly as an offset into a
			# recording that was started at the same moment as the session.
			"started_offset_s":     (float(started) - anchor_unix) if started != null else null,
			"confirmed_offset_s":   (float(confirmed) - anchor_unix) if confirmed != null else null,
			"decision_time_s":      t.get("decision_time_s"),
		})

	var manifest: Dictionary = {
		"session_id":          session_id,
		"group_id":            group_id,
		"treatment":           treatment,
		"participant_ids":     participant_ids,
		# The zero point all *_offset_s values are measured from.
		"session_started_utc": _iso_utc(anchor_unix),
		"session_started_unix": anchor_unix,
		"rounds":              rounds,
		"alignment_note": "Times are UTC. To locate a round inside an audio "
			+ "recording, subtract the recorder's own start time from "
			+ "started_unix/confirmed_unix. If the recording was started at "
			+ "the same moment as the session, started_offset_s and "
			+ "confirmed_offset_s are already the offsets in seconds. Record "
			+ "the recorder's start time in the session protocol — it is the "
			+ "one value this file cannot know.",
	}

	var path: String = _session_dir() + "audio_manifest.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()
		print("[DataLogger] Audio manifest saved to %s" % path)
	else:
		push_error("[DataLogger] Could not write to %s" % path)


static func _iso_utc(unix_s: Variant) -> Variant:
	if unix_s == null:
		return null
	return Time.get_datetime_string_from_unix_time(int(unix_s), false) + "Z"


## Per-resident before/after routes, travel times and stress, one block per
## round — the simulated-resident half of the research output, alongside the
## participant-level rows in events.json.
func _write_residents() -> void:
	if resident_rows.is_empty():
		return
	var path: String = _session_dir() + "residents.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(resident_rows, "\t"))
		file.close()
		print("[DataLogger] Resident detail saved to %s" % path)
	else:
		push_error("[DataLogger] Could not write to %s" % path)
