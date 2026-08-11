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
##
## 2 (11 Aug 2026): renames and one encoding fix, taken deliberately while no
## participant data existed and so nothing could be invalidated. Booleans became
## 1/0, the -1 "undefined" sentinel in the share columns became blank, the money
## columns dropped the "credits" wording left over from when the budget was
## coins, travel time gained its unit, and the seat-dependent
## own_route_upgrade_share pair was replaced by own_route_spend_share, which is
## correct for every seat. Sessions written under 1 are still readable: the
## version is stamped on every row.
const SCHEMA_VERSION: int = 2

## Where an analysis column reads from, when the two names differ.
##
## events.json is the SOURCE OF RECORD and keeps the field names it has always
## used; the analysis tables are free to name things well. Renaming the raw log
## too would rewrite the one file that is meant never to be rewritten, for a
## cosmetic gain, so the translation lives here instead: one declaration both
## row builders read, rather than a rename scattered through the writers.
const COLUMN_SOURCE: Dictionary = {
	"travel_time_min":          "time",
	"city_avg_travel_time_min": "city_avg_time",
	"budget_spent":             "credits_spent",
	"budget_spent_cumulative":  "credits_spent_cumulative",
	"budget_remaining":         "credits_remaining",
}


## The events.json field a column is built from, or the column's own name when
## it is not renamed.
static func source_field(column: String) -> String:
	return COLUMN_SOURCE.get(column, column)

const TABLE_ROUNDS:    String = "rounds"
const TABLE_DECISIONS: String = "decisions"
const TABLE_UPGRADES:  String = "upgrades"
const TABLE_SURVEYS:   String = "surveys"
const TABLE_RESIDENTS: String = "residents"
const TABLE_NETWORK_LINKS: String = "network_links"
const TABLE_NETWORK_NODES: String = "network_nodes"

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
		["budget_available", "Money available this round, in dollars."],
		["budget_spent", "Money spent this round, in dollars. Removals refund the wallet but are NOT subtracted here."],
		["budget_spent_cumulative", "Money spent across every round so far. In a group session there is one shared purse, so this describes the session rather than any one player."],
		["budget_remaining", "Money left when the round was confirmed."],
	])

	cols.append_array(_quad("travel_time_min", "Travel time in minutes over the chosen route", "lower"))
	cols.append_array(_quad("safety", "Safety score: 100 - 50 x (this route's stress / what the SAME route's stress would be fully unimproved). Per-route normalised, so it answers 'what share of this commute's own starting risk has been removed'. Observed range is 50 (untouched) to about 95 (fully protected, cautious rider), NOT 0-100. Two riders with the same score can have very different raw stress", "higher"))
	cols.append_array(_quad("stress", "Raw stress exposure along the route: sum of beta x base_stress x base_time. Absolute, not normalised, so it scales with how much stressful road was actually ridden. Related to safety but NOT interchangeable with it: the two are exactly linear for a fixed route and diverge when the route changes, because the normalising denominator changes with it", "lower"))
	cols.append_array(_quad("impedance", "Impedance, the quantity Dijkstra actually minimises: time weighted by stress and infrastructure", "lower"))

	cols.append_array(_cols([
		["home_node", "This rider's origin. Same coordinate form the residents use, so player and resident commutes are directly comparable."],
		["work_node", "This rider's destination."],
		["route_changed", "1 if this round's route differs from the route held at the start of it, otherwise 0."],
		["route_changed_from_baseline", "1 if this round's route differs from the Round 1 route, i.e. from the commute before any investment at all. Distinct from route_changed, which only looks back one round: someone can reroute and later return to where they started."],
		["route_n_links", "Number of links in the chosen route."],
		["route_links", "The chosen route as link IDs, pipe separated. Joins against link_id in upgrades.csv."],
		["route_links_baseline", "The Round 1 route, before any investment. Carried on every row so the comparison against the starting commute needs no lookup back to Round 1."],
		["upgraded_links_on_new_route_n", "How many links bought this round ended up on the NEW route. Distinct from own_route below, which was decided before the recalculation."],
		["own_route_spend_share", "Share of this round's spending that landed on THIS rider's own route, 0 to 1. The headline self-interest measure: high means the money went on their own commute, low means it went elsewhere in the city. BLANK when nothing was spent that round, because a share of no spending is undefined rather than zero; budget_spent tells those two apart. Computed from the round's purchases against each rider's own route, so it holds a real value for every seat in a group session, not only whoever's wallet the shared budget sits in."],
		["own_route_spend_share_cumulative", "The same measure across every round so far, weighted by what was spent in each. Blank until anything has been bought."],
		["n_upgrades", "Links bought this round."],
		["n_upgrades_painted", "Of those, painted lanes."],
		["n_upgrades_protected", "Of those, protected lanes."],
		["n_removals", "Previously built upgrades taken back OFF the network this round, i.e. confirmed demolitions. This is NOT the count of selections the participant changed their mind about before confirming: a link staged and then unstaged never reaches the network, so it leaves this column at 0. For choices reconsidered during the round use changed_or_removed in decisions.csv, or n_interaction_events below."],
		["n_interaction_events", "Staging actions before confirmation: selections, level changes and withdrawals. A measure of how much the decision was reworked."],
		["city_feedback_shown", "The city-wide message the participant actually read this round, verbatim, pipe separated. Empty in the individual treatment, which is shown none."],
		["city_metrics_shown", "1 if the city columns below were ON SCREEN this round, otherwise 0. They are COMPUTED in every treatment, including T1 where they are hidden, so a city value with this set to 0 is a genuine measurement the participant could not see, not missing data. That is what makes T1 city figures usable as the counterfactual for 'would this player have helped the city had they known'."],
	]))

	cols.append_array(_quad("city_avg_travel_time_min", "Mean travel time in minutes across all simulated residents", "lower"))
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
		["travel_time_min", "Travel time in minutes over their route in this phase."],
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


## network_links.csv: one row per undirected road link. The board itself.
##
## Exported because every other table refers to links by ID while nothing on
## disk said what a link WAS. Without it nobody can re-run Dijkstra
## independently, audit a stress value, or check that a cost matches its
## length — they can only take the game's word for the numbers. Together with
## parameters.json (which carries the per-metre rates, the time factors and the
## personality betas) this is enough to reproduce every route in the session
## from scratch.
##
## Immutable columns only. What players changed during the session lives in
## upgrades.csv; this describes the network they started from, which is why
## upgrade_level is absent and initial_upgrade_level is not.
static func network_links_columns() -> Array:
	if _cache.has(TABLE_NETWORK_LINKS):
		return _cache[TABLE_NETWORK_LINKS]
	var cols: Array = _cols([
		["schema_version", "Version of this column dictionary."],
		["session_id", "The run this network belongs to. The network is a fixed authored list, so this is identical across sessions of the same build; compare network_signature in parameters.json to confirm two sessions share a board."],
		["link_id", "Canonical undirected link ID, 'x,y-x,y' with the lower node first. This is the form every other table joins on."],
		["from_node", "One endpoint, as 'x,y'. Direction is not meaningful: the link is undirected and stored once here."],
		["to_node", "The other endpoint, as 'x,y'."],
		["from_name", "Fictional place name of from_node, as shown to participants."],
		["to_name", "Fictional place name of to_node."],
		["length_m", "Link length in metres. Upgrade cost is this times the per-metre rate in parameters.json."],
		["base_time_min", "Unimproved travel time in minutes. Immutable: upgrades never change it, they apply a speed factor to it (see time_factor_by_level in parameters.json)."],
		["base_stress", "Inherent stress of the road, 0 to 1, from its role in the network rather than its length: arterials sit near 0.82 and backstreets near 0.22. Immutable. This is the term an upgrade buys relief FROM, never changes."],
		["beta_painted", "Stress relief factor a painted lane would give this link, computed as 0.8 - 0.3 x base_stress. Personality independent. Recorded because it is a formula rather than a table and so cannot be read off parameters.json."],
		["initial_upgrade_level", "What this link already had before anyone played: 0 none, 1 painted, 2 protected. The city does not start blank. Nobody paid for these, they cannot be removed by a participant, and they are already counted in the Round 1 baseline."],
		["initial_level_name", "Readable form of the column above."],
		["cost_painted", "What upgrading this link to painted costs, in dollars."],
		["cost_protected", "What upgrading this link to protected costs, in dollars."],
	])
	_cache[TABLE_NETWORK_LINKS] = cols
	return cols


## network_nodes.csv: one row per junction, so the map can be redrawn and node
## IDs appearing in route_links, home_node and work_node can be named.
static func network_nodes_columns() -> Array:
	if _cache.has(TABLE_NETWORK_NODES):
		return _cache[TABLE_NETWORK_NODES]
	var cols: Array = _cols([
		["schema_version", "Version of this column dictionary."],
		["session_id", "The run this network belongs to."],
		["node_id", "Junction ID as 'x,y'. Joins against home_node and work_node in rounds.csv, and against the endpoints in network_links.csv."],
		["name", "Fictional place name shown to participants. Invented deliberately: real street names would let local knowledge bias where people invest."],
		["map_label", "Short label drawn on the map, empty when the node is drawn unlabelled."],
		["map_x", "Horizontal screen position used to draw the node. Layout only; routing uses base_time, never geometry."],
		["map_y", "Vertical screen position used to draw the node."],
		["degree", "How many links meet here."],
	])
	_cache[TABLE_NETWORK_NODES] = cols
	return cols


## Every table, for generating the codebook.
static func all_tables() -> Dictionary:
	return {
		TABLE_ROUNDS:    rounds_columns(),
		TABLE_DECISIONS: decisions_columns(),
		TABLE_UPGRADES:  upgrades_columns(),
		TABLE_SURVEYS:   surveys_columns(),
		TABLE_RESIDENTS: residents_columns(),
		TABLE_NETWORK_LINKS: network_links_columns(),
		TABLE_NETWORK_NODES: network_nodes_columns(),
	}


## What each FILE in a session folder is, keyed by filename.
##
## The per-column descriptions above cover the tidy CSVs, but a session folder
## also holds JSON that no column list describes, and a researcher opening the
## folder had no way to tell which files were the source of record, which were
## derived, and which they could ignore. Anything written into a session folder
## belongs here: DataLogger._verify_codebook_coverage() reads the finished folder
## back and warns on any file it does not describe, which is the file-level
## counterpart of a column being unable to exist without a description.
static func file_notes() -> Dictionary:
	return {
		"events.json": "SOURCE OF RECORD. Every logged event in one array, appended as the session ran: consent, one entry per pre-survey, one per round, a final snapshot, and one per post-survey. Row kinds are told apart by the `round` field, which is an int for a round and a String marker otherwise, so this does not load as a table. Every CSV in this folder is derived from it. If a CSV and this file ever disagree, this one is right.",
		"rounds.csv": "The workhorse. One row per participant per round, which is the unit of analysis. Start here.",
		"decisions.csv": "One row per link selection, in the order made. CAUTION when joining: a round in which the participant confirmed without selecting anything contributes NO rows here, so an inner join against this file silently drops that round. Join from rounds.csv outward, never into it.",
		"upgrades.csv": "One row per link actually bought or removed. What was committed to, as against decisions.csv, which is what was done on the way there.",
		"surveys.csv": "One row per participant per session, every survey item as its own column. Post-survey items q5 to q7 are answered ONLY in the group treatment: they ask about the discussion, so they are deliberately not shown, and are blank rather than missing, in T1 and T2. The group treatment in turn leaves the pre-survey columns blank, because it assigns every player the average personality instead of surveying them.",
		"residents.csv": "One row per simulated resident per round per phase. The city's own outcomes, and the basis of every city metric. Large: residents x rounds x 2.",
		"network_links.csv": "The road network the session was played on, one row per undirected link. Immutable properties only.",
		"network_nodes.csv": "The junctions of that network, with names and map positions.",
		"parameters.json": "Every setting the session ran under: budget, rounds, per-metre costs, alpha and beta tables, the benefit definition, and network_signature. Read this before comparing two sessions, since these values have changed between builds.",
		"codebook.csv": "This file. One row per file and per column, generated from the same declarations the writers use, so a column cannot exist here with a stale description or go undescribed.",
		"summary.json": "One object describing the whole session: final values, session totals, and the post-survey responses. Everything here is derivable from the per-round tables except the session totals, so treat it as convenience rather than as evidence.",
		"summary.csv": "summary.json as a single header row plus a single data row, for dropping into a spreadsheet. Its columns are exactly the keys of summary.json; nested values are JSON encoded into one cell.",
		"residents.json": "The per-resident detail behind residents.csv, in its original nested form. residents.csv is the analysis-ready version of the same data.",
		"audio_manifest.json": "Round start and end times, as UTC and as offsets from the session start, for locating a round inside a discussion recording. The recorder's own start time is the one value this file cannot know, so it must be written into the session protocol by hand. Group sessions only in practice, though it is written for every session.",
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
##
## Booleans render as 1/0 rather than true/false (schema 2). The words load as
## text in every statistics package and have to be recoded before they can be
## averaged, counted or used as a predictor, and the survey "don't know" flags
## beside them were already 1/0 — so the file had two encodings for the same
## kind of value. One numeric encoding throughout, and "what fraction of rounds
## changed the route" is just a mean.
static func csv_cell(value: Variant) -> String:
	var s: String
	if value == null:
		return ""
	elif value is bool:
		s = "1" if value else "0"
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
