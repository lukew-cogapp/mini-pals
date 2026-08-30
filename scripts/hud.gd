extends CanvasLayer
## Resource counts, the active pal, and transient messages.

const MESSAGE_TIME := 2.5
const MESSAGE_QUEUED_TIME := 1.4
## Always shown, in this order, so the middle of the bar does not reorder
## itself as items come and go.
const CORE_ITEMS := ["wood", "stone"]
## Matches pal_boss.tscn's display_name; catching it is the win condition.
const BOSS_NAME := "Mushroom King"
## Row prefixes: a tick for done, a small triangle for the live objective.
const MARK_DONE := "✓"
const MARK_NOW := "▸"

@onready var _level: Label = $Bar/Margin/Row/LevelBox/Level
@onready var _xp_bar: Control = $Bar/Margin/Row/LevelBox/Xp
@onready var _xp_fill: ColorRect = $Bar/Margin/Row/LevelBox/Xp/Fill
@onready var _items: VBoxContainer = $ItemPanel/ItemPad/Items
@onready var _pal: Label = $Bar/Margin/Row/Pal
@onready var _message: Label = $Message
@onready var _timer: Timer = $MessageTimer
@onready var _help: PanelContainer = $Help
@onready var _health_fill: ColorRect = $Health/Fill
@onready var _health_value: Label = $Health/Value
@onready var _fade: ColorRect = $Fade
@onready var _cube_count: Label = $Bar/Margin/Row/CubeBox/Count
@onready var _reticule: Control = $Reticule
@onready var _reticule_label: Label = $Reticule/Label
@onready var _objectives: VBoxContainer = $ObjectivePanel/ObjectivePad/Col/Rows
@onready var _minimap_panel: PanelContainer = $MinimapPanel

var _health_width := 0.0
var _health_tween: Tween
var _hurt_tween: Tween
## Kept separate from _hurt_tween: a hit landing during the death fade must
## not cancel the fade to black.
var _fade_tween: Tween
var _fading := false
var _icon_cache := {}
## Catching a pal flashes the catch, the XP and sometimes a level in the same
## frame. One label showing the last of them meant the catch was never read,
## so they queue and take their turn instead.
var _messages: Array[String] = []


func _ready() -> void:
	# Autoloaded, so the singleton name is how everything else reaches flash().
	Inventory.changed.connect(_refresh)
	Party.changed.connect(_refresh)
	_timer.timeout.connect(_next_message)
	_message.text = ""
	_help.visible = false
	_reticule.visible = false
	_health_width = _health_fill.size.x
	_xp_bar.resized.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		_help.visible = not _help.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("minimap"):
		# The map only. The objectives list is the signposting and stays put.
		_minimap_panel.visible = not _minimap_panel.visible
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
	if _message.text == "":
		_show_message(text)
		return
	if text != _message.text and not _messages.has(text):
		_messages.append(text)


func _next_message() -> void:
	if _messages.is_empty():
		_message.text = ""
		return
	_show_message(_messages.pop_front())


func _show_message(text: String) -> void:
	_message.text = text
	# Queued messages get a shorter turn, so a catch and its XP do not leave
	# the player waiting five seconds to see the world again.
	_timer.start(MESSAGE_TIME if _messages.is_empty() else MESSAGE_QUEUED_TIME)


func set_reticule(on: bool, text := "", locked := false) -> void:
	_reticule.visible = on
	if not on:
		return
	_reticule.modulate = Color(1.0, 0.82, 0.35, 1.0) if locked \
		else Color(1.0, 0.96, 0.86, 0.8)
	_reticule_label.text = text
	_reticule_label.visible = text != ""


## Level and pal on the bottom bar, carried items as a list in the top-left
## corner. Everything used to be one concatenated label, which grew sideways
## with every new drop until it ran off both ends of the screen.
func _refresh() -> void:
	_level.text = "Lv%d" % Party.player_level
	# Progress to the next level reads as a bar; the raw numbers were noise.
	var frac := clampf(float(Party.xp) / float(Tuning.PLAYER_XP_PER_LEVEL), 0.0, 1.0)
	_xp_fill.size.x = maxf(0.0, (_xp_bar.size.x - 4.0) * frac)

	# The King makes throws free, so the stock is not what is left to throw.
	_cube_count.text = (
		Tuning.INFINITE_CUBE_TEXT if Party.infinite_cubes()
		else str(Inventory.count("cube"))
	)
	_refresh_items()
	_refresh_objectives()

	if Party.members.is_empty():
		_pal.text = ""
	elif Party.active:
		_pal.text = "%s Lv%d%s  (%d)" % [
			Party.active.display_name, Party.active.level,
			_buff_text(Party.active), Party.members.size(),
		]
	else:
		_pal.text = "no pal out  (%d)" % Party.members.size()


func _buff_text(pal: Pal) -> String:
	if Party.infinite_cubes():
		return " (free cubes)"
	match pal.buff_kind:
		&"speed":
			return " (+%d%% speed)" % roundi(Party.buff(&"speed") * 100.0)
		&"gather":
			return " (+%d gather)" % int(Party.buff(&"gather"))
		&"damage":
			return " (+%d punch)" % int(Party.buff(&"damage"))
		_:
			return ""


## The top-left item list. Rows are created once and then only shown, hidden
## and relabelled: rebuilding the list on every pickup would churn nodes on a
## signal that fires for each swing of a punch.
func _refresh_items() -> void:
	var shown := CORE_ITEMS.duplicate()
	for item in Inventory.items():
		if item not in shown and Inventory.count(item) > 0:
			shown.append(item)

	while _items.get_child_count() < min(shown.size(), Tuning.ITEM_ROWS_MAX):
		_items.add_child(_make_item_row())

	for i in _items.get_child_count():
		var row: HBoxContainer = _items.get_child(i)
		if i >= shown.size():
			row.visible = false
			continue
		var item: String = shown[i]
		row.visible = true
		var icon: TextureRect = row.get_child(0)
		icon.texture = _icon_for(item)
		var label: Label = row.get_child(1)
		label.text = "%s  %d" % [String(item).capitalize().replace("_", " "), Inventory.count(item)]


func _make_item_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(Tuning.ITEM_ICON_SIZE, Tuning.ITEM_ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 0.96, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	row.add_child(label)
	return row


## Icons are cached: `load` on an already-loaded path is cheap, but this runs
## once per item per inventory change, which is every swing of a punch.
func _icon_for(item: String) -> Texture2D:
	if item in _icon_cache:
		return _icon_cache[item]
	var tex: Texture2D = null
	if item in Tuning.ITEM_ICONS:
		tex = load(Tuning.ITEM_ICONS[item]) as Texture2D
	_icon_cache[item] = tex
	return tex


## --- Objectives ------------------------------------------------------------
##
## The chain, in order, each step evaluated against live state rather than a
## stored flag: catch pals, reach the level that unlocks the key, gather its
## three drops, craft it, take it to the altar, catch the King.
## The text lives here rather than in tuning.gd because it is content, not a
## number to playtest, and it reads next to the condition it describes.
##
## Returns [{text, done}] in chain order, earliest first.
func _objective_chain() -> Array[Dictionary]:
	var chain: Array[Dictionary] = []
	var caught := Party.members.size()
	chain.append({
		"text": "Catch pals %d/%d" % [mini(caught, Tuning.OBJECTIVE_CATCH_TARGET),
			Tuning.OBJECTIVE_CATCH_TARGET],
		"done": caught >= Tuning.OBJECTIVE_CATCH_TARGET,
	})
	chain.append({
		"text": "Reach level %d (Lv%d)" % [Tuning.KEY_UNLOCK_LEVEL, Party.player_level],
		"done": Party.player_level >= Tuning.KEY_UNLOCK_LEVEL,
	})
	# One row per key material, so the player is told which drop to go and find
	# rather than "gather materials".
	for item in Tuning.KEY_RECIPE:
		var need: int = Tuning.KEY_RECIPE[item]
		var have := Inventory.count(item)
		chain.append({
			"text": "%s %d/%d" % [_item_name(item), mini(have, need), need],
			"short": _item_name(item),
			"done": have >= need,
		})
	# Crafting spends the materials, so holding a key and having already spent
	# one on a summon both count as crafted.
	var key_made := Inventory.count("altar_key") > 0 or _boss_summoned()
	chain.append({"text": "Craft the Altar Key at the bench", "done": key_made})
	chain.append({"text": "Use the key at the altar (R)", "done": _boss_summoned()})
	chain.append({"text": "Catch the Mushroom King", "done": _king_caught()})
	# Crafting spends the key materials, which would un-tick their rows and
	# walk the panel backwards. Anything before a finished step is finished,
	# and its count is dropped: "Demon horn 0/3" beside a tick reads as a bug.
	var seen_done := false
	for i in range(chain.size() - 1, -1, -1):
		if seen_done and not chain[i].done:
			chain[i].done = true
			chain[i].text = chain[i].get("short", chain[i].text)
		elif chain[i].done:
			seen_done = true
	return chain


## The altar removes the key before it spawns the boss, so a boss in the world
## is the only evidence a summon happened.
func _boss_summoned() -> bool:
	for pal in get_tree().get_nodes_in_group("pal"):
		if is_instance_valid(pal) and pal.display_name == BOSS_NAME:
			return true
	return _king_caught()


func _king_caught() -> bool:
	for pal in Party.members:
		# Party.store frees a duplicate species and emits `changed` in the same
		# breath, so a freed pal can still be in the array when this runs.
		if is_instance_valid(pal) and pal.display_name == BOSS_NAME:
			return true
	return false


func _item_name(item: String) -> String:
	return String(item).capitalize().replace("_", " ")


## The top-right objective list. Rows are built once and reused, like the item
## list: this runs on every inventory change, which is every swing of a punch.
##
## Shows the first unfinished objective with the last OBJECTIVE_DONE_ROWS
## finished ones above it, so the list is a short moving window over the chain
## rather than all of it.
func _refresh_objectives() -> void:
	var chain := _objective_chain()
	var current := chain.size() - 1
	for i in chain.size():
		if not chain[i].done:
			current = i
			break
	# The window ENDS at the current objective, so it is always the bottom row
	# and nothing further down the chain is spoiled early.
	var first: int = maxi(0, current - Tuning.OBJECTIVE_DONE_ROWS)
	var shown := chain.slice(first, current + 1)

	while _objectives.get_child_count() < Tuning.OBJECTIVE_ROWS_MAX:
		_objectives.add_child(_make_objective_row())

	for i in _objectives.get_child_count():
		var label: Label = _objectives.get_child(i)
		if i >= shown.size():
			label.visible = false
			continue
		var entry: Dictionary = shown[i]
		label.visible = true
		label.text = "%s %s" % [MARK_DONE if entry.done else MARK_NOW, entry.text]
		label.add_theme_color_override("font_color",
			Tuning.OBJECTIVE_DONE_COLOR if entry.done else Tuning.OBJECTIVE_ACTIVE_COLOR)
		label.add_theme_font_size_override("font_size",
			Tuning.OBJECTIVE_FONT_SIZE if entry.done else Tuning.OBJECTIVE_TITLE_FONT_SIZE)


func _make_objective_row() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	return label
