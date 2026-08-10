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


func show_for_link(link_id: String, credits_remaining: int, alpha: float, pending_level: int = -1) -> void:
	_current_link_id = link_id
	var link: CityNetwork.Link = GameManager.network.links[link_id]

	var link_safety := Player.link_preview_safety(link, alpha)
	# effective_time, not base_time — an already-upgraded road is genuinely
	# quicker to ride, so the popup must agree with the time the player sees
	# on their route rather than quoting the unimproved figure.
	if SafetyDisplay.debug_mode:
		link_info_label.text = "Time: %.1f min  |  Stress: %.2f  |  Safety: %d" % [
			link.effective_time(), link.stress_score, int(link_safety)]
	else:
		link_info_label.text = "Time: %.1f min  |  Safety: %s" % [
			link.effective_time(), SafetyDisplay.format(link_safety)]

	# Abstract effect arrows instead of raw stress/time deltas — protected
	# relief is always stronger than painted, hence the extra ↓. Cost is
	# per-link (scales with the road's length via base_time), not flat.
	var painted_cost: int   = Player.cost_for_link(link, 1)
	var protected_cost: int = Player.cost_for_link(link, 2)
	painted_button.text   = "Painted Lane  —  %s   (stress ↓  time ↓)" % Player.format_dollars(painted_cost)
	protected_button.text = "Protected Track  —  %s   (stress ↓↓  time ↓)" % Player.format_dollars(protected_cost)

	var level_names := ["No Bike Lane", "Painted Lane", "Protected Track"]
	var effective_level := pending_level if pending_level >= 0 else link.upgrade_level

	if pending_level > 0 and pending_level != link.upgrade_level:
		current_label.text = "%s  →  %s (pending)" % \
				[level_names[link.upgrade_level], level_names[pending_level]]
	elif pending_level == 0:
		current_label.text = "%s  →  Removal pending" % level_names[link.upgrade_level]
	else:
		current_label.text = "Current: %s" % level_names[effective_level]

	painted_button.disabled   = effective_level >= 1 or credits_remaining < painted_cost
	protected_button.disabled = effective_level >= 2 or credits_remaining < protected_cost

	if pending_level == 0:
		remove_button.visible = true
		remove_button.text    = "Cancel Removal"
	elif effective_level > 0:
		remove_button.visible = true
		var refund: int = Player.cost_for_link(link, effective_level)
		if pending_level > 0:
			remove_button.text = "Cancel Upgrade  (+%s)" % Player.format_dollars(refund)
		else:
			remove_button.text = "Remove Upgrade  (+%s)" % Player.format_dollars(refund)
	else:
		remove_button.visible = false

	visible = true


func _on_upgrade_chosen(level: int) -> void:
	upgrade_chosen.emit(_current_link_id, level)
	hide()
