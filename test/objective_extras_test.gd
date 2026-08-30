extends GutTest
## Headless objective assertions for the cave and the boss outcome.
##
## The cave is optional and last, so it never becomes the row the player is
## told to do next. The King line finishes on either outcome: catching wins,
## defeating leaves the crown, and without the second case a player who
## killed him keeps a permanent unfinished row on a fight needing a new key.
##
## One test function, not several: each stage adds to the inventory the
## previous stage left behind, which is what the chain reads.

var _world: Node


## Inventory outlives a single suite now that every test shares one process,
## so a glow cap or crown another script gathered would read here as progress
## this test never made.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(5)
	Inventory._counts.clear()


func after_all() -> void:
	_world.free()


func _find(chain, needle):
	for c in chain:
		if needle in c.text:
			return c
	return null


func test_the_cave_and_the_king_rows() -> void:
	var chain = Hud._objective_chain()
	var cave = _find(chain, "cave")
	var king = _find(chain, "Mushroom King")
	assert_not_null(cave, "the cave is an objective: rows=%d" % chain.size())
	assert_false(cave.done, "the cave starts undone")
	assert_true(
		king != null and "Catch" in king.text,
		"the king row starts as catch, not defeat: text=%s" % (king.text if king else "<none>"),
	)

	Inventory.add(Tuning.OBJECTIVE_CAVE_ITEM, 1)
	cave = _find(Hud._objective_chain(), "cave")
	assert_true(cave != null and cave.done, "a glow cap ticks the cave")

	Inventory.add(Tuning.OBJECTIVE_CROWN_ITEM, 1)
	king = _find(Hud._objective_chain(), "Mushroom King")
	assert_true(
		king != null and king.done,
		"the crown finishes the king line: text=%s" % (king.text if king else "<none>"),
	)
	assert_true(
		king != null and "Defeated" in king.text,
		"and it says defeated, not caught: text=%s" % (king.text if king else "<none>"),
	)
