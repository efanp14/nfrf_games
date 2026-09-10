class_name SurveyIdentityBanner
extends HBoxContainer
## SurveyIdentityBanner.gd
## Says whose turn it is at the top of a survey: the seat colour, the seat
## number, and that participant's ID.
##
## The group treatment runs the closing survey one member at a time on a single
## shared screen, and it used to announce only "Player 2 of 3". Nothing on that
## screen said WHICH of the three people at the table was player 2 -- the seat
## is a colour everywhere else in the game (their pins, their route, their row on
## every summary) and an ID on a card in their pocket, and the survey named
## neither. Three people then have to work out between them who answers, which is
## the one moment in the session where getting it wrong silently attaches one
## person's attitudes to another person's decisions.
##
## Shown only when there is more than one player. A solo session has nobody to
## disambiguate from, and a research identifier on screen for no reason is not
## something a participant should be reading.
##
## One class rather than a copy in each survey, because the opening and closing
## surveys must not drift on this: whatever identifies a seat in one has to
## identify the same seat in the other.

const SWATCH_PX: float = 26.0
const FONT_SIZE: int = 20

var _swatch: ColorRect
var _seat_label: Label
var _id_label: Label


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 14)

	# The seat colour, taken from the same list the map, the route bands and both
	# summary screens read, so the square here is the square on their pins.
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(SWATCH_PX, SWATCH_PX)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_swatch)

	_seat_label = Label.new()
	_seat_label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(_seat_label)

	# Gold, matching every other emphasis in the interface, and in the hyphenated
	# form the researcher wrote on the participant's card rather than the packed
	# form the logs store.
	_id_label = Label.new()
	_id_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_id_label.add_theme_color_override("font_color", Palette.BRAND_GOLD)
	add_child(_id_label)


## `participant_id` may be empty, in which case only the seat is named -- which
## is still better than nothing, and is what a session run without IDs gets.
func set_player(player_num: int, total_players: int, participant_id: String) -> void:
	visible = total_players > 1
	if not visible:
		return
	var colour: Color = Palette.seat_color(player_num - 1)
	_swatch.color = colour
	_seat_label.text = "Player %d of %d" % [player_num, total_players]
	_seat_label.add_theme_color_override("font_color", colour)
	var shown := ParticipantId.format_for_display(participant_id.strip_edges())
	_id_label.text = shown
	_id_label.visible = not shown.is_empty()
