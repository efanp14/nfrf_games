extends Node
## Checks every screen still fits at every interface size the menu offers
## (DisplaySettings), on a laptop-shaped and a tablet-shaped screen.
##
##   godot --headless --path . res://tools/probe_interface_scale.tscn
##
## Raising the content scale shrinks the design area each screen is laid out
## in: at 145% a 1080p laptop leaves 745 design pixels of height. A screen that
## fitted at 100% can lose its only button off the bottom at that size, and the
## failure is silent, as the round summary showed once already. So for each size
## this measures the button that moves the session on, and for the surveys,
## which scroll vertically by design, that the panel is not wider than the
## screen.

## Design-pixel window sizes under test. The project stretches with an expand
## aspect, so a 16:10 tablet lays out at 1920x1200 rather than 1920x1080.
const SCREENS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1920, 1200)]

var _failures: int = 0
var _area: Vector2


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL  %s" % what)


func _ready() -> void:
	for screen in SCREENS:
		for s in DisplaySettings.SCALES:
			get_window().size = screen
			get_window().content_scale_factor = s
			for _f in range(4):
				await get_tree().process_frame
			_area = get_viewport().get_visible_rect().size
			print("%dx%d at %d%%: %.0fx%.0f design px"
					% [screen.x, screen.y, int(round(s * 100.0)), _area.x, _area.y])
			await _check_menu()
			await _check_intro()
			await _check_round_summary()
			await _check_end_screen()
			await _check_survey("res://scenes/ui/PreSurvey.tscn")
			await _check_survey("res://scenes/ui/PostSurvey.tscn")

	get_window().content_scale_factor = 1.0
	print("")
	print("FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _settle() -> void:
	for _f in range(3):
		await get_tree().process_frame


## Whole control inside the visible area.
func _inside(what: String, c: Control) -> void:
	var r := Rect2(c.global_position, c.size)
	if r.position.x < -0.5 or r.position.y < -0.5 \
			or r.end.x > _area.x + 0.5 or r.end.y > _area.y + 0.5:
		_fail("%s at %s, outside the %.0fx%.0f visible area" % [what, r, _area.x, _area.y])


## The heaviest menu: the group treatment with the most seats it allows.
func _check_menu() -> void:
	var menu: MainMenu = load("res://scenes/ui/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu.treatment_option.select(2)
	menu._on_treatment_changed(2)
	menu._player_count_spin.value = menu._player_count_spin.max_value
	await _settle()
	# The menu scrolls once it is taller than the screen, so a button is
	# reachable if scrolling brings it fully into view.
	var scroll: ScrollContainer = menu.get_node("ScrollContainer")
	for button: Button in [menu.start_button, menu.quit_button]:
		scroll.ensure_control_visible(button)
		await _settle()
		_inside("menu %s button (T3, %d seats)" % [button.text,
				int(menu._player_count_spin.value)], button)
	menu.queue_free()
	await get_tree().process_frame


## Every page, since the lane page carries diagrams and is the tallest.
func _check_intro() -> void:
	var intro: NarrativeIntro = load("res://scenes/ui/NarrativeIntro.tscn").instantiate()
	add_child(intro)
	await get_tree().process_frame
	intro.show_narrative(int(GameManager.Treatment.GROUP_DISCUSSION))
	for page in range(intro.PAGE_ORDER.size()):
		intro._page = page
		intro._show_page()
		await _settle()
		_inside("intro page %d Continue button" % (page + 1), intro.continue_button)
	intro.queue_free()
	await get_tree().process_frame


func _check_round_summary() -> void:
	var rs: RoundSummary = load("res://scenes/ui/RoundSummary.tscn").instantiate()
	add_child(rs)
	await get_tree().process_frame
	var rows: Array = []
	for i in range(3):
		rows.append({"time": 28.6 + i, "safety": 54.0 + i, "time_delta": 0.2,
				"alpha": PersonalityConfig.ALPHA_AVERAGE, "route_changed": i == 0})
	rs.show_results({
		"round": 2, "alpha": PersonalityConfig.ALPHA_AVERAGE, "players": rows,
		"personal_time": 28.6, "time_delta": 0.2, "personal_safety": 54.0,
		"route_changed": true,
		"city_avg_time": 25.3, "city_avg_safety": 52.0, "city_coverage": 12.0,
		"city_avg_time_baseline": 25.7, "city_avg_safety_baseline": 51.0,
		"city_coverage_baseline": 11.0,
		"residents_total": 99, "residents_time_improved": 20,
		"residents_time_improved_pct": 20.0, "residents_time_improvement_mean": 2.0,
		"residents_safety_improved_pct": 16.0,
	}, int(GameManager.Treatment.GROUP_DISCUSSION), false)
	await _settle()
	_inside("round summary Next Round button (T3, 3 seats)", rs.next_button)
	_inside("round summary panel", rs.get_node("SidePanel"))
	rs.queue_free()
	await get_tree().process_frame


func _check_end_screen() -> void:
	var es: EndScreen = load("res://scenes/ui/EndScreen.tscn").instantiate()
	add_child(es)
	await get_tree().process_frame
	var rows: Array = []
	for i in range(3):
		rows.append({"final_time": 28.6 + i, "total_time_saved": 1.2,
				"final_safety": 54.0, "alpha": PersonalityConfig.ALPHA_AVERAGE})
	es.show_results({
		"players": rows, "city_coverage": 12.0, "final_time": 28.6,
		"baseline_time": 29.8, "total_time_saved": 1.2, "final_safety": 54.0,
		"alpha": PersonalityConfig.ALPHA_AVERAGE,
	})
	await _settle()
	_inside("end screen Finish button", es.finish_button)
	es.queue_free()
	await get_tree().process_frame


## Surveys scroll vertically, so only the width can push anything off screen.
func _check_survey(path: String) -> void:
	var survey: CanvasLayer = load(path).instantiate()
	add_child(survey)
	await get_tree().process_frame
	if survey is PreSurvey:
		(survey as PreSurvey).show_for_player(2, 3, "PCYXA6")
	else:
		(survey as PostSurvey).show_survey(int(GameManager.Treatment.GROUP_DISCUSSION), 2, 3, "PCYXA6")
	await _settle()
	var panel: Control = survey.get_node("ScrollContainer/OuterMargin/Centerer/PanelContainer")
	if panel.size.x > _area.x + 0.5:
		_fail("%s panel is %.0f wide, wider than the %.0f visible"
				% [path.get_file(), panel.size.x, _area.x])
	survey.queue_free()
	await get_tree().process_frame
