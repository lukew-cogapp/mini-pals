extends SceneTree
## Asserts the island's Area3D zones describe the same map the radius maths
## used to: land out to the shore wall, ash over the demon annulus only,
## and nothing at all beyond the water.

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

	# Mid-annulus, where the demons and dead trees live.
	var mid = Tuning.ISLAND_RADIUS * (Tuning.DEMON_RING_MIN + Tuning.DEMON_RING_MAX) * 0.5
	var in_ring = Vector3(mid, 0.0, 0.0)
	check(zone_script.is_inside(space, in_ring, ASH), "demon annulus is ASH")
	# The ash sits on top of the island, so it is land as well.
	check(zone_script.is_inside(space, in_ring, LAND), "demon annulus is still LAND")

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

	# The zone edges must agree with the numbers they were built from, or a
	# scattered thing near a boundary lands in a different place than before.
	var eps = 0.05
	var just_in = Vector3(Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MIN + eps, 0.0, 0.0)
	var just_out = Vector3(Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MIN - eps, 0.0, 0.0)
	check(zone_script.is_inside(space, just_in, ASH), "just inside the ring is ASH")
	check(not zone_script.is_inside(space, just_out, ASH), "just inside the hole is not ASH")

	var outer_in = Vector3(Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MAX - eps, 0.0, 0.0)
	var outer_out = Vector3(Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MAX + eps, 0.0, 0.0)
	check(zone_script.is_inside(space, outer_in, ASH), "just inside the outer edge is ASH")
	check(not zone_script.is_inside(space, outer_out, ASH), "just past the outer edge is not ASH")

	print("FAILURES=%d" % failures)
	quit(1 if failures else 0)
