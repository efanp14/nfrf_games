extends Node
## Audio.gd
## Interface sound effects: hover, click, and the upgrade confirmation.
##
## Autoload. Wires itself to every button in the game rather than being called
## from each UI script, because buttons here are not all in scenes: the survey
## response bubbles, the demographic dropdowns and the participant ID rows are
## all built with .new() at runtime, and any hand-wired list would miss them and
## would silently miss every button added later. Subscribing to the scene tree
## instead means a button is covered the moment it exists.
##
## Nothing here touches game state. Sound is presentation, and it must stay that
## way: no method on this node may influence routing, metrics or logging.

const SFX_HOVER   := preload("res://assets/sounds/on-hover-sfx.mp3")
const SFX_CLICK   := preload("res://assets/sounds/button-press.mp3")
const SFX_UPGRADE := preload("res://assets/sounds/road-upgrade.mp3")

## Deliberately quiet. These are confirmation cues in a lab session that may run
## next to other people, not game feedback meant to be noticed on its own.
## Hover sits furthest down because it fires far more often than the other two,
## and the upgrade sits highest because it marks the one action of the round
## that actually costs money.
const DB_HOVER:   float = -24.0
const DB_CLICK:   float = -18.0
const DB_UPGRADE: float = -14.0

## Voices available at once. A click landing on top of a still-playing hover
## needs somewhere to go, or it would cut the hover off mid sample.
const VOICES: int = 4

## Minimum gap between two hover sounds. Dragging the mouse across the map
## crosses several roads within a few frames, and without this the hover sample
## machine-guns. Long enough to stop the burst, short enough that deliberately
## moving between two buttons still sounds both.
const HOVER_COOLDOWN_S: float = 0.06

## Set false to silence the game entirely. Intended for the group treatment,
## where the discussion is recorded on a separate device for speaker separation
## and game audio played over speakers could bleed into that recording. Left on
## by default so the decision can follow a pilot rather than precede it.
var enabled: bool = true

var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _last_hover_s: float = -1.0
## Buttons already connected, so a node re-entering the tree cannot stack a
## second connection and double the sound.
var _wired: Dictionary = {}


func _ready() -> void:
	# Keep playing while the tree is paused: menus and popups are the parts of
	# this game most likely to pause it, and they are exactly where the click
	# sound matters.
	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in range(VOICES):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_voices.append(player)

	# Catch buttons that already exist (this autoload is ready before the main
	# scene, but a reload or a deferred add can still land either side of it),
	# then everything added from here on.
	get_tree().node_added.connect(_on_node_added)
	_wire_existing(get_tree().root)


func _wire_existing(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_wire_existing(child)


## Connects any pressable control as it enters the tree. BaseButton rather than
## Button so checkboxes, dropdowns and texture buttons are covered by the same
## path.
func _on_node_added(node: Node) -> void:
	if not (node is BaseButton) or _wired.has(node.get_instance_id()):
		return
	_wired[node.get_instance_id()] = true
	var button := node as BaseButton
	button.pressed.connect(_on_button_pressed.bind(button))
	button.mouse_entered.connect(_on_button_hovered.bind(button))
	button.tree_exited.connect(func(): _wired.erase(button.get_instance_id()))


## Most buttons click. A button carrying the "sfx" meta plays that sound
## instead, which is how the upgrade buttons get their own cue without this file
## needing to know what an upgrade is.
##
## The meta is read HERE rather than when the button was connected, because a
## node is added to the tree before its owner's _ready() runs, so the flag will
## not have been set yet at connection time.
func _on_button_pressed(button: BaseButton) -> void:
	if str(button.get_meta("sfx", "")) == "upgrade":
		play_upgrade()
	else:
		play_click()


## A disabled button is not pressable, so it should not answer to the mouse.
func _on_button_hovered(button: BaseButton) -> void:
	if button.disabled:
		return
	play_hover()


func play_hover() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_hover_s < HOVER_COOLDOWN_S:
		return
	_last_hover_s = now
	_play(SFX_HOVER, DB_HOVER)


func play_click() -> void:
	_play(SFX_CLICK, DB_CLICK)


func play_upgrade() -> void:
	_play(SFX_UPGRADE, DB_UPGRADE)


## Round-robins the voice pool. Prefers a free player, and only steals the
## oldest slot when every voice is busy, so overlapping sounds cut each other
## off as rarely as possible.
func _play(stream: AudioStream, volume_db: float) -> void:
	if not enabled or _voices.is_empty():
		return
	var player: AudioStreamPlayer = _voices[_next_voice]
	for candidate: AudioStreamPlayer in _voices:
		if not candidate.playing:
			player = candidate
			break
	_next_voice = (_next_voice + 1) % _voices.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()
