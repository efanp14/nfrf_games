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
var _hud: GameHUD


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL  %s" % what)


func _ready() -> void:
	# The heaviest HUD: three seats, each with its own row on the status card.
	_hud = load("res://scenes/ui/GameHUD.tscn").instantiate()
	add_child(_hud)
	await get_tree().process_frame
	var alpha := PersonalityConfig.ALPHA_AVERAGE
	GameManager.start_game([alpha, alpha, alpha], GameManager.Treatment.GROUP_DISCUSSION)
	await _settle()

	for screen in SCREENS:
		for s in DisplaySettings.SCALES:
			get_window().size = screen
			get_window().content_scale_factor = s
			for _f in range(4):
				await get_tree().process_frame
			_area = get_viewport().get_visible_rect().size
			print("%dx%d at %d%%: %.0fx%.0f design px"
					% [screen.x, screen.y, int(round(s * 100.0)), _area.x, _area.y])
			# Each check returns true as its last act. A script error inside one
			# aborts it, and the await then yields null rather than stopping the
			# probe, so without this an error would read as a pass.
			if not await _check_hud(): _fail("HUD check did not finish")
			if not await _check_upgrade_popup(): _fail("upgrade popup check did not finish")
			if not await _check_menu(): _fail("menu check did not finish")
			if not await _check_intro(): _fail("intro check did not finish")
			if not await _check_round_summary(): _fail("round summary check did not finish")
			if not await _check_end_screen(): _fail("end screen check did not finish")
			for path in ["res://scenes/ui/PreSurvey.tscn", "res://scenes/ui/PostSurvey.tscn"]:
				if not await _check_survey(path): _fail("%s check did not finish" % path.get_file())

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


## The HUD floats in the corners, so the risk is corners meeting: the left
## column (status card, rail, and the legend when open) growing down into the
## researcher rail at the bottom left, or the city card meeting the status card.
func _check_hud() -> bool:
	var left: Control = _hud.get_node("HUDRoot/LeftColumn")
	var bottom_rail: Control = _hud.get_node("HUDRoot/BottomLeftRail")
	var city: Control = _hud.get_node("HUDRoot/CityPanel")
	for legend_open in [false, true]:
		if _hud.legend_popover.visible != legend_open:
			_hud._on_legend_pressed()
		await _settle()
		var tag := "legend open" if legend_open else "legend closed"
		# Piece by piece rather than the column's bounding box: the legend opens
		# to the right of the rail buttons, so the box spans empty space above
		# the researcher rail that nothing is drawn in.
		var b := Rect2(bottom_rail.global_position, bottom_rail.size)
		var c := Rect2(city.global_position, city.size)
		var pieces: Array = [_hud.get_node_or_null("HUDRoot/LeftColumn/StatusCard"),
				_hud.get_node_or_null("HUDRoot/LeftColumn/RailRow/ControlRail")]
		if legend_open:
			pieces.append(_hud.legend_popover)
		# Checked one by one: Array.has(null) does not match a null Object.
		for piece in pieces:
			if piece == null:
				_fail("HUD layout changed: StatusCard or RailRow/ControlRail not found")
				return true
		for piece: Control in pieces:
			var r := Rect2(piece.global_position, piece.size)
			if r.intersects(b):
				_fail("HUD (%s): %s ends at y=%.0f, researcher rail starts at y=%.0f"
						% [tag, piece.name, r.end.y, b.position.y])
			if city.visible and r.intersects(c):
				_fail("HUD (%s): %s overlaps the city card" % [tag, piece.name])
		_inside("HUD left column (%s)" % tag, left)
		_inside("HUD researcher rail", bottom_rail)
		_inside("HUD End Round button", _hud.end_round_button)
		if city.visible:
			_inside("HUD city card", city)
	if _hud.legend_popover.visible:
		_hud._on_legend_pressed()

	# The in-game size card: on screen, clear of the bottom-left rail, the one
	# size in use marked, and never open at the same time as the legend.
	_inside("HUD settings gear", _hud.settings_button)
	_hud._on_legend_pressed()
	_hud._on_settings_pressed()
	await _settle()
	if _hud.legend_popover.visible:
		_fail("legend still open after opening the size card")
	var card := Rect2(_hud.settings_popover.global_position, _hud.settings_popover.size)
	_inside("HUD size card", _hud.settings_popover)
	if card.intersects(Rect2(bottom_rail.global_position, bottom_rail.size)):
		_fail("HUD size card overlaps the bottom-left rail")
	var marked := 0
	for b in _hud._size_buttons:
		if b.theme_type_variation == &"PillButtonActive":
			marked += 1
	if marked != 1:
		_fail("size card marks %d sizes as in use, expected 1" % marked)
	_hud._on_legend_pressed()
	await _settle()
	if _hud.settings_popover.visible:
		_fail("size card still open after opening the legend")
	_hud._on_legend_pressed()
	return true


func _check_upgrade_popup() -> bool:
	var popup: UpgradePopup = load("res://scenes/ui/UpgradePopup.tscn").instantiate()
	add_child(popup)
	await get_tree().process_frame
	var link_id: String = GameManager.network.links.keys()[0]
	popup.show_for_link(link_id, Player.DEFAULT_BUDGET_PER_ROUND, PersonalityConfig.ALPHA_AVERAGE, 1)
	await _settle()
	for button: Button in [popup.painted_button, popup.protected_button, popup.cancel_button]:
		_inside("upgrade popup '%s'" % button.text.get_slice("  ", 0), button)
	popup.queue_free()
	await get_tree().process_frame
	return true


## The heaviest menu: the group treatment with the most seats it allows.
func _check_menu() -> bool:
	var menu: MainMenu = load("res://scenes/ui/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu.treatment_option.select(2)
	menu._on_treatment_changed(2)
	menu._player_count_spin.value = menu._player_count_spin.max_value
	await _settle()
	# Moving the menu into a ScrollContainer must not have uncentred it.
	# Measured against the space beside the scrollbar, which takes a few pixels
	# of width at the sizes where the menu scrolls.
	var panel: Control = menu.get_node("ScrollContainer/CenterContainer/PopupPanel")
	var holder: Control = menu.get_node("ScrollContainer/CenterContainer")
	var centre_x: float = panel.global_position.x + panel.size.x / 2.0
	var space_centre_x: float = holder.global_position.x + holder.size.x / 2.0
	if holder.size.x < _area.x - 20.0 or absf(centre_x - space_centre_x) > 1.0:
		_fail("menu panel centred at x=%.0f in a %.0f-wide space, screen is %.0f wide"
				% [centre_x, holder.size.x, _area.x])
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
	return true


## Every page, since the lane page carries diagrams and is the tallest.
func _check_intro() -> bool:
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
	return true


func _check_round_summary() -> bool:
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
	return true


func _check_end_screen() -> bool:
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
	return true


## Surveys scroll vertically, so only the width can push anything off screen.
func _check_survey(path: String) -> bool:
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
	return true
