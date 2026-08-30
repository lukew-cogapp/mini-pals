extends GutTest
## Demon biome assertions, ported from test/biome_test.gd.
##
## Asserts the demon biome is a distinct place: dead trees only on the
## scorched blob, living scenery only off it, and everything solid.

var _world: Node
var _scenery: Node
var _island: Node3D
var _space
var _zone_script
var _ash

var _dead: Array[Node3D] = []
var _living: Array[Node3D] = []
var _rocks: Array[Node3D] = []
var _palms: Array[Node3D] = []


func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)

	_scenery = _world.get_node("Scenery")
	_island = _world.get_node("Island")
	_space = _island.get_world_3d()
	_zone_script = load("res://scripts/zone.gd")
	_ash = _zone_script.Kind.ASH

	for child in _scenery.get_children():
		if not child is Node3D:
			continue
		var n: Node3D = child
		if n.is_in_group("tree"):
			# Palms share the tree group (they are bitten for wood too) but
			# are shore dressing, scattered by their own band and count.
			if n.scene_file_path.contains("palm"):
				_palms.append(n)
			elif n.scene_file_path.contains("deadtree"):
				_dead.append(n)
			else:
				_living.append(n)
		elif n.is_in_group("rock"):
			_rocks.append(n)

	print("counts: dead=%d living_trees=%d rocks=%d palms=%d" % [
		_dead.size(), _living.size(), _rocks.size(), _palms.size()])


func after_all() -> void:
	_world.free()


func test_scatter_counts_match_tuning() -> void:
	assert_eq(_dead.size(), Tuning.DEAD_TREE_COUNT, "dead tree count == DEAD_TREE_COUNT")
	assert_eq(_living.size(), Tuning.TREE_COUNT, "living tree count == TREE_COUNT")
	assert_eq(_palms.size(), Tuning.PALM_COUNT, "palm count == PALM_COUNT")
	assert_eq(_rocks.size(), Tuning.ROCK_COUNT, "rock count == ROCK_COUNT")


## Membership is the zone's answer, not a radius: the blob's edge is a
## noise curve, and the zone is the one thing that defines it.
func test_dead_trees_stay_on_the_blob_and_living_scenery_off_it() -> void:
	var bad_dead := 0
	var far_dead := 0.0
	for n in _dead:
		if not _zone_script.is_inside(_space, n.position, _ash):
			bad_dead += 1
		far_dead = max(far_dead, n.position.distance_to(Tuning.ALTAR_POS))
	print("dead trees: %d, furthest %.2f m from the altar (nominal r=%.1f)" % [
		_dead.size(), far_dead, Tuning.ASH_RADIUS])
	assert_true(bad_dead == 0, "all dead trees on the scorched blob (off by %d)" % bad_dead)

	var bad_living := 0
	for n in _living + _rocks:
		if _zone_script.is_inside(_space, n.position, _ash):
			bad_living += 1
	print("living scenery on the blob: %d" % bad_living)
	assert_true(bad_living == 0, "no living trees or rocks on the scorched blob")


func test_every_scattered_node_has_collision() -> void:
	var no_shape := 0
	for n in _dead + _living + _rocks:
		var found := false
		for c in n.get_children():
			if c is CollisionShape3D and c.shape != null:
				found = true
		if not found:
			no_shape += 1
	assert_true(no_shape == 0, "every scattered node has a non-null collision shape")


## Read the real vertices. The mesh is the thing the player sees, so its
## own numbers decide, not the constants it was built from.
func test_ash_blob_shape_and_placement() -> void:
	var ash: Node = _world.get_node("Island/Ash")
	assert_not_null(ash, "Island has an Ash blob")
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

	assert_true(
		from_altar_max < Tuning.ASH_MAX_RADIUS + 0.01, "blob stays inside its bounding circle"
	)
	assert_true(
		from_origin_max < Tuning.ISLAND_RADIUS - Tuning.BEACH_WIDTH,
		"blob stays on the grass and never reaches the beach",
	)

	# The edge must not be a circle. That was the complaint.
	assert_true(
		from_altar_max - from_altar_min > Tuning.ASH_RADIUS * 0.1,
		"blob edge is irregular, not a circle (spread %.2f m)" % (from_altar_max - from_altar_min),
	)

	# The spawn is on the far side of the island, so it must stay green.
	assert_true(
		not _zone_script.is_inside(_space, Vector3.ZERO, _ash),
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
	assert_true(pct > 5.0 and pct < 20.0, "blob covers a corner of the island, not most of it")

	assert_true(
		Tuning.ALTAR_POS.length() < Tuning.ISLAND_RADIUS - Tuning.BEACH_WIDTH,
		"altar is inside the grass",
	)

	assert_true(
		Tuning.ISLAND_RADIUS * Tuning.PALM_BAND.x > from_origin_max,
		"palms start beyond the ash, so none stands on scorched ground",
	)
