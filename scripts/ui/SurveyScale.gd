class_name SurveyScale
## SurveyScale.gd
## The six point response scale shared by both research surveys.
##
## Why this is its own class rather than a list inside each survey script: the
## two surveys must present an identical scale, and the personality value alpha
## is derived from the exact mapping between a displayed option and a number.
## If each survey carried its own copy, the two could drift apart, and a drifted
## scale is not recoverable once sessions have been run.
##
## Display order is AGREE FIRST, matching the official question file. The stored
## value is deliberately independent of that display order: agreement always
## scores 5 and disagreement always scores 1, so reordering the buttons on
## screen can never silently reverse the scoring.

## Logged in place of a number when a participant answers "Don't know / Not
## applicable". Kept as a string rather than folded into the numeric scale so
## analysis can separate a genuine neutral opinion from an absent one, which a
## bare 3 could not express.
const DK: String = "dk"

## What a "Don't know" answer contributes to alpha: the middle of the scale,
## identical to "Neither agree nor disagree". A DK answer should neither drop a
## participant out of the personality calculation nor pull them toward either
## end of it.
const NEUTRAL_SCORE: float = 3.0

## Width of one response column. The headers and the buttons beneath them both
## read this, so they stay aligned as a matrix.
const COLUMN_WIDTH: float = 112.0

## Diameter of one response bubble.
const BUBBLE_SIZE: float = 26.0


## Width of the question column: the wrapped item text on the left of each row.
## Both surveys read this so their rows line up with each other and with the
## header row above them.
##
## Widened along with the question font, so a 16pt item still runs to about the
## number of lines it did at 12pt. The survey panels grew to match.
const QUESTION_COLUMN_WIDTH: float = 380.0


## The wrapped item text at the left of one scale row.
##
## Lived in both surveys as identical copies, down to the comment below, which
## is the drift this class exists to prevent.
##
## 12 up to 16: the question text and the scale headers were the smallest text
## in the participant-facing game, below even the map legend, which was raised
## off 11 on 24 Aug 2026 for the same reason. Playtesters reported both surveys
## as uncomfortable to read.
const QUESTION_FONT_SIZE: int = 16


static func question_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(QUESTION_COLUMN_WIDTH, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", QUESTION_FONT_SIZE)
	return lbl

## The bubbles are drawn here rather than left to the engine's default checkbox
## icons, which sit at very low contrast against the dark survey panel and make
## the chosen answer hard to pick out. An unanswered bubble is a dark disc with
## a clearly lit ring; a chosen one fills solid and bright, so a filled row
## reads at a glance from across a desk. That matters more than usual here: in
## the group treatment three people share one screen, and a participant who
## cannot tell which option is selected may answer a question twice or skip it.

## Faint banding behind alternate rows. With six columns of identical bubbles,
## banding is what keeps the eye on one question's row while travelling to the
## right-hand columns.


## Presented left to right in this order. `value` is what gets stored and
## logged.
const OPTIONS: Array = [
	{"label": "Strongly\nagree",              "value": 5},
	{"label": "Somewhat\nagree",              "value": 4},
	{"label": "Neither agree\nnor disagree",  "value": 3},
	{"label": "Somewhat\ndisagree",           "value": 2},
	{"label": "Strongly\ndisagree",           "value": 1},
	{"label": "Don't know /\nNot applicable", "value": DK},
]


## The number a stored response contributes to alpha. "Don't know" reads as the
## neutral middle; every other option carries its own value regardless of where
## it happens to sit on screen.
static func score_for(response: Variant) -> float:
	if typeof(response) == TYPE_STRING:
		return NEUTRAL_SCORE
	return float(response)


## Column headers for a block of scale questions, aligned with the buttons that
## build_response_row() produces. Participants read the full option wording
## once at the top of the block rather than decoding abbreviations on every row.
static func build_header_row(question_column_width: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(question_column_width, 0)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	for opt: Dictionary in OPTIONS:
		var lbl := Label.new()
		lbl.text = opt["label"]
		lbl.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Raised with the question text beside it. 14 rather than 16: the widest
		# header line is "Not applicable", which at 15 would overrun COLUMN_WIDTH
		# and break the alignment between a header and the bubbles under it.
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Palette.SURVEY_HEADER)
		row.add_child(lbl)
	return row


## One bubble state. Corner radius is half the diameter, which makes the box a
## circle at this size.
static func _bubble_style(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(BUBBLE_SIZE / 2.0))
	return sb


## Puts a question row on a banded background. `index` is the row's position
## within its block, so alternate rows pick up the stripe.
static func banded_row(row: Control, index: int) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.ROW_STRIPE if index % 2 == 1 else Color(0, 0, 0, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(row)
	return panel


## One question's six radio buttons, sized to sit under the headers above.
## `on_pick` is called with the chosen option's stored value.
static func build_response_row(on_pick: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var group := ButtonGroup.new()
	for opt: Dictionary in OPTIONS:
		var holder := CenterContainer.new()
		holder.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)

		var btn := Button.new()
		btn.toggle_mode         = true
		btn.button_group        = group
		btn.custom_minimum_size = Vector2(BUBBLE_SIZE, BUBBLE_SIZE)
		btn.focus_mode          = Control.FOCUS_NONE
		btn.tooltip_text        = (opt["label"] as String).replace("\n", " ")

		btn.add_theme_stylebox_override("normal",
			_bubble_style(Palette.BUBBLE_FILL, Palette.BUBBLE_BORDER))
		btn.add_theme_stylebox_override("hover",
			_bubble_style(Palette.BUBBLE_HOVER_FILL, Palette.BUBBLE_HOVER_BORDER))
		# Both pressed states carry the selected look, so hovering an already
		# chosen bubble does not make it appear to revert.
		btn.add_theme_stylebox_override("pressed",
			_bubble_style(Palette.BUBBLE_SELECTED_FILL, Palette.BUBBLE_SELECTED_BORDER))
		btn.add_theme_stylebox_override("hover_pressed",
			_bubble_style(Palette.BUBBLE_SELECTED_FILL, Palette.BUBBLE_SELECTED_BORDER))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		# Snapshotted per iteration so each button reports its own option.
		var value: Variant = opt["value"]
		btn.pressed.connect(func() -> void: on_pick.call(value))

		holder.add_child(btn)
		box.add_child(holder)
	return box
