class_name LogSchema
## LogSchema.gd
## The column layout of the analysis-ready CSVs, declared once, with a plain
## English description attached to every column.
##
## Why this file exists. The JSON logs record everything the research design
## asks for, but a researcher opening `rounds.csv` six months from now meets
## seventy columns with names like `impedance_baseline`, and nothing on disk
## says what any of them mean or how `_before`, `_baseline` and `_delta` differ.
## Declaring the columns and their descriptions in the same place means the
## codebook is generated from the exact list the writer emits, so the two cannot
## drift: a column cannot exist without a description, and a description cannot
## survive the column being renamed.
##
## Content only. The writers live in DataLogger, and cross-session aggregation
## lives in tools/aggregate_logs.py, which deliberately does not read this file
## (it unions whatever headers it finds) so that adding a column here never
## requires touching the aggregator.

## Bumped when the meaning of an existing column changes, which should be
## almost never: columns are added, not repurposed (guardrail 6). Stamped on
## every emitted row so a session can always be read with the right dictionary.
const SCHEMA_VERSION: int = 1

const TABLE_ROUNDS:    String = "rounds"
const TABLE_DECISIONS: String = "decisions"
const TABLE_UPGRADES:  String = "upgrades"
const TABLE_SURVEYS:   String = "surveys"
const TABLE_RESIDENTS: String = "residents"

## Separator for list-valued cells (route link IDs, feedback lines). A pipe
## rather than a comma so the cell needs no quoting, and rather than JSON so a
## spreadsheet shows something a person can read.
const LIST_SEP: String = "|"

## Built once per run, since the survey-derived columns require walking
## SurveyQuestions.
static var _cache: Dictionary = {}


## One value / before / baseline / delta block for a metric that is recorded
## four ways. Generated rather than typed out four times per metric, because the
## distinction between the three comparisons is exactly what gets muddled, and
## generating it means all four metrics explain it identically.
##
## `improves_when` is "lower" for time, stress and impedance and "higher" for
## safety; it decides which way the delta is subtracted, which is the single
## most misread thing in this data.
static func _quad(base: String, human: String, improves_when: String) -> Array:
	var delta_form: String = "baseline minus current" if improves_when == "lower" \
			else "current minus baseline"
	return [
		{"col": base,
		 "desc": "%s after this round's upgrades were applied and routes recalculated." % human},
		{"col": base + "_before",
		 "desc": "%s at the START of this round, before the upgrades were confirmed. Pair with the column above for the before/after comparison." % human},
		{"col": base + "_baseline",
		 "desc": "%s on the untouched Round 1 network. This is the STATIC Prospect Theory reference point and never rolls forward." % human},
		{"col": base + "_delta",
		 "desc": "Gain against the Round 1 baseline (%s), NOT against the previous round. Signed so positive always means improvement." % delta_form},
	]


static func _cols(pairs: Array) -> Array:
	var out: Array = []
	for p: Array in pairs:
		out.append({"col": p[0], "desc": p[1]})
	return out


## rounds.csv: one row per participant per round. The primary long-format
## dataset: round nested in participant, participant crossed with treatment.
static func rounds_columns() -> Array:
	if _cache.has(TABLE_ROUNDS):
		return _cache[TABLE_ROUNDS]

	var cols: Array = _cols([
		["schema_version", "Version of this column dictionary."],
		["session_id", "One run of one treatment. NOT a person: someone playing their second treatment gets a new session ID."],
		["sitting_id", "One SITTING. Identical on both halves of a back-to-back T1-then-T2 sitting, and equal to session_id for a session that stood alone. Group by this to treat the paired individual treatments as one visit."],
		["group_id", "The set of people who play the group treatment together. Asked for ONLY in that treatment, so it is blank on individual sessions in the per-session files. The aggregator fills it in from the group session naming the same participant, and marks those rows group_id_derived. Blank after that means the person never played a group session, so no group was ever recorded for them."],
		["chained_from_session_id", "The session immediately before this one, set only on the T2 half of a back-to-back T1-then-T2 sitting. Blank means this session began on its own. Use it to separate order/fatigue effects from treatment effects."],
		["participant_id", "The ID the researcher entered for this person. The join key across all of their sessions."],
		["player_num", "Seat number within this session, 1-based. Always 1 outside the group treatment."],
		["treatment", "0 = individual, 1 = individual plus city metrics, 2 = group discussion."],
		["treatment_label", "Readable form of the column above."],
		["treatment_ordinal", "Which treatment in the fixed order this was for this person, counted on the machine that ran it. WARNING: the count is per-machine, so a group session run on a second computer reports 1 rather than 3. Do not join on this; join on treatment."],
		["group_mode", "True in the group treatment. Group rows share one screen, one mouse and one budget."],
		["num_players", "People seated in this session."],
		["round", "1-based round number."],
		["alpha", "Stress sensitivity used for this person's routing this session. 3.0 cautious, 1.5 average, 0.4 confident."],
		["personality", "Name of the alpha band above."],
		["alpha_source", "Where alpha came from: 'survey' answered this session, 'stored' reused from an earlier session on this machine, 'default' assigned without asking (the group treatment does this). A 'default' row did NOT play at their own sensitivity, which matters when comparing them against their solo sessions."],
		["timestamp_s", "Seconds from session start to the end of this round."],
		["decision_time_s", "Seconds the round was open, from shown to confirmed. In the group treatment this is the deliberation time."],
		["budget_available", "Money available this round."],
		["credits_spent", "Money spent this round. Removals refund the wallet but are NOT subtracted here."],
		["credits_spent_cumulative", "Money spent across every round so far. In a group session there is one shared purse, so this describes the session rather than any one player."],
		["credits_remaining", "Money left when the round was confirmed."],
	])

	cols.append_array(_quad("time", "Travel time in minutes over the chosen route", "lower"))
	cols.append_array(_quad("safety", "Safety score: 100 - 50 x (this route's stress / what the SAME route's stress would be fully unimproved). Per-route normalised, so it answers 'what share of this commute's own starting risk has been removed'. Observed range is 50 (untouched) to about 95 (fully protected, cautious rider), NOT 0-100. Two riders with the same score can have very different raw stress", "higher"))
	cols.append_array(_quad("stress", "Raw stress exposure along the route: sum of beta x base_stress x base_time. Absolute, not normalised, so it scales with how much stressful road was actually ridden. Related to safety but NOT interchangeable with it: the two are exactly linear for a fixed route and diverge when the route changes, because the normalising denominator changes with it", "lower"))
	cols.append_array(_quad("impedance", "Impedance, the quantity Dijkstra actually minimises: time weighted by stress and infrastructure", "lower"))

	cols.append_array(_cols([
		["home_node", "This rider's origin. Same coordinate form the residents use, so player and resident commutes are directly comparable."],
		["work_node", "This rider's destination."],
		["route_changed", "True if this round's route differs from the route held at the start of it."],
		["route_changed_from_baseline", "True if this round's route differs from the Round 1 route, i.e. from the commute before any investment at all. Distinct from route_changed, which only looks back one round: someone can reroute and later return to where they started."],
		["route_n_links", "Number of links in the chosen route."],
		["route_links", "The chosen route as link IDs, pipe separated. Joins against link_id in upgrades.csv."],
		["route_links_baseline", "The Round 1 route, before any investment. Carried on every row so the comparison against the starting commute needs no lookup back to Round 1."],
		["upgraded_links_on_new_route_n", "How many links bought this round ended up on the NEW route. Distinct from own_route below, which was decided before the recalculation."],
		["own_route_upgrade_share", "Share of this round's spending that went to links on this rider's own route at the moment of purchase. -1 means nothing was spent, which is NOT the same as 0 percent. Only meaningful for the seat holding the budget; see the next column."],
		["cumulative_own_route_upgrade_share", "The same measure across every round so far. -1 means nothing has been spent yet."],
		["group_spend_on_my_route_share", "Share of the round's spending that landed on THIS rider's route, computed from the purchases rather than from their own wallet. Unlike own_route_upgrade_share it is a real value for every seat in a group session, so it is the column to use when comparing self-interested against collective allocation. -1 means nothing was spent."],
		["n_upgrades", "Links bought this round."],
		["n_upgrades_painted", "Of those, painted lanes."],
		["n_upgrades_protected", "Of those, protected lanes."],
		["n_removals", "Previously built upgrades taken back off the network this round."],
		["n_interaction_events", "Staging actions before confirmation: selections, level changes and withdrawals. A measure of how much the decision was reworked."],
		["city_feedback_shown", "The city-wide message the participant actually read this round, verbatim, pipe separated. Empty in the individual treatment, which is shown none."],
		["city_metrics_shown", "Whether the city columns below were ON SCREEN this round. They are COMPUTED in every treatment, including T1 where they are hidden, so a city value with this set false is a genuine measurement the participant could not see, not missing data. That is what makes T1 city figures usable as the counterfactual for 'would this player have helped the city had they known'."],
	]))

	cols.append_array(_quad("city_avg_time", "Mean travel time in minutes across all simulated residents", "lower"))
	cols.append_array(_quad("city_avg_safety", "Mean safety score across all simulated residents", "higher"))
	cols.append_array(_quad("city_avg_stress", "Mean route stress across all simulated residents", "lower"))

	cols.append_array(_cols([
		["city_coverage_pct", "Percentage of network links carrying any upgrade."],
		["city_coverage_pct_before", "The same at the start of this round."],
		["city_coverage_pct_baseline", "The same on the untouched Round 1 network."],
		["residents_total", "Simulated residents in the city."],
		["residents_time_improved", "Residents whose travel time is better than on the Round 1 network."],
		["residents_time_improved_pct", "The same as a percentage."],
		["residents_time_worsened", "Residents whose travel time is worse than Round 1."],
		["residents_time_no_benefit", "Residents not improved on time. Includes the worsened, which are also broken out above."],
		["residents_time_no_benefit_pct", "The same as a percentage."],
		["residents_time_improvement_mean", "Mean minutes saved, averaged over the improved residents ONLY, not over the whole city."],
		["residents_safety_improved", "Residents whose route safety is better than on the Round 1 network."],
		["residents_safety_improved_pct", "The same as a percentage."],
		["residents_safety_worsened", "Residents whose route safety is worse than Round 1."],
		["residents_safety_no_benefit", "Residents not improved on safety. Includes the worsened."],
		["residents_safety_no_benefit_pct", "The same as a percentage."],
		["residents_safety_improvement_mean", "Mean safety points gained, averaged over the improved residents ONLY."],
		["residents_stress_improved", "Residents whose raw route stress is lower than on the Round 1 network. Reported alongside safety because safety is a normalised transform of stress and the two are not interchangeable across routes of different lengths."],
		["residents_stress_improved_pct", "The same as a percentage."],
		["residents_stress_worsened", "Residents whose raw route stress is higher than Round 1."],
		["residents_stress_no_benefit", "Residents not improved on stress. Includes the worsened."],
		["residents_stress_no_benefit_pct", "The same as a percentage."],
		["residents_stress_improvement_mean", "Mean raw stress reduction, averaged over the improved residents ONLY."],
		["residents_total_time_saved_min", "Minutes saved summed across all residents. Excludes the human players, who are a different population."],
		["residents_total_safety_gained", "Safety points gained summed across all residents. Excludes the human players."],
		["residents_total_stress_reduced", "Raw stress reduction summed across all residents. Excludes the human players."],
	]))

	_cache[TABLE_ROUNDS] = cols
	return cols


## decisions.csv: one row per link selection, in the order they were made.
##
## upgrades.csv says what was bought; this says what was DONE on the way there.
## The gap between the two is the decision process: order of choice, levels
## re-picked, and links selected then withdrawn before confirming. What someone
## nearly did is evidence about how they decided, and it is only visible here.
static func decisions_columns() -> Array:
	if _cache.has(TABLE_DECISIONS):
		return _cache[TABLE_DECISIONS]
	var cols: Array = _cols([
		["schema_version", "Version of this column dictionary."],
		["session_id", "The run this action belongs to."],
		["sitting_id", "The sitting this action belongs to; identical across a paired T1-then-T2 visit."],
		["group_id", "The set of people this session belongs to. Blank on individual sessions, which are not asked for a group; see the fuller note on the same column in rounds.csv."],
		["participant_id", "Who acted. BLANK in a group session, where the group is the actor; see decision_maker_type."],
		["treatment", "0 = individual, 1 = individual plus city metrics, 2 = group discussion."],
		["round", "1-based round number."],
		["decision_maker_id", "The participant in a solo session, the group in a group one. Who the choice belongs to."],
		["decision_maker_type", "'participant' or 'group'. The unit that made the decision, which is NOT the unit that experiences the outcome. For that see rounds.csv, which has a row per person even in a group session."],
		["selection_order", "Position within the round, 1-based. Read as 'the Nth thing done this round'."],
		["t_s", "Seconds from the start of the round to this action. Gaps between consecutive actions are thinking or, in a group session, discussion."],
		["action", "'select' staged an upgrade on a fresh link, 'change_level' re-picked a different level on an already-staged link, 'unstage' withdrew a staged upgrade, 'stage_removal' staged taking an existing upgrade back off."],
		["link_id", "The road link acted on. Joins against upgrades.csv and the route_links columns."],
		["level", "The level staged by this action. For 'unstage', the level being withdrawn."],
		["level_name", "Readable form of the column above."],
		["confirmed", "Whether this action survived into what the round actually committed to. False for anything withdrawn or later overridden."],
		["changed_or_removed", "Whether a LATER action in the same round touched this same link, i.e. whether this selection was altered before confirmation. True marks a pick the person reconsidered."],
	])
	_cache[TABLE_DECISIONS] = cols
	return cols


## upgrades.csv: one row per link bought or removed.
static func upgrades_columns() -> Array:
	if _cache.has(TABLE_UPGRADES):
		return _cache[TABLE_UPGRADES]
	var cols: Array = _cols([
		["schema_version", "Version of this column dictionary."],
		["session_id", "The run this purchase belongs to."],
		["sitting_id", "The sitting this run belongs to; identical across a paired T1-then-T2 visit."],
		["group_id", "The set of people this session belongs to. Blank on individual sessions, which are not asked for a group; see the fuller note on the same column in rounds.csv."],
		["participant_id", "Who bought it. BLANK in a group session, and blank there means 'the group decided', not 'missing': three people share one screen and one mouse, so the game cannot know whose hand it was. Attribution inside a group session comes from the audio recording, aligned via audio_manifest.json."],
		["treatment", "0 = individual, 1 = individual plus city metrics, 2 = group discussion."],
		["round", "1-based round number."],
		["action", "'upgrade' for a purchase, 'removal' for an upgrade taken back off the network."],
		["link_id", "The road link. Joins against route_links in rounds.csv and residents.csv."],
		["level", "1 = painted lane, 2 = protected lane. For a removal, the level it was removed FROM."],
		["level_name", "Readable form of the column above."],
		["cost", "Money spent, or refunded on a removal."],
		["length_m", "Link length in metres. Cost is this times the per-metre rate for the level."],
		["base_time_min", "Unimproved travel time over the link in minutes. Immutable; upgrades never change it."],
		["own_route", "True if the link was on the buyer's route at the MOMENT OF PURCHASE. In a group session this is player 1's route, since that is the seat the purchase is recorded against."],
		["on_new_route", "True if the link ended up on the route after recalculation. Differs from own_route when the purchase caused a reroute."],
	])
	_cache[TABLE_UPGRADES] = cols
	return cols


## residents.csv: one row per simulated resident per round per phase.
static func residents_columns() -> Array:
	if _cache.has(TABLE_RESIDENTS):
		return _cache[TABLE_RESIDENTS]
	var cols: Array = _cols([
		["schema_version", "Version of this column dictionary."],
		["session_id", "The run this snapshot belongs to."],
		["sitting_id", "The sitting this run belongs to."],
		["group_id", "The set of people this session belongs to. Blank on individual sessions, which are not asked for a group; see the fuller note on the same column in rounds.csv."],
		["treatment", "0 = individual, 1 = individual plus city metrics, 2 = group discussion."],
		["round", "1-based round number."],
		["phase", "'before' = the start of the round, 'after' = once the round's upgrades were applied. Every resident appears twice per round."],
		["resident_index", "Stable identifier for this simulated resident. The set and their home/work pairs are a fixed authored list, identical on every run."],
		["home", "Origin node."],
		["work", "Destination node."],
		["alpha", "This resident's stress sensitivity."],
		["time", "Travel time in minutes over their route in this phase."],
		["stress", "Raw stress exposure along their route: sum of beta x base_stress x base_time. Absolute, so a long commute reads higher than a short one at the same comfort."],
		["safety", "Safety score for their route: 100 - 50 x (current stress / that same route's fully unimproved stress). Per-route normalised, so it is comparable across residents with commutes of different lengths in a way raw stress is not. Floor is 50, not 0."],
		["impedance", "Impedance of their route, the quantity Dijkstra minimised."],
		["n_links", "Number of links in their route."],
		["route_links", "Their route as link IDs, pipe separated."],
	])
	_cache[TABLE_RESIDENTS] = cols
	return cols


## surveys.csv: one row per participant per session, with every item as its own
## column. Generated from SurveyQuestions so adding an item extends the file
## without anyone remembering to update this list.
##
## Attitude items get a second `_dk` column. "Don't know" is stored as the string
## "dk", and left in the numeric column it would turn an otherwise numeric
## variable into text in every statistics package. Splitting it keeps the number
## numeric and keeps "did not know" measurable rather than silently recoded.
static func surveys_columns() -> Array:
	if _cache.has(TABLE_SURVEYS):
		return _cache[TABLE_SURVEYS]

	var cols: Array = _cols([
		["schema_version", "Version of this column dictionary."],
		["session_id", "The run these answers were given in."],
		["group_id", "The set of people this session belongs to. Blank on individual sessions, which are not asked for a group; see the fuller note on the same column in rounds.csv."],
		["participant_id", "Who answered. The join key across all of their sessions."],
		["player_num", "Seat number within this session, 1-based."],
		["treatment", "0 = individual, 1 = individual plus city metrics, 2 = group discussion."],
		["treatment_ordinal", "Which treatment in the fixed order this was for this person, as counted on the machine that ran it. See the warning on the same column in rounds.csv."],
		["alpha", "Stress sensitivity derived from the attitude items."],
		["alpha_mean", "Mean of the attitude items that alpha was banded from. 'Don't know' counts as the neutral middle here."],
		["personality", "Name of the alpha band: cautious, average or confident."],
		["alpha_source", "'survey' answered this session, 'stored' reused from an earlier session on this machine, 'default' assigned without asking."],
	])

	for q: Dictionary in SurveyQuestions.PRE:
		cols.append_array(_survey_item_columns("pre_", q, "Opening survey"))
		if str(q.get("key", "")) == SurveyQuestions.GENDER_KEY:
			cols.append({
				"col": "pre_" + SurveyQuestions.GENDER_SELF_DESCRIBED_KEY,
				"desc": "Opening survey: free text written in when the participant self described their gender. Blank otherwise.",
			})
	for q: Dictionary in SurveyQuestions.POST:
		var note: String = "Closing survey"
		if bool(q.get("group_only", false)):
			note += " (asked ONLY in the group treatment, so blank elsewhere by design, not missing data)"
		cols.append_array(_survey_item_columns("post_", q, note))

	_cache[TABLE_SURVEYS] = cols
	return cols


static func _survey_item_columns(prefix: String, q: Dictionary, note: String) -> Array:
	var key: String = prefix + str(q.get("key", ""))
	var text: String = str(q.get("text", ""))
	if int(q.get("kind", SurveyQuestions.Kind.CHOICE)) == SurveyQuestions.Kind.LIKERT:
		return [
			{"col": key, "desc": "%s: \"%s\" 1 strongly disagree to 5 strongly agree. Blank if answered 'Don't know'." % [note, text]},
			{"col": key + "_dk", "desc": "1 if the participant answered 'Don't know / Not applicable' to the item above, otherwise 0."},
		]
	return [{"col": key, "desc": "%s: \"%s\" The chosen option, verbatim." % [note, text]}]


## Every table, for generating the codebook.
static func all_tables() -> Dictionary:
	return {
		TABLE_ROUNDS:    rounds_columns(),
		TABLE_DECISIONS: decisions_columns(),
		TABLE_UPGRADES:  upgrades_columns(),
		TABLE_SURVEYS:   surveys_columns(),
		TABLE_RESIDENTS: residents_columns(),
	}


## Readable names for the coded values, so a CSV is legible without a lookup
## table. These name the MODEL, not the screen: the participant-facing rename of
## the unimproved level to "No Bike Lane" is a display decision and does not
## belong in the data, where the level's own name is what analysis refers to.
static func treatment_label(treatment: int) -> String:
	match treatment:
		0: return "T1 individual"
		1: return "T2 individual plus city"
		2: return "T3 group discussion"
	return "unknown"


static func infra_level_name(level: int) -> String:
	match level:
		0: return "unimproved"
		1: return "painted"
		2: return "protected"
	return "unknown"


static func header_for(columns: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for c: Dictionary in columns:
		out.append(str(c["col"]))
	return out


## Renders one value as a CSV cell.
##
## The important case is null. `str(null)` in GDScript produces the literal text
## "<null>", and a single one of those anywhere in a column makes every reader
## treat the whole column as text rather than numbers, quietly, with no error,
## which is the worst way for a data problem to behave. An absent value is an
## empty cell, which every statistics package reads as missing.
##
## Lists of scalars join with LIST_SEP rather than being JSON encoded, so a
## route reads as a route in a spreadsheet instead of as an escaped blob.
static func csv_cell(value: Variant) -> String:
	var s: String
	if value == null:
		return ""
	elif value is bool:
		s = "true" if value else "false"
	elif value is Array or value is PackedStringArray:
		s = _join_scalars(value)
	elif value is Dictionary:
		s = JSON.stringify(value)
	else:
		s = str(value)
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		s = "\"%s\"" % s.replace("\"", "\"\"")
	return s


## Arrays of plain values join readably; anything nested falls back to JSON,
## because a pipe-joined list of dictionaries would be unparseable either way
## and at least JSON is honest about it.
static func _join_scalars(list: Variant) -> String:
	var parts: PackedStringArray = []
	for item in list:
		if item is Dictionary or item is Array:
			return JSON.stringify(list)
		parts.append("" if item == null else str(item))
	return LIST_SEP.join(parts)


static func csv_row(values: Array) -> String:
	var cells: PackedStringArray = []
	for v in values:
		cells.append(csv_cell(v))
	return ",".join(cells)


## Pulls the values for a declared column list out of a row dictionary, so the
## header and the data can never fall out of step: a column with no matching key
## becomes an empty cell rather than shifting every later value one place left.
static func row_values(columns: Array, row: Dictionary) -> Array:
	var out: Array = []
	for c: Dictionary in columns:
		out.append(row.get(str(c["col"]), null))
	return out
