class_name CityFeedback
## CityFeedback.gd
##
## Defines the citywide feedback shown to participants in T2 and T3.
## T1 does not display citywide feedback, although the underlying metrics
## are still calculated and logged by GameManager.
##
## Participant-facing citywide information is intentionally kept simple:
##   1. City average commute time
##   2. City safety
##   3. Number of residents whose travel became safer
##
## Other metrics such as network coverage, travel-time benefit counts,
## stress changes, and citywide deltas remain available in the backend/logs
## for analysis but are not shown to participants.


## Main citywide outcomes shown in T2 and T3.
static func lines(metrics: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"City average commute:   %.1f min" % metrics.get("avg_time", 0.0),
		"City safety:   %s" % SafetyDisplay.format_route_bb(
			metrics.get("avg_safety", 0.0),
			PersonalityConfig.ALPHA_AVERAGE
		),
	])


## Kept for compatibility with screens that previously displayed changes
## relative to the Round-1 baseline.
## We now intentionally show only the current citywide values.
static func lines_with_change(
	metrics: Dictionary,
	_baseline: Dictionary
) -> PackedStringArray:
	return lines(metrics)


## Collective safety impact shown below the resident icons.
static func benefit_lines(metrics: Dictionary) -> PackedStringArray:
	if not metrics.has("residents_total"):
		return PackedStringArray()

	return PackedStringArray([
		safety_caption(metrics)
	])


## Travel-time benefit remains calculated in the backend but is no longer
## shown to participants.
## Kept as an empty helper for compatibility with any existing callers.
static func time_benefit_lines(_metrics: Dictionary) -> PackedStringArray:
	return PackedStringArray()


## Converts the percentage of simulated residents whose safety improved
## relative to the original network into five person icons.
##
## Each full person represents 20% of residents.
## Each half person represents 10%.
static func safety_icon_halves(metrics: Dictionary) -> int:
	var pct: float = metrics.get("residents_safety_improved_pct", 0.0)

	if pct <= 0.0:
		return 0

	if pct >= 100.0:
		return 10

	return clampi(int(round(pct / 10.0)), 1, 9)


## Text shown underneath the resident icons.
static func safety_caption(metrics: Dictionary) -> String:
	var halves := safety_icon_halves(metrics)

	if halves == 0:
		return "Your upgrades did not make travel safer
		 for any residents"

	if halves == 10:
		return "Your upgrades made travel safer
		 for all residents"

	return "Your upgrades made travel safer
	 for about %d in 10 residents" % halves
