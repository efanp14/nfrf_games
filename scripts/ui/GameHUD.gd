class_name GameHUD
extends CanvasLayer

signal end_round_pressed
## One signal carrying the whole view mode rather than a boolean per button:
## the city-routes heatmap and the stress view both take over the centre line,
## so they are mutually exclusive and a pair of independent booleans could ask
## for both at once. Emits a CityGrid.ViewMode value.
signal view_mode_changed(mode: int)
## Hide or show the simulated residents on the map: their neighbourhood and
## workplace markers, and the bikes they ride at round end. Display only; the
## residents are still simulated, still counted and still logged either way.
signal resident_visuals_toggled(hidden: bool)
## Hide or show the players' own route bands on the map. Display only: the
## routes are still computed, still drive every metric and are still logged.
signal player_routes_toggled(hidden: bool)

@onready var round_label: Label         = %RoundLabel
@onready var budget_label: Label        = %BudgetLabel
@onready var time_label: RichTextLabel  = %TimeLabel
@onready var safety_label: RichTextLabel = %SafetyLabel
@onready var city_panel: PanelContainer  = %CityPanel
@onready var city_time_label: Label     = %CityTimeLabel
@onready var city_safety_label: RichTextLabel = %CitySafetyLabel
@onready var coverage_label: Label      = %CoverageLabel
@onready var benefit_label: Label       = %BenefitLabel
@onready var city_view_button: Button   = %CityViewButton
@onready var stress_view_button: Button = %StressViewButton
@onready var end_round_button: Button   = %EndRoundButton
@onready var debug_button: Button       = %DebugButton
@onready var resident_visuals_button: Button = %ResidentVisualsButton
@onready var player_routes_button: Button = %PlayerRoutesButton
@onready var map_legend: Control        = %MapLegend
@onready var legend_button: Button      = %LegendButton
@onready var legend_popover: PanelContainer = %LegendPopover

## Cached so toggling debug mode can re-render immediately without waiting
## for the next GameManager signal.
var _last_round_results: Dictionary = {}
var _last_city_metrics: Dictionary = {}

## Which map view is active. The city-routes button is T2/T3 only (it lives
## inside CityPanel, hidden in T1); the stress button is available in every
## treatment, since how dangerous a road feels is personal information rather
## than a collective view.
##
## Both buttons drive this one value, so turning either view on turns the other
## off and the labels below can never disagree with what the map is drawing.
var _view_mode: int = CityGrid.ViewMode.PLAYER_ROUTES


func _ready() -> void:
	end_round_button.pressed.connect(func(): end_round_pressed.emit())
	debug_button.pressed.connect(_on_debug_pressed)
	resident_visuals_button.pressed.connect(_on_resident_visuals_pressed)
	_refresh_resident_visuals_button()
	player_routes_button.pressed.connect(_on_player_routes_pressed)
	_refresh_player_routes_button()
	city_view_button.pressed.connect(_on_city_view_pressed)
	stress_view_button.pressed.connect(_on_stress_view_pressed)
	legend_button.pressed.connect(_on_legend_pressed)
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.city_metrics_updated.connect(_on_city_metrics_updated)
	GameManager.game_over.connect(_on_game_over)
	_sync_initial_state()


func _on_city_view_pressed() -> void:
	_set_view_mode(CityGrid.ViewMode.PLAYER_ROUTES
			if _view_mode == CityGrid.ViewMode.NPC_HEATMAP
			else CityGrid.ViewMode.NPC_HEATMAP)


func _on_stress_view_pressed() -> void:
	_set_view_mode(CityGrid.ViewMode.PLAYER_ROUTES
			if _view_mode == CityGrid.ViewMode.STRESS
			else CityGrid.ViewMode.STRESS)


## Each button's label names what pressing it WILL do, so a button reads as an
## action rather than a status. Both are refreshed on every change because
## switching straight from one view to the other has to reset the label on the
## button that was not pressed.
##
## The active view also takes the gold PillButtonActive style. On the old sidebar
## the label was the only signal, and reading two lines of text is a poor way to
## answer "which view am I in"; with the rail floating over the map it has to be
## answerable at a glance.
func _set_view_mode(mode: int) -> void:
	_view_mode = mode
	var heatmap_on: bool = _view_mode == CityGrid.ViewMode.NPC_HEATMAP
	var stress_on: bool  = _view_mode == CityGrid.ViewMode.STRESS
	city_view_button.text = "Back: My Route" if heatmap_on else "City routes"
	stress_view_button.text = "Back: My Route" if stress_on else "Road stress"
	_style_toggle(city_view_button, heatmap_on)
	_style_toggle(stress_view_button, stress_on)
	view_mode_changed.emit(_view_mode)


## A rail button that is currently "on" reads gold; everything else is quiet.
func _style_toggle(button: Button, active: bool) -> void:
	button.theme_type_variation = &"PillButtonActive" if active else &"PillButton"


## The legend is a floating card rather than a permanent column, so it starts
## closed and the map starts clear. The label names the state the way the debug
## and resident buttons do.
func _on_legend_pressed() -> void:
	legend_popover.visible = not legend_popover.visible
	legend_button.text = "Hide legend" if legend_popover.visible else "Legend"
	_style_toggle(legend_button, legend_popover.visible)
	if legend_popover.visible:
		# Rebuilt on open rather than kept live: it is hidden most of the time,
		# and the player count and the resident toggle can both have moved since
		# it was last drawn.
		map_legend.refresh()


func _on_debug_pressed() -> void:
	SafetyDisplay.debug_mode = not SafetyDisplay.debug_mode
	debug_button.text = "Debug: ON" if SafetyDisplay.debug_mode else "Debug: OFF"
	_style_toggle(debug_button, SafetyDisplay.debug_mode)
	if not _last_round_results.is_empty():
		_render_personal(_last_round_results)
	if not _last_city_metrics.is_empty():
		_render_city(_last_city_metrics)


## Sits beside the debug toggle because both are researcher controls rather than
## part of the game, but it is not debug: it changes what a participant sees.
##
## The label names the current state rather than the action, matching the debug
## button beside it. The view buttons above use the opposite convention because
## they switch between named views; here there is one thing with two states.
func _on_resident_visuals_pressed() -> void:
	var hidden := not CityGrid.hide_resident_visuals
	_refresh_resident_visuals_button(hidden)
	# Emit BEFORE refreshing the legend: the flag is only set once main.gd
	# passes this to CityGrid, and the legend reads that flag to decide which
	# rows to draw. Refreshing first would repaint against the old value.
	resident_visuals_toggled.emit(hidden)
	# The legend drops its neighbourhood and workplace rows to match, so it
	# never explains a symbol that is no longer on the map.
	map_legend.refresh()


## A participant control rather than a researcher one, so it sits with the view
## toggles at the top of the rail. Three route bands on one map is a lot of
## colour in the group treatment, and a player who wants to read the road under
## their own route has no other way to see it.
##
## Same label convention as the resident toggle: one thing with two states, so
## the label names the state.
func _on_player_routes_pressed() -> void:
	var hidden := not CityGrid.hide_player_routes
	_refresh_player_routes_button(hidden)
	# Emitted before the legend refresh, as with the resident toggle: the flag
	# is set by CityGrid on the way through, and the legend reads it to decide
	# whether to draw its route rows.
	player_routes_toggled.emit(hidden)
	map_legend.refresh()


func _refresh_player_routes_button(hidden: bool = CityGrid.hide_player_routes) -> void:
	player_routes_button.text = "Routes: Hidden" if hidden else "Routes: Shown"
	_style_toggle(player_routes_button, hidden)


func _refresh_resident_visuals_button(hidden: bool = CityGrid.hide_resident_visuals) -> void:
	resident_visuals_button.text = "Residents: Hidden" if hidden else "Residents: Shown"
	_style_toggle(resident_visuals_button, hidden)


func _sync_initial_state() -> void:
	if not GameManager.game_running:
		return
	round_label.text  = "Round %d / %d" % [GameManager.current_round, GameManager.total_rounds]
	budget_label.text = "Budget: " + Player.format_dollars(GameManager.human_player.credits_per_round)
	_apply_treatment_visibility()


func _on_round_started(round_num: int, budget: int) -> void:
	round_label.text       = "Round %d / %d" % [round_num, GameManager.total_rounds]
	budget_label.text      = "Budget: " + Player.format_dollars(budget)
	_apply_treatment_visibility()
	end_round_button.disabled = false


## Everything collective, hidden in T1: the city card and the button that
## switches the map to the city's routes.
##
## The button used to live inside the city panel and inherited this for free.
## It now sits on the rail with the personal controls, so it needs saying out
## loud, and it needs saying in both places the card's visibility is set.
## Guardrail 1 is that treatment decides what is SHOWN and nothing else; a
## collective view reachable from T1 would break it, quietly, in a way only a
## participant would notice.
func _apply_treatment_visibility() -> void:
	var collective: bool = GameManager.treatment != GameManager.Treatment.INDIVIDUAL
	city_panel.visible       = collective
	city_view_button.visible = collective
	# Every treatment. A player's own route is personal information, the same
	# argument that puts the stress view in all three, so this is set here
	# rather than left to inherit anything.
	player_routes_button.visible = true


func _on_round_ended(_round_num: int, results: Dictionary) -> void:
	_last_round_results = results
	_render_personal(results)
	end_round_button.disabled = true


## Time stays a raw number (travel time + money are the only raw numbers
## shown to participants); safety is star-rating-only unless debug mode is
## on (SafetyDisplay.format_bb handles that).
func _render_personal(results: Dictionary) -> void:
	var players_data: Array = results.get("players", [])
	if players_data.size() <= 1:
		safety_label.visible = true
		time_label.text   = "Time: %.1f min" % results.get("personal_time", 0.0)
		safety_label.text = "Safety: " + SafetyDisplay.format_bb(results.get("personal_safety", 0.0))
		return

	# A ROW PER PLAYER, not one line listing everybody.
	#
	# Both figures used to be laid out along a single line each ("Time  P1: 28.6
	# P2: 20.8 ..."), and a label reports the width of its longest line as its
	# minimum. Five players made that line about 590px, which the card containing
	# it has to honour, so it stretched from 226px to over 600 and reached a third
	# of the way across the map. Rows are bounded by the widest single row
	# instead, so the card stays the same width whatever the player count.
	#
	# This mattered when the card was a fixed sidebar and matters more now that it
	# floats over the board, where the width it takes is width the player cannot
	# see through.
	#
	# Time and safety share a row, so five players cost five lines rather than
	# ten, and each player's two numbers read together.
	safety_label.visible = false
	var rows: PackedStringArray = []
	for i in range(players_data.size()):
		var pd: Dictionary = players_data[i]
		rows.append("P%d   %.1f min   %s" % [
			i + 1, pd.get("time", 0.0), SafetyDisplay.format_bb(pd.get("safety", 0.0))])
	time_label.text = "\n".join(rows)


func _on_city_metrics_updated(metrics: Dictionary) -> void:
	_last_city_metrics = metrics
	_render_city(metrics)


## City-wide outcomes ARE shown to participants in T2/T3 (the whole point of
## those conditions); the panel itself is hidden in T1 by city_panel.visible.
## Text comes from CityFeedback so it matches what the log records verbatim.
func _render_city(metrics: Dictionary) -> void:
	var text := CityFeedback.lines(metrics)
	city_time_label.text   = text[0]
	city_safety_label.text = text[1]
	coverage_label.text    = text[2]

	# How many residents are better off than on the original network. Absent
	# until the first round is confirmed, so the label hides rather than
	# showing a placeholder "0%" that would read as a real result.
	var benefit := CityFeedback.benefit_lines(metrics)
	benefit_label.visible = not benefit.is_empty()
	benefit_label.text    = "\n".join(benefit)


func _on_game_over(_final: Dictionary) -> void:
	end_round_button.text     = "Game Over"
	end_round_button.disabled = true


func update_budget(credits_remaining: int) -> void:
	budget_label.text = "Budget: " + Player.format_dollars(credits_remaining)
