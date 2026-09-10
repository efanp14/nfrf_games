class_name PlayerRow
## PlayerRow.gd
## The one-line-per-seat row shared by the round summary and the end screen.
##
## Both screens built this by hand, line for line, including a duplicated copy
## of the comment below -- which is a rule the project has already been bitten
## by, so it is worth having in one place.
##
## Rich text, because the safety stars in the row are gold like every other
## rating; the seat colour therefore has to go on `default_color` rather than
## `font_color`.

## Row height and text size. The end screen used 12pt against the round
## summary's 16 for the same kind of row, with nothing saying why; 16 wins
## because in a group session three people read one screen from a table.
const FONT_SIZE: int = 16
const MIN_HEIGHT: float = 22.0


## WRAPPING IS OFF AND MUST STAY OFF. `fit_content` with wrapping on makes a
## RichTextLabel's minimum HEIGHT a function of a width its container has not
## settled yet. On the frame these panels appear that width is about zero, so
## three of these rows asked for 1,664px between them and the panel sized itself
## 2,967px tall on a 1,080px screen: the separator and the button below went off
## the bottom, and a group session could not leave the round. Wrapping off makes
## the height one line whatever the width. tools/probe_round_summary.tscn holds
## this by measuring both panels on the frame they are shown.
static func make(seat_index: int, text: String) -> RichTextLabel:
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.fit_content = true
	row.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.custom_minimum_size = Vector2(0, MIN_HEIGHT)
	row.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	row.add_theme_color_override("default_color", Palette.seat_color(seat_index))
	row.text = text
	return row


## The box these rows go in. Both screens built it with the same five
## statements in _ready().
static func make_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.visible = false
	return box


## Empties the box between rounds.
static func clear(box: VBoxContainer) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
