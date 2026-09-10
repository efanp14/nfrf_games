extends Node
## Checks that what a participant SEES agrees with what the model computes:
## the safety star rating, and the map's effective-stress cues.
##
##   godot --headless res://tools/probe_safety_stars.tscn
##
## The rating used to map the raw 0-100 score onto five stars, but the score only
## ever runs 50 to 95: a route with nothing improved reads exactly 50 by
## construction, and the best reachable is 100 - beta_protected x 50.
##
## Measured over the 3,552 logged player-rounds on the development machine, 99.4%
## rendered as exactly three stars. Most of those rounds bought nothing, where a
## flat rating is correct rather than broken, so the sharper statement is this:
## of the nine rider-sessions in that corpus whose own route safety ever moved,
## the old mapping failed to show it in two, including the one realistic
## low-spend run (50.0 -> 51.7 -> 57.2, which read three stars at every step).
## And every participant began on three stars out of five for a commute with no
## infrastructure on it at all, because the bottom 40% of the scale could not be
## reached.
##
## This probe holds the replacement to the properties that were missing: an
## untouched commute reads empty, and buying things changes the number.

var _failures: int = 0


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL  %s" % what)


func _ready() -> void:
	_ends_of_the_scale()
	_monotonic()
	_link_scale_untouched()
	_debug_shows_the_raw_score()
	_a_real_commute_moves()
	_a_small_spend_moves()
	_map_stress_matches_the_model()
	_routing_is_unchanged()

	print("")
	print("FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## Untouched must read empty and fully protected must read full, for every
## personality rather than only for the cautious one.
func _ends_of_the_scale() -> void:
	for alpha: float in [PersonalityConfig.ALPHA_CAUTIOUS,
			PersonalityConfig.ALPHA_AVERAGE, PersonalityConfig.ALPHA_CONFIDENT]:
		var low := Player.safety_floor()
		var high := Player.safety_ceiling(alpha)
		var label := PersonalityConfig.personality_name_for_alpha(alpha)
		if SafetyDisplay.route_stars(low, alpha) != 0:
			_fail("%s: an untouched route reads %d stars, not 0"
					% [label, SafetyDisplay.route_stars(low, alpha)])
		if SafetyDisplay.route_stars(high, alpha) != SafetyDisplay.STARS_MAX:
			_fail("%s: a fully protected route reads %d stars, not %d"
					% [label, SafetyDisplay.route_stars(high, alpha), SafetyDisplay.STARS_MAX])
		print("%-9s floor %.1f -> 0 stars, ceiling %.1f -> %d stars"
				% [label, low, high, SafetyDisplay.STARS_MAX])
		# Anything outside the range must clamp rather than run off either end.
		if SafetyDisplay.route_stars(low - 20.0, alpha) != 0:
			_fail("%s: a score below the floor did not clamp to 0" % label)
		if SafetyDisplay.route_stars(high + 20.0, alpha) != SafetyDisplay.STARS_MAX:
			_fail("%s: a score above the ceiling did not clamp to full" % label)


func _monotonic() -> void:
	for alpha: float in [PersonalityConfig.ALPHA_CAUTIOUS,
			PersonalityConfig.ALPHA_AVERAGE, PersonalityConfig.ALPHA_CONFIDENT]:
		var previous := -1
		var score := Player.safety_floor()
		while score <= Player.safety_ceiling(alpha) + 0.001:
			var stars := SafetyDisplay.route_stars(score, alpha)
			if stars < previous:
				_fail("stars went backwards at %.2f for alpha %.1f" % [score, alpha])
				break
			previous = stars
			score += 0.25
	print("Stars never decrease as safety rises, for all three personalities")


## The upgrade popup rates ONE link, on a different scale that was already tuned
## to spread across the stars (Player.LINK_PREVIEW_STRESS_SCALE). Normalising it
## the way a route is normalised would undo that, so it must stay as it was.
func _link_scale_untouched() -> void:
	for pair: Array in [[0.0, 0], [50.0, 3], [100.0, 5]]:
		var got := SafetyDisplay.link_stars(float(pair[0]))
		if got != int(pair[1]):
			_fail("link preview: %.0f reads %d stars, expected %d"
					% [pair[0], got, int(pair[1])])
	print("Single-link preview still uses the plain 0-100 mapping")


## The number behind the debug toggle has to remain the value in the logs. A
## testing aid showing a different number from rounds.csv would be worse than
## having none at all.
func _debug_shows_the_raw_score() -> void:
	SafetyDisplay.debug_mode = true
	var text := SafetyDisplay.format_route_bb(54.0, PersonalityConfig.ALPHA_AVERAGE)
	SafetyDisplay.debug_mode = false
	if not text.ends_with(" (54)"):
		_fail("debug readout shows '%s', not the raw score 54" % text)
	else:
		print("Debug readout still reports the raw logged score, not the position")


## The case the change exists for: take a real commute off the real network and
## protect it one link at a time, the way a participant spends a budget.
func _a_real_commute_moves() -> void:
	var network := CityNetwork.new(0)
	var pair: Array = CityNetwork.HOME_WORK_PAIRS[0]
	var alpha := PersonalityConfig.ALPHA_AVERAGE
	var route: Dictionary = network.find_route(pair[0], pair[1], alpha)
	var links: Array = Player.route_link_ids(route)
	if links.is_empty():
		_fail("could not build a commute to test against")
		return

	var seen: Dictionary = {}
	var steps: Array = []
	for _step in range(links.size() + 1):
		# Re-solve each time: protecting a link can move the rider onto a
		# different road, which is the whole point of the model and would make a
		# fixed link list wrong after the first purchase.
		var current: Dictionary = network.find_route(pair[0], pair[1], alpha)
		var score: float = Player.route_safety(current, network, alpha)
		var stars: int = SafetyDisplay.route_stars(score, alpha)
		seen[stars] = true
		steps.append("%d" % stars)
		var remaining: Array = Player.route_link_ids(current)
		var upgraded := false
		for link_id: String in remaining:
			var link: CityNetwork.Link = network.links.get(link_id)
			if link != null and link.upgrade_level < 2:
				network.upgrade_link(link_id, 2)
				upgraded = true
				break
		if not upgraded:
			break

	print("Protecting one link at a time along a real commute: %s stars"
			% " -> ".join(PackedStringArray(steps)))
	# A whole commute bought out is far more than a budget allows, so this is the
	# generous end of the range and the bar is set accordingly. The realistic case
	# is _a_small_spend_moves() below.
	if seen.size() < 3:
		_fail("a whole commute produced only %d distinct star readings" % seen.size())


## The case that actually failed in the field, replayed from the numbers a real
## session recorded: an average rider whose safety crept 50.0 -> 51.7 -> 57.2
## over three rounds and who was shown three stars out of five at every step.
func _a_small_spend_moves() -> void:
	var alpha := PersonalityConfig.ALPHA_AVERAGE
	var recorded: Array[float] = [50.0, 51.7, 57.2]
	var stars: Array = []
	for score: float in recorded:
		stars.append(SafetyDisplay.route_stars(score, alpha))
	print("A real session's three rounds (50.0, 51.7, 57.2) now read %s stars"
			% " -> ".join(PackedStringArray(stars.map(func(v): return str(v)))))
	if stars[0] != 0:
		_fail("a commute with nothing bought on it reads %d stars, not empty" % stars[0])
	if stars[0] == stars[2]:
		_fail("three rounds of investment still produce no visible change")


## The map's stress colour, car count and car speed must describe the road the
## MODEL has, for the rider actually playing.
##
## LinkSegment used to carry its own `beta_est = [1.0, 0.65, 0.3]` for this, a
## relief no rider ever gets. Checked here across every link and every
## personality, because the error changed sign with personality: it understated
## what a cautious rider had bought and overstated what a confident one had.
func _map_stress_matches_the_model() -> void:
	var network := CityNetwork.new(0)
	var scene: PackedScene = load("res://scenes/components/LinkSegment.tscn")
	var seg: LinkSegment = scene.instantiate()
	add_child(seg)

	var old_table: Array = [1.0, 0.65, 0.3]
	var worst := 0.0
	var worst_where := ""
	var old_worst := 0.0
	var checked := 0
	for alpha: float in [PersonalityConfig.ALPHA_CAUTIOUS,
			PersonalityConfig.ALPHA_AVERAGE, PersonalityConfig.ALPHA_CONFIDENT]:
		for link_id: String in network.links:
			var link: CityNetwork.Link = network.links[link_id]
			for level in range(3):
				# Drive the real segment the map draws with, not a copy of the
				# formula: the point is that the DISPLAY reads the model.
				seg.setup(link_id, PackedVector2Array([Vector2.ZERO, Vector2(100, 0)]),
						level, link.stress_score, alpha)
				var shown: float = seg._effective_stress()
				link.upgrade_level = level
				var model: float = link.stress_score * link.effective_beta(alpha)
				link.upgrade_level = link.initial_upgrade_level
				checked += 1
				if absf(model - shown) > worst:
					worst = absf(model - shown)
					worst_where = "%s level %d alpha %.1f (map %.3f, model %.3f)" % [
							link_id, level, alpha, shown, model]
				old_worst = maxf(old_worst,
						absf(model - link.stress_score * float(old_table[level])))
	seg.queue_free()

	if worst > 0.0001:
		_fail("map and model disagree by %.4f at %s" % [worst, worst_where])
	else:
		print("LinkSegment stress equals model stress across %d link/level/personality cases"
				% checked)
		print("  (the fixed table it used to carry was off by up to %.2f effective stress)"
				% old_worst)


## Routing must be untouched by the above: beta_for() was extracted from
## Link.effective_beta(), so the two have to return identical values or every
## route in the game has quietly changed.
func _routing_is_unchanged() -> void:
	var network := CityNetwork.new(0)
	var checked := 0
	for alpha: float in [PersonalityConfig.ALPHA_CAUTIOUS,
			PersonalityConfig.ALPHA_AVERAGE, PersonalityConfig.ALPHA_CONFIDENT]:
		for link_id: String in network.links:
			var link: CityNetwork.Link = network.links[link_id]
			for level in range(3):
				link.upgrade_level = level
				if not is_equal_approx(link.effective_beta(alpha),
						CityNetwork.beta_for(level, link.stress_score, alpha)):
					_fail("Link.effective_beta disagrees with beta_for on %s" % link_id)
					return
				checked += 1
			link.upgrade_level = link.initial_upgrade_level
	print("Link.effective_beta matches beta_for on all %d combinations" % checked)
