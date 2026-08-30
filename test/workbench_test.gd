extends GutTest
## Headless workbench assertions.
##
## One bench on a 110 m island meant walking back across the map to spend
## what you gathered. These pin that the authored set is present, reachable,
## clear of the scorched ground, and spread far enough that B is never
## ambiguous between two.

var _world: Node


## Freed in after_all with free rather than by add_child_autofree, which frees
## at the end of the test that called it and would leave later tests reading a
## dead world.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(10)


func after_all() -> void:
	_world.free()


func _benches() -> Array:
	return get_tree().get_nodes_in_group("workbench")


func test_every_authored_bench_is_in_the_world() -> void:
	assert_eq(
		_benches().size(),
		Tuning.WORKBENCH_POSITIONS.size(),
		"every authored bench is in the world",
	)


func test_no_bench_is_out_past_the_shore_wall() -> void:
	var worst_land := 0.0
	for b in _benches():
		var r := Vector2(b.global_position.x, b.global_position.z).length()
		worst_land = maxf(worst_land, r)
	assert_true(
		worst_land < Tuning.SHORE_WALL_RADIUS,
		(
			"no bench is out past the shore wall: furthest=%.1f wall=%.1f"
			% [worst_land, Tuning.SHORE_WALL_RADIUS]
		),
	)


func test_no_bench_sits_on_the_scorched_ground() -> void:
	var in_ash := 0
	for b in _benches():
		if Zone.is_inside(_world.get_world_3d(), b.global_position, Zone.Kind.ASH):
			in_ash += 1
	assert_eq(in_ash, 0, "no bench sits on the scorched ground")


## Two benches close enough to both be in range would make B ambiguous.
func test_benches_are_not_on_top_of_each_other() -> void:
	var benches := _benches()
	var closest := 9999.0
	for i in benches.size():
		for j in range(i + 1, benches.size()):
			closest = minf(
				closest, benches[i].global_position.distance_to(benches[j].global_position)
			)
	assert_true(
		closest > Tuning.WORKBENCH_RANGE * 3.0,
		(
			"benches are not on top of each other: closest pair=%.1f range=%.1f"
			% [closest, Tuning.WORKBENCH_RANGE]
		),
	)
