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
@onready var _prompt_panel: PanelContainer = $PromptPanel
@onready var _prompt_label: Label = $PromptPanel/PromptPad/Prompt

var _health_width := 0.0
var _health_tween: Tween
var _hurt_tween: Tween
## Kept separate from _hurt_tween: a hit landing during the death fade must
## not cancel the fade to black.
var _fade_tween: Tween
var _fading := false
var _icon_cache := {}
## Last level drawn, so _refresh can tell a level-up from any other change.
var _shown_level := 1
## Catching a pal flashes the catch, the XP and sometimes a level in the same
## frame. One label showing the last of them meant the catch was never read,
## so they queue and take their turn instead.
var _messages: Array[String] = []
var _prompt_timer := 0.0
var _prompt_tween: Tween


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
	# Player level gates the whole endgame, and levelling up used to be a
	# queued message behind the catch and the XP that caused it: 1.4 s in the
	# same small label as "+2 Pelt". Pulsing the label gives it a channel of
	# its own that cannot be missed or queued behind anything.
	if Party.player_level > _shown_level:
		_shown_level = Party.player_level
		_pulse_level()
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
		&"drop":
			return " (+%d drops)" % int(Party.buff(&"drop"))
		_:
			return ""


## The top-left item list. Rows are created once and then only shown, hidden
## and relabelled: rebuilding the list on every pickup would churn nodes on a
## signal that fires for each swing of a punch.
func _refresh_items() -> void:
	var shown := CORE_ITEMS.duplicate()
	for item in Inventory.items():
		# Cubes have the bottom bar to themselves. Listing them here as well
		# put the same count on screen twice, in two different styles.
		if item == "cube":
			continue
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
	chain.append({
		# The key comes from InputMap like every prompt does. This row named a
		# literal R while `prompt_test` existed precisely because bindings
		# have moved once already.
		"text": "Use the key at the altar (%s)" % _key_name("interact"),
		"done": _boss_summoned(),
	})
	# Catching wins; defeating is the consolation prize. Either finishes the
	# line, so a player who killed him is not left with a permanent red tick
	# on a fight they cannot fight again until they craft another key.
	var beaten := Inventory.count(Tuning.OBJECTIVE_CROWN_ITEM) > 0
	chain.append({
		"text": "Catch the Mushroom King" if not beaten else "Defeated the Mushroom King",
		"short": "Mushroom King",
		"done": _king_caught() or beaten,
	})
	# Optional, and last: finding the cave is a side trip, not a step on the
	# way to the altar, so it never becomes the row the player is told to do
	# next and never blocks the chain behind it.
	chain.append({
		"text": "Find the cave and its Grottolo",
		"short": "The cave",
		"optional": true,
		"done": Inventory.count(Tuning.OBJECTIVE_CAVE_ITEM) > 0 or _has_species("Grottolo"),
	})
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


## True once a species is in the party, by name.
func _has_species(species: String) -> bool:
	for pal in Party.members:
		if is_instance_valid(pal) and pal.display_name == species:
			return true
	return false


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
		# An optional row is never what the player is told to do next, or a
		# side trip would hide the rest of the chain behind it.
		if not chain[i].done and not chain[i].get("optional", false):
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


## --- Contextual key prompts ------------------------------------------------
##
## One line naming the key for whatever the player is standing next to, so the
## controls are learned in place rather than off the / overlay. Exactly one
## shows at a time: standing between a bench and a tree must not stack two, so
## the checks below run in priority order and the first hit wins.
##
## Priority, highest first: altar, workbench, rideable pal, gatherable node.
## The altar and the bench are places the player deliberately walked to and
## there is one of each in the world; a caught pal follows everywhere and would
## otherwise mask both; trees and rocks are underfoot everywhere, so they lose.
##
## The key text is read from InputMap, never written down here. Bindings have
## already moved once, and a prompt naming a key that does nothing is worse
## than no prompt.
func _process(delta: float) -> void:
	_prompt_timer -= delta
	if _prompt_timer > 0.0:
		return
	_prompt_timer = Tuning.PROMPT_POLL_INTERVAL
	_set_prompt(_prompt_text())


func _set_prompt(text: String) -> void:
	if text == "":
		if _prompt_panel.visible:
			_fade_prompt(0.0, false)
		return
	_prompt_label.text = text
	if not _prompt_panel.visible:
		_prompt_panel.modulate.a = 0.0
		_prompt_panel.visible = true
		_fade_prompt(1.0, true)


func _fade_prompt(alpha: float, keep_visible: bool) -> void:
	if _prompt_tween:
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_panel, "modulate:a", alpha,
		Tuning.PROMPT_FADE_TIME)
	if not keep_visible:
		_prompt_tween.tween_callback(func() -> void: _prompt_panel.visible = false)


## The one prompt to show, or "" for none. Ranges are the same constants the
## actions themselves check, so a prompt can never appear out of reach.
func _prompt_text() -> String:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return ""
	var here := player.global_position

	for altar in get_tree().get_nodes_in_group("altar"):
		if here.distance_to(altar.global_position) > Tuning.ALTAR_RANGE:
			continue
		return _key_line("interact", "Summon the Mushroom King"
			if Inventory.count("altar_key") > 0 else "The altar wants a key")

	for bench in get_tree().get_nodes_in_group("workbench"):
		if here.distance_to(bench.global_position) <= Tuning.WORKBENCH_RANGE:
			return _key_line("build", "Craft at the workbench")

	# Riding is offered for a caught pal only, and only while on foot: the
	# same key dismounts, and the player already knows they are aboard.
	if player.get("mount") == null:
		for node in get_tree().get_nodes_in_group("pal"):
			var pal := node as Pal
			if pal == null or not pal.caught or not pal.rideable or not pal.visible:
				continue
			if here.distance_to(pal.global_position) <= Tuning.RIDE_MOUNT_DISTANCE:
				return _key_line("ride", "Ride %s" % pal.display_name)

	# Facing matters here and nowhere else, because a punch does: standing
	# beside a tree with your back to it gathers nothing.
	var facing: Vector3 = player.facing()
	for node in get_tree().get_nodes_in_group("resource_node"):
		if not node.is_available():
			continue
		var to_node: Vector3 = node.global_position - here
		to_node.y = 0.0
		if to_node.length() > Tuning.GATHER_RANGE:
			continue
		if to_node.normalized().dot(facing) <= Tuning.GATHER_FACING_DOT:
			continue
		return _key_line("punch", "Gather")

	return ""


func _key_line(action: StringName, what: String) -> String:
	return "%s   %s" % [_key_name(action), what]


## The bound key, and the pad button if the action has one, straight from
## InputMap. The first keyboard event wins; a pad button is appended so a
## controller player is told their own button rather than a key they do not
## have.
## Swell the level label and flash it gold, then settle back.
##
## `pivot_offset` is set from the label's own size each time rather than once
## in _ready: the text is "Lv1" at the start and "Lv10" later, so a pivot
## measured once grows wrong and the label scales off its own corner.
func _pulse_level() -> void:
	_level.pivot_offset = _level.size * 0.5
	var tween := create_tween().set_parallel()
	tween.tween_property(
		_level, "scale", Vector2.ONE * Tuning.LEVEL_PULSE_SCALE,
		Tuning.LEVEL_PULSE_TIME * 0.4
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		_level, "modulate", Tuning.LEVEL_PULSE_COLOUR, Tuning.LEVEL_PULSE_TIME * 0.4
	)
	tween.chain().set_parallel()
	tween.tween_property(
		_level, "scale", Vector2.ONE, Tuning.LEVEL_PULSE_TIME * 0.6
	).set_trans(Tween.TRANS_SINE)
	tween.tween_property(
		_level, "modulate", Color.WHITE, Tuning.LEVEL_PULSE_TIME * 0.6
	)


## Public, because the world's opening hint names keys too and every one of
## them has to come from InputMap rather than a literal.
func key_name(action: StringName) -> String:
	return _key_name(action)


func _key_name(action: StringName) -> String:
	var key := ""
	var pad := ""
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if key == "" and event is InputEventKey:
			key = _key_event_name(event)
		elif key == "" and event is InputEventMouseButton:
			# Some actions are mouse-only: `aim` is right-click and nothing
			# else. Without this the name came back empty and the prompt read
			# "Hold  to aim".
			key = _mouse_button_name(event.button_index)
		elif pad == "" and event is InputEventJoypadButton:
			pad = _pad_button_name(event.button_index)
	if key == "":
		key = pad
		pad = ""
	# Build is keyboard B and pad B, which printed as "B / B" and read as a bug.
	if pad == "" or pad == key:
		return key
	return "%s / %s" % [key, pad]


## Named for the hand, not the API: a player looks for "right click", not for
## BUTTON_RIGHT or an index.
func _mouse_button_name(index: int) -> String:
	match index:
		MOUSE_BUTTON_LEFT:
			return "left click"
		MOUSE_BUTTON_RIGHT:
			return "right click"
		MOUSE_BUTTON_MIDDLE:
			return "middle click"
		_:
			return "mouse %d" % index


## The project binds by physical keycode, so that is what is read. Reporting
## the layout-mapped label instead would need a display server, and this runs
## headless in the tests.
func _key_event_name(event: InputEventKey) -> String:
	var code := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	return OS.get_keycode_string(code)


## The face and shoulder buttons this game binds, named the way the pad has
## them printed rather than by Godot's enum.
func _pad_button_name(index: int) -> String:
	match index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-pad up"
		JOY_BUTTON_DPAD_DOWN: return "D-pad down"
		JOY_BUTTON_DPAD_LEFT: return "D-pad left"
		JOY_BUTTON_DPAD_RIGHT: return "D-pad right"
		_: return "pad %d" % index
