extends Node
## Checks that the end-of-round and end-of-game panels fit on the screen, and in
## particular that the button which advances the session is reachable.
##
##   godot --headless res://tools/probe_round_summary.tscn
##
## THE BUG THIS EXISTS FOR. A group session could not leave round 2: the round
## summary appeared with its "Next Round" button missing, and there was no other
## way forward. The cause was `fit_content` on a RichTextLabel and `autowrap` on
## a Label, both of which make a control's minimum HEIGHT a function of a width
## the container has not settled yet. On the frame the panel is shown that width
## is about zero, so a wrapping label asks for hundreds of pixels: three player
## rows claimed 1,664px between them and the city block 1,817px, sizing the panel
## 2,967px tall on a 1,080px screen. Everything below went off the bottom.
##
## It recovered on a later layout pass in some situations and not others, which
## is why it read as intermittent and why nobody could say what triggered it.
##
## The fix is that no control's minimum height may depend on a width nobody has
## decided: rows that do not need to wrap have wrapping turned off, and rows that
## do have an explicit minimum width. This probe measures the panel on the FIRST
## frame, before any settling, because that is the frame a participant sees.

## Measured against the project's own base resolution, which is the size the UI is
## always laid out at: stretch mode is canvas_items with an expand aspect, so the
## LOGICAL viewport stays at this base whatever the physical screen is, and the
## whole interface is scaled to fit. Testing invented window sizes would test the
## scaler rather than the layout.
##
## How much of that height the panel may demand before this is called a failure.
## Not 100%: a panel that exactly fills the screen has no room for the next label
## anyone adds, and the failure mode is silent (a button off the bottom, no error
## anywhere), so it is worth failing early.
const MAX_HEIGHT_SHARE: float = 0.85

var _failures: int = 0


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL  %s" % what)


func _ready() -> void:
	get_window().size = Vector2i(
			int(ProjectSettings.get_setting("display/window/size/viewport_width")),
			int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	# Several frames, because the resize has to reach the CanvasLayers before any
	# of their children can be measured against it.
	for _f in range(4):
		await get_tree().process_frame
	var actual: Vector2 = get_viewport().get_visible_rect().size
	var size := Vector2i(actual)
	print("Viewport under test: %dx%d" % [size.x, size.y])
	# One player and three: the group treatment builds its rows in code, which is
	# where the bug was, but the single-player branch has its own set of labels.
	for players in [1, 3]:
		await _check_round_summary(size, players)
	await _check_end_screen(size, 3)

	print("")
	print("FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _results(players: int) -> Dictionary:
	var rows: Array = []
	for i in range(players):
		rows.append({
			"time": 28.6 + i, "safety": 54.0 + i, "time_delta": 0.2,
			"alpha": PersonalityConfig.ALPHA_AVERAGE, "route_changed": i == 0,
		})
	return {
		"round": 2, "alpha": PersonalityConfig.ALPHA_AVERAGE,
		"players": rows,
		"personal_time": 28.6, "time_delta": 0.2, "personal_safety": 54.0,
		"route_changed": true,
		"city_avg_time": 25.3, "city_avg_safety": 52.0, "city_coverage": 12.0,
		"city_avg_time_baseline": 25.7, "city_avg_safety_baseline": 51.0,
		"city_coverage_baseline": 11.0,
		"residents_total": 99, "residents_time_improved": 20,
		"residents_time_improved_pct": 20.0, "residents_time_improvement_mean": 2.0,
		"residents_safety_improved_pct": 16.0,
	}


## The round summary, measured on the frame it is shown rather than after it has
## had a chance to correct itself.
func _check_round_summary(screen: Vector2i, players: int) -> void:
	var rs: RoundSummary = load("res://scenes/ui/RoundSummary.tscn").instantiate()
	add_child(rs)
	await get_tree().process_frame

	# The city block is the taller half and is only shown outside T1, so the
	# group treatment is the case that has to fit.
	rs.show_results(_results(players), int(GameManager.Treatment.GROUP_DISCUSSION), false)

	var panel: Control = rs.get_node("SidePanel")
	var label := "%dx%d, %d player(s)" % [screen.x, screen.y, players]

	# THE FRAME THAT BROKE. Positions are all still at the origin here, so the
	# meaningful quantity is the minimum size: a panel that demands more height
	# than the screen has is one whose bottom controls are already unreachable.
	var demanded: float = panel.get_combined_minimum_size().y
	var allowed: float = float(screen.y) * MAX_HEIGHT_SHARE
	if demanded > allowed:
		_fail("%s: on its first frame the panel demands %.0fpx of height, over the %.0fpx allowed on a %dpx screen"
				% [label, demanded, allowed, screen.y])

	# And then where things actually land, once layout has settled.
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = rs.next_button
	var bottom: float = button.global_position.y + button.size.y
	var right: float = panel.global_position.x + panel.size.x

	if bottom > float(screen.y):
		_fail("%s: Next Round runs %.0fpx below the bottom of the screen"
				% [label, bottom - float(screen.y)])
	elif panel.global_position.x < 0.0:
		_fail("%s: the panel starts %.0fpx off the left of the screen"
				% [label, -panel.global_position.x])
	elif right > float(screen.x) + 1.0:
		_fail("%s: the panel runs %.0fpx off the right of the screen"
				% [label, right - float(screen.x)])
	else:
		print("%-24s panel %.0fx%.0f at x=%.0f, first-frame demand %.0fpx, Next Round ends at y=%.0f of %d"
				% [label, panel.size.x, panel.size.y, panel.global_position.x,
				demanded, bottom, screen.y])
	rs.queue_free()
	await get_tree().process_frame


## The closing screen has the same shape of risk: its rows are built in code and
## its Finish button is the only way to the closing survey.
func _check_end_screen(screen: Vector2i, players: int) -> void:
	var es: EndScreen = load("res://scenes/ui/EndScreen.tscn").instantiate()
	add_child(es)
	await get_tree().process_frame

	var rows: Array = []
	for i in range(players):
		rows.append({
			"final_time": 28.6 + i, "total_time_saved": 1.2, "final_safety": 54.0,
			"alpha": PersonalityConfig.ALPHA_AVERAGE,
		})
	es.show_results({
		"players": rows, "city_coverage": 12.0, "final_time": 28.6,
		"baseline_time": 29.8, "total_time_saved": 1.2, "final_safety": 54.0,
		"alpha": PersonalityConfig.ALPHA_AVERAGE,
	})
	var popup: Control = es.get_node("CenterContainer/PopupPanel")
	var demanded: float = popup.get_combined_minimum_size().y
	if demanded > float(screen.y) * MAX_HEIGHT_SHARE:
		_fail("%dx%d: on its first frame the end screen demands %.0fpx of height"
				% [screen.x, screen.y, demanded])
	await get_tree().process_frame
	await get_tree().process_frame

	var button: Button = es.finish_button
	var bottom: float = button.global_position.y + button.size.y
	var label := "%dx%d, %d player(s)" % [screen.x, screen.y, players]
	if bottom > float(screen.y):
		_fail("%s: Finish runs %.0fpx below the bottom of the screen"
				% [label, bottom - float(screen.y)])
	elif button.global_position.y < 0.0:
		_fail("%s: Finish sits above the top of the screen" % label)
	else:
		print("%-24s end screen Finish ends at y=%.0f of %d" % [label, bottom, screen.y])
	es.queue_free()
	await get_tree().process_frame
