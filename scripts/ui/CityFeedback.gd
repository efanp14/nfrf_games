class_name CityFeedback
## CityFeedback.gd
## Single definition of the city-wide feedback participants are shown in
## T2/T3 (T1 never sees it, but the underlying metrics are still computed and
## logged — see GameManager).
##
## Why this exists as its own class rather than as formatting inside each UI
## script: the research log has to record "the exact citywide feedback shown
## after the round." If the HUD, the round summary and the logger each built
## their own strings, the log could silently drift from what a participant
## actually read. Everything routes through here instead, so the recorded text
## is the shown text by construction.
##
## Pure static formatting — no node/scene dependencies, no game state written.
## Reads model values it is handed; never becomes the source of truth.

## Which city metrics participants see. Travel time stays a raw number (the
## project shows time and money as numbers); safety reuses the same star
## rating as personal safety, so the two read on one scale; coverage is a
## plain percentage of the network upgraded.
static func lines(metrics: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"City average commute:   %.1f min" % metrics.get("avg_time", 0.0),
		"City safety:   %s" % SafetyDisplay.format_route_bb(
			metrics.get("avg_safety", 0.0), PersonalityConfig.ALPHA_AVERAGE),
		"Network upgraded:   %d%%" % int(round(metrics.get("coverage", 0.0))),
	])


## Same three metrics, each with a change indicator against `baseline` — the
## Round-1 values, since the Prospect Theory reference point is static. Used by
## the round summary, so participants see gains accumulate against the original
## city rather than resetting each round. `baseline` may be empty (nothing to
## compare against yet), in which case this falls back to plain lines().
static func lines_with_change(metrics: Dictionary, baseline: Dictionary) -> PackedStringArray:
	var before := baseline
	if before.is_empty():
		return lines(metrics)
	return PackedStringArray([
		"City average commute:   %.1f min%s" % [
			metrics.get("avg_time", 0.0),
			_change_suffix(before.get("avg_time", 0.0) - metrics.get("avg_time", 0.0), "min", 0.05)],
		"City safety:   %s%s" % [
			SafetyDisplay.format_route_bb(
					metrics.get("avg_safety", 0.0), PersonalityConfig.ALPHA_AVERAGE),
			_change_suffix(metrics.get("avg_safety", 0.0) - before.get("avg_safety", 0.0), "pts", 0.05)],
		# "pts", not "%", so a rise from 12% to 13% reads as "1.4 pts" rather
		# than the ambiguous "1.4 % better" (relative change or percentage
		# points?). Coverage is measured in percentage points.
		"Network upgraded:   %d%%%s" % [
			int(round(metrics.get("coverage", 0.0))),
			_change_suffix(metrics.get("coverage", 0.0) - before.get("coverage", 0.0), "pts", 0.5)],
	])


## The collective-impact message: how many of the city's residents are better
## off than they were on the original network. Two independent figures, time
## and safety, phrased as plain sentences rather than a metrics table — this is
## the line meant to make the public-goods trade-off legible, so it reads as
## something that happened to people rather than as another statistic.
##
## The average is stated only when somebody actually gained, since "the average
## saving was 0.0 min" under a 0% headline is noise. Returns an empty array
## when the figures are absent (T1, or before the first round has been
## confirmed), so callers can append it unconditionally.
##
## Everything shown, in screen order: the travel-time sentences, then the
## caption under the person icons. The log records this whole list, so it stays
## the one record of what was read.
static func benefit_lines(metrics: Dictionary) -> PackedStringArray:
	var out := time_benefit_lines(metrics)
	if not out.is_empty():
		out.append(safety_caption(metrics))
	return out


## The travel-time half, shown as plain text (owner, Oct 2026: "keep the travel
## time as it is").
static func time_benefit_lines(metrics: Dictionary) -> PackedStringArray:
	if not metrics.has("residents_total"):
		return PackedStringArray()

	var out := PackedStringArray()
	var time_pct: float = metrics.get("residents_time_improved_pct", 0.0)
	out.append("%d%% of residents saw a faster commute" % int(round(time_pct)))
	if metrics.get("residents_time_improved", 0) > 0:
		out.append("Their average saving was %.1f min" % metrics.get("residents_time_improvement_mean", 0.0))
	return out


## How many residents travel more safely than on the original network, as five
## person icons that may be half filled (ResidentIcons): tenths of the city,
## counted in half figures, 0 to 10.
##
## Rounded to the nearest tenth with two exceptions, both so the picture never
## overstates or erases a result: any improvement at all fills at least half a
## figure (4% does not read as nobody), and anything short of everyone stops at
## nine halves (97% does not read as the whole city).
static func safety_icon_halves(metrics: Dictionary) -> int:
	var pct: float = metrics.get("residents_safety_improved_pct", 0.0)
	if pct <= 0.0:
		return 0
	if pct >= 100.0:
		return 10
	return clampi(int(round(pct / 10.0)), 1, 9)


## The sentence under the icons, in the same tenths the icons show, so the
## picture and the words can never disagree.
static func safety_caption(metrics: Dictionary) -> String:
	var halves := safety_icon_halves(metrics)
	if halves == 0:
		return "No residents had safer travel"
	if halves == 10:
		return "All residents had safer travel"
	return "About %d in 10 residents had safer travel" % halves


## `improvement` is already signed so positive = better, matching the delta
## convention used throughout the log. Returns "" when the change is below
## `epsilon`, so an unchanged metric reads as a plain value rather than a
## distracting "+0.0".
##
## The triangle means BETTER or WORSE, never up or down. RoundSummary and
## EndScreen were brought into line with this rather than the other way
## round: these lines and the personal lines share one panel, and a glyph
## that tracked each number's own direction made the two halves of that
## panel contradict each other.
static func _change_suffix(improvement: float, unit: String, epsilon: float) -> String:
	if improvement > epsilon:
		return "   (▲ %.1f %s better)" % [improvement, unit]
	if improvement < -epsilon:
		return "   (▼ %.1f %s worse)" % [absf(improvement), unit]
	return ""
