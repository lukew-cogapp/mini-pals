extends GutTest
## The shallows, ported from test/water_test.gd.
##
## The shore wall gates them, a swimmer opens it, and fish stay out of a
## walker's reach.
##
## One world, shared across the whole script, and the tests run in order: the
## later ones mount and dismount and depend on the wall state the earlier ones
## left. Keep the order.

var _world
var _player


## Freed in after_all, not by add_child_autofree, which frees at the end of
## the test that called it rather than at the end of the script. free, not
## queue_free: GUT counts children still parented when the script ends.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	_player = _world.get_node("Player")
	await wait_physics_frames(20)


func after_all() -> void:
	_world.free()


func _radius(node) -> float:
	return Vector2(node.global_position.x, node.global_position.z).length()


## The gate is arithmetic, not a rule: a cube aimed from the shore wall
## reaches SHORE_WALL_RADIUS + CUBE_AIM_DISTANCE, and every fish starts
## beyond that. Retuning any of the three would otherwise reopen it.
func test_fish_spawn_beyond_throw_range() -> void:
	var reach = Tuning.SHORE_WALL_RADIUS + Tuning.CUBE_AIM_DISTANCE
	assert_true(
		Tuning.FISH_RING_MIN - Tuning.SHORE_WALL_RADIUS > Tuning.CUBE_AIM_DISTANCE,
		(
			"closest possible fish spawn is beyond throw range of the sand  fish_ring_min=%.1f shore_wall=%.1f aim=%.1f reach=%.1f"
			% [
				Tuning.FISH_RING_MIN,
				Tuning.SHORE_WALL_RADIUS,
				Tuning.CUBE_AIM_DISTANCE,
				reach,
			]
		),
	)
	# The band must also be wide enough that fish are not pinned to the far
	# wall, which is what reads as "they hug the edge" in play.
	assert_true(
		Tuning.FISH_RING_MAX - Tuning.FISH_RING_MIN >= 20.0,
		(
			"fish band is wide enough to swim in  band=%.1f..%.1f width=%.1f"
			% [
				Tuning.FISH_RING_MIN,
				Tuning.FISH_RING_MAX,
				Tuning.FISH_RING_MAX - Tuning.FISH_RING_MIN,
			]
		),
	)
	assert_true(
		Tuning.FISH_RING_MAX < Tuning.SHALLOW_WALL_RADIUS,
		(
			"the fish band fits inside the shallow wall  fish_max=%.1f shallow_wall=%.1f"
			% [Tuning.FISH_RING_MAX, Tuning.SHALLOW_WALL_RADIUS]
		),
	)


## Walk outward off the beach. On foot the shore wall must hold.
func test_walker_stopped_at_shore_wall() -> void:
	var angle := TAU / 48.0
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	_player.global_position = radial * (Tuning.SHORE_WALL_RADIUS - 3.0) + Vector3.UP
	_player.velocity = Vector3.ZERO
	var pivot = _player.get_node("CameraPivot")
	pivot.rotation = Vector3(0.0, atan2(radial.x, radial.z), 0.0)

	Input.action_press("move_back")
	await wait_physics_frames(200)
	Input.action_release("move_back")

	var r := _radius(_player)
	assert_true(
		r < Tuning.SHORE_WALL_RADIUS + 1.0,
		(
			"a walker on foot is stopped at the shore wall  radius=%.2f shore_wall=%.2f"
			% [r, Tuning.SHORE_WALL_RADIUS]
		),
	)


func _mount_swimmer(at_radius: float, angle: float):
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var pal = load("res://scenes/pal_mudwader.tscn").instantiate()
	_world.add_child(pal)
	await wait_process_frames(1)
	pal.global_position = radial * at_radius + Vector3.UP
	pal.velocity = Vector3.ZERO
	pal.caught = true
	pal.state = pal.State.RIDDEN
	_player.global_position = pal.seat_position()
	_player.velocity = Vector3.ZERO
	_player.mount = pal
	_player._set_collision_enabled(false)
	_player._set_shore_wall_enabled(not pal.swimmer)
	var pivot = _player.get_node("CameraPivot")
	pivot.rotation = Vector3(0.0, atan2(radial.x, radial.z), 0.0)
	# The wall's shapes are disabled deferred, so give physics a frame.
	await wait_physics_frames(1)
	return pal


func _release_mount(pal) -> void:
	if _player.mount:
		_player.mount = null
	_player._set_collision_enabled(true)
	_player._set_shore_wall_enabled(true)
	if is_instance_valid(pal):
		pal.queue_free()
	await wait_physics_frames(1)


func test_rider_passes_shore_wall() -> void:
	var pal = await _mount_swimmer(Tuning.SHORE_WALL_RADIUS - 3.0, 0.3)
	assert_true(
		pal.swimmer and pal.rideable,
		(
			"the mudwader is a swimmer and rideable  swimmer=%s rideable=%s"
			% [pal.swimmer, pal.rideable]
		),
	)

	Input.action_press("move_back")
	await wait_physics_frames(200)
	Input.action_release("move_back")

	var r := _radius(pal)
	assert_true(
		r > Tuning.SHORE_WALL_RADIUS + 3.0,
		(
			"a player riding a swimmer passes the shore wall  radius=%.2f shore_wall=%.2f"
			% [r, Tuning.SHORE_WALL_RADIUS]
		),
	)
	await _release_mount(pal)


func test_rider_stopped_at_shallow_wall() -> void:
	var pal = await _mount_swimmer(Tuning.SHALLOW_WALL_RADIUS - 6.0, 1.1)

	Input.action_press("move_back")
	await wait_physics_frames(300)
	Input.action_release("move_back")

	var r := _radius(pal)
	assert_true(
		r < Tuning.SHALLOW_WALL_RADIUS + 1.0,
		(
			"a player riding a swimmer is stopped at the shallow wall  radius=%.2f shallow_wall=%.2f"
			% [r, Tuning.SHALLOW_WALL_RADIUS]
		),
	)
	await _release_mount(pal)


## Many wander cycles, with the idle timer forced short so the fish keeps
## picking new targets rather than standing about for the whole run.
func test_fish_never_leaves_the_shallows() -> void:
	var fish = []
	for node in get_tree().get_nodes_in_group("pal"):
		if node.water_only:
			fish.append(node)
	assert_true(fish.size() > 0, "fish were spawned into the world  found=%d" % fish.size())
	if fish.is_empty():
		return

	var zone_script = load("res://scripts/zone.gd")
	var space = (_world as Node3D).get_world_3d()

	var spawn_ok := true
	var spawn_detail := ""
	for f in fish:
		var r = Vector2(f.global_position.x, f.global_position.z).length()
		if r < Tuning.FISH_RING_MIN - 0.5 or r > Tuning.FISH_RING_MAX + 0.5:
			spawn_ok = false
			spawn_detail = (
				"radius=%.2f band=%.1f..%.1f"
				% [r, Tuning.FISH_RING_MIN, Tuning.FISH_RING_MAX]
			)
	assert_true(spawn_ok, "every fish spawns inside its band  %s" % spawn_detail)

	var worst_in := 1e9
	var worst_out := 0.0
	var left_shallow := 0
	for cycle in 40:
		for f in fish:
			f._enter_wander()
		await wait_physics_frames(30)
		for f in fish:
			var r = Vector2(f.global_position.x, f.global_position.z).length()
			worst_in = minf(worst_in, r)
			worst_out = maxf(worst_out, r)
			if not zone_script.is_inside(space, f.global_position, zone_script.Kind.SHALLOW):
				left_shallow += 1

	assert_true(
		left_shallow == 0,
		(
			"a fish never leaves the shallow zone across many wander cycles  escapes=%d closest=%.2f furthest=%.2f"
			% [left_shallow, worst_in, worst_out]
		),
	)
	assert_true(
		worst_in > Tuning.SHORE_WALL_RADIUS + Tuning.CUBE_AIM_DISTANCE,
		(
			"a wandering fish never comes within throw range of the shore  closest=%.2f reach=%.2f"
			% [worst_in, Tuning.SHORE_WALL_RADIUS + Tuning.CUBE_AIM_DISTANCE]
		),
	)


func test_dismount_in_shallows_lands_on_land() -> void:
	var angle := 2.0
	var pal = await _mount_swimmer(Tuning.SHORE_WALL_RADIUS + 25.0, angle)
	var zone_script = load("res://scripts/zone.gd")
	var space = (_world as Node3D).get_world_3d()

	var before := _radius(pal)
	var dismounted = _player._dismount()
	var r := _radius(_player)
	var on_land = zone_script.is_inside(space, _player.global_position, zone_script.Kind.LAND)
	assert_true(
		dismounted and on_land and r < Tuning.SHORE_WALL_RADIUS,
		(
			"dismounting in the shallows puts the player on land  dismounted=%s on_land=%s radius=%.2f mount_radius=%.2f"
			% [dismounted, on_land, r, before]
		),
	)
	assert_true(
		not zone_script.is_inside(space, _player.global_position, zone_script.Kind.SHALLOW),
		"the dismount landing is not in water  radius=%.2f" % r,
	)
	await _release_mount(pal)


## The wall must come back, or one ride would open the shallows for good.
func test_shore_wall_restored_after_dismount() -> void:
	var pal = await _mount_swimmer(Tuning.SHORE_WALL_RADIUS - 4.0, 3.0)
	var wall = _world.find_child("ShoreWall", true, false)
	assert_not_null(wall, "the island built a ShoreWall")
	if wall == null:
		await _release_mount(pal)
		return

	var disabled_while_riding := true
	for child in wall.get_children():
		if child is CollisionShape3D and not child.disabled:
			disabled_while_riding = false
	assert_true(
		disabled_while_riding,
		(
			"the shore wall is down while riding a swimmer  segments=%d"
			% wall.get_child_count()
		),
	)

	_player._dismount(true)
	await wait_physics_frames(1)
	var restored := true
	for child in wall.get_children():
		if child is CollisionShape3D and child.disabled:
			restored = false
	assert_true(restored, "the shore wall collision is restored after dismount")

	# And it actually stops a walker again, not just on paper.
	var radial := Vector3(cos(3.0), 0.0, sin(3.0))
	_player.global_position = radial * (Tuning.SHORE_WALL_RADIUS - 3.0) + Vector3.UP
	_player.velocity = Vector3.ZERO
	var pivot = _player.get_node("CameraPivot")
	pivot.rotation = Vector3(0.0, atan2(radial.x, radial.z), 0.0)
	Input.action_press("move_back")
	await wait_physics_frames(200)
	Input.action_release("move_back")
	var r := _radius(_player)
	assert_true(
		r < Tuning.SHORE_WALL_RADIUS + 1.0,
		"after dismount the restored wall still stops a walker  radius=%.2f" % r,
	)
	await _release_mount(pal)
