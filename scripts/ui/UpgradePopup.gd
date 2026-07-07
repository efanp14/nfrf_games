class_name UpgradePopup
extends CanvasLayer

signal upgrade_chosen(link_id: String, level: int)
signal downgrade_requested(link_id: String)
signal cancelled

@onready var link_info_label: Label   = %LinkInfoLabel
@onready var current_label: Label     = %CurrentLabel
@onready var painted_button: Button   = %PaintedButton
@onready var protected_button: Button = %ProtectedButton
@onready var remove_button: Button    = %RemoveButton
@onready var cancel_button: Button    = %CancelButton

var _current_link_id: String = ""


func _ready() -> void:
	visible = false
	painted_button.pressed.connect(func(): _on_upgrade_chosen(1))
	protected_button.pressed.connect(func(): _on_upgrade_chosen(2))
	remove_button.pressed.connect(func(): downgrade_requested.emit(_current_link_id); hide())
	cancel_button.pressed.connect(func(): cancelled.emit(); hide())


func show_for_link(link_id: String, credits_remaining: int, pending_level: int = -1) -> void:
	_current_link_id = link_id
	var link: CityNetwork.Link = GameManager.network.links[link_id]

	var friendly_name := GameManager.network.link_display_name(link_id)
	var link_safety := int(100.0 * (1.0 - link.beta * link.stress_score))
	link_info_label.text = "%s\nTime: %.1f min  |  Stress: %.2f  |  Safety: %d" % [
		friendly_name, link.base_time, link.stress_score, link_safety]

	var level_names := ["Unimproved", "Painted Lane", "Protected Track"]
	var effective_level := pending_level if pending_level >= 0 else link.upgrade_level

	if pending_level > 0 and pending_level != link.upgrade_level:
		current_label.text = "%s  →  %s (pending)" % \
				[level_names[link.upgrade_level], level_names[pending_level]]
	elif pending_level == 0:
		current_label.text = "%s  →  Removal pending" % level_names[link.upgrade_level]
	else:
		current_label.text = "Current: %s" % level_names[effective_level]

	painted_button.disabled   = effective_level >= 1 or credits_remaining < Player.COST_PAINTED_LANE
	protected_button.disabled = effective_level >= 2 or credits_remaining < Player.COST_PROTECTED_TRACK

	if pending_level == 0:
		remove_button.visible = true
		remove_button.text    = "Cancel Removal"
	elif effective_level > 0:
		remove_button.visible = true
		var refund: int = Player.COST_PAINTED_LANE if effective_level == 1 \
				else Player.COST_PROTECTED_TRACK
		if pending_level > 0:
			remove_button.text = "Cancel Upgrade  (+$%d)" % refund
		else:
			remove_button.text = "Remove Upgrade  (+$%d)" % refund
	else:
		remove_button.visible = false

	visible = true


func _on_upgrade_chosen(level: int) -> void:
	upgrade_chosen.emit(_current_link_id, level)
	hide()
