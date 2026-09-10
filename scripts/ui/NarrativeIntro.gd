class_name NarrativeIntro
extends CanvasLayer
## NarrativeIntro.gd
## Shown once per session, after the pre-survey(s) and before Round 1, and
## reopenable from the rail at any point during play. Same content for every
## player in a group (T3 shares one screen already).
##
## Copy source: "Narrative Draft - July 2026" (owner-approved 27 Jul 2026),
## restructured 30 Aug 2026 after a student playtest. The source doc's
## "Research note" paragraphs are researcher-facing only and are intentionally
## NOT reproduced here.
##
## THE STRUCTURE IS THE POINT. It used to be two pages of continuous prose, and
## playtesters could not answer three separate questions from it: what is this
## place, who am I, and what do I actually do. So there is now one page per
## question, in that order, and a page of pictures for the two things being
## bought. A Back button, because a participant who has moved on and wants the
## previous page again otherwise has no way back.
##
## NEUTRALITY (README, guardrail 8). Whether a participant invests in their own commute
## or in the city is the dependent variable, so nothing here may push either
## way. Page three states the RULES that make the choice available -- that any
## road can be upgraded, that the budget refills -- flatly and without comment,
## because a participant who believes they may only touch their own commute
## cannot choose to do otherwise, and that silence is itself a bias. No page
## praises, suggests or ranks a way to play.

signal narrative_finished

const SPEAKER_TEXTURE := preload("res://assets/images/speaker.png")

## Page indices, so the flow reads as names rather than as numbers.
enum Page { WHAT, ROLE, DO, LANES, TREATMENT }

const PAGE_ORDER: Array = [Page.WHAT, Page.ROLE, Page.DO, Page.LANES, Page.TREATMENT]

const TITLES: Dictionary = {
	Page.WHAT:  "What is CycleCity?",
	Page.ROLE:  "What is my role?",
	Page.DO:    "What do I need to do?",
	Page.LANES: "The two kinds of bike lane",
	Page.TREATMENT: "Before you begin",
}

const BODY_WHAT := "CycleCity is a city that has grown faster than its bike network.

Some streets are calm and pleasant to ride. Others are busy and stressful, with nothing between a rider and the traffic.

Every street on the map is a real route somebody uses to get to work."

const BODY_ROLE := "You are a resident taking part in the city's planning process.

You have a home and a workplace of your own, marked on the map, and you ride between them. Your route is drawn in your own colour, with arrows showing the direction you travel.

The city has given you a budget to spend on bike lanes."

## Money, budget refill, what a click does, and the two things playtesters got
## wrong by not being told: that any road is available, and that this is about
## how a street feels to ride rather than about car traffic.
const BODY_DO := "Click any road on the map to see what it would cost to improve, then choose a painted or a protected lane. Click End Round when you have finished.

You have $1,300,000 each round, and there are three rounds. Anything you do not spend does NOT carry over, so there is nothing to be gained by saving it.

You can upgrade any road in the city. You are not limited to the roads on your own route.

Everything measured here is about cycling: how long your ride takes, and how calm or stressful it feels. The cars on the map show how busy a street is. Nothing you build changes anything for them.

A few streets already have bike lanes at the start. Those were built before you arrived."

const BODY_LANES := "The map shows what has been built on every street."

const TREATMENT_BODY: Dictionary = {
	GameManager.Treatment.INDIVIDUAL: "In this session, you will make decisions on your own.

After each round you will see how your choices affected your commute.

Where will you invest first?",

	GameManager.Treatment.COLLECTIVE_INFO: "In this session, you will still make decisions on your own.

This time the City will also report back on the whole network after each round. You will see how your upgrades affected your commute, and how they affected everyone else's.

Where will you invest this round?",

	GameManager.Treatment.GROUP_DISCUSSION: "In this session you are not deciding alone.

You and the other residents share one map and one budget. Each of you has your own home and workplace, and the same street can matter very differently to each of you.

Talk it over before confirming, and confirm the upgrades together.",
}

@onready var speaker_icon: TextureRect  = %SpeakerIcon
@onready var title_label: Label         = %TitleLabel
@onready var body_label: Label          = %BodyLabel
@onready var continue_button: Button    = %ContinueButton
@onready var back_button: Button        = %BackButton
@onready var diagram_box: Control       = %DiagramBox

var _treatment: int = 0
var _page: int = 0
## True when this was opened from the rail mid-game rather than before Round 1.
## A reopened briefing must not restart the round when it closes.
var _reopened: bool = false


func _ready() -> void:
	visible = false
	# The scrim comes from Palette rather than from the scene, so every
	# screen's backdrop is set in the one place colours are declared.
	($Overlay as ColorRect).color = Palette.OVERLAY_FULL
	speaker_icon.texture = SPEAKER_TEXTURE
	continue_button.pressed.connect(_on_continue_pressed)
	back_button.pressed.connect(_on_back_pressed)
	diagram_box.add_child(LaneDiagram.new())


func show_narrative(treatment: int) -> void:
	_treatment = treatment
	_reopened = false
	_page = 0
	_show_page()
	visible = true


## Reopened from the rail during play. Same pages; the difference is that
## closing it returns to the round rather than starting one.
func reopen(treatment: int) -> void:
	_treatment = treatment
	_reopened = true
	_page = 0
	_show_page()
	visible = true


func _show_page() -> void:
	var page: int = PAGE_ORDER[_page]
	title_label.text = TITLES[page]
	match page:
		Page.WHAT:  body_label.text = BODY_WHAT
		Page.ROLE:  body_label.text = BODY_ROLE
		Page.DO:    body_label.text = BODY_DO
		Page.LANES: body_label.text = BODY_LANES
		Page.TREATMENT: body_label.text = TREATMENT_BODY.get(_treatment, "")
	diagram_box.visible = page == Page.LANES

	var last: bool = _page == PAGE_ORDER.size() - 1
	if last:
		continue_button.text = "Close" if _reopened else "Begin"
	else:
		continue_button.text = "Continue"
	# Hidden rather than disabled on the first page: a permanently dead button
	# reads as something being broken.
	back_button.visible = _page > 0


func _on_back_pressed() -> void:
	if _page == 0:
		return
	_page -= 1
	_show_page()


func _on_continue_pressed() -> void:
	if _page < PAGE_ORDER.size() - 1:
		_page += 1
		_show_page()
		return
	visible = false
	# A reopened briefing is just a panel closing. Only the first pass through
	# starts the game, or main.gd would start a second round on top of the one
	# already running.
	if not _reopened:
		narrative_finished.emit()
