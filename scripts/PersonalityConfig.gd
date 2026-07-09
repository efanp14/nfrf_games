class_name PersonalityConfig
## PersonalityConfig.gd
## Single source of truth for personality-derived constants.
## alpha/beta/threshold values must not be duplicated or hardcoded elsewhere —
## reference this class instead (guardrail: "no magic numbers").

const ALPHA_CAUTIOUS:  float = 3.0
const ALPHA_AVERAGE:   float = 1.5
const ALPHA_CONFIDENT: float = 0.4

## Pre-survey mean(Q5..Q8) thresholds that select a personality type.
const SURVEY_MEAN_CAUTIOUS_MAX:  float = 2.5   # mean < 2.5  -> Cautious
const SURVEY_MEAN_CONFIDENT_MIN: float = 3.5   # mean > 3.5  -> Confident

## Protected-lane beta (infrastructure relief), keyed by the cyclist's
## personality — not by road stress. Painted-lane beta stays stress-derived
## (CityNetwork.Link.effective_beta) since the spec gives it as a flat range,
## not a personality table.
const BETA_PROTECTED_CAUTIOUS:  float = 0.1
const BETA_PROTECTED_AVERAGE:   float = 0.2
const BETA_PROTECTED_CONFIDENT: float = 0.6


static func alpha_for_survey_mean(mean: float) -> float:
	if mean < SURVEY_MEAN_CAUTIOUS_MAX:
		return ALPHA_CAUTIOUS
	elif mean > SURVEY_MEAN_CONFIDENT_MIN:
		return ALPHA_CONFIDENT
	return ALPHA_AVERAGE


## Every alpha in play is assigned from exactly one of the three constants
## above and never changes at runtime (guardrail), so bucketing by midpoint
## is safe and avoids relying on exact float equality.
static func beta_protected_for_alpha(alpha: float) -> float:
	if alpha >= (ALPHA_CAUTIOUS + ALPHA_AVERAGE) / 2.0:
		return BETA_PROTECTED_CAUTIOUS
	elif alpha >= (ALPHA_AVERAGE + ALPHA_CONFIDENT) / 2.0:
		return BETA_PROTECTED_AVERAGE
	return BETA_PROTECTED_CONFIDENT
