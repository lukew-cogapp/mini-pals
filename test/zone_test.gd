extends SceneTree
## Asserts the island's Area3D zones describe the map the mesh draws: land
## out to the shore wall, ash over the scorched blob only, and nothing at all
## beyond the water.

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
	# Autoloads register after _init starts, and naming the Zone type here
	# would compile it before Tuning exists, so everything stays untyped and
	# nothing may touch either before this yields.
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	await process_frame

	var zone_script = load("res://scripts/zone.gd")
	var LAND = zone_script.Kind.LAND
	var ASH = zone_script.Kind.ASH
	var space = (world as Node3D).get_world_3d()

	var spawn = Vector3.ZERO
	check(zone_script.is_inside(space, spawn, LAND), "spawn is LAND")
	check(not zone_script.is_inside(space, spawn, ASH), "spawn is not ASH")

	# The middle of the blob, where the demons and dead trees live.
	var in_blob = Tuning.ALTAR_POS + Vector3(Tuning.ASH_RADIUS * 0.3, 0.0, 0.0)
	check(zone_script.is_inside(space, in_blob, ASH), "middle of the blob is ASH")
	# The ash sits on top of the island, so it is land as well.
	check(zone_script.is_inside(space, in_blob, LAND), "middle of the blob is still LAND")

	# The blob is one place, not a band: the far side of the island from the
	# altar must be clean, which the old annulus could never be.
	var far_side = -Tuning.ALTAR_POS
	check(not zone_script.is_inside(space, far_side, ASH), "far side of the island is not ASH")
	check(zone_script.is_inside(space, far_side, LAND), "far side of the island is still LAND")

	var past_wall = Vector3(Tuning.SHORE_WALL_RADIUS + 5.0, 0.0, 0.0)
	check(not zone_script.is_inside(space, past_wall, LAND), "past the shore wall is not LAND")

	var off_map = Vector3(Tuning.WATER_RADIUS * 2.0, 0.0, 0.0)
	check(zone_script.zone_at(space, off_map) == null, "zone lookup returns null off the map")

	# The altar stands out among the demons, so it must sit on ash.
	check(zone_script.is_inside(space, Tuning.ALTAR_POS, ASH), "altar stands on ASH")

	# Every zone the island built should be registered and in the group.
	var zones = world.get_tree().get_nodes_in_group("zone")
	print("zones found: %d" % zones.size())
	check(zones.size() >= 3, "island built its zones")

	# The edge is a noise curve now, so "just inside" and "just outside" are
	# taken either side of the zone's own answer for the radius at each angle,
	# which is the same curve the mesh was built from.
	var eps = 0.05
	var ash_zone = null
	for z in zones:
		if z.kind == ASH:
			ash_zone = z
	check(ash_zone != null, "found the ash zone")

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
		if not zone_script.is_inside(space, inside, ASH):
			straddles += 1
		if zone_script.is_inside(space, outside, ASH):
			straddles += 1
	print("edge radius %.2f..%.2f (nominal %.1f)" % [wobble_min, wobble_max, Tuning.ASH_RADIUS])
	check(straddles == 0, "zone edge matches edge_radius_at all round (off by %d)" % straddles)

	# An irregular edge is the whole point: a constant radius would be the
	# circle the owner rejected.
	check(
		wobble_max - wobble_min > Tuning.ASH_RADIUS * 0.1,
		"edge radius varies with angle rather than being a circle",
	)
	check(wobble_max <= Tuning.ASH_MAX_RADIUS, "edge never exceeds the bounding circle")

	print("FAILURES=%d" % failures)
	quit(1 if failures else 0)
