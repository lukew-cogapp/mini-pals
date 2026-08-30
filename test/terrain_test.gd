extends GutTest
## Hill, cave and cave-species assertions, ported from the old SceneTree suite.
##
## The hills are hand-placed mounds on top of the island's flat plane, so the
## things worth pinning are the ones inspection cannot answer: that the
## surface a raycast finds is the surface the placement maths promised, that
## the player can get up a hill and in and out of the cave, and that props
## scattered onto a hillside sit on it rather than in it or over it.

var _world: Node3D
var _player: CharacterBody3D
var _terrain: Node3D
var _cave_rids: Array[RID] = []


## GUT shares one process, so an earlier suite's leftovers arrive here. An
## active pal is the one that would actually change an answer: the walking
## tests drive the player for a fixed number of frames, and a leaked speed
## buff moves them further in the same time.
func before_all() -> void:
	Party.members.clear()
	Party.active = null
	Party.player_level = 1

	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	_player = _world.get_node("Player")
	_terrain = _world.get_node("Terrain")
	await wait_physics_frames(20)


## free, not queue_free: GUT counts children still parented when the script
## ends.
func after_all() -> void:
	_world.free()


## The ground under a point, as the physics server sees it. Everything that
## has to agree with `Terrain.height_at` is checked against this rather than
## against the maths again, so a mesh built from the wrong numbers cannot
## pass by being consistently wrong.
func _ground_under(x: float, z: float, skip: Array[RID] = []) -> float:
	var from := Vector3(x, 60.0, z)
	var to := Vector3(x, -20.0, z)
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
	var exclude: Array[RID] = [_player.get_rid()]
	exclude.append_array(skip)
	ray.exclude = exclude
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return -999.0
	return (hit.position as Vector3).y


func test_hills_exist_and_have_relief() -> void:
	var built := 0
	for child in _terrain.get_children():
		if child.name.begins_with("Hill") and child is CSGShape3D:
			built += 1
	assert_eq(
		built,
		Tuning.HILLS.size(),
		"a CSG solid per authored hill  solids=%d hills=%d" % [built, Tuning.HILLS.size()],
	)

	# The point of the whole change: the island must not be flat any more.
	var tallest := 0.0
	for hill in Tuning.HILLS:
		tallest = maxf(tallest, Terrain.height_at(hill[0], hill[1]) as float)
	assert_true(
		tallest > Tuning.STEP_HEIGHT * 4.0,
		(
			"the island has real relief  tallest summit %.2f m, step height %.2f"
			% [tallest, Tuning.STEP_HEIGHT]
		),
	)


## The drawn hill, the collider and the arithmetic must be one surface. This
## is the assertion that catches a mesh built from stale numbers.
func test_height_matches_a_raycast() -> void:
	var worst := 0.0
	var worst_at := Vector3.ZERO
	for hill in Tuning.HILLS:
		# Summit, mid-slope in four directions, and just outside the rim.
		var samples: Array[Vector2] = [Vector2.ZERO]
		for k in 4:
			var a := TAU * k / 4.0
			var r: float = hill[2]
			samples.append(Vector2(cos(a), sin(a)) * r * 0.5)
			samples.append(Vector2(cos(a), sin(a)) * r * 1.2)
		for s in samples:
			var x: float = hill[0] + s.x
			var z: float = hill[1] + s.y
			var want := Terrain.height_at(x, z)
			# The cave, its boulders and the scattered props are all real
			# geometry standing on this hill, and a ray fired down through
			# them is supposed to stop on them. Excluding them asks the
			# question this assertion is actually about: does the hill
			# surface match the maths.
			var got := _ground_under(x, z, _obstacles())
			# Off the rim the flat plane answers, which is height 0 too.
			var off := absf(got - want)
			if off > worst:
				worst = off
				worst_at = Vector3(x, want, z)
	assert_true(
		worst < 0.25,
		(
			"the collider surface matches Terrain.height_at  worst mismatch %.3f m near %s"
			% [worst, worst_at]
		),
	)


## Every physics body standing ON the ground rather than being it: the cave's
## slabs and mouth boulders, and every scattered tree and rock. Cached after
## the first walk, since the hill sampler asks once per sample point.
##
## The scenery matters as much as the cave. A sample point that happens to
## land on a trunk reads the trunk's top as the ground and the assertion
## fails on a hill that is perfectly correct, which is exactly what a
## reshuffled hill layout turned up here.
func _obstacles() -> Array[RID]:
	if not _cave_rids.is_empty():
		return _cave_rids
	var roots: Array[Node] = [_world.get_node("Scenery")]
	var cave: Node = _terrain.get_node_or_null("Cave")
	if cave != null:
		roots.append(cave)
	for root in roots:
		for node in _walk(root):
			var body := node as PhysicsBody3D
			if body:
				_cave_rids.append(body.get_rid())
	return _cave_rids


## Drive the player up the tallest hill under its own physics. A slope the
## controller refuses is a hill nobody can use, and the step-up probe in
## player.gd was written for a flat world.
func test_player_walks_up_a_hill() -> void:
	var hill: Array = _tallest_hill()
	var summit := Vector2(hill[0], hill[1])
	# Start out on the skirt, facing the summit.
	var start_dir := Vector2(1.0, 0.0)
	var radius: float = hill[2]
	var start := summit + start_dir * (radius * 0.95)
	_player.global_position = Vector3(
		start.x, Terrain.height_at(start.x, start.y) + 1.0, start.y
	)
	_player.velocity = Vector3.ZERO
	await wait_physics_frames(1)

	var began := _player.global_position.y
	# Point the camera at the summit and hold "forward".
	var to_summit := Vector3(summit.x - start.x, 0.0, summit.y - start.y).normalized()
	var pivot: Node3D = _player.get_node("CameraPivot")
	pivot.rotation = Vector3(0.0, atan2(-to_summit.x, -to_summit.z), 0.0)

	Input.action_press("move_forward")
	await wait_physics_frames(400)
	Input.action_release("move_forward")

	var climbed := _player.global_position.y - began
	assert_true(
		climbed > float(hill[3]) * 0.4,
		(
			"the player can walk up a hill  climbed %.2f m of a %.1f m hill, ended at %s"
			% [climbed, float(hill[3]), _player.global_position]
		),
	)


## Dropped onto a summit the player must land on it, not sink through the
## trimesh onto the plane underneath.
func test_player_does_not_fall_through_a_hill() -> void:
	var hill: Array = _tallest_hill()
	var summit_y: float = Terrain.height_at(hill[0], hill[1])
	_player.global_position = Vector3(hill[0], summit_y + 3.0, hill[1])
	_player.velocity = Vector3.ZERO
	await wait_physics_frames(90)

	var rest := _player.global_position.y
	assert_true(
		rest > summit_y - 0.5,
		(
			"the player rests on the hill rather than falling through it  resting y=%.2f, summit y=%.2f"
			% [rest, summit_y]
		),
	)


## In through the mouth and back out again. A cave that traps the player is
## worse than no cave, so this drives both directions rather than asserting
## the geometry looks open.
func test_player_can_walk_into_and_out_of_the_cave() -> void:
	var mouth: Vector3 = _terrain.mouth_position()
	# The mouth opens along +Z in the cave's own frame; out in the world that
	# is CAVE_FACING from the hill centre.
	var out := Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
	var outside := mouth + out * 6.0
	_player.global_position = outside + Vector3.UP * 1.5
	_player.velocity = Vector3.ZERO
	await wait_physics_frames(1)

	var pivot: Node3D = _player.get_node("CameraPivot")
	# Face into the hill, which is the opposite of the way the mouth opens.
	pivot.rotation = Vector3(0.0, atan2(out.x, out.z), 0.0)
	Input.action_press("move_forward")
	await wait_physics_frames(240)
	Input.action_release("move_forward")

	var inside := _player.global_position
	var depth := (inside - mouth).dot(-out)
	assert_true(
		depth > 1.5,
		(
			"the player can walk into the cave  got %.2f m past the mouth, hollow is %.1f m deep, pos=%s"
			% [depth, Tuning.CAVE_DEPTH, inside]
		),
	)

	# Now turn round and walk back out.
	pivot.rotation = Vector3(0.0, atan2(-out.x, -out.z), 0.0)
	Input.action_press("move_forward")
	await wait_physics_frames(300)
	Input.action_release("move_forward")

	var back := _player.global_position
	var out_depth := (back - mouth).dot(-out)
	assert_true(
		out_depth < depth - 1.0,
		(
			"the player is not trapped in the cave  went from %.2f m in to %.2f m in, pos=%s"
			% [depth, out_depth, back]
		),
	)


## Nothing scattered may float over the ground or be buried in it. This is
## the assertion the hills most needed: scatter runs before the physics
## server has any colliders, so its placement is arithmetic and this is the
## only thing that checks the arithmetic against the world that got built.
func test_props_sit_on_the_surface() -> void:
	var scenery: Node = _world.get_node("Scenery")
	var checked := 0
	var floating := 0
	var buried := 0
	var worst := 0.0
	var worst_name := ""
	for child in scenery.get_children():
		var n := child as Node3D
		if n == null or n.is_in_group("pal"):
			continue
		# Shore dressing deliberately sits on the lower beach, and both the
		# beach and the hills are offsets on the same plane, so the surface
		# a prop should meet is its own base y plus the hill under it.
		var ground: float = Terrain.height_at(n.position.x, n.position.z)
		var expected := ground
		if _is_beach_dressing(n):
			expected = ground - 0.35
		var off: float = n.position.y - expected
		checked += 1
		if off > 0.1:
			floating += 1
		elif off < -0.1:
			buried += 1
		if absf(off) > absf(worst):
			worst = off
			worst_name = n.name
	assert_true(
		floating == 0 and buried == 0,
		(
			"every scattered prop sits on the ground  checked=%d floating=%d buried=%d worst=%.3f on %s"
			% [checked, floating, buried, worst, worst_name]
		),
	)

	# And the same again against the physics server, on the props that
	# actually landed on a hill, so this cannot pass by agreeing with itself.
	var on_hills := 0
	var bad := 0
	var worst_ray := 0.0
	for child in scenery.get_children():
		var n := child as Node3D
		if n == null or n.is_in_group("pal"):
			continue
		if Terrain.height_at(n.position.x, n.position.z) < 0.5:
			continue
		on_hills += 1
		# Exclude the prop's own body, or the ray stops on the trunk it was
		# fired to check and every tree on a hillside reads as buried.
		var skip: Array[RID] = []
		if n is StaticBody3D:
			skip.append((n as StaticBody3D).get_rid())
		var surface := _ground_under(n.position.x, n.position.z, skip)
		var off: float = n.position.y - surface
		if absf(off) > 0.6:
			bad += 1
		if absf(off) > absf(worst_ray):
			worst_ray = off
	assert_true(
		on_hills > 0 and bad == 0,
		(
			"props on a hillside meet the collider the player walks on  on hills=%d off the surface=%d worst=%.3f m"
			% [on_hills, bad, worst_ray]
		),
	)


## Every authored position, as opposed to every scattered one. The benches
## and the altar are hand-placed constants rather than rolls, so nothing in
## the scatter path covers them, and a bench on a hillside is exactly what
## floats or buries when a hill moves.
func test_authored_props_sit_on_the_surface() -> void:
	var scenery: Node = _world.get_node("Scenery")
	var checked := 0
	var off_ground := 0
	var worst := 0.0
	var worst_name := ""
	var authored: Array[Vector3] = [Tuning.ALTAR_POS]
	for at in Tuning.WORKBENCH_POSITIONS:
		authored.append(at)

	for child in scenery.get_children():
		var n := child as Node3D
		if n == null:
			continue
		var is_authored := false
		for at in authored:
			if Vector2(n.position.x - at.x, n.position.z - at.z).length() < 0.01:
				is_authored = true
				break
		if not is_authored:
			continue
		checked += 1
		var off: float = n.position.y - Terrain.height_at(n.position.x, n.position.z)
		if absf(off) > 0.1:
			off_ground += 1
		if absf(off) > absf(worst):
			worst = off
			worst_name = n.name
	assert_eq(
		checked,
		authored.size(),
		"one node per authored position  found=%d authored=%d" % [checked, authored.size()],
	)
	assert_eq(
		off_ground,
		0,
		(
			"every authored prop sits on the ground  checked=%d off the ground=%d worst=%.3f on %s"
			% [checked, off_ground, worst, worst_name]
		),
	)


## The cave's boulders, sat on the ground like every scattered prop. They
## were not, once: they march back into a rising hillside on a fixed offset
## from the cave root, and on a steep mound the far ones hung in the air with
## their shadows on the ground below them. Nothing covered them, because the
## scattered-prop assertion only ever walked Scenery.
func test_cave_decorations_sit_on_the_ground() -> void:
	var cave: Node3D = _terrain.get_node("Cave")
	var checked := 0
	var floating := 0
	var buried := 0
	var worst := 0.0
	for child in cave.get_children():
		var n := child as Node3D
		# The boulders are the instanced rock scenes; the slabs are meshes
		# and bodies built here and are covered by their own test.
		if n == null or n.scene_file_path == "":
			continue
		var at: Vector3 = cave.transform * n.position
		var ground := Terrain.height_at(at.x, at.z)
		checked += 1
		# A boulder is sunk into the ground by design, so the bound is
		# one-sided: it may be in the ground, never over it.
		var off := at.y - ground
		if off > 0.1:
			floating += 1
		elif off < -1.5:
			buried += 1
		if absf(off) > absf(worst):
			worst = off
	assert_true(
		checked > 0,
		"the cave has decorations to check  checked=%d" % checked,
	)
	assert_true(
		floating == 0 and buried == 0,
		(
			"every cave decoration sits in the ground  checked=%d floating=%d buried=%d worst=%+.3f"
			% [checked, floating, buried, worst]
		),
	)


## Shells alone are dropped onto the lower beach; palms stand on the last of
## the grass, at ground level like everything else.
func _is_beach_dressing(n: Node3D) -> bool:
	return n.scene_file_path.contains("shell")


## The cave species is the reason to find the cave, so it must not be
## findable anywhere else.
func test_cave_species_lives_only_in_the_cave() -> void:
	var mouth: Vector3 = _terrain.mouth_position()
	var found := 0
	var strays := 0
	var furthest := 0.0
	for node in get_tree().get_nodes_in_group("pal"):
		var pal := node as Node3D
		if pal == null or pal.display_name != "Grottolo":
			continue
		found += 1
		var d := Vector2(
			pal.global_position.x - mouth.x, pal.global_position.z - mouth.z
		).length()
		furthest = maxf(furthest, d)
		if d > Tuning.GROTTOLO_RADIUS:
			strays += 1
	assert_eq(
		found,
		Tuning.GROTTOLO_COUNT,
		"the cave species spawned  found=%d expected=%d" % [found, Tuning.GROTTOLO_COUNT],
	)
	assert_eq(
		strays,
		0,
		(
			"the cave species is only near the cave  strays=%d furthest %.2f m from the mouth (limit %.1f)"
			% [strays, furthest, Tuning.GROTTOLO_RADIUS]
		),
	)

	# And no OTHER species wandered into the hollow at spawn, which would
	# make the cave a place you find a Wolf in.
	var intruders := 0
	for node in get_tree().get_nodes_in_group("pal"):
		var pal := node as Node3D
		if pal == null or pal.display_name == "Grottolo":
			continue
		var d := Vector2(
			pal.global_position.x - mouth.x, pal.global_position.z - mouth.z
		).length()
		if d < Tuning.CAVE_WIDTH * 0.5:
			intruders += 1
	assert_eq(intruders, 0, "no other species spawned inside the cave mouth  intruders=%d" % intruders)


## The placement rules the tuning block writes down, asserted rather than
## trusted. A hill on the spawn or across the shore wall is exactly the kind
## of thing that is invisible until half the existing suites go red.
func test_hills_clear_the_spawn_and_the_walls() -> void:
	var on_spawn: float = Terrain.height_at(0.0, 0.0)
	assert_true(on_spawn < 0.01, "the spawn is still flat  height at the origin %.3f m" % on_spawn)

	var too_far := 0
	var on_ash := 0
	var closest_gap := INF
	for hill in Tuning.HILLS:
		var centre := Vector2(hill[0], hill[1])
		var hill_radius: float = hill[2]
		var reach: float = centre.length() + hill_radius * Tuning.HILL_SKIRT
		# Must not touch the shore wall, or something could climb over it.
		var gap: float = Tuning.SHORE_WALL_RADIUS - reach
		closest_gap = minf(closest_gap, gap)
		if gap <= 0.0:
			too_far += 1
		# Must not lift the scorched blob, where the altar and the boss are.
		if Zone.is_inside(
			_world.get_world_3d(), Vector3(hill[0], 0.0, hill[1]), Zone.Kind.ASH
		):
			on_ash += 1
	assert_eq(
		too_far,
		0,
		"no hill reaches the shore wall  offenders=%d closest gap %.2f m" % [too_far, closest_gap],
	)
	assert_eq(on_ash, 0, "no hill stands on the scorched blob  hills on ash=%d" % on_ash)

	var altar_lift: float = Terrain.height_at(Tuning.ALTAR_POS.x, Tuning.ALTAR_POS.z)
	assert_true(
		altar_lift < 0.01, "the altar's ground is flat  height at the altar %.3f m" % altar_lift
	)


## The horizon islands are decoration and must stay that way. The assertion
## that matters is the last one: an island inside the shallow wall would be
## swimmable-to, and since it has no collider the player would swim through
## it, which looks worse than an empty horizon.
func test_distant_islands_are_decoration_only() -> void:
	var root: Node = _terrain.get_node_or_null("DistantIslands")
	assert_not_null(root, "the horizon islands were built")
	if root == null:
		return

	var meshes := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			meshes += 1
	assert_eq(
		meshes,
		Tuning.DISTANT_ISLANDS.size(),
		(
			"one mesh per authored horizon island  meshes=%d authored=%d"
			% [meshes, Tuning.DISTANT_ISLANDS.size()]
		),
	)

	# Nothing physical, anywhere under them.
	var bodies := 0
	var shapes := 0
	var grouped := 0
	for node in _walk(root):
		if node is CollisionShape3D or node is CollisionPolygon3D:
			shapes += 1
		if node is PhysicsBody3D or node is Area3D:
			bodies += 1
		if node.is_in_group("pal") or node.is_in_group("resource_node"):
			grouped += 1
	assert_true(
		bodies == 0 and shapes == 0,
		"no horizon island has a collider  bodies=%d shapes=%d" % [bodies, shapes],
	)
	assert_eq(
		grouped, 0, "no horizon island is gatherable or catchable  grouped nodes=%d" % grouped
	)

	# Every island, skirt included, beyond anything the player can reach.
	var too_near := 0
	var closest := INF
	for spec in Tuning.DISTANT_ISLANDS:
		var distance: float = spec[1]
		var radius: float = spec[2]
		var inner: float = distance - radius
		closest = minf(closest, inner)
		if inner < Tuning.DISTANT_ISLAND_MIN_RADIUS:
			too_near += 1
	assert_eq(
		too_near,
		0,
		(
			"every horizon island is out past the shallow wall  offenders=%d nearest edge %.1f m, wall at %.1f, floor %.1f"
			% [
				too_near,
				closest,
				Tuning.SHALLOW_WALL_RADIUS,
				Tuning.DISTANT_ISLAND_MIN_RADIUS,
			]
		),
	)

	# And inside the water disc, or they hang off the edge of the sea.
	var off_map := 0
	var furthest := 0.0
	for spec in Tuning.DISTANT_ISLANDS:
		var distance: float = spec[1]
		var radius: float = spec[2]
		var outer: float = distance + radius
		furthest = maxf(furthest, outer)
		if outer > Tuning.WATER_RADIUS:
			off_map += 1
	assert_eq(
		off_map,
		0,
		(
			"every horizon island sits on the water disc  offenders=%d furthest edge %.1f m, water ends at %.1f"
			% [off_map, furthest, Tuning.WATER_RADIUS]
		),
	)

	# Meeting the sea, not hovering over it. The mesh's own lowest vertex is
	# the rim, so this reads the built geometry rather than the constants.
	var floating := 0
	var highest_rim := -INF
	for child in root.get_children():
		var m := child as MeshInstance3D
		if m == null:
			continue
		var rim: float = m.position.y + (m.mesh.get_aabb() as AABB).position.y
		highest_rim = maxf(highest_rim, rim)
		if rim > Tuning.WATER_LEVEL:
			floating += 1
	assert_eq(
		floating,
		0,
		(
			"every horizon island meets the water rather than floating  floating=%d highest rim %.2f m, water at %.2f"
			% [floating, highest_rim, Tuning.WATER_LEVEL]
		),
	)

	# They must never become ground: something scattered onto one would be
	# placed on unreachable decoration.
	var lifted := 0
	for spec in Tuning.DISTANT_ISLANDS:
		var bearing: float = spec[0]
		var distance: float = spec[1]
		var at := Vector3(cos(bearing), 0.0, sin(bearing)) * distance
		if Terrain.height_at(at.x, at.z) > 0.01:
			lifted += 1
	assert_eq(lifted, 0, "horizon islands are not part of the ground height  islands raising height_at=%d" % lifted)


## Every descendant of `node`, so a collider cannot hide one level down.
func _walk(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_walk(child))
	return found


func _tallest_hill() -> Array:
	var best: Array = Tuning.HILLS[0]
	for hill in Tuning.HILLS:
		if float(hill[3]) > float(best[3]):
			best = hill
	return best
