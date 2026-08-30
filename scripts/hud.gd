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
@onready var _reticule: Control = $Reticule
@onready var _reticule_label: Label = $Reticule/Label

var _health_width := 0.0
var _health_tween: Tween
var _hurt_tween: Tween
## Kept separate from _hurt_tween: a hit landing during the death fade must
## not cancel the fade to black.
var _fade_tween: Tween
var _fading := false


func _ready() -> void:
	# Autoloaded, so the singleton name is how everything else reaches flash().
	Inventory.changed.connect(_refresh)
	Party.changed.connect(_refresh)
	_timer.timeout.connect(func() -> void: _message.text = "")
	_message.text = ""
	_help.visible = false
	_reticule.visible = false
	_health_width = _health_fill.size.x
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		_help.visible = not _help.visible
		get_viewport().set_input_as_handled()


func set_health(hp: float, max_hp: float) -> void:
	var width := _health_width * clampf(hp / max_hp, 0.0, 1.0)
	if _health_tween:
		_health_tween.kill()
	_health_tween = create_tween()
	_health_tween.tween_property(_health_fill, "size:x", width, Tuning.HEALTH_TWEEN_TIME)
	_health_value.text = "%d / %d" % [floori(hp), roundi(max_hp)]


## A hit: the bar blinks white and the screen takes a red wash. The wash
## borrows the Fade rect, so it is skipped outright while a death fade owns
## it rather than being killed and restarted alongside it.
func hurt_flash() -> void:
	if _hurt_tween:
		_hurt_tween.kill()
	_health_fill.color = Tuning.HEALTH_FLASH_COLOR
	_hurt_tween = create_tween()
	_hurt_tween.parallel().tween_property(_health_fill, "color",
		Tuning.HEALTH_FILL_COLOR, Tuning.HURT_FLASH_TIME)
	if _fading:
		return
	_fade.color = Color(Tuning.HURT_FLASH_COLOR, 0.0)
	_hurt_tween.parallel().tween_property(_fade, "color:a",
		Tuning.HURT_FLASH_ALPHA, Tuning.HURT_FLASH_TIME * 0.3)
	_hurt_tween.chain().tween_property(_fade, "color", Color(0.0, 0.0, 0.0, 0.0),
		Tuning.HURT_FLASH_TIME * 0.7)


## Death fade: 1.0 blacks the screen out, 0.0 brings it back.
func fade_to(alpha: float, secs: float) -> void:
	# _fading gates hurt_flash, which shares the Fade rect and would otherwise
	# wash it red and drop it back to transparent part-way through the fade.
	_fading = alpha > 0.0
	if _hurt_tween:
		_hurt_tween.kill()
	_health_fill.color = Tuning.HEALTH_FILL_COLOR
	_fade.color = Color(0.0, 0.0, 0.0, _fade.color.a)
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", alpha, secs)


func flash(text: String) -> void:
	_message.text = text
	_timer.start(MESSAGE_TIME)


func set_reticule(on: bool, text := "", locked := false) -> void:
	_reticule.visible = on
	if not on:
		return
	_reticule.modulate = Color(1.0, 0.82, 0.35, 1.0) if locked \
		else Color(1.0, 0.96, 0.86, 0.8)
	_reticule_label.text = text
	_reticule_label.visible = text != ""


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
