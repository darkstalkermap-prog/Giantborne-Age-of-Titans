class_name UiScreen
extends Control
## Base of every modal screen (plan §2.10.2): pause, title (P06), shrine (P05), dialogue (P13),
## inventory, attributes, forge (P12), end (P13). A ScreenStack opens, stacks and closes them;
## while any open screen pauses_game(), the tree is paused, the input context is MENU and the
## mouse is free.
##
## Screens run while the game is paused (PROCESS_MODE_ALWAYS), fill the screen and stop mouse
## input from reaching the game. Those defaults are set when the screen first enters the tree
## (_notification runs for every class of the hierarchy, so subclasses need no super()).
## Override pauses_game(), first_focus() (pad navigation starts there), on_open(), on_close()
## and cancel() (Esc / pad B); finish with close(result).

signal closed(result: Dictionary)

var stack: ScreenStack
var args: Dictionary = {}
## The SCREENS key this screen was opened with ("" when pushed directly).
var screen_name := ""
var _base_set := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and not _base_set:
		_base_set = true
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP


## True while open: the game is paused (the title screen is the exception).
func pauses_game() -> bool:
	return true


## The control that gets the focus when the screen opens (pad navigation), or null.
func first_focus() -> Control:
	return null


## After the screen was added and shown (its _ready has run).
func on_open() -> void:
	pass


## Before the screen is removed (closed, or the stack closed everything).
func on_close() -> void:
	pass


## Esc / pad B. Default: close({"cancelled": true}).
func cancel() -> void:
	close({"cancelled": true})


## Closes the screen with a result (emitted by `closed`). The stack frees it afterwards.
func close(result: Dictionary = {}) -> void:
	if stack != null and is_instance_valid(stack) and stack.has_screen(self):
		stack.pop(self, result)
		return
	visible = false
	closed.emit(result)


func is_open() -> bool:
	return stack != null and is_instance_valid(stack) and stack.has_screen(self)
