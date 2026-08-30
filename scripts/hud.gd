extends CanvasLayer
## Resource counts, the active pal, and transient messages.

const MESSAGE_TIME := 2.5

@onready var _counts: Label = $Bar/Margin/Counts
@onready var _message: Label = $Message
@onready var _timer: Timer = $MessageTimer
@onready var _help: PanelContainer = $Help


func _ready() -> void:
	# Autoloaded, so the singleton name is how everything else reaches flash().
	Inventory.changed.connect(_refresh)
	Party.changed.connect(_refresh)
	_timer.timeout.connect(func() -> void: _message.text = "")
	_message.text = ""
	_help.visible = false
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		_help.visible = not _help.visible
		get_viewport().set_input_as_handled()


func flash(text: String) -> void:
	_message.text = text
	_timer.start(MESSAGE_TIME)


func _refresh() -> void:
	var out := "Wood %d     Stone %d     Cubes %d" % [
		Inventory.count("wood"), Inventory.count("stone"), Inventory.count("cube")
	]
	out += "     Catch %d%%" % roundi(Tuning.CUBE_CATCH_CHANCE * 100.0)
	if not Party.members.is_empty():
		var name := Party.active.display_name if Party.active else "none"
		out += "     Pal: %s (%d)" % [name, Party.members.size()]
	_counts.text = out
