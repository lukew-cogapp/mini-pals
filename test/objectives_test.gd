extends SceneTree
## Headless assertions for the top-right objectives panel. Run:
##   godot --headless --path . -s test/objectives_test.gd
##
## The panel is derived from live state, not stored progress, so every check
## here drives real Inventory / Party calls and reads the rows back.

var _fails := 0
var _hud
var _inv
var _party


func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	for i in 5:
		await physics_frame
	_hud = get_root().get_node("Hud")
	_inv = get_root().get_node("Inventory")
	_party = get_root().get_node("Party")

	# The world spawns pals, so start from a party the test controls.
	_party.members.clear()
	_party.active = null
	_party.player_level = 1
	_inv.changed.emit()
	await process_frame

	_check("a fresh game asks for catches first",
		_current() == "Catch pals 0/%d" % Tuning.OBJECTIVE_CATCH_TARGET,
		"current=%s" % _current())
	_check("the first row is the live one, not a tick",
		_rows()[0].begins_with(_hud.MARK_NOW), "row0=%s" % _rows()[0])

	# Catching enough pals advances past the first link in the chain.
	for i in Tuning.OBJECTIVE_CATCH_TARGET:
		_party.members.append(_fake_pal("Filler %d" % i))
	_party.changed.emit()
	await process_frame
	_check("catching the target advances to the level objective",
		_current() == "Reach level %d (Lv1)" % Tuning.KEY_UNLOCK_LEVEL,
		"current=%s" % _current())
	_check("the cleared catch objective is ticked above it",
		_rows()[0].begins_with(_hud.MARK_DONE), "row0=%s" % _rows()[0])

	# Reaching KEY_UNLOCK_LEVEL changes what is shown to the key materials.
	_party.player_level = Tuning.KEY_UNLOCK_LEVEL
	_party.changed.emit()
	await process_frame
	var first_item: String = Tuning.KEY_RECIPE.keys()[0]
	var need: int = Tuning.KEY_RECIPE[first_item]
	_check("reaching the unlock level moves on to the key materials",
		_current() == "%s 0/%d" % [_hud._item_name(first_item), need],
		"current=%s" % _current())

	# Gathering advances within a material and then past it. The exact string
	# matters: this is the panel's only report of real counts.
	_inv.add(first_item, 1)
	await process_frame
	_check("a partial gather shows the real count",
		_current() == "%s 1/%d" % [_hud._item_name(first_item), need],
		"current=%s" % _current())
	_inv.add(first_item, need - 1)
	await process_frame
	_check("a finished material advances the chain",
		_current() != "%s %d/%d" % [_hud._item_name(first_item), need, need],
		"current=%s" % _current())

	# Every key material, so the next objective is the craft.
	for item in Tuning.KEY_RECIPE:
		var short: int = Tuning.KEY_RECIPE[item] - _inv.count(item)
		if short > 0:
			_inv.add(item, short)
	await process_frame
	_check("all materials held asks for the craft",
		_current() == "Craft the Altar Key at the bench", "current=%s" % _current())

	# Crafting: the key in hand, materials spent, exactly as the bench does it.
	for item in Tuning.KEY_RECIPE:
		_inv.remove(item, Tuning.KEY_RECIPE[item])
	_inv.add("altar_key", 1)
	await process_frame
	_check("holding a key advances to the altar",
		_current() == "Use the key at the altar (R)", "current=%s" % _current())
	_check("the craft stays ticked once the materials are spent",
		_rows()[-2].begins_with(_hud.MARK_DONE), "rows=%s" % str(_rows()))

	# Catching the boss is the win, and the last objective.
	_party.members.append(_fake_pal(_hud.BOSS_NAME))
	_party.changed.emit()
	await process_frame
	_check("catching the King finishes the chain",
		_current() == "Catch the Mushroom King" and _rows()[-1].begins_with(_hud.MARK_DONE),
		"rows=%s" % str(_rows()))

	_check("the panel never exceeds its row cap",
		_rows().size() <= Tuning.OBJECTIVE_ROWS_MAX,
		"visible=%d cap=%d" % [_rows().size(), Tuning.OBJECTIVE_ROWS_MAX])

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


## The visible row texts, top to bottom.
func _rows() -> Array[String]:
	var out: Array[String] = []
	for row in _hud._objectives.get_children():
		if row.visible:
			out.append(row.text)
	return out


## The text of the last row, which is always the live objective: the window
## shows finished objectives above the current one and nothing below it.
func _current() -> String:
	var rows := _rows()
	if rows.is_empty():
		return ""
	return rows[-1].substr(2)


## A real Pal, because Party.members is typed Array[Pal]. Untyped and loaded
## at runtime: naming Pal here would compile pal.gd before the autoloads it
## references have registered (see CLAUDE.md).
func _fake_pal(pal_name: String):
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	pal.display_name = pal_name
	get_root().add_child(pal)
	return pal


func _check(check_name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", check_name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", check_name, "  ", detail)
