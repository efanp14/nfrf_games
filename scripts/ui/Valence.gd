class_name Valence
## Valence.gd
## One place for "did this get better or worse, and how is that shown".
##
## THE TRIANGLE CARRIES VALENCE, NOT DIRECTION: up is always better and down is
## always worse, on every screen. It used to track each number's own direction,
## so the round summary's personal half read down-is-better (a commute time
## falls as it improves) while the city half directly beneath it read
## up-is-better (safety and coverage rise). Both were locally sensible and
## together they were unreadable -- playtesters reported the round result as
## showing "the opposite" of what they had just done.
##
## The glyph is also the colour-blind-safe second channel beside the teal/red
## pair (README, guardrail 7), so it has to mean exactly one thing.
##
## This exists because that rule was being maintained by four separate hands:
## CityFeedback stated it and honoured it, while RoundSummary and EndScreen
## re-implemented it inline at four call sites with the threshold written out
## eight times -- and one of those four, the end screen's per-seat row, had
## already drifted to carrying no glyph at all.

## Below this, a change is treated as no change. Shared so the screens cannot
## disagree about what counts as movement.
const EPSILON: float = 0.05

const BETTER: String = "▲"
const WORSE:  String = "▼"

enum Sense { WORSE, SAME, BETTER }


## `improvement` must already be signed so that positive means better, matching
## the delta convention the log uses throughout (design doc 3.7). A caller
## holding a raw time difference has to flip its sign before it gets here.
static func sense(improvement: float, epsilon: float = EPSILON) -> Sense:
	if improvement > epsilon:
		return Sense.BETTER
	if improvement < -epsilon:
		return Sense.WORSE
	return Sense.SAME


## The glyph alone, or "" when nothing moved.
static func glyph(improvement: float, epsilon: float = EPSILON) -> String:
	match sense(improvement, epsilon):
		Sense.BETTER: return BETTER
		Sense.WORSE:  return WORSE
		_:            return ""


## Picks between three ready-made phrasings and prefixes the glyph. Each screen
## words its own sentence; only the choosing and the glyph live here.
static func phrase(improvement: float, better: String, worse: String,
		same: String, epsilon: float = EPSILON) -> String:
	match sense(improvement, epsilon):
		Sense.BETTER: return "%s  %s" % [BETTER, better]
		Sense.WORSE:  return "%s  %s" % [WORSE, worse]
		_:            return same


## Colours a label by valence, clearing the override when nothing moved so the
## text falls back to the theme rather than being tinted "unchanged".
static func paint(label: Label, improvement: float, epsilon: float = EPSILON) -> void:
	match sense(improvement, epsilon):
		Sense.BETTER: label.add_theme_color_override("font_color", Palette.DELTA_GAIN)
		Sense.WORSE:  label.add_theme_color_override("font_color", Palette.DELTA_LOSS)
		_:            label.remove_theme_color_override("font_color")
