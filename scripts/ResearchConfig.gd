class_name ResearchConfig
## ResearchConfig.gd
## Study-design parameters that are not game mechanics: how participants are
## identified, and how those identifiers map onto groups.
##
## Kept out of PersonalityConfig deliberately. That file holds the values that
## feed the routing model (alpha, beta, thresholds); these describe how a study
## session is organised. Mixing the two would make it easy to change a research
## protocol setting while believing you were changing a model parameter.


## How many participants make up one group, under the sequential numbering the
## owner described: participants 1-3 are group 1, 4-6 are group 2, and so on.
##
## A constant rather than a literal because the group-decision treatment already
## supports an adjustable player count, so the two can disagree. If a session is
## ever run with a different number of people at the screen, this is the value
## that has to move with it, and it has to move in one place.
const GROUP_SIZE: int = 3

## In the group treatment, assign every player the AVERAGE personality instead
## of running the opening survey (owner decision, 5 Aug 2026: "we are going to
## use an average personality for the algorithm for each player to skip the
## friction of asking them all the surveys again").
##
## ⚠️ This is a deliberate, sanctioned exception to the project's "treatment is
## display only" guardrail — it is the one place a treatment changes a routing
## input rather than only what is shown. Do **not** "fix" it by removing the
## branch, and do not read it as licence to add other treatment branches.
##
## Flip to false to go back to asking. Nothing else needs to change: the survey
## queue already asks anyone this machine has no record for.
##
## The trade-off, recorded so it is not rediscovered as a surprise: a person
## whose individual sessions ran at cautious or confident sensitivity will
## experience their own commute differently in the group session, so a change in
## how they invest has more than one possible explanation. Every affected row is
## marked `alpha_source = "default"` so those participants stay identifiable.
const GROUP_TREATMENT_USES_DEFAULT_ALPHA: bool = true

## Characters a participant or group ID may contain. Deliberately narrow:
## these strings become filenames in the participant store and folder names in
## the research output, so a slash or a colon in an ID would either fail to
## write or silently write somewhere unintended.
const ID_ALLOWED := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"


## Whether a typed ID is safe to use. Empty is rejected because an unidentified
## participant cannot be joined to anything later, which is the entire purpose
## of asking for the ID.
static func is_valid_id(text: String) -> bool:
	if text.strip_edges().is_empty():
		return false
	for c in text:
		if not ID_ALLOWED.contains(c):
			return false
	return true


## Which group a participant number belongs to, under the sequential scheme
## above. One-based on both sides: participant 1 is the first member of group 1.
## Returns 0 for a non-positive number, meaning "no group could be derived".
static func group_for_participant(participant_number: int) -> int:
	if participant_number < 1:
		return 0
	return ((participant_number - 1) / GROUP_SIZE) + 1


## Display/log form of a group number.
static func group_id(group_number: int) -> String:
	return "g%03d" % group_number


## Best guess at the group for a set of participant IDs, used only to pre-fill
## the group field on the menu.
##
## IDs are free text, so this can only work when they happen to be plain numbers
## following the owner's scheme. Anything else returns an empty string, which
## the caller must treat as "ask the researcher" rather than as a group — the
## alternative would be inventing a group number and recording it as though it
## were derived, which is worse than admitting it is unknown.
static func suggested_group_id(ids: Array) -> String:
	if ids.is_empty():
		return ""
	var groups := {}
	for id in ids:
		var text := str(id).strip_edges()
		if not text.is_valid_int():
			return ""
		var group_number := group_for_participant(int(text))
		if group_number == 0:
			return ""
		groups[group_number] = true
	# Only offer a suggestion when every participant lands in the SAME group.
	# A session spanning two groups is a legitimate thing for a researcher to
	# do, but there is no single right answer to fill in, so it goes to them.
	if groups.size() != 1:
		return ""
	return group_id(groups.keys()[0])
