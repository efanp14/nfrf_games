class_name SafetyDisplay
## SafetyDisplay.gd
## Single source of truth for turning a raw 0-100 safety score into the
## emoji participants see (numeric safety is hidden from participants; a
## debug toggle reveals the raw number for testing).
## Thresholds are heuristic (owner-confirmed 7 Jul 2026, no pilot data yet)
## — recalibrate here, in one place, if playtesting shows the score's real
## range doesn't land where these buckets expect.

const THRESHOLD_GOOD: float = 70.0
const THRESHOLD_OK:   float = 40.0

## View-only preference, not game state — lives here rather than on
## GameManager/Player so toggling it can never affect routing/logging
## (guardrail: visual layer must not become the model).
static var debug_mode: bool = false


static func emoji_for(score: float) -> String:
	if score >= THRESHOLD_GOOD:
		return "🙂"
	elif score >= THRESHOLD_OK:
		return "😐"
	return "🙁"


## Label text for a single safety score: emoji only, or emoji + raw number
## when debug mode is on.
static func format(score: float) -> String:
	if debug_mode:
		return "%s (%d)" % [emoji_for(score), int(score)]
	return emoji_for(score)
