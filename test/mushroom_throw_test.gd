extends GutTest
## Headless mushroom-throw assertions.
##
## The King's job is free throws, so what leaves your hand while he is out is
## one of his mushrooms rather than a crafted cube. Both meshes live in the
## scene and throw() picks one: a runtime load would stutter the first throw.
##
## Summoning the King is a precondition for the mushroom cases rather than a
## case of its own, so it happens inside them: a test that depends on the
## order the previous one left the party in breaks the moment either moves.

var _world: Node


## Party outlives a single suite now that every test shares one process, so a
## pal another script left active would read here as the King already out.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(10)


func before_each() -> void:
	Party.members.clear()
	Party.active = null


func after_all() -> void:
	Party.members.clear()
	Party.active = null
	_world.free()


func _thrown_cube() -> Node3D:
	var cube: Node3D = load("res://scenes/pal_cube.tscn").instantiate()
	_world.add_child(cube)
	await wait_physics_frames(1)
	cube.throw(Vector3(0, 5, 0), Vector3.ZERO)
	await wait_physics_frames(1)
	return cube


## Stores the King in the party and returns him, active.
func _summon_king() -> Node3D:
	var king: Node3D = load("res://scenes/pal_boss.tscn").instantiate()
	_world.add_child(king)
	await wait_physics_frames(1)
	king.level = Tuning.BOSS_LEVEL
	king.caught = true
	Party.store(king)
	await wait_physics_frames(1)
	return king


func test_without_the_king_a_cube_is_thrown() -> void:
	var cube := await _thrown_cube()
	assert_true(
		cube._cube.visible and not cube._mushroom.visible,
		(
			"without the King a cube is thrown: cube=%s mushroom=%s"
			% [cube._cube.visible, cube._mushroom.visible]
		),
	)
	cube.queue_free()


func test_the_king_counts_as_out() -> void:
	await _summon_king()
	assert_true(
		Party.infinite_cubes(),
		(
			"the King counts as out: active=%s"
			% (Party.active.display_name if Party.active else "<none>")
		),
	)


func test_with_the_king_out_a_mushroom_is_thrown() -> void:
	await _summon_king()
	var cube := await _thrown_cube()
	assert_true(
		cube._mushroom.visible and not cube._cube.visible,
		(
			"with the King out a mushroom is thrown: cube=%s mushroom=%s"
			% [cube._cube.visible, cube._mushroom.visible]
		),
	)
	assert_eq(
		cube._mesh,
		cube._mushroom,
		"the pop tween scales the mushroom, not the cube: mesh=%s" % cube._mesh.name,
	)
	cube.queue_free()
