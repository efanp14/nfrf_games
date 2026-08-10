class_name SurveyQuestions
## SurveyQuestions.gd
## Verbatim content of both research surveys, transcribed from the official
## question file supplied by the project owner.
##
## The wording here is authoritative and must not be paraphrased, reordered or
## "improved". The attitude items are drawn from established instruments (risk
## tolerance and self efficacy in the opening survey, deliberation quality in
## the closing one), and altering their wording breaks comparability with the
## literature they come from. An earlier build shipped invented approximations
## of these items, including one reverse worded item that has no counterpart in
## the official set, which is the exact failure this file exists to prevent.
##
## Content only. Rendering lives in the survey scenes, and the response scale
## lives in SurveyScale.

enum Kind { CHOICE, LIKERT }

## Gender is the one question that accepts a written answer alongside the fixed
## options, so it needs named keys rather than being handled positionally.
const GENDER_KEY: String = "q2"
const GENDER_SELF_DESCRIBED_KEY: String = "q2_self_described"
const GENDER_SELF_DESCRIBED_OPTION: String = "I identify as"

## The four attitude items alpha is derived from. Listed explicitly rather than
## taken as "the last four questions", so that adding a demographic question
## later cannot silently change who is classified as cautious or confident.
const ALPHA_KEYS: Array = ["q8", "q9", "q10", "q11"]

const SECTION_DEMOGRAPHICS: String = "Section 1: Individual Demographics"
const SECTION_CYCLING: String = "Section 2: Cycling Behavior"


## The survey shown before play. Eleven questions: five demographic, two on
## cycling behaviour, four attitude items scored into alpha.
const PRE: Array = [
	{"key": "q1", "kind": Kind.CHOICE, "section": SECTION_DEMOGRAPHICS,
	 "text": "What is your age category?",
	 "options": ["18-24", "25-29", "30-34", "35-39", "40-44", "45-49", "50-54",
				 "55-59", "60-64", "65-69", "70-74", "75-79", "80-84", "85+"]},

	{"key": "q2", "kind": Kind.CHOICE, "section": SECTION_DEMOGRAPHICS,
	 "text": "What is your gender?",
	 "options": ["Male", "Female", "Non-binary", "Prefer not to say",
				 GENDER_SELF_DESCRIBED_OPTION]},

	{"key": "q3", "kind": Kind.CHOICE, "section": SECTION_DEMOGRAPHICS,
	 "text": "What is your primary employment status?",
	 "options": ["Employed full-time", "Employed part-time", "Self-employed",
				 "Student", "Retired", "Unemployed", "Other"]},

	{"key": "q4", "kind": Kind.CHOICE, "section": SECTION_DEMOGRAPHICS,
	 "text": "Which statement best describes your current work or school arrangement?",
	 "options": ["Completely remote", "Hybrid", "Completely in-person"]},

	{"key": "q5", "kind": Kind.CHOICE, "section": SECTION_DEMOGRAPHICS,
	 "text": "Do you have a valid driver's license?",
	 "options": ["Yes", "No"]},

	{"key": "q6", "kind": Kind.CHOICE, "section": SECTION_CYCLING,
	 "text": "How often do you cycle in a typical week?",
	 "options": ["Never", "1-2 days", "3-4 days", "5+ days"]},

	{"key": "q7", "kind": Kind.CHOICE, "section": SECTION_CYCLING,
	 "text": "How long have you cycled at this frequency?",
	 "options": ["Never", "<1 year", "1-3 years", ">3 years"]},

	{"key": "q8", "kind": Kind.LIKERT, "section": SECTION_CYCLING,
	 "text": "I would cycle on a busy road with no bike lane if it saved 5 minutes."},

	{"key": "q9", "kind": Kind.LIKERT, "section": SECTION_CYCLING,
	 "text": "I sometimes take routes that feel unsafe because they are faster."},

	{"key": "q10", "kind": Kind.LIKERT, "section": SECTION_CYCLING,
	 "text": "I feel confident cycling alongside fast-moving traffic."},

	{"key": "q11", "kind": Kind.LIKERT, "section": SECTION_CYCLING,
	 "text": "I feel comfortable finding a cycling route in a city I do not know well."},
]


## The survey shown after play. Every item uses the shared scale.
##
## `group_only` marks the three items that ask about a group discussion. They
## are meaningless to someone who played alone, so they are shown only in the
## group treatment rather than collecting noise from T1 and T2 participants.
const POST: Array = [
	{"key": "q1", "kind": Kind.LIKERT, "group_only": false,
	 "text": "My investment decisions improved my own commute time."},

	{"key": "q2", "kind": Kind.LIKERT, "group_only": false,
	 "text": "The final improvements were distributed fairly across the city."},

	{"key": "q3", "kind": Kind.LIKERT, "group_only": false,
	 "text": "I focused more on my own route than the city overall."},

	{"key": "q4", "kind": Kind.LIKERT, "group_only": false,
	 "text": "I would accept a longer commute if it made the city safer."},

	{"key": "q5", "kind": Kind.LIKERT, "group_only": true,
	 "text": "I changed my mind during the discussion because of someone's reason."},

	{"key": "q6", "kind": Kind.LIKERT, "group_only": true,
	 "text": "I felt my reasons were genuinely heard and considered by others."},

	{"key": "q7", "kind": Kind.LIKERT, "group_only": true,
	 "text": "The group made a decision that was fair to everyone."},
]


## Mean of the four attitude items, using the explicit map in SurveyScale.
##
## No item is reverse scored: the official set contains no reverse worded
## question, so every response is taken at face value. Absent answers are
## skipped rather than defaulted to a neutral value. The survey cannot be
## submitted until every question is answered, and quietly substituting a
## middle value for a missing one would hide it if that ever stopped being true.
static func alpha_mean(responses: Dictionary) -> float:
	var total: float = 0.0
	var counted: int = 0
	for key: String in ALPHA_KEYS:
		if not responses.has(key):
			continue
		total += SurveyScale.score_for(responses[key])
		counted += 1
	if counted == 0:
		return SurveyScale.NEUTRAL_SCORE
	return total / float(counted)
