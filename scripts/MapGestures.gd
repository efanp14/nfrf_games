class_name MapGestures
## MapGestures.gd
## Whether a multi-touch map gesture is in progress, shared between the scene
## that recognises gestures (scenes/main.gd) and the roads that must not react
## to them (scripts/ui/LinkSegment.gd).
##
## A pinch is two fingers, and Godot emulates the mouse from the FIRST of them.
## So without this, spreading two fingers to zoom in on a district fires a road
## tap the instant the first finger lands, and the upgrade popup opens over the
## map the player was trying to look at. The fingers also lift a few
## milliseconds apart, so the gesture has to stay latched briefly after the last
## one leaves or the straggler registers as a tap of its own.
##
## Static rather than an autoload: it is one integer with no lifecycle, nothing
## to configure, and no state worth carrying across a scene reload. It holds a
## DEADLINE rather than a boolean, so a gesture that ends abruptly cannot leave
## the flag stuck on; the lock simply expires.

static var _locked_until_ms: int = 0


## Suppresses road taps for `ms` from now. Called repeatedly while a gesture
## runs; the latest deadline wins, and an earlier one can never shorten it.
static func lock(ms: int) -> void:
	_locked_until_ms = maxi(_locked_until_ms, Time.get_ticks_msec() + ms)


static func is_active() -> bool:
	return Time.get_ticks_msec() < _locked_until_ms
