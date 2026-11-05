class_name ShrineTab
extends VBoxContainer
## Base of the shrine screen's tabs (ShrineScreen.TABS; P05 Rest and Grow, P12 Loadout and
## Attributes). The screen creates each tab whose file exists, calls setup() once, then adds
## the tab only when available() is true. It calls refresh() whenever the tab is shown and
## after any tab ran a shrine action (rest, grow, ...), and focuses first_focus() for pad
## navigation. A tab changes the game only through the shrine's or the player's public API
## (Shrine.rest / grow, GiantPlayer.set_loadout_slot, ...) and then calls
## screen.notify_changed(), so the other tabs (and the header) refresh.

var screen: ShrineScreen


## Called once, before the tab enters the tree. Build the controls here or in _ready.
func setup(p_screen: ShrineScreen) -> void:
	screen = p_screen


## The tab button's text.
func tab_title() -> String:
	return name


## False to leave the tab out (e.g. the shrine record turns the Loadout tab off).
func available() -> bool:
	return true


## Re-read everything shown from the shrine and the player.
func refresh() -> void:
	pass


## The control that gets the focus when the tab is shown (pad navigation), or null.
func first_focus() -> Control:
	return null


func shrine() -> Shrine:
	return screen.shrine if screen != null else null


func player() -> GiantPlayer:
	return screen.player if screen != null else null


func record() -> Dictionary:
	var s := shrine()
	return s.record() if s != null else {}
