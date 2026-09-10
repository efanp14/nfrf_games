extends Node
## Checks the pieces of the HUD that only exist at runtime: the round banner, the
## first-round hint, the selected-road highlight, and whether anything drawn over
## the map can actually be read.
##
##   godot --headless res://tools/probe_hud.tscn
##
## The legibility check exists because the hint shipped invisible. It was a bare
## Label sitting straight on the map, so it inherited the theme's cream body
## colour (#F2EFEA) while the map's background is #F6F1E6 beige. Those are within
## a couple of percent of each other. Nothing errors, nothing looks wrong in the
## scene tree, and the text simply is not there -- which is the worst kind of
## defect for a control whose whole job is to tell a participant what to do.

## WCAG AA for large text. The overlays here are 20px and up, so this is the
## right bar; body text would want 4.5.
const MIN_CONTRAST: float = 3.0

var _failures: int = 0


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL  %s" % what)


func _ready() -> void:
	var hud: GameHUD = load("res://scenes/ui/GameHUD.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame

	await _banner_and_hint(hud)
	_overlays_do_not_eat_input(hud)
	_overlays_are_legible(hud)
	await _selection(hud)

	print("")
	print("FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _banner_and_hint(hud: GameHUD) -> void:
	if hud.round_banner.visible:
		_fail("banner visible before any round started")
	if hud.hint_panel.visible:
		_fail("hint visible before any round started")

	GameManager.start_game([PersonalityConfig.ALPHA_AVERAGE], GameManager.Treatment.INDIVIDUAL)
	await get_tree().process_frame
	if not hud.round_banner.visible:
		_fail("banner did not appear on round 1")
	if hud.banner_label.text != "Round 1 of 3":
		_fail("banner says '%s'" % hud.banner_label.text)
	if not hud.hint_panel.visible:
		_fail("hint did not appear on round 1")
	print("Round 1: banner '%s' shown, hint shown" % hud.banner_label.text)

	hud.dismiss_hint()
	if hud.hint_panel.visible:
		_fail("hint survived dismiss_hint()")
	else:
		print("Hint clears when a road is opened")

	# By the second round a participant has done this once, and a standing
	# instruction becomes furniture.
	hud._on_round_started(2, 1300000)
	await get_tree().process_frame
	if hud.hint_panel.visible:
		_fail("hint came back in round 2")
	elif hud.banner_label.text != "Round 2 of 3":
		_fail("round 2 banner says '%s'" % hud.banner_label.text)
	else:
		print("Round 2: banner '%s', hint stays away" % hud.banner_label.text)

	# It has to get out of the way on its own, or it covers the map all round.
	await get_tree().create_timer(GameHUD.BANNER_HOLD_S + GameHUD.BANNER_FADE_S + 0.6).timeout
	if hud.round_banner.visible:
		_fail("banner never faded away")
	else:
		print("Banner faded away on its own")


## HUDRoot floats over the board and the roads read _unhandled_input, so a
## Control here that accepted events would swallow taps on the streets beneath.
func _overlays_do_not_eat_input(hud: GameHUD) -> void:
	var bad: Array[String] = []
	for node: Node in [hud.hint_panel, hud.hint_label, hud.round_banner, hud.banner_label]:
		var ctl := node as Control
		if ctl != null and ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			bad.append(ctl.name)
	if bad.is_empty():
		print("Neither overlay intercepts input meant for the roads")
	else:
		_fail("these would swallow clicks on the map: %s" % ", ".join(bad))


## Relative luminance per WCAG, so "can this be read" is a number rather than an
## opinion.
static func _luminance(c: Color) -> float:
	var parts: Array = [c.r, c.g, c.b]
	var out: Array = []
	for v: float in parts:
		out.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2]


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## What is actually behind a label: its nearest PanelContainer's own fill, or the
## map itself if it has none. That distinction is the bug -- a label with no card
## under it is sitting on Palette.MAP_BACKGROUND whatever the theme says its
## colour is.
func _surface_behind(label: Label) -> Color:
	var node: Node = label.get_parent()
	while node != null:
		var panel := node as PanelContainer
		if panel != null:
			var style := panel.get_theme_stylebox("panel")
			var flat := style as StyleBoxFlat
			if flat != null:
				return flat.bg_color
		node = node.get_parent()
	return Palette.MAP_BACKGROUND


func _overlays_are_legible(hud: GameHUD) -> void:
	for label: Label in [hud.hint_label, hud.banner_label]:
		var fg: Color = label.get_theme_color("font_color")
		var bg: Color = _surface_behind(label)
		var ratio: float = _contrast(fg, bg)
		if ratio < MIN_CONTRAST:
			_fail("%s is %s on %s, contrast %.2f:1 (needs %.1f) -- effectively invisible"
					% [label.name, fg.to_html(false), bg.to_html(false), ratio, MIN_CONTRAST])
		else:
			print("%-12s %s on %s, contrast %.1f:1"
					% [label.name, fg.to_html(false), bg.to_html(false), ratio])


func _selection(hud: GameHUD) -> void:
	var grid: CityGrid = load("res://scenes/CityGrid.tscn").instantiate()
	add_child(grid)
	await get_tree().process_frame
	# _build() normally runs off round_started, which fired before this node
	# existed, so drive it directly.
	grid._build()
	await get_tree().process_frame
	if grid._segments.is_empty():
		_fail("the map built no road segments")
		return

	var any_id := ""
	for k: String in GameManager.network.links:
		any_id = k
		break
	grid.set_selected_link(any_id)
	if _count_selected(grid) != 1:
		_fail("%d segments selected, expected exactly 1" % _count_selected(grid))
	else:
		print("Selecting a road marks exactly one of %d segments" % grid._segments.size())
	grid.set_selected_link("")
	if _count_selected(grid) != 0:
		_fail("%d segments still selected after clearing" % _count_selected(grid))
	else:
		print("Clearing the selection unmarks it")


func _count_selected(grid: CityGrid) -> int:
	var n := 0
	for seg: LinkSegment in grid._segments.values():
		if seg._selected:
			n += 1
	return n
