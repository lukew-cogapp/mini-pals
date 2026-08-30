extends GutTest
## Cube-catch assertions, ported from test/cube_hit_test.gd.
##
## Throws are lobs, so a throw the player reads as on target often lands a
## step short. The sweep used to be a zero-radius ray and the landing had no
## grab at all, so those visibly-close throws counted as misses.

var _world: Node


func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(10)


func after_all() -> void:
	_world.free()


func _drop(name: String, offset: Vector3, want_hit: bool) -> void:
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	_world.add_child(pal)
	await wait_physics_frames(1)
	pal.global_position = Vector3(0, 0, -20)
	pal.set_physics_process(false)
	await wait_physics_frames(1)

	var cube = load("res://scenes/pal_cube.tscn").instantiate()
	_world.add_child(cube)
	var got := [false]
	cube.resolved.connect(func(p, _ok): got[0] = (p == pal))
	# Dropped from above, so only the landing logic decides it.
	cube.throw(pal.global_position + offset + Vector3.UP * 5.0, Vector3.ZERO)

	for i in 200:
		await wait_physics_frames(1)
		if not is_instance_valid(cube):
			break

	assert_true(
		got[0] == want_hit,
		"%s -> %s hit=%s wanted=%s"
		% [name, "caught" if want_hit else "missed", got[0], want_hit],
	)
	if is_instance_valid(pal):
		pal.queue_free()
	await wait_physics_frames(1)


func test_lands_a_step_to_the_side() -> void:
	# Straight down beside a pal: the old ray never touched its capsule.
	await _drop("lands a step to the side", Vector3(1.1, 0, 0), true)


func test_lands_right_on_it() -> void:
	await _drop("lands right on it", Vector3(0.0, 0, 0), true)


func test_lands_well_away() -> void:
	await _drop("lands well away", Vector3(6.0, 0, 0), false)
