extends GutTest
## The cave has to be a hole in a hill, not a box on a lawn.
##
## Two assertions, and the first is the one whose absence let a broken cave
## ship. A screenshot framed at the mouth looks perfectly correct while the
## back and side walls stand proud of the grass thirty metres away, so the
## check that matters is geometric: every part of the cave, except the
## doorway itself, sits under `Terrain.height_at` at its own footprint.
##
## The second is the older pair, kept because a sealed cave is a worse bug
## than a visible one: the player can walk in, and can walk out again.

const TERRAIN := preload("res://scripts/terrain.gd")

var _world: Node3D
var _terrain: Node3D
var _cave: Node3D


func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(2)
	_terrain = _world.get_node("Terrain")
	_cave = _terrain.get_node("Cave")


func after_all() -> void:
	_world.free()


## Along the cave's own axis: 0 at the mouth, positive going in.
func _depth_of(world_point: Vector3) -> float:
	var inward := -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
	return (world_point - _cave.global_position).dot(inward)


## Hill above a world point, negative when the point is out in the open air.
func _cover_at(world_point: Vector3) -> float:
	return TERRAIN.height_at(world_point.x, world_point.z) - world_point.y


## Points all over a box mesh's surface, in world space.
##
## A grid, not just the eight corners. The hill is a dome and a slab is a box,
## so the thinnest cover over a roof is in the MIDDLE of its span, not at a
## corner: a corner-only check reported metres of cover while the roof was
## plainly visible from overhead through the middle of the hill.
func _corners(node: MeshInstance3D) -> Array:
	var box := node.mesh as BoxMesh
	if box == null:
		return []
	var out := []
	var steps := Tuning.CAVE_FACE_SAMPLES
	for ix in steps + 1:
		for iy in steps + 1:
			for iz in steps + 1:
				# Surface only: skip anything strictly inside the box.
				var on_face := (
					ix == 0 or ix == steps
					or iy == 0 or iy == steps
					or iz == 0 or iz == steps
				)
				if not on_face:
					continue
				var local := Vector3(
					(float(ix) / steps - 0.5) * box.size.x,
					(float(iy) / steps - 0.5) * box.size.y,
					(float(iz) / steps - 0.5) * box.size.z,
				)
				out.append(node.global_transform * local)
	return out


## Every VisualInstance3D at or under a node. A boulder is an instanced scene,
## so its mesh is a descendant rather than the node itself.
func _visuals_of(node: Node) -> Array:
	var out := []
	var vis := node as VisualInstance3D
	if vis != null:
		out.append(vis)
	for child in node.get_children():
		out.append_array(_visuals_of(child))
	return out


## Nothing the cave owns may stand above the hill it is cut into.
##
## Every child is checked, not just the wall slabs: a boulder hanging in the
## air and a light floating over the summit are the same failure as a proud
## wall, and both have shipped here. The mouth is exempt for the length of
## CAVE_APRON, because that is the doorway, and rock meeting air there is the
## entire point of a cave.
func test_nothing_stands_proud_of_the_hill() -> void:
	var worst := INF
	var worst_name := ""
	var worst_point := Vector3.ZERO
	var checked := 0
	var proud: Array[String] = []

	for child in _cave.get_children():
		var node := child as Node3D
		if node == null:
			continue
		# Skip the slabs' own collision bodies, whose mesh twin is checked
		# already. NOT every StaticBody3D: the mouth boulders are static
		# bodies too, and skipping those excluded all nine from the check
		# while it still reported green.
		if node is StaticBody3D and node.name.ends_with("Body"):
			continue
		var points: Array = []
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.mesh is BoxMesh:
			points = _corners(mesh)
		elif node is Light3D:
			# A light's AABB is its illumination range, not a solid, so only
			# its position has to be underground.
			points = [node.global_position]
		else:
			# A boulder is a surface prop and is SUPPOSED to break the grass,
			# so the burial rule does not apply to it at all;
			# test_boulders_sit_in_the_hill governs those instead, on the
			# two things that actually matter for a rock: its underside is
			# in the ground, and it does not stand up like a wall.
			continue

		for point in points:
			if _depth_of(point) < Tuning.CAVE_APRON:
				continue
			checked += 1
			var cover := _cover_at(point)
			if cover < worst:
				worst = cover
				worst_name = node.name
				worst_point = point
			if cover < Tuning.CAVE_COVER and not proud.has(node.name):
				proud.append(node.name)

	assert_gt(checked, 0, "the burial check actually sampled something")
	assert_true(
		proud.is_empty(),
		(
			"nothing behind the cave mouth stands proud of the hill  "
			+ "proud=%s worst=%s at %.1f m cover %.2f (want >= %.2f)"
			% [proud, worst_name, _depth_of(worst_point), worst, Tuning.CAVE_COVER]
		),
	)
	gut.p("worst cover behind the apron: %s %.2f m at depth %.1f m"
		% [worst_name, worst, _depth_of(worst_point)])


## The cave pals live on the cave floor, so they are buried too, and a pal
## standing inside the rock face is the same bug read from the other end.
func test_cave_pals_stand_on_the_cave_floor() -> void:
	var floor_y := _cave.global_position.y
	var found := 0
	for pal in get_tree().get_nodes_in_group("pal"):
		var node := pal as Node3D
		if node == null:
			continue
		# The cave species only. A radius around the mouth also catches
		# whatever the respawn trickle dropped on the hillside above, which
		# is on the surface where it belongs and says nothing about the cave.
		if node.get("display_name") != Tuning.GROTTOLO_NAME:
			continue
		found += 1
		assert_almost_eq(
			node.global_position.y,
			floor_y,
			Tuning.CAVE_HEIGHT,
			"a cave pal stands on the cave floor  %s at y=%.2f, floor y=%.2f"
			% [node.name, node.global_position.y, floor_y],
		)
	gut.p("cave pals checked: %d" % found)


## Every pal's collider, to be excluded from a structural sweep.
func _pal_rids() -> Array[RID]:
	var out: Array[RID] = []
	for pal in get_tree().get_nodes_in_group("pal"):
		var body := pal as CollisionObject3D
		if body != null:
			out.append(body.get_rid())
	return out


## The mouth is a hole, not a wall. Sweep a capsule in from outside and it
## must reach the middle of the chamber.
func test_the_cave_can_be_walked_into() -> void:
	var inward := -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
	var space := _cave.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8

	var start := _cave.global_position + Vector3.UP * 1.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = inward * (Tuning.CAVE_DEPTH * 0.5)
	query.collision_mask = 0xFFFFFFFF
	# Structure only. The chamber is stocked with Grottolos, and a capsule
	# bumping a resident says nothing about whether the mouth is a hole.
	query.exclude = _pal_rids()
	var hit := space.cast_motion(query)
	assert_almost_eq(
		hit[0],
		1.0,
		0.35,
		"the mouth is open  a capsule walking in stopped at %.2f of the way" % hit[0],
	)


## And out again. The same sweep, reversed from the back of the chamber.
func test_the_cave_is_not_a_trap() -> void:
	var inward := -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
	var space := _cave.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8

	var start := (
		_cave.global_position
		+ inward * (Tuning.CAVE_DEPTH * 0.5)
		+ Vector3.UP * 1.2
	)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = -inward * (Tuning.CAVE_DEPTH * 0.5)
	query.collision_mask = 0xFFFFFFFF
	# Structure only. The chamber is stocked with Grottolos, and a capsule
	# bumping a resident says nothing about whether the mouth is a hole.
	query.exclude = _pal_rids()
	var hit := space.cast_motion(query)
	assert_almost_eq(
		hit[0],
		1.0,
		0.35,
		"the cave is not a trap  a capsule walking out stopped at %.2f of the way" % hit[0],
	)



## Mouth boulders sit in the hillside: base underground, and not so much of
## them above it that the mouth reads as a boulder wall instead of a cave.
##
## They are the only cave part allowed to break the surface at all, since a
## rock lying on a slope is what makes the opening read as rock. The bound is
## on how much: nine boulders standing five metres clear is what the owner saw
## and called a wall.
func test_boulders_sit_in_the_hill() -> void:
	var tallest := 0.0
	var tallest_name := ""
	var found := 0
	for child in _cave.get_children():
		var node := child as Node3D
		if node == null or not (node is StaticBody3D):
			continue
		if node.name.ends_with("Body"):
			continue
		found += 1
		var stands := -INF
		for entry in _visuals_of(node):
			var vis: VisualInstance3D = entry
			var aabb := vis.get_aabb()
			var top := aabb.position + Vector3(
				aabb.size.x * 0.5, aabb.size.y, aabb.size.z * 0.5
			)
			stands = maxf(stands, -_cover_at(vis.global_transform * top))
		if stands > tallest:
			tallest = stands
			tallest_name = node.name
		# The BOTTOM of the mesh, not the node origin. A rock model's origin
		# is not necessarily at its own base, so an origin underground still
		# leaves the visible underside hanging with sky beneath it, which is
		# what the owner keeps seeing and what passed a check on the origin.
		var lowest := INF
		for entry in _visuals_of(node):
			var vis2: VisualInstance3D = entry
			var ab := vis2.get_aabb()
			var base := ab.position + Vector3(ab.size.x * 0.5, 0.0, ab.size.z * 0.5)
			lowest = minf(lowest, _cover_at(vis2.global_transform * base))
		assert_gt(
			lowest,
			-Tuning.CAVE_ROCK_FLOAT_TOLERANCE,
			"a mouth boulder's underside is in the ground  %s floats %.2f m up"
			% [node.name, -lowest],
		)

	assert_eq(found, Tuning.CAVE_ROCK_COUNT, "every mouth boulder was checked")
	assert_lt(
		tallest,
		Tuning.CAVE_ROCK_MAX_PROUD,
		"no mouth boulder stands up like a wall  %s stands %.2f m proud (max %.2f)"
		% [tallest_name, tallest, Tuning.CAVE_ROCK_MAX_PROUD],
	)
	gut.p("tallest mouth boulder stands %.2f m proud" % tallest)


## The check that matches what the eye sees: from a ring of eye positions on
## the real ground, no chamber slab may be visible.
##
## A height comparison is not enough on its own, and this is why the previous
## attempt shipped broken. `height_at` at a slab's corners can read as buried
## while the hill's flank BETWEEN the slab and the viewer is lower, so the
## chamber shows through from thirty metres away on open ground. A ray from
## the eye to each corner answers the actual question.
func test_no_slab_is_visible_from_outside() -> void:
	var space := _cave.get_world_3d().direct_space_state
	var exposed: Array[String] = []
	var checked := 0

	# The ring of eye positions, plus one straight overhead. Directly above
	# is the one viewpoint with no hill flank between the eye and the roof,
	# so it is the angle the ring cannot speak for, and the roof read as a
	# plain slab on the grass there while every ring bearing was clean.
	var eyes: Array[Vector3] = []
	for i in Tuning.CAVE_SIGHT_BEARINGS:
		var angle := TAU * i / float(Tuning.CAVE_SIGHT_BEARINGS)
		var eye := _cave.global_position + Vector3(
			cos(angle) * Tuning.CAVE_SIGHT_DISTANCE,
			0.0,
			sin(angle) * Tuning.CAVE_SIGHT_DISTANCE,
		)
		eye.y = TERRAIN.height_at(eye.x, eye.z) + Tuning.CAVE_SIGHT_EYE_HEIGHT
		eyes.append(eye)
	eyes.append(_cave.global_position + Vector3.UP * Tuning.CAVE_SIGHT_ABOVE)

	for eye in eyes:

		for child in _cave.get_children():
			var mesh := child as MeshInstance3D
			if mesh == null or not (mesh.mesh is BoxMesh):
				continue
			for corner in _corners(mesh):
				# The mouth itself is meant to be seen into, so corners on
				# the doorway side are not a failure.
				if _depth_of(corner) < Tuning.CAVE_APRON:
					continue
				checked += 1
				# An eye out in front of the mouth is looking INTO the cave,
				# which is the point of a cave. Only eyes off to the side or
				# behind may see no opening at all.
				var to_eye := (eye - _cave.global_position).normalized()
				var outward := Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
				if to_eye.dot(outward) > Tuning.CAVE_SIGHT_MOUTH_DOT:
					continue
				var query := PhysicsRayQueryParameters3D.create(eye, corner)
				query.collision_mask = 0xFFFFFFFF
				query.exclude = _pal_rids()
				var hit := space.intersect_ray(query)
				if hit.is_empty():
					var label := "%s seen from %v" % [mesh.name, eye]
					if not exposed.has(label):
						exposed.append(label)

	assert_gt(checked, 0, "the sightline check actually sampled something")
	assert_true(
		exposed.is_empty(),
		"no chamber slab is visible from open ground  exposed=%s" % [exposed],
	)
	gut.p("sightlines checked: %d, all blocked by hill" % checked)


## Walk in from OPEN GRASS, not from the doorway.
##
## This is the assertion whose absence let an unenterable cave pass every
## other check here. Sinking the chamber far enough buries the mouth as well
## as the roof, and the result is a hill with no opening in it at all; a
## sweep that starts at the door plane cannot see that, because it starts
## inside a cave that can no longer be reached. Start on the grass beyond the
## approach cutting and walk the whole way to the middle of the chamber.
func test_the_cave_can_be_reached_from_outside() -> void:
	var inward := -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
	var space := _cave.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8

	# From the outer lip of the cutting, where its floor meets the grass.
	# Further out than that and the ground has risen above the trench floor,
	# so a level capsule walks into the trench's end wall, which is a step
	# down rather than a blockage and is not what this is testing.
	var out := Tuning.CAVE_RAMP
	var start := _cave.global_position - inward * out
	start.y = _cave.global_position.y + 1.2

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = inward * (out + Tuning.CAVE_DEPTH * 0.5)
	query.collision_mask = 0xFFFFFFFF
	query.exclude = _pal_rids()
	var hit := space.cast_motion(query)
	assert_almost_eq(
		hit[0],
		1.0,
		0.35,
		"the cave is reachable from open grass  a capsule walking in from %.1f m out stopped at %.2f of the way"
		% [out, hit[0]],
	)
