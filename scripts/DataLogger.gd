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

## Identifies the set of people playing together, entered by the researcher in
## the group treatment only. It is what links a discussion recorded on a
## separate device back to the rounds it covers, via group ID + session ID +
## round number.
##
## EMPTY on an individual session, and that is not missing data: those sessions
## have no group decision and no recording, so the field is not asked for. Which
## group a solo participant belonged to is recovered afterwards by matching
## their participant ID against the group session they took part in; see
## tools/aggregate_logs.py, which fills it in and marks it as derived.
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

## Snapshot of the settings this session ran under, from
## GameManager.session_parameters(). Pushed in by the scene layer rather than
## read from here, keeping this file's only job the recording of what it is
## handed.
var game_parameters: Dictionary = {}

## The session this one immediately followed, empty unless this is the second
## half of a chained T1-into-T2 sitting.
##
## T1 and T2 are played back to back in one sitting, and the scene reloads
## between them, so one sitting writes TWO session folders. They already share
## participant_id and group_id, but nothing said they were one sitting — that
## had to be inferred from the two session IDs being close together, which is
## a guess dressed as a fact. T1-then-T2 in a single sitting carries an order
## and fatigue effect that the same pair played on separate days does not, and
## the analysis has to be able to tell them apart.
var chained_from_session_id: String = ""


func _ready() -> void:
	_ensure_session_identity()


## Assigns a PROVISIONAL session identity immediately, replaced by a readable
## one as soon as the participants are known (see set_participant_identity and
## _compose_session_id).
##
## Something has to exist from the very first moment: were these ever left
## empty, _session_dir() would collapse to "research_sessions//" and every
## session would silently overwrite the same files. Cheap insurance on
## write-once research data. The provisional form also survives as the FINAL
## name for a session that never reaches the participant step, which is how an
## abandoned run still lands somewhere rather than vanishing.
func _ensure_session_identity() -> void:
	if not session_id.is_empty():
		return
	session_start_unix = Time.get_unix_time_from_system()
	session_id = _free_folder_name("session_%d" % int(session_start_unix))
	# group_id is deliberately NOT given a placeholder. It is asked for only in
	# the group treatment, where it ties a separately recorded discussion to the
	# rounds it covers; an individual session has no group decision and no
	# recording. Minting "group_<timestamp>" here would fill every solo row with
	# a group that exists nowhere and belongs to no one, which reads as data
	# rather than as absence. Blank is the honest value, and which group a solo
	# participant belonged to is recovered from the group session at analysis
	# time (tools/aggregate_logs.py).
	start_time = Time.get_ticks_msec() / 1000.0


## The requested name, or that name with _2, _3 and so on appended until the
## folder is free.
##
## Names are minute-resolution, so two sessions started in the same minute by
## the same participant would otherwise land on the same folder and the second
## would overwrite the first. Unlikely by hand, but the chained T1-into-T2 flow
## starts its second session automatically, and a session restarted after a
## false start is exactly the case where write-once data would be lost silently.
func _free_folder_name(base: String) -> String:
	var candidate := base
	var suffix := 2
	while DirAccess.dir_exists_absolute("user://research_sessions/%s/" % candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


## A folder name a researcher can read at a glance:
##
##     T1-p001-2026-08-10_1435
##     T3-p001_p002_p003-2026-08-10_1512
##
## Treatment, then who played, then when to the minute. Sessions used to be
## named by raw Unix timestamp, which sorted correctly but meant finding one
## participant's session required opening folders until you found it.
##
## Only the characters an ID may already contain are used, so the name is safe
## on every filesystem. A colon cannot appear here even though it reads well in
## a date: Windows forbids it in a path, as it does / \ ? * " < > and |.
## Participant IDs are validated against the same allowed set at entry
## (ResearchConfig.is_valid_id), so nothing typed by a researcher can produce an
## unwritable folder.
##
## The time is LOCAL, not UTC, because it is matched against a paper session log
## written in the room. Timestamps INSIDE the files stay UTC, the audio manifest
## included; only this label is local.
func _compose_session_id() -> String:
	var parts := PackedStringArray(["T%d" % (treatment + 1)])
	var who := _joined_participant_ids()
	if not who.is_empty():
		parts.append(who)
	parts.append(_local_minute_stamp())
	return _free_folder_name("-".join(parts))


## Participant IDs joined for the folder name, capped so a large group or long
## IDs cannot push the path past what the filesystem accepts. Past the cap the
## name keeps the first ID and says how many others there were; the full list is
## in participant_ids inside every file, so nothing is lost.
func _joined_participant_ids() -> String:
	const MAX_LEN: int = 48
	var clean := PackedStringArray()
	for id in participant_ids:
		var s := str(id).strip_edges()
		if not s.is_empty():
			clean.append(s)
	if clean.is_empty():
		return ""
	var joined := "_".join(clean)
	if joined.length() <= MAX_LEN:
		return joined
	return "%s_and%d" % [clean[0], clean.size() - 1]


func _local_minute_stamp() -> String:
	var zone: Dictionary = Time.get_time_zone_from_system()
	var local_unix: int = int(session_start_unix) + int(zone.get("bias", 0)) * 60
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(local_unix)
	return "%04d-%02d-%02d_%02d%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


## Called once, after every player's survey position is settled, with one entry
## per player in human_players order.
##
## The group is taken as given: blank stays blank, because the menu only asks
## for it in the group treatment.
##
## IDs carry no personally identifying information: they are whatever the
## research team assigned, and the mapping from an ID back to a person lives
## outside the game.
func set_participant_identity(ids: Array, entered_group_id: String, ordinals: Array,
		from_session_id: String = "") -> void:
	_ensure_session_identity()
	participant_ids = []
	for id in ids:
		participant_ids.append(str(id))
	treatment_ordinals = ordinals.duplicate()
	chained_from_session_id = from_session_id.strip_edges()

	if not entered_group_id.strip_edges().is_empty():
		group_id = entered_group_id.strip_edges()

	# This is the first moment both the treatment and the participants are
	# known, so it is the earliest the readable folder name can be built. It is
	# also still safe: nothing has been written to disk yet, since every write
	# happens at round end or later.
	_adopt_session_id(_compose_session_id())


## Switches to the final session ID, carrying the change into anything already
## recorded under the provisional one.
##
## Entries are stamped with session_id at the moment they are appended, and the
## consent marker is appended just before this runs. Renaming without the
## back-fill would leave that one row pointing at a session ID no folder on disk
## ever uses, which is the kind of inconsistency that is invisible until someone
## tries to join the tables months later.
func _adopt_session_id(new_id: String) -> void:
	if new_id.is_empty() or new_id == session_id:
		return
	var old_id := session_id
	session_id = new_id
	for entry: Dictionary in log_entries:
		if entry.get("session_id") == old_id:
			entry["session_id"] = new_id
	for block: Dictionary in resident_rows:
		if block.get("session_id") == old_id:
			block["session_id"] = new_id


## Null rather than "" for an unchained session, so the field reads as absent in
## JSON and as an empty cell in CSV instead of as a session ID that is somehow
## the empty string.
func _chained_from_or_null() -> Variant:
	return chained_from_session_id if not chained_from_session_id.is_empty() else null


## Identifies the SITTING rather than the run: the same value on both halves of
## a chained T1-into-T2 sitting, and equal to the session ID for a session that
## stood alone.
##
## The two halves cannot simply share a session_id — a session is a folder, and
## the scene reload between treatments creates a second logger writing a second
## folder, so a shared ID would have them overwrite each other. This gives the
## sitting its own key instead, which makes "group by the person's sitting" a
## plain grouping rather than a self-join through chained_from_session_id.
func sitting_id() -> String:
	_ensure_session_identity()
	return chained_from_session_id if not chained_from_session_id.is_empty() else session_id


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
		"schema_version": LogSchema.SCHEMA_VERSION,
		"session_id": session_id,
		"sitting_id": sitting_id(),
		"group_id":   group_id,
		"treatment":  treatment,
		"round":      round_num,
		"residents_before": results.get("residents_before", []),
		"residents_after":  results.get("residents_after", []),
	})

	var entry: Dictionary = {
		# -- identity --
		# Stamped per entry rather than wrapping the file in an object, which
		# would change events.json from an array into a different shape and
		# break every existing reader (guardrail 6). Additive only.
		"schema_version":         LogSchema.SCHEMA_VERSION,
		"session_id":             session_id,
		# The same on both halves of a chained T1-into-T2 sitting.
		"sitting_id":             sitting_id(),
		"group_id":               group_id,
		"participant_id":         (participant_ids[0] as Variant) if participant_ids.size() > 0 else null,
		# This person's position in the fixed treatment order (1 = first).
		"treatment_ordinal":      (treatment_ordinals[0] as Variant) if treatment_ordinals.size() > 0 else null,
		# Set only on the second half of a chained T1-into-T2 sitting.
		"chained_from_session_id": _chained_from_or_null(),
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
		# The Round-1 route, i.e. the commute before any investment at all.
		"route_links_baseline":   results.get("route_links_baseline", []),
		"route_changed":          results.get("route_changed", null),
		"route_changed_from_baseline": results.get("route_changed_from_baseline", null),
		# Which links bought this round ended up on the player's NEW route
		# (each upgrade's own_route flag below is the pre-purchase answer).
		"upgraded_links_on_new_route": results.get("upgraded_links_on_new_route", []),
		# -- budget --
		"budget_available":       results.get("budget_available", null),
		"credits_spent":          results.get("credits_spent", 0),
		"credits_spent_cumulative": results.get("credits_spent_cumulative", null),
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
		# The same share computed from the round's purchases rather than from a
		# player's own purse. Identical to own_route_upgrade_share here (this row
		# is player 0's), but in group mode it is the only one of the two that
		# holds a real value for the other players — see each entry of "players"
		# below, and GameManager._spend_share_on_route().
		"group_spend_on_my_route_share":      results.get("group_spend_on_my_route_share", null),
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
		# Raw stress alongside the normalised safety score above. Safety is a
		# transform of stress, but not a linear one across routes of differing
		# length, so the spec's "average stress improvement" is its own measure.
		"residents_stress_improved":          results.get("residents_stress_improved", null),
		"residents_stress_improved_pct":      results.get("residents_stress_improved_pct", null),
		"residents_stress_worsened":          results.get("residents_stress_worsened", null),
		"residents_stress_no_benefit":        results.get("residents_stress_no_benefit", null),
		"residents_stress_no_benefit_pct":    results.get("residents_stress_no_benefit_pct", null),
		"residents_stress_improvement_mean":  results.get("residents_stress_improvement_mean", null),
		"residents_total_time_saved_min":     results.get("residents_total_time_saved_min", null),
		"residents_total_safety_gained":      results.get("residents_total_safety_gained", null),
		"residents_total_stress_reduced":     results.get("residents_total_stress_reduced", null),
		# The exact city-wide feedback text the participant read this round,
		# verbatim (empty in T1, which is shown none). Built from the same
		# source the UI renders, so it cannot drift from what was on screen.
		"city_feedback_shown":    results.get("city_feedback_shown", []),
		# Whether the city figures above were on screen. They are computed in
		# every treatment, so without this a T1 city value is indistinguishable
		# from a value the participant actually saw. Hidden is not missing.
		"city_metrics_shown":     results.get("city_metrics_shown", null),
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
## Splits log_entries by row kind. One array holds five different shapes of row,
## told apart by `round`, which is an int for a round and a String for every
## marker — so the int case MUST be checked first: GDScript errors, rather than
## returning false, on `int == String`. Shared by the summary and by every CSV
## writer so that rule is implemented once.
func _partition_entries() -> Dictionary:
	var out: Dictionary = {
		"rounds": [], "pre": [], "post": [], "final": {}, "consent": {},
	}
	for entry: Dictionary in log_entries:
		var round_val: Variant = entry.get("round")
		if round_val is int:
			out["rounds"].append(entry)
		elif round_val == "FINAL":
			out["final"] = entry
		elif round_val == "POST_SURVEY":
			out["post"].append(entry)
		elif round_val == "PRE_SURVEY":
			out["pre"].append(entry)
		elif round_val == "CONSENT":
			out["consent"] = entry
	return out


func _build_session_summary() -> Dictionary:
	var parts: Dictionary = _partition_entries()
	var round_entries: Array = parts["rounds"]
	var pre_survey_entries: Array = parts["pre"]
	var post_survey_entries: Array = parts["post"]
	var final_entry: Dictionary = parts["final"]
	var consent_timestamp_s: Variant = (parts["consent"] as Dictionary).get("timestamp_s")
	var consent_process: Variant = (parts["consent"] as Dictionary).get("consent_process")

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
		"schema_version":        LogSchema.SCHEMA_VERSION,
		"session_id":            session_id,
		"sitting_id":            sitting_id(),
		"group_id":              group_id,
		"chained_from_session_id": _chained_from_or_null(),
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
		"final_residents_stress_improved_pct":     last_round.get("residents_stress_improved_pct"),
		"final_residents_stress_improvement_mean": last_round.get("residents_stress_improvement_mean"),
		"final_residents_total_time_saved_min":    last_round.get("residents_total_time_saved_min"),
		"final_residents_total_safety_gained":     last_round.get("residents_total_safety_gained"),
		"post_survey_responses": post_survey_by_player,
	}


## One subfolder per session, under a top-level directory of our own
## (distinct from Godot's own user://logs/, which the engine uses for its
## own log files — sharing that folder made it easy to mistake engine logs
## for research data). Every file for a session lives together here — the JSON
## records, the analysis-ready CSVs, the parameter snapshot and the codebook —
## so a researcher can zip or copy one folder per participant/group and have
## both the data and the meaning of every column travel with it.
func _session_dir() -> String:
	_ensure_session_identity()
	return "user://research_sessions/%s/" % session_id


func _write_session_summary() -> void:
	var summary := _build_session_summary()
	DirAccess.make_dir_recursive_absolute(_session_dir())
	_write_analysis_tables()

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


# --- Analysis-ready CSVs -----------------------------------------------------
#
# These carry no information the JSON files do not already hold. They exist
# because of the shape it is held in: events.json is one array mixing five row
# kinds, told apart by a field that is an int for a round and a String for
# everything else, which no statistics package will load as a table. The unit of
# analysis is the participant-round, and until now no file anywhere held all
# participant-rounds.
#
# The JSON is left exactly as it was (guardrail 6) and these are written beside
# it, so nothing already collected is invalidated and anything already reading
# the logs keeps working.


## Emits the tidy tables, the parameter snapshot and the codebook. Called from
## _write_session_summary(), which runs once at the true end of a session — the
## point at which every piece of the session, including the closing survey, is
## finally available.
func _write_analysis_tables() -> void:
	var parts: Dictionary = _partition_entries()
	_write_table("rounds.csv",    LogSchema.rounds_columns(),    _rounds_rows(parts))
	_write_table("decisions.csv", LogSchema.decisions_columns(), _decisions_rows(parts))
	_write_table("upgrades.csv",  LogSchema.upgrades_columns(),  _upgrades_rows(parts))
	_write_table("surveys.csv",   LogSchema.surveys_columns(),   _surveys_rows(parts))
	_write_table("residents.csv", LogSchema.residents_columns(), _residents_rows())
	_write_parameters()
	_write_codebook()
	print("[DataLogger] Analysis tables written to %s" % _session_dir())


## Writes one table, header first. The header is written even when there are no
## rows: a headerless empty file breaks concatenation across sessions, while an
## empty table with a header simply contributes nothing.
func _write_table(filename: String, columns: Array, rows: Array) -> void:
	var path: String = _session_dir() + filename
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[DataLogger] Could not write %s" % path)
		return
	file.store_line(",".join(LogSchema.header_for(columns)))
	for row: Dictionary in rows:
		file.store_line(LogSchema.csv_row(LogSchema.row_values(columns, row)))
	file.close()


## One row per participant per round: three rows for a solo session, three per
## seat for a group one.
##
## Built from each round's `players` array rather than from the top-level
## personal_* fields, which describe player 1 only. In a group session the other
## two participants exist solely inside that array, so a per-round row taken
## from the top level would silently discard two thirds of the people who played.
func _rounds_rows(parts: Dictionary) -> Array:
	var alpha_source_by_player: Dictionary = {}
	for e: Dictionary in parts["pre"]:
		alpha_source_by_player[int(e.get("player_num", 0))] = e.get("alpha_source", null)

	var rows: Array = []
	for entry: Dictionary in parts["rounds"]:
		var players: Array = entry.get("players", [])
		if players.is_empty():
			players = [_player_view_from_entry(entry)]

		var upgrades: Array = entry.get("upgrades", [])
		var painted: int = 0
		var protected_count: int = 0
		for u: Dictionary in upgrades:
			if int(u.get("level", 0)) == 1:
				painted += 1
			elif int(u.get("level", 0)) == 2:
				protected_count += 1

		for i in range(players.size()):
			var p: Dictionary = players[i]
			var alpha: float = float(p.get("alpha", 0.0))
			var route_links: Array = p.get("route_links", [])
			var row: Dictionary = {
				"schema_version": LogSchema.SCHEMA_VERSION,
				"session_id":     entry.get("session_id"),
				"sitting_id":     entry.get("sitting_id"),
				"group_id":       entry.get("group_id"),
				"chained_from_session_id": entry.get("chained_from_session_id"),
				"participant_id": p.get("participant_id",
						participant_ids[i] if i < participant_ids.size() else null),
				"player_num":     i + 1,
				"treatment":      entry.get("treatment"),
				"treatment_label": LogSchema.treatment_label(int(entry.get("treatment", -1))),
				"treatment_ordinal": (treatment_ordinals[i] as Variant) if i < treatment_ordinals.size() else null,
				"group_mode":     entry.get("group_mode"),
				"num_players":    players.size(),
				"round":          entry.get("round"),
				"alpha":          alpha,
				"personality":    PersonalityConfig.personality_name_for_alpha(alpha),
				"alpha_source":   alpha_source_by_player.get(i + 1, null),
				"timestamp_s":    entry.get("timestamp_s"),
				"decision_time_s": entry.get("decision_time_s"),
				"budget_available":  entry.get("budget_available"),
				"credits_spent":     entry.get("credits_spent"),
				"credits_spent_cumulative": entry.get("credits_spent_cumulative"),
				"credits_remaining": entry.get("credits_remaining"),
				"home_node":      p.get("home"),
				"work_node":      p.get("work"),
				"route_changed":  p.get("route_changed"),
				"route_changed_from_baseline": p.get("route_changed_from_baseline"),
				"route_n_links":  route_links.size(),
				"route_links":    route_links,
				"route_links_baseline": p.get("route_links_baseline", []),
				"upgraded_links_on_new_route_n": (p.get("upgraded_links_on_new_route", []) as Array).size(),
				"own_route_upgrade_share": p.get("own_route_upgrade_share"),
				"cumulative_own_route_upgrade_share": p.get("cumulative_own_route_upgrade_share"),
				"group_spend_on_my_route_share": p.get("group_spend_on_my_route_share"),
				"n_upgrades":            upgrades.size(),
				"n_upgrades_painted":    painted,
				"n_upgrades_protected":  protected_count,
				"n_removals":            (entry.get("removals", []) as Array).size(),
				"n_interaction_events":  (entry.get("interaction_events", []) as Array).size(),
				"city_feedback_shown":   entry.get("city_feedback_shown", []),
				"city_metrics_shown":    entry.get("city_metrics_shown"),
			}
			# Per-player metric quads. The player rows name these without the
			# "personal_" prefix the top-level fields carry.
			for metric: String in ["time", "safety", "stress", "impedance"]:
				row[metric]              = p.get(metric)
				row[metric + "_before"]  = p.get(metric + "_before")
				row[metric + "_baseline"] = p.get(metric + "_baseline")
				row[metric + "_delta"]   = p.get(metric + "_delta")
			# City and resident figures describe the whole session, so they
			# REPEAT across a group's rows. Summing them down the column would
			# count one city three times over.
			for key: String in ["city_avg_time", "city_avg_safety", "city_avg_stress"]:
				row[key]               = entry.get(key)
				row[key + "_before"]   = entry.get(key + "_before")
				row[key + "_baseline"] = entry.get(key + "_baseline")
				row[key + "_delta"]    = entry.get(key + "_delta")
			for key: String in ["city_coverage_pct", "city_coverage_pct_before",
					"city_coverage_pct_baseline"]:
				row[key] = entry.get(key)
			for c: Dictionary in LogSchema.rounds_columns():
				var col: String = str(c["col"])
				if col.begins_with("residents_"):
					row[col] = entry.get(col)
			rows.append(row)
	return rows


## Fallback shape for a round that carries no `players` array. Should never fire
## with the current GameManager, which always emits one entry per player, but
## the writer would otherwise drop the round entirely and leave a session
## looking as though it were never played.
func _player_view_from_entry(entry: Dictionary) -> Dictionary:
	return {
		"participant_id": entry.get("participant_id"),
		"alpha":     entry.get("alpha"),
		"time":      entry.get("personal_time"),
		"time_before":   entry.get("personal_time_before"),
		"time_baseline": entry.get("personal_time_baseline"),
		"time_delta":    entry.get("time_delta_from_baseline"),
		"safety":          entry.get("personal_safety"),
		"safety_before":   entry.get("safety_before"),
		"safety_baseline": entry.get("safety_baseline"),
		"safety_delta":    entry.get("safety_delta"),
		"stress":          entry.get("personal_stress"),
		"stress_before":   entry.get("personal_stress_before"),
		"stress_baseline": entry.get("personal_stress_baseline"),
		"stress_delta":    entry.get("stress_delta"),
		"impedance":          entry.get("personal_impedance"),
		"impedance_before":   entry.get("personal_impedance_before"),
		"impedance_baseline": entry.get("personal_impedance_baseline"),
		"impedance_delta":    entry.get("impedance_delta"),
		"route_links":   entry.get("route_links", []),
		"route_changed": entry.get("route_changed"),
		"own_route_upgrade_share": entry.get("own_route_upgrade_share"),
		"cumulative_own_route_upgrade_share": entry.get("cumulative_own_route_upgrade_share"),
		"group_spend_on_my_route_share": entry.get("group_spend_on_my_route_share"),
		"upgraded_links_on_new_route": entry.get("upgraded_links_on_new_route", []),
	}


## One row per link bought or removed, flattening what is otherwise an array of
## dictionaries buried inside a round row. This is the closest thing in the data
## to the decision itself, so it is worth being directly readable.
func _upgrades_rows(parts: Dictionary) -> Array:
	var rows: Array = []
	for entry: Dictionary in parts["rounds"]:
		var group_mode: bool = bool(entry.get("group_mode", false))
		# Left empty in a group session, where empty means "the group decided",
		# not "missing": one screen and one mouse, so the game has no way to know
		# whose hand it was. The audio recording is what answers that.
		var buyer: Variant = null if group_mode else entry.get("participant_id")

		for u: Dictionary in entry.get("upgrades", []):
			rows.append(_upgrade_row(entry, buyer, "upgrade",
					u.get("link"), int(u.get("level", 0)), u.get("cost"),
					u.get("length_m"), u.get("base_time_min"),
					u.get("own_route"), u.get("on_new_route")))
		for r: Dictionary in entry.get("removals", []):
			# A removal records the level it came off and the money returned;
			# there is no own_route flag, so those stay blank rather than false.
			rows.append(_upgrade_row(entry, buyer, "removal",
					r.get("link"), int(r.get("from_level", 0)), r.get("refund"),
					r.get("length_m"), r.get("base_time_min"), null, null))
	return rows


func _upgrade_row(entry: Dictionary, buyer: Variant, action: String, link: Variant,
		level: int, cost: Variant, length_m: Variant, base_time_min: Variant,
		own_route: Variant, on_new_route: Variant) -> Dictionary:
	return {
		"schema_version": LogSchema.SCHEMA_VERSION,
		"session_id":     entry.get("session_id"),
		"sitting_id":     entry.get("sitting_id"),
		"group_id":       entry.get("group_id"),
		"participant_id": buyer,
		"treatment":      entry.get("treatment"),
		"round":          entry.get("round"),
		"action":         action,
		"link_id":        link,
		"level":          level,
		"level_name":     LogSchema.infra_level_name(level),
		"cost":           cost,
		"length_m":       length_m,
		"base_time_min":  base_time_min,
		"own_route":      own_route,
		"on_new_route":   on_new_route,
	}


## One row per link selection, in the order the links were picked.
##
## Distinct from upgrades.csv, which lists what was BOUGHT. This lists what was
## DONE: the order links were chosen in, levels re-picked, and selections
## withdrawn before confirming. The difference between the two is the decision
## process — whether someone chose decisively or reworked their plan, and what
## they nearly did but did not do — and that is a behavioural measure in its own
## right, not bookkeeping. It exists in events.json today but reached no table.
##
## `confirmed` and `changed_or_removed` are derived here rather than recorded at
## the time, because neither can be known until the round is confirmed: whether
## a pick survived is only settled by what the round ended up buying.
func _decisions_rows(parts: Dictionary) -> Array:
	var rows: Array = []
	for entry: Dictionary in parts["rounds"]:
		var events: Array = entry.get("interaction_events", [])
		if events.is_empty():
			continue

		# What the round actually committed to, keyed by link.
		var confirmed_level: Dictionary = {}
		for u: Dictionary in entry.get("upgrades", []):
			confirmed_level[str(u.get("link", ""))] = int(u.get("level", 0))
		var confirmed_removal: Dictionary = {}
		for r: Dictionary in entry.get("removals", []):
			confirmed_removal[str(r.get("link", ""))] = true

		# A pick counts as changed or removed if any LATER action in the same
		# round touched the same link, which is exactly the question "was this
		# selection altered before confirmation".
		var later_touches: Dictionary = {}
		for i in range(events.size()):
			var link: String = str((events[i] as Dictionary).get("link", ""))
			for j in range(i + 1, events.size()):
				if str((events[j] as Dictionary).get("link", "")) == link:
					later_touches[i] = true
					break

		var group_mode: bool = bool(entry.get("group_mode", false))
		for i in range(events.size()):
			var e: Dictionary = events[i]
			var link: String = str(e.get("link", ""))
			var action: String = str(e.get("action", ""))
			var level: int = int(e.get("level", 0))
			var survived: bool = false
			if action == GameManager.ACTION_STAGE_REMOVAL:
				survived = confirmed_removal.has(link)
			elif action != GameManager.ACTION_UNSTAGE:
				survived = confirmed_level.get(link, -1) == level
			rows.append({
				"schema_version": LogSchema.SCHEMA_VERSION,
				"session_id":     entry.get("session_id"),
				"sitting_id":     entry.get("sitting_id"),
				"group_id":       entry.get("group_id"),
				"participant_id": null if group_mode else entry.get("participant_id"),
				"treatment":      entry.get("treatment"),
				"round":          entry.get("round"),
				# Who is acting. In a group session that is the group, not a
				# person: one screen, one mouse.
				"decision_maker_id": entry.get("group_id") if group_mode \
						else entry.get("participant_id"),
				"decision_maker_type": "group" if group_mode else "participant",
				# Position within the round, 1-based. The underlying counter runs
				# across the whole session, so it is re-ranked here to be read
				# directly as "the Nth thing done this round".
				"selection_order": i + 1,
				"t_s":             e.get("t_s"),
				"action":          action,
				"link_id":         link,
				"level":           level,
				"level_name":      LogSchema.infra_level_name(level),
				"confirmed":       survived,
				"changed_or_removed": later_touches.has(i),
			})
	return rows


## One row per participant, with every survey item as its own column.
##
## The alternative — the whole response set as JSON in one cell, which is what
## summary.csv does — is unusable in a spreadsheet and awkward everywhere else.
## Note that the opening and closing surveys both number their items from one,
## so the prefixes are what keep pre_q1 and post_q1 from colliding: they are
## entirely different questions.
func _surveys_rows(parts: Dictionary) -> Array:
	var by_player: Dictionary = {}

	for e: Dictionary in parts["pre"]:
		var num: int = int(e.get("player_num", 0))
		var row: Dictionary = by_player.get(num, {})
		row["schema_version"] = LogSchema.SCHEMA_VERSION
		row["session_id"]     = e.get("session_id")
		row["group_id"]       = e.get("group_id")
		row["participant_id"] = e.get("participant_id")
		row["player_num"]     = num
		row["treatment"]      = e.get("treatment")
		row["treatment_ordinal"] = e.get("treatment_ordinal")
		row["alpha"]        = e.get("alpha")
		row["alpha_mean"]   = e.get("alpha_mean")
		row["personality"]  = e.get("personality")
		row["alpha_source"] = e.get("alpha_source")
		_flatten_responses(row, "pre_", SurveyQuestions.PRE, e.get("responses", {}))
		var responses: Dictionary = e.get("responses", {})
		if responses.has(SurveyQuestions.GENDER_SELF_DESCRIBED_KEY):
			row["pre_" + SurveyQuestions.GENDER_SELF_DESCRIBED_KEY] = \
					responses[SurveyQuestions.GENDER_SELF_DESCRIBED_KEY]
		by_player[num] = row

	for e: Dictionary in parts["post"]:
		var num: int = int(e.get("player_num", 0))
		var row: Dictionary = by_player.get(num, {
			"schema_version": LogSchema.SCHEMA_VERSION,
			"session_id": e.get("session_id"),
			"group_id": e.get("group_id"),
			"participant_id": e.get("participant_id"),
			"player_num": num,
			"treatment": e.get("treatment"),
		})
		_flatten_responses(row, "post_", SurveyQuestions.POST, e.get("responses", {}))
		by_player[num] = row

	var nums: Array = by_player.keys()
	nums.sort()
	var rows: Array = []
	for n in nums:
		rows.append(by_player[n])
	return rows


## Writes one column per item, and for attitude items a second `_dk` column.
##
## "Don't know" is stored as the string "dk". Left in the numeric column, a
## single one of those makes the whole variable text in every statistics package
## — so the number stays numeric and blank, and the fact that the participant
## did not know becomes its own 0/1 variable rather than being recoded to a 3
## and lost. An item that was never answered at all leaves BOTH columns blank,
## so "did not know" stays distinguishable from "was not asked".
func _flatten_responses(row: Dictionary, prefix: String, questions: Array,
		responses: Dictionary) -> void:
	for q: Dictionary in questions:
		var key: String = str(q.get("key", ""))
		var col: String = prefix + key
		if not responses.has(key):
			row[col] = null
			if int(q.get("kind", SurveyQuestions.Kind.CHOICE)) == SurveyQuestions.Kind.LIKERT:
				row[col + "_dk"] = null
			continue
		var value: Variant = responses[key]
		if int(q.get("kind", SurveyQuestions.Kind.CHOICE)) != SurveyQuestions.Kind.LIKERT:
			row[col] = value
			continue
		var is_dk: bool = typeof(value) == TYPE_STRING
		row[col] = null if is_dk else value
		row[col + "_dk"] = 1 if is_dk else 0


## One row per resident per round per phase, flattening the before/after arrays
## into a `phase` column so the whole city is one rectangular table.
func _residents_rows() -> Array:
	var rows: Array = []
	for block: Dictionary in resident_rows:
		for phase: String in ["before", "after"]:
			for r: Dictionary in block.get("residents_%s" % phase, []):
				var route_links: Array = r.get("route_links", [])
				rows.append({
					"schema_version": LogSchema.SCHEMA_VERSION,
					"session_id": block.get("session_id"),
					"sitting_id": block.get("sitting_id"),
					"group_id":   block.get("group_id"),
					"treatment":  block.get("treatment"),
					"round":      block.get("round"),
					"phase":      phase,
					"resident_index": r.get("resident_index"),
					"home":       r.get("home"),
					"work":       r.get("work"),
					"alpha":      r.get("alpha"),
					"time":       r.get("time"),
					"stress":     r.get("stress"),
					"safety":     r.get("safety"),
					"impedance":  r.get("impedance"),
					"n_links":    route_links.size(),
					"route_links": route_links,
				})
	return rows


## The settings this session ran under, so the folder describes itself.
func _write_parameters() -> void:
	var params: Dictionary = game_parameters.duplicate()
	params["schema_version"] = LogSchema.SCHEMA_VERSION
	params["session_id"]     = session_id
	params["group_id"]       = group_id
	params["treatment"]      = treatment
	params["treatment_label"] = LogSchema.treatment_label(treatment)
	params["chained_from_session_id"] = _chained_from_or_null()
	var path: String = _session_dir() + "parameters.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(params, "\t"))
		file.close()
	else:
		push_error("[DataLogger] Could not write %s" % path)


## The data dictionary, written into each session folder so a researcher opening
## one folder has both the data and the meaning of every column without needing
## anything else. Generated from the same declarations the writers use, so a
## column can never appear here with a stale description or go undescribed.
func _write_codebook() -> void:
	var path: String = _session_dir() + "codebook.csv"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[DataLogger] Could not write %s" % path)
		return
	file.store_line("file,column,description")
	var tables: Dictionary = LogSchema.all_tables()
	var names: Array = tables.keys()
	names.sort()
	for table_name: String in names:
		for c: Dictionary in tables[table_name]:
			file.store_line(LogSchema.csv_row(
					["%s.csv" % table_name, c["col"], c["desc"]]))
	file.close()


## Delegated so every CSV this file writes renders values the same way. The
## previous local version wrote the literal "<null>" for a missing value, which
## silently turned any column containing one into text for every reader; see
## LogSchema.csv_cell().
func _csv_cell(value: Variant) -> String:
	return LogSchema.csv_cell(value)


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
