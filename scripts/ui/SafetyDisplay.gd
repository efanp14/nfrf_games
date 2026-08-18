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


## How many of the five stars a score earns.
static func filled_stars(score: float) -> int:
	return clampi(int(round(score / 100.0 * STARS_MAX)), 0, STARS_MAX)


## Plain text, no markup. Kept as the readable form for anywhere BBCode is not
## being rendered: probes, printouts, and anything read rather than displayed.
static func stars_for(score: float) -> String:
	var filled: int = filled_stars(score)
	return STAR_FILLED.repeat(filled) + STAR_EMPTY.repeat(STARS_MAX - filled)


## The rating marked up for a RichTextLabel, with the earned stars in gold. This
## is what every screen shows.
##
## An earned star should look like something earned. In the body text colour the
## rating read as punctuation, and an empty star carried exactly as much weight
## as a filled one, so the count had to be read rather than seen.
##
## The debug number stays in the default colour on purpose: it is a testing aid,
## not part of what a participant is meant to take in.
static func format_bb(score: float) -> String:
	var filled: int = filled_stars(score)
	var out := "[color=#%s]%s[/color]" % [
			Palette.BRAND_GOLD.to_html(false), STAR_FILLED.repeat(filled)]
	if filled < STARS_MAX:
		out += "[color=#%s]%s[/color]" % [
				Palette.STAR_EMPTY_COLOR.to_html(false),
				STAR_EMPTY.repeat(STARS_MAX - filled)]
	if debug_mode:
		out += " (%d)" % int(score)
	return out
