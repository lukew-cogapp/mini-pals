extends SceneTree
## Headless objective assertions for the cave and the boss outcome. Run:
##   godot --headless --path . -s test/objective_extras_test.gd
##
## The cave is optional and last, so it never becomes the row the player is
## told to do next. The King line finishes on either outcome: catching wins,
## defeating leaves the crown, and without the second case a player who
## killed him keeps a permanent unfinished row on a fight needing a new key.

var _fails := 0

func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	var hud = get_root().get_node("Hud")
	var inv = get_root().get_node("Inventory")
	var tuning = get_root().get_node("Tuning")
	for i in 5:
		await physics_frame

	inv.items().clear()
	var chain = hud._objective_chain()
	var texts := []
	for c in chain:
		texts.append(c.text)
	var cave = _find(chain, "cave")
	var king = _find(chain, "Mushroom King")
	_check("the cave is an objective", cave != null, "rows=%d" % chain.size())
	_check("the cave starts undone", cave != null and not cave.done, "")
	_check("the king row starts as catch, not defeat",
		king != null and "Catch" in king.text, "text=%s" % (king.text if king else "<none>"))

	inv.add(tuning.OBJECTIVE_CAVE_ITEM, 1)
	cave = _find(hud._objective_chain(), "cave")
	_check("a glow cap ticks the cave", cave != null and cave.done, "")

	inv.add(tuning.OBJECTIVE_CROWN_ITEM, 1)
	king = _find(hud._objective_chain(), "Mushroom King")
	_check("the crown finishes the king line", king != null and king.done,
		"text=%s" % (king.text if king else "<none>"))
	_check("and it says defeated, not caught",
		king != null and "Defeated" in king.text, "text=%s" % (king.text if king else "<none>"))

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _find(chain, needle):
	for c in chain:
		if needle in c.text:
			return c
	return null


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)
