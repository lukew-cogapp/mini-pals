extends CanvasLayer
## Resource counts, the active pal, and transient messages.

const MESSAGE_TIME := 2.5

@onready var _counts: Label = $Bar/Margin/Counts
@onready var _message: Label = $Message
@onready var _timer: Timer = $MessageTimer
@onready var _help: PanelContainer = $Help
@onready var _health_fill: ColorRect = $Health/Fill
@onready var _health_value: Label = $Health/Value
@onready var _fade: ColorRect = $Fade

var _health_width := 0.0


func _ready() -> void:
	# Autoloaded, so the singleton name is how everything else reaches flash().
	Inventory.changed.connect(_refresh)
	Party.changed.connect(_refresh)
	_timer.timeout.connect(func() -> void: _message.text = "")
	_message.text = ""
	_help.visible = false
	_health_width = _health_fill.size.x
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		_help.visible = not _help.visible
		get_viewport().set_input_as_handled()


func set_health(hp: float, max_hp: float) -> void:
	_health_fill.size.x = _health_width * clampf(hp / max_hp, 0.0, 1.0)
	_health_value.text = "%d / %d" % [floori(hp), roundi(max_hp)]


## Death fade: 1.0 blacks the screen out, 0.0 brings it back.
func fade_to(alpha: float, secs: float) -> void:
	create_tween().tween_property(_fade, "color:a", alpha, secs)


func flash(text: String) -> void:
	_message.text = text
	_timer.start(MESSAGE_TIME)


func _refresh() -> void:
	var out := "Lv%d  %d/%d" % [Party.player_level, Party.xp, Tuning.PLAYER_XP_PER_LEVEL]
	out += "     Wood %d     Stone %d     Cubes %d" % [
		Inventory.count("wood"), Inventory.count("stone"), Inventory.count("cube")
	]
	# Pal drops appear once owned, so the bar starts short.
	for item in Inventory.items():
		if item in ["wood", "stone", "cube"]:
			continue
		var n: int = Inventory.count(item)
		if n > 0:
			out += "     %s %d" % [String(item).capitalize(), n]
	if Inventory.count("cube") == 0:
		out += "     (no cubes: F to gather, B at the bench)"
	if not Party.members.is_empty():
		if Party.active:
			out += "     Pal: %s Lv%d%s (%d)" % [
				Party.active.display_name, Party.active.level,
				_buff_text(Party.active), Party.members.size(),
			]
		else:
			out += "     Pal: none (%d)" % Party.members.size()
	_counts.text = out


func _buff_text(pal: Pal) -> String:
	match pal.buff_kind:
		&"speed":
			return " (+%d%% speed)" % roundi(Party.buff(&"speed") * 100.0)
		&"gather":
			return " (+%d gather)" % int(Party.buff(&"gather"))
		_:
			return ""
