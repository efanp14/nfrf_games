class_name ChatPanel
extends CanvasLayer

@onready var messages_box: VBoxContainer = %MessagesBox
@onready var scroll: ScrollContainer     = %ScrollContainer


func _ready() -> void:
	visible = false


## Append a chat message bubble. Called via GameManager.chat_message_received signal.
func add_message(round_num: int, text: String) -> void:
	var label := Label.new()
	label.text             = "[Round %d]  %s" % [round_num, text]
	label.autowrap_mode    = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	messages_box.add_child(label)
	_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
