class_name NarrativeIntro
extends CanvasLayer
## NarrativeIntro.gd
## Shown once per session, after the pre-survey(s) and before Round 1 —
## a two-page orientation: a generic "welcome to CycleCity" page, then a
## page describing how this specific treatment condition works. Same
## content for every player in a group (T3 shares one screen already).
##
## Copy source: "Narrative Draft - July 2026" (owner-approved 27 Jul 2026).
## The source doc's "Research note" paragraphs are researcher-facing only
## and are intentionally NOT reproduced here.

signal narrative_finished

const SPEAKER_TEXTURE := preload("res://assets/images/AI-GEN Speaker.png")

const INTRO_TITLE := "Welcome to CycleCity"
const INTRO_BODY := "CycleCity is growing fast, but its bike network has not caught up. Some streets feel smooth and connected, while others are stressful, disconnected, or difficult to ride.

City leaders have opened a new resident planning challenge: help decide where the next cycling upgrades should go. You have been selected to take part.

In each round, you will receive limited credits to improve the network. Painted lanes are cheaper, while protected lanes cost more but provide greater comfort and safety benefits.

You cannot fix every street, so every choice matters.

Use the credits however you think is best."

const TREATMENT_TITLE := "Before You Begin"
const TREATMENT_BODY: Dictionary = {
	GameManager.Treatment.INDIVIDUAL: "In this round, you will make decisions on your own.

Your home and work locations are shown on the map, along with the city's cycling network. After each round, you will see how your choices affect your commute.

Where will you invest first?",

	GameManager.Treatment.COLLECTIVE_INFO: "In this round, you will still make decisions on your own.

This time, the City will also share citywide feedback after your choices. You will see how your upgrades affect your commute and how they affect the broader cycling network.

Where will you invest this round?",

	GameManager.Treatment.COLLECTIVE_CHAT: "In this round, you are no longer making decisions alone.

You and other residents are sitting together in front of one shared city map. Each person has their own home and work location and may experience the network differently.

Before confirming the upgrades, you will have a chance to talk with the other residents and decide together how the budget should be used.

When your group is ready, confirm the upgrades together.",
}

@onready var speaker_icon: TextureRect  = %SpeakerIcon
@onready var title_label: Label         = %TitleLabel
@onready var body_label: Label          = %BodyLabel
@onready var continue_button: Button    = %ContinueButton

var _treatment: int = 0
var _on_page_two: bool = false


func _ready() -> void:
	visible = false
	speaker_icon.texture = SPEAKER_TEXTURE
	continue_button.pressed.connect(_on_continue_pressed)


func show_narrative(treatment: int) -> void:
	_treatment = treatment
	_on_page_two = false
	_show_page()
	visible = true


func _show_page() -> void:
	if _on_page_two:
		title_label.text = TREATMENT_TITLE
		body_label.text = TREATMENT_BODY.get(_treatment, "")
		continue_button.text = "Begin"
	else:
		title_label.text = INTRO_TITLE
		body_label.text = INTRO_BODY
		continue_button.text = "Continue"


func _on_continue_pressed() -> void:
	if _on_page_two:
		visible = false
		narrative_finished.emit()
	else:
		_on_page_two = true
		_show_page()
