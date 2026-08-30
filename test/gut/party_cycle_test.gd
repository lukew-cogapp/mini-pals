extends GutTest
## Party-cycling assertions, ported from test/party_cycle_test.gd.
##
## Pressing 1 or 3 while riding used to stow the pal out from under the
## player. The rider's own collider is disabled while mounted, so nothing
## was left to stand on and the player fell through the world.
##
## One test function, not three: the checks are stages of a single ride, and
## splitting them would rebuild the world for each.

func test_cycling_the_party_while_mounted_is_survivable() -> void:
	var world: Node = add_child_autofree(load("res://scenes/world.tscn").instantiate())
	await wait_process_frames(1)
	var player = world.get_node("Player")
	await wait_physics_frames(30)

	var wolf = load("res://scenes/pal_wolf.tscn").instantiate()
	var other = load("res://scenes/pal_cactoro.tscn").instantiate()
	world.add_child(wolf)
	world.add_child(other)
	await wait_physics_frames(1)
	player.global_position = Vector3(0, 1, 0)
	wolf.global_position = Vector3(1.2, 0, 0)
	other.global_position = Vector3(-1.2, 0, 0)
	await wait_physics_frames(10)

	wolf.caught = true
	other.caught = true
	Party.members.append(wolf)
	Party.members.append(other)
	Party.active = wolf
	await wait_physics_frames(1)

	player._toggle_ride()
	await wait_physics_frames(1)
	assert_not_null(player.mount, "we are on the pal")

	player._cycle_party(1)
	await wait_physics_frames(90)

	var y: float = player.global_position.y
	assert_true(y > -2.0, "cycling does not drop the player through the world: player y=%.2f" % y)
	assert_null(player.mount, "cycling while mounted steps us off first")
