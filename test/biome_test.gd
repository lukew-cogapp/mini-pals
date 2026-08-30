extends SceneTree
## Asserts the demon biome is a distinct place: dead trees only inside the
## annulus, living scenery only outside it, and everything solid.

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
	var inner := Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MIN
	var outer := Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MAX

	var dead: Array[Node3D] = []
	var living: Array[Node3D] = []
	var rocks: Array[Node3D] = []
	for child in scenery.get_children():
		if not child is Node3D:
			continue
		var n: Node3D = child
		if n.is_in_group("tree"):
			if n.scene_file_path.contains("deadtree"):
				dead.append(n)
			else:
				living.append(n)
		elif n.is_in_group("rock"):
			rocks.append(n)

	print("counts: dead=%d living_trees=%d rocks=%d" % [dead.size(), living.size(), rocks.size()])
	check(dead.size() == Tuning.DEAD_TREE_COUNT, "dead tree count == DEAD_TREE_COUNT")
	check(living.size() == Tuning.TREE_COUNT, "living tree count == TREE_COUNT")
	check(rocks.size() == Tuning.ROCK_COUNT, "rock count == ROCK_COUNT")

	var worst_in := 0.0
	var bad_dead := 0
	for n in dead:
		var d := n.position.length()
		if d < inner or d > outer:
			bad_dead += 1
			worst_in = max(worst_in, absf(d - clampf(d, inner, outer)))
	print("dead tree radii: min=%.2f max=%.2f (annulus %.1f..%.1f)" % [
		_min_r(dead), _max_r(dead), inner, outer])
	check(bad_dead == 0, "all dead trees inside the demon annulus (off by %d)" % bad_dead)

	var bad_living := 0
	for n in living + rocks:
		var d := n.position.length()
		if d >= inner and d <= outer:
			bad_living += 1
	print("living scenery in ring: %d" % bad_living)
	check(bad_living == 0, "no living trees or rocks inside the annulus")

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
	check(ash != null, "Island has an Ash disc")
	# Read the real vertex radii: a solid disc would silently paint the whole
	# island, which is exactly the bug this ring replaced.
	var verts: PackedVector3Array = (ash as MeshInstance3D).mesh.get_faces()
	var ash_in := INF
	var ash_out := 0.0
	for v in verts:
		var r := Vector3(v.x, 0.0, v.z).length()
		ash_in = min(ash_in, r)
		ash_out = max(ash_out, r)
	print("ash ring %.2f..%.2f  island=%.2f  altar dist=%.2f" % [
		ash_in, ash_out, Tuning.ISLAND_RADIUS, Tuning.ALTAR_POS.length()])
	check(ash_out < Tuning.ISLAND_RADIUS, "ash does not reach the beach")
	check(ash_in > Tuning.SCATTER_CLEAR_RADIUS * 2.0, "ash leaves the island centre green")
	check(ash_in <= inner and ash_out >= outer, "ash covers the whole demon annulus")
	check(
		Tuning.ALTAR_POS.length() < Tuning.ISLAND_RADIUS - Tuning.BEACH_WIDTH,
		"altar is inside the grass",
	)

	check(
		Tuning.ISLAND_RADIUS * Tuning.PALM_BAND.x > ash_out,
		"palms start beyond the ash, so none stands on scorched ground",
	)

	print("FAILURES=%d" % failures)
	quit(1 if failures else 0)


func _min_r(a: Array[Node3D]) -> float:
	var m := INF
	for n in a:
		m = min(m, n.position.length())
	return m


func _max_r(a: Array[Node3D]) -> float:
	var m := 0.0
	for n in a:
		m = max(m, n.position.length())
	return m
