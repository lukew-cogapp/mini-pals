extends SceneTree
## Asserts the demon biome is a distinct place: dead trees only on the
## scorched blob, living scenery only off it, and everything solid.

var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: %s" % label)
	else:
		print("ok: %s" % label)


func _init() -> void:
	call_deferred("run")


func run() -> void:
	# Autoloads register after _init starts, so nothing may touch Tuning
	# before this yields.
	await process_frame
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	await process_frame

	var scenery: Node = world.get_node("Scenery")
	var island: Node3D = world.get_node("Island")
	var space := island.get_world_3d()
	var zone_script = load("res://scripts/zone.gd")
	var ASH = zone_script.Kind.ASH

	var dead: Array[Node3D] = []
	var living: Array[Node3D] = []
	var rocks: Array[Node3D] = []
	var palms: Array[Node3D] = []
	for child in scenery.get_children():
		if not child is Node3D:
			continue
		var n: Node3D = child
		if n.is_in_group("tree"):
			# Palms share the tree group (they are bitten for wood too) but
			# are shore dressing, scattered by their own band and count.
			if n.scene_file_path.contains("palm"):
				palms.append(n)
			elif n.scene_file_path.contains("deadtree"):
				dead.append(n)
			else:
				living.append(n)
		elif n.is_in_group("rock"):
			rocks.append(n)

	print("counts: dead=%d living_trees=%d rocks=%d palms=%d" % [
		dead.size(), living.size(), rocks.size(), palms.size()])
	check(dead.size() == Tuning.DEAD_TREE_COUNT, "dead tree count == DEAD_TREE_COUNT")
	check(living.size() == Tuning.TREE_COUNT, "living tree count == TREE_COUNT")
	check(palms.size() == Tuning.PALM_COUNT, "palm count == PALM_COUNT")
	check(rocks.size() == Tuning.ROCK_COUNT, "rock count == ROCK_COUNT")

	# Membership is the zone's answer, not a radius: the blob's edge is a
	# noise curve, and the zone is the one thing that defines it.
	var bad_dead := 0
	var far_dead := 0.0
	for n in dead:
		if not zone_script.is_inside(space, n.position, ASH):
			bad_dead += 1
		far_dead = max(far_dead, n.position.distance_to(Tuning.ALTAR_POS))
	print("dead trees: %d, furthest %.2f m from the altar (nominal r=%.1f)" % [
		dead.size(), far_dead, Tuning.ASH_RADIUS])
	check(bad_dead == 0, "all dead trees on the scorched blob (off by %d)" % bad_dead)

	var bad_living := 0
	for n in living + rocks:
		if zone_script.is_inside(space, n.position, ASH):
			bad_living += 1
	print("living scenery on the blob: %d" % bad_living)
	check(bad_living == 0, "no living trees or rocks on the scorched blob")

	var no_shape := 0
	for n in dead + living + rocks:
		var found := false
		for c in n.get_children():
			if c is CollisionShape3D and c.shape != null:
				found = true
		if not found:
			no_shape += 1
	check(no_shape == 0, "every scattered node has a non-null collision shape")

	var ash: Node = world.get_node("Island/Ash")
	check(ash != null, "Island has an Ash blob")
	# Read the real vertices. The mesh is the thing the player sees, so its
	# own numbers decide, not the constants it was built from.
	var verts: PackedVector3Array = (ash as MeshInstance3D).mesh.get_faces()
	var centre := Vector3(Tuning.ALTAR_POS.x, 0.0, Tuning.ALTAR_POS.z)
	var from_altar_max := 0.0
	var from_altar_min := INF
	var from_origin_max := 0.0
	for v in verts:
		var flat := Vector3(v.x, 0.0, v.z)
		var d := flat.distance_to(centre)
		from_altar_max = max(from_altar_max, d)
		# Skip the fan's own centre vertex, which is always at distance zero.
		if d > 0.001:
			from_altar_min = min(from_altar_min, d)
		from_origin_max = max(from_origin_max, flat.length())
	print("blob edge %.2f..%.2f from the altar; furthest point %.2f from origin (island %.1f)" % [
		from_altar_min, from_altar_max, from_origin_max, Tuning.ISLAND_RADIUS])

	check(from_altar_max < Tuning.ASH_MAX_RADIUS + 0.01, "blob stays inside its bounding circle")
	check(
		from_origin_max < Tuning.ISLAND_RADIUS - Tuning.BEACH_WIDTH,
		"blob stays on the grass and never reaches the beach",
	)

	# The edge must not be a circle. That was the complaint.
	check(
		from_altar_max - from_altar_min > Tuning.ASH_RADIUS * 0.1,
		"blob edge is irregular, not a circle (spread %.2f m)" % (from_altar_max - from_altar_min),
	)

	# The spawn is on the far side of the island, so it must stay green.
	check(
		not zone_script.is_inside(space, Vector3.ZERO, ASH),
		"island spawn is not on scorched ground",
	)

	# Area, as a fraction of the island. The old annulus covered 59%, which is
	# what made it read as a target painted on the map.
	var area := 0.0
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		area += absf((b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)) * 0.5
	var island_area := PI * Tuning.ISLAND_RADIUS * Tuning.ISLAND_RADIUS
	var pct := area / island_area * 100.0
	print("blob area %.1f m2 = %.1f%% of the island" % [area, pct])
	check(pct > 5.0 and pct < 20.0, "blob covers a corner of the island, not most of it")

	check(
		Tuning.ALTAR_POS.length() < Tuning.ISLAND_RADIUS - Tuning.BEACH_WIDTH,
		"altar is inside the grass",
	)

	check(
		Tuning.ISLAND_RADIUS * Tuning.PALM_BAND.x > from_origin_max,
		"palms start beyond the ash, so none stands on scorched ground",
	)

	print("FAILURES=%d" % failures)
	quit(1 if failures else 0)

