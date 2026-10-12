extends Node
## Checks the person icons for "residents with safer travel": the rounding, that
## the picture matches its caption, that the log records the caption the screen
## shows, and that both screens carrying them fit at every interface size.
##
##   godot --headless --path . res://tools/probe_resident_icons.tscn

var _failures: int = 0


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL  %s" % what)


func _ready() -> void:
	_rounding()
	await _picture_matches_caption()
	_log_matches_screen()
	await _fits_at_every_size()
	print("")
	print("FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _m(pct: float) -> Dictionary:
	return {"residents_total": 99, "residents_safety_improved_pct": pct,
			"residents_time_improved_pct": 15.2, "residents_time_improved": 15,
			"residents_time_improvement_mean": 2.47}


## Nearest tenth, except that any gain shows at least half a figure and anything
## short of everyone stops at nine halves.
func _rounding() -> void:
	var cases := {0.0: 0, 1.0: 1, 4.0: 1, 5.0: 1, 15.0: 2, 27.3: 3, 34.9: 3,
			35.0: 4, 50.0: 5, 87.0: 9, 94.9: 9, 96.0: 9, 99.9: 9, 100.0: 10}
	for pct in cases:
		var got := CityFeedback.safety_icon_halves(_m(pct))
		if got != cases[pct]:
			_fail("%.1f%% fills %d halves, expected %d" % [pct, got, cases[pct]])
	print("Rounding checked on %d cases" % cases.size())


func _picture_matches_caption() -> void:
	var icons := ResidentIcons.new()
	add_child(icons)
	await get_tree().process_frame
	for pct in [0.0, 4.0, 27.3, 50.0, 87.0, 100.0]:
		icons.show_metrics(_m(pct))
		var halves := icons.filled_halves()
		var caption: String = icons._caption.text
		var expected := CityFeedback.safety_caption(_m(pct))
		if caption != expected:
			_fail("%.1f%%: caption '%s', expected '%s'" % [pct, caption, expected])
		if halves != CityFeedback.safety_icon_halves(_m(pct)):
			_fail("%.1f%%: %d halves drawn" % [pct, halves])
		if halves > 0 and halves < 10 and not caption.contains("%d in 10" % halves):
			_fail("%.1f%%: %d halves drawn but caption says '%s'" % [pct, halves, caption])
	icons.show_metrics({})
	if icons.visible:
		_fail("icons visible with no result yet")
	icons.queue_free()
	print("Picture and caption agree")


## The log's record of what was read must contain exactly the screen's lines.
func _log_matches_screen() -> void:
	var m := _m(27.3)
	var logged := CityFeedback.benefit_lines(m)
	var shown := CityFeedback.time_benefit_lines(m)
	shown.append(CityFeedback.safety_caption(m))
	if logged != shown:
		_fail("log records %s but the screen shows %s" % [logged, shown])
	for line in logged:
		if line.contains("saw safer travel"):
			_fail("log still records the old percentage line: %s" % line)
	print("Log records: %s" % " | ".join(logged))


func _fits_at_every_size() -> void:
	var a := PersonalityConfig.ALPHA_AVERAGE
	var hud: GameHUD = load("res://scenes/ui/GameHUD.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	GameManager.start_game([a, a, a], GameManager.Treatment.GROUP_DISCUSSION)
	var metrics := _m(27.3)
	metrics.merge({"avg_time": 25.3, "avg_safety": 52.0, "coverage": 12.0})
	hud._on_city_metrics_updated(metrics)

	for s in DisplaySettings.SCALES:
		get_window().size = Vector2i(1920, 1080)
		get_window().content_scale_factor = s
		for _f in range(4):
			await get_tree().process_frame
		var area := get_viewport().get_visible_rect().size
		var card: Control = hud.get_node("HUDRoot/CityPanel")
		var r := Rect2(card.global_position, card.size)
		if r.end.x > area.x + 0.5 or r.end.y > area.y + 0.5 or r.position.x < 0.0:
			_fail("%d%%: city card with icons at %s, outside %s" % [int(s * 100), r, area])
		if not hud._resident_icons().visible:
			_fail("%d%%: icons hidden on the city card" % int(s * 100))

		var rs: RoundSummary = load("res://scenes/ui/RoundSummary.tscn").instantiate()
		add_child(rs)
		await get_tree().process_frame
		var res := metrics.duplicate()
		res.merge({"round": 2, "alpha": a, "players": [
				{"time": 28.6, "safety": 54.0, "time_delta": 0.0, "alpha": a},
				{"time": 29.6, "safety": 55.0, "time_delta": 0.0, "alpha": a},
				{"time": 30.6, "safety": 56.0, "time_delta": 0.0, "alpha": a}],
				"city_avg_time": 25.3, "city_avg_safety": 52.0, "city_coverage": 12.0,
				"city_avg_time_baseline": 25.7, "city_avg_safety_baseline": 51.0,
				"city_coverage_baseline": 11.0})
		rs.show_results(res, int(GameManager.Treatment.GROUP_DISCUSSION), false)
		var demanded: float = rs.get_node("SidePanel").get_combined_minimum_size().y
		for _f in range(3):
			await get_tree().process_frame
		var bottom: float = rs.next_button.global_position.y + rs.next_button.size.y
		if bottom > area.y:
			_fail("%d%%: round summary Next Round ends at y=%.0f of %.0f (first frame wanted %.0f)"
					% [int(s * 100), bottom, area.y, demanded])
		else:
			print("%d%%: round summary first-frame demand %.0fpx of %.0f, Next Round ends at y=%.0f"
					% [int(s * 100), demanded, area.y, bottom])
		rs.queue_free()
		await get_tree().process_frame
	get_window().content_scale_factor = 1.0
