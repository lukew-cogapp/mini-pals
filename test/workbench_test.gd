extends SceneTree
## Headless workbench assertions. Run:
##   godot --headless --path . -s test/workbench_test.gd
##
## One bench on a 110 m island meant walking back across the map to spend
## what you gathered. These pin that the authored set is present, reachable,
## clear of the scorched ground, and spread far enough that B is never
## ambiguous between two.

var _fails := 0

func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	var tuning = get_root().get_node("Tuning")
	for i in 10:
		await physics_frame

	var benches = get_nodes_in_group("workbench")
	_check("every authored bench is in the world",
		benches.size() == tuning.WORKBENCH_POSITIONS.size(),
		"found=%d want=%d" % [benches.size(), tuning.WORKBENCH_POSITIONS.size()])

	var worst_land := 0.0
	var in_ash := 0
	for b in benches:
		var r = Vector2(b.global_position.x, b.global_position.z).length()
		worst_land = maxf(worst_land, r)
		if Zone.is_inside(world.get_world_3d(), b.global_position, Zone.Kind.ASH):
			in_ash += 1
	_check("no bench is out past the shore wall", worst_land < tuning.SHORE_WALL_RADIUS,
		"furthest=%.1f wall=%.1f" % [worst_land, tuning.SHORE_WALL_RADIUS])
	_check("no bench sits on the scorched ground", in_ash == 0, "in_ash=%d" % in_ash)

	# Two benches close enough to both be in range would make B ambiguous.
	var closest := 9999.0
	for i in benches.size():
		for j in range(i + 1, benches.size()):
			closest = minf(closest, benches[i].global_position.distance_to(benches[j].global_position))
	_check("benches are not on top of each other", closest > tuning.WORKBENCH_RANGE * 3.0,
		"closest pair=%.1f range=%.1f" % [closest, tuning.WORKBENCH_RANGE])

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)
