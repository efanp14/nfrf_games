class_name ConsentScreen
extends CanvasLayer
## ConsentScreen.gd
## Shown once per session, before the pre-survey. Gates entry on an explicit
## acknowledgement checkbox.
##
## IMPORTANT: the body text in ConsentScreen.tscn is placeholder — it must
## be replaced with your institution's REB/IRB-approved consent wording
## before running real sessions. This script only builds the mechanism
## (gated agree/decline, logged to the session record).

signal consent_given
signal consent_declined

@onready var ack_checkbox: CheckBox = %AckCheckBox
@onready var agree_button: Button   = %AgreeButton
@onready var decline_button: Button = %DeclineButton


func _ready() -> void:
	visible = false
	ack_checkbox.toggled.connect(_on_ack_toggled)
	agree_button.pressed.connect(_on_agree_pressed)
	decline_button.pressed.connect(_on_decline_pressed)
	agree_button.disabled = true


func show_consent() -> void:
	ack_checkbox.button_pressed = false
	agree_button.disabled = true
	visible = true


func _on_ack_toggled(pressed: bool) -> void:
	agree_button.disabled = not pressed


func _on_agree_pressed() -> void:
	visible = false
	consent_given.emit()


func _on_decline_pressed() -> void:
	visible = false
	consent_declined.emit()
