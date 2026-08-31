extends GutTest
## Headless assertions for the top-right objectives panel, ported from
## test/objectives_test.gd.
##
## The panel is derived from live state, not stored progress, so every check
## here drives real Inventory / Party calls and reads the rows back.
##
## One test function, not several: each stage builds on the party and
## inventory state the previous stage left behind.

var _world: Node
var _hud
var _inv
var _party
var _fake_pals: Array = []


func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(5)
	_hud = Hud
	_inv = Inventory
	_party = Party
	# The autoloads outlive a single suite now that every test shares one
	# process, so anything an earlier script gathered would be read here as
	# progress this test never made. The panel reports real counts, so a
	# stray pelt shows up as 1/3 rather than 0/3.
	_inv._counts.clear()
	_inv._counts["cube"] = Tuning.STARTING_CUBES


func after_all() -> void:
	for pal in _fake_pals:
		pal.free()
	_world.free()


func test_objective_chain_advances_stage_by_stage() -> void:
	# The world spawns pals, so start from a party the test controls.
	_party.members.clear()
	_party.active = null
	_party.player_level = 1
	_inv.changed.emit()
	await wait_process_frames(1)

	assert_eq(
		_current(),
		"Catch pals 0/%d" % Tuning.OBJECTIVE_CATCH_TARGET,
		"a fresh game asks for catches first",
	)
	assert_true(
		_rows()[0].begins_with(_hud.MARK_NOW),
		"the first row is the live one, not a tick: row0=%s" % _rows()[0],
	)

	# Catching enough pals advances past the first link in the chain.
	for i in Tuning.OBJECTIVE_CATCH_TARGET:
		_party.members.append(_fake_pal("Filler %d" % i))
	_party.changed.emit()
	await wait_process_frames(1)
	assert_eq(
		_current(),
		"Reach level %d (Lv1)" % Tuning.KEY_UNLOCK_LEVEL,
		"catching the target advances to the level objective",
	)
	assert_true(
		_rows()[0].begins_with(_hud.MARK_DONE),
		"the cleared catch objective is ticked above it: row0=%s" % _rows()[0],
	)

	# Reaching KEY_UNLOCK_LEVEL changes what is shown to the key materials.
	_party.player_level = Tuning.KEY_UNLOCK_LEVEL
	_party.changed.emit()
	await wait_process_frames(1)
	var first_item: String = Tuning.KEY_RECIPE.keys()[0]
	var need: int = Tuning.KEY_RECIPE[first_item]
	assert_eq(
		_current(),
		"%s 0/%d" % [_hud._item_name(first_item), need],
		"reaching the unlock level moves on to the key materials",
	)

	# Gathering advances within a material and then past it. The exact string
	# matters: this is the panel's only report of real counts.
	_inv.add(first_item, 1)
	await wait_process_frames(1)
	assert_eq(
		_current(),
		"%s 1/%d" % [_hud._item_name(first_item), need],
		"a partial gather shows the real count",
	)
	_inv.add(first_item, need - 1)
	await wait_process_frames(1)
	assert_ne(
		_current(),
		"%s %d/%d" % [_hud._item_name(first_item), need, need],
		"a finished material advances the chain",
	)

	# Every key material, so the next objective is the craft.
	for item in Tuning.KEY_RECIPE:
		var short: int = Tuning.KEY_RECIPE[item] - _inv.count(item)
		if short > 0:
			_inv.add(item, short)
	await wait_process_frames(1)
	assert_eq(
		_current(), "Craft the Altar Key at the bench", "all materials held asks for the craft"
	)

	# Crafting: the key in hand, materials spent, exactly as the bench does it.
	for item in Tuning.KEY_RECIPE:
		_inv.remove(item, Tuning.KEY_RECIPE[item])
	_inv.add("altar_key", 1)
	await wait_process_frames(1)
	assert_eq(
		# Built from InputMap, not spelled out: the row names whatever
		# `interact` is bound to, and it carries the pad button too.
		_current(),
		"Use the key at the altar (%s)" % Hud.key_name("interact"),
		"holding a key advances to the altar",
	)
	assert_true(
		_rows()[-2].begins_with(_hud.MARK_DONE),
		"the craft stays ticked once the materials are spent: rows=%s" % str(_rows()),
	)

	# Catching the boss is the win and the last REQUIRED objective. The cave
	# is optional and sits after it, so it may still show unfinished; what
	# matters is that the King himself is ticked and is no longer what the
	# player is being told to do.
	_party.members.append(_fake_pal(_hud.BOSS_NAME))
	_party.changed.emit()
	await wait_process_frames(1)
	var king_row := ""
	for row in _rows():
		if "Mushroom King" in row:
			king_row = row
	assert_true(
		king_row.begins_with(_hud.MARK_DONE),
		"catching the King ticks its row: rows=%s" % str(_rows()),
	)
	assert_ne(
		_current(), "Catch the Mushroom King",
		"the King is no longer the current objective once caught",
	)

	assert_true(
		_rows().size() <= Tuning.OBJECTIVE_ROWS_MAX,
		(
			"the panel never exceeds its row cap: visible=%d cap=%d"
			% [_rows().size(), Tuning.OBJECTIVE_ROWS_MAX]
		),
	)


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
	add_child(pal)
	_fake_pals.append(pal)
	return pal
