class_name SafetyDisplay
## SafetyDisplay.gd
## Single source of truth for turning a raw 0-100 safety score into the
## 5-star rating participants see (numeric safety is hidden from
## participants; a debug toggle reveals the raw number for testing).
## Linear mapping (each star = 20 points) rather than named thresholds —
## simplest thing that reads as "roughly how safe, out of 5" without needing
## separately-tuned cut points; recalibrate STARS_MAX here if playtesting
## shows the score's real range doesn't spread across the 5 stars well.

const STARS_MAX: int = 5
const STAR_FILLED: String = "★"
const STAR_EMPTY: String  = "☆"

## View-only preference, not game state — lives here rather than on
## GameManager/Player so toggling it can never affect routing/logging
## (guardrail: visual layer must not become the model).
static var debug_mode: bool = false


static func stars_for(score: float) -> String:
	var filled: int = clampi(int(round(score / 100.0 * STARS_MAX)), 0, STARS_MAX)
	return STAR_FILLED.repeat(filled) + STAR_EMPTY.repeat(STARS_MAX - filled)


## Label text for a single safety score: stars only, or stars + raw number
## when debug mode is on.
static func format(score: float) -> String:
	if debug_mode:
		return "%s (%d)" % [stars_for(score), int(score)]
	return stars_for(score)
