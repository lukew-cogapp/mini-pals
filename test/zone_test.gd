extends GutTest
## Zone assertions, ported from test/zone_test.gd.
##
## Asserts the island's Area3D zones describe the map the mesh draws: land
## out to the shore wall, ash over the scorched blob only, and nothing at all
## beyond the water.

var _world: Node
var _zone_script
var _space
var _LAND
var _ASH


func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)

	_zone_script = load("res://scripts/zone.gd")
	_LAND = _zone_script.Kind.LAND
	_ASH = _zone_script.Kind.ASH
	_space = (_world as Node3D).get_world_3d()


func after_all() -> void:
	_world.free()


func test_spawn_and_blob_membership() -> void:
	var spawn = Vector3.ZERO
	assert_true(_zone_script.is_inside(_space, spawn, _LAND), "spawn is LAND")
	assert_true(not _zone_script.is_inside(_space, spawn, _ASH), "spawn is not ASH")

	# The middle of the blob, where the demons and dead trees live.
	var in_blob = Tuning.ALTAR_POS + Vector3(Tuning.ASH_RADIUS * 0.3, 0.0, 0.0)
	assert_true(_zone_script.is_inside(_space, in_blob, _ASH), "middle of the blob is ASH")
	# The ash sits on top of the island, so it is land as well.
	assert_true(_zone_script.is_inside(_space, in_blob, _LAND), "middle of the blob is still LAND")

	# The blob is one place, not a band: the far side of the island from the
	# altar must be clean, which the old annulus could never be.
	var far_side = -Tuning.ALTAR_POS
	assert_true(
		not _zone_script.is_inside(_space, far_side, _ASH), "far side of the island is not ASH"
	)
	assert_true(
		_zone_script.is_inside(_space, far_side, _LAND), "far side of the island is still LAND"
	)

	# The altar stands out among the demons, so it must sit on ash.
	assert_true(_zone_script.is_inside(_space, Tuning.ALTAR_POS, _ASH), "altar stands on ASH")


func test_edges_of_the_map() -> void:
	var past_wall = Vector3(Tuning.SHORE_WALL_RADIUS + 5.0, 0.0, 0.0)
	assert_true(not _zone_script.is_inside(_space, past_wall, _LAND), "past the shore wall is not LAND")

	var off_map = Vector3(Tuning.WATER_RADIUS * 2.0, 0.0, 0.0)
	assert_null(_zone_script.zone_at(_space, off_map), "zone lookup returns null off the map")


func test_ash_zone_edge_matches_the_mesh_curve() -> void:
	# Every zone the island built should be registered and in the group.
	var zones = _world.get_tree().get_nodes_in_group("zone")
	print("zones found: %d" % zones.size())
	assert_true(zones.size() >= 3, "island built its zones")

	# The edge is a noise curve now, so "just inside" and "just outside" are
	# taken either side of the zone's own answer for the radius at each angle,
	# which is the same curve the mesh was built from.
	var eps = 0.05
	var ash_zone = null
	for z in zones:
		if z.kind == _ASH:
			ash_zone = z
	assert_not_null(ash_zone, "found the ash zone")

	var straddles = 0
	var wobble_min = INF
	var wobble_max = 0.0
	for i in 32:
		var angle = TAU * i / 32
		var r = ash_zone.edge_radius_at(angle)
		wobble_min = min(wobble_min, r)
		wobble_max = max(wobble_max, r)
		var dir = Vector3(cos(angle), 0.0, sin(angle))
		var inside = Tuning.ALTAR_POS + dir * (r - eps)
		var outside = Tuning.ALTAR_POS + dir * (r + eps)
		if not _zone_script.is_inside(_space, inside, _ASH):
			straddles += 1
		if _zone_script.is_inside(_space, outside, _ASH):
			straddles += 1
	print("edge radius %.2f..%.2f (nominal %.1f)" % [wobble_min, wobble_max, Tuning.ASH_RADIUS])
	assert_true(straddles == 0, "zone edge matches edge_radius_at all round (off by %d)" % straddles)

	# An irregular edge is the whole point: a constant radius would be the
	# circle the owner rejected.
	assert_true(
		wobble_max - wobble_min > Tuning.ASH_RADIUS * 0.1,
		"edge radius varies with angle rather than being a circle",
	)
	assert_true(wobble_max <= Tuning.ASH_MAX_RADIUS, "edge never exceeds the bounding circle")
