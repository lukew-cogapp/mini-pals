extends GutTest
## Party assertions, ported from test/party_store_test.gd.
##
## A caught pal that is freed elsewhere does not remove itself from
## Party.members, so store() read display_name off a freed object and threw.
## It surfaced as an intermittent failure in unrelated suites.

var _world: Node


## Freed in after_all, not by add_child_autofree, which frees at the end of
## the test that called it rather than at the end of the script. free, not
## queue_free: GUT counts children still parented when the script ends.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(10)


func after_all() -> void:
	_world.free()


func test_storing_a_pal_survives_a_freed_member() -> void:
	var doomed = load("res://scenes/pal_wolf.tscn").instantiate()
	_world.add_child(doomed)
	await wait_physics_frames(1)
	doomed.caught = true
	Party.members.append(doomed)

	# Free it behind the party's back, as a death elsewhere would.
	doomed.free()
	await wait_physics_frames(1)

	var fresh = load("res://scenes/pal_cactoro.tscn").instantiate()
	_world.add_child(fresh)
	await wait_physics_frames(1)
	fresh.caught = true
	Party.store(fresh)
	await wait_physics_frames(1)

	assert_true(
		fresh in Party.members,
		"storing a pal survives a freed member members=%d" % Party.members.size(),
	)
	assert_true(
		Party.members.all(func(p): return is_instance_valid(p)),
		"the freed member is gone from the party members=%d" % Party.members.size(),
	)
