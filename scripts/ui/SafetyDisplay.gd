class_name SafetyDisplay
## SafetyDisplay.gd
## Single source of truth for turning a raw 0-100 safety score into the
## 5-star rating participants see (numeric safety is hidden from
## participants; a debug toggle reveals the raw number for testing).
##
## TWO SCALES, because two different things are being rated and one mapping
## cannot serve both. Pick by what the number describes, not by which is
## shorter to type:
##
##   format_route_bb()  a whole ROUTE's safety. Normalised against what that
##                      rider can actually reach on that route.
##   format_link_bb()   ONE link in isolation, from the upgrade popup. Stays on
##                      the plain 0-100 mapping, which Player.LINK_PREVIEW_STRESS_SCALE
##                      was already tuned against.
##
## There is deliberately no scale-free format_bb() any more: a call site has to
## say which of the two it means.

const STARS_MAX: int = 5
const STAR_FILLED: String = "★"
const STAR_EMPTY: String  = "☆"

## View-only preference, not game state — lives here rather than on
## GameManager/Player so toggling it can never affect routing/logging
## (guardrail: visual layer must not become the model).
static var debug_mode: bool = false


## Where a route's score sits between "nothing improved" and "as good as this
## rider can get it", 0 to 1.
##
## The rating used to read the raw score as though it ran 0 to 100. It does not:
## an untouched route always reads exactly 50 by construction and the best
## reachable is 100 - beta_protected x 50, so the whole live range was 50 to 95.
## Two consequences, both measured rather than argued (tools/probe_safety_stars):
##
##   - every participant opened on THREE stars out of five for a commute with no
##     infrastructure on it whatsoever, because the bottom 40% of the scale could
##     not be reached;
##   - of the nine rider-sessions on file whose own route safety ever moved, two
##     showed no change in the rating at all, the realistic low-spend one among
##     them: 50.0 -> 51.7 -> 57.2 across three rounds read three stars at every
##     step. That is what playtesters reported as the round result showing "the
##     opposite" of what they had just done.
##
## Normalising instead means untouched reads zero stars, fully protected reads
## five, and every purchase in between moves it, for all three personalities
## rather than only the cautious one. The score itself is untouched and so is
## everything logged: this is display (guardrail 8).
static func route_progress(score: float, rider_alpha: float) -> float:
	var low: float  = Player.safety_floor()
	var high: float = Player.safety_ceiling(rider_alpha)
	if high - low <= 0.0:
		return 0.0
	return clampf((score - low) / (high - low), 0.0, 1.0)


## How many of the five stars a ROUTE's score earns.
static func route_stars(score: float, rider_alpha: float) -> int:
	return clampi(int(round(route_progress(score, rider_alpha) * STARS_MAX)), 0, STARS_MAX)


## How many of the five stars a SINGLE LINK's preview score earns. Plain 0-100:
## Player.LINK_PREVIEW_STRESS_SCALE is already chosen so the network's links
## spread across the stars on this mapping (see the note beside it), so
## normalising here would undo that tuning.
static func link_stars(score: float) -> int:
	return clampi(int(round(score / 100.0 * STARS_MAX)), 0, STARS_MAX)


## A route rating marked up for a RichTextLabel, with the earned stars in gold.
##
## An earned star should look like something earned. In the body text colour the
## rating read as punctuation, and an empty star carried exactly as much weight
## as a filled one, so the count had to be read rather than seen.
##
## The debug number stays in the default colour on purpose, and stays the RAW
## 0-100 score rather than the normalised position: it is the value the logs
## hold, and a testing aid that did not match the log would be worse than none.
static func format_route_bb(score: float, rider_alpha: float) -> String:
	return _format(route_stars(score, rider_alpha), score)


## One link in isolation, for the upgrade popup.
static func format_link_bb(score: float) -> String:
	return _format(link_stars(score), score)


static func _format(filled: int, raw_score: float) -> String:
	var out := "[color=#%s]%s[/color]" % [
			Palette.BRAND_GOLD.to_html(false), STAR_FILLED.repeat(filled)]
	if filled < STARS_MAX:
		out += "[color=#%s]%s[/color]" % [
				Palette.STAR_EMPTY_COLOR.to_html(false),
				STAR_EMPTY.repeat(STARS_MAX - filled)]
	if debug_mode:
		out += " (%d)" % int(raw_score)
	return out
