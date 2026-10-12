class_name DisplaySettings
## DisplaySettings.gd
## How large the whole interface is drawn on this device: text, panels, buttons,
## pins, everything. One setting rather than a font size per screen, chosen on
## the main menu and remembered per device.
##
## Why it exists. The project is laid out for a 1920x1080 window and stretched to
## fit (`canvas_items`, `expand`). On a laptop that is the size it was designed
## at. On an 11-inch tablet the same layout lands on a screen about three
## quarters the height, so every piece of text is physically about 70% of what
## it was tuned at. Testing on the tablets reported the surveys and instructions
## as too small, which is that, not those screens being badly sized.
##
## Why the whole interface rather than only the text. Raising font sizes one by
## one touches fifteen-odd places, breaks screens whose columns are sized to
## their text (the survey scale headers), and still leaves the map and the HUD
## small. Scaling the window's content keeps every screen in the proportions it
## was designed and checked at.
##
## Display only: nothing here reaches routing, costs or any metric. The chosen
## value is recorded in parameters.json, since how large the text was is part of
## what the participant saw.

## The sizes offered, as content scale factors. Capped at 1.45 because the round
## summary panel needs about 640 of 1080 design pixels on the frame it appears
## (tools/probe_round_summary.tscn); at 1.45 on a 1080p laptop that is 745
## available, which still fits.
const SCALES: Array[float] = [1.0, 1.15, 1.3, 1.45]
const SCALE_LABELS: Array[String] = ["Standard", "Large", "Larger", "Largest"]

## Remembered per device, beside the machine letter rather than among the
## session folders: a preference of the hardware, not data.
const SETTINGS_PATH: String = "user://display_settings.cfg"

## Physical height of one design pixel on the screen the layout was tuned on, a
## 15.6-inch 1080p laptop: 7.65 inches over 1080 pixels.
const REFERENCE_INCHES_PER_PX: float = 7.65 / 1080.0

## Used on a touch device that does not report a usable DPI. Matches a typical
## 11-inch 16:10 tablet.
const FALLBACK_TOUCH_SCALE: float = 1.3


## The scale in effect: what was chosen on this device, or else a suggestion
## worked out from its screen.
static func current_scale() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved: float = float(cfg.get_value("display", "scale", -1.0))
		if saved > 0.0:
			return _nearest_step(saved)
	return suggested_scale()


static func set_scale(scale: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # Missing is fine; it is created below.
	cfg.set_value("display", "scale", _nearest_step(scale))
	if cfg.save(SETTINGS_PATH) != OK:
		push_warning("DisplaySettings: could not write %s" % SETTINGS_PATH)


## Applies the scale to the root window. Every Control and the map are drawn
## inside it, so this is the only place the scale needs setting.
static func apply(window: Window, scale: float = -1.0) -> void:
	window.content_scale_factor = current_scale() if scale <= 0.0 else _nearest_step(scale)


## A starting size for a device that has never been set. Desktop gets the size
## the layout was designed at. A touch device gets whatever brings a design pixel
## back to its physical size on the reference laptop, from the screen's reported
## DPI, snapped to an offered step. Android's reported DPI can be off by a
## density bucket, which is why the result is only a default and the menu can
## override it.
static func suggested_scale() -> float:
	if not DisplayServer.is_touchscreen_available():
		return SCALES[0]
	var dpi: int = DisplayServer.screen_get_dpi()
	var screen: Vector2i = DisplayServer.screen_get_size()
	if dpi <= 0 or screen.y <= 0:
		return FALLBACK_TOUCH_SCALE
	# Design pixels on screen at scale 1.0, using the stretch rules in
	# project.godot: the design size is fitted inside the screen, and the
	# spare axis is expanded.
	var design := Vector2(
			float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
			float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))
	var fit: float = minf(screen.x / design.x, screen.y / design.y)
	var inches_per_design_px: float = (1.0 / float(dpi)) * fit
	return _nearest_step(REFERENCE_INCHES_PER_PX / inches_per_design_px)


static func label_for(scale: float) -> String:
	return SCALE_LABELS[SCALES.find(_nearest_step(scale))]


static func _nearest_step(scale: float) -> float:
	var best: float = SCALES[0]
	for s in SCALES:
		if absf(s - scale) < absf(best - scale):
			best = s
	return best
