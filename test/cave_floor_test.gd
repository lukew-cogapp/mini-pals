extends GutTest
## The cave has a floor everywhere the player can stand, checked in seconds.
##
## `cave_fall_test.gd` answers the same question by walking a real body down
## the approach at every speed and offset, which is the honest test and takes
## four minutes. This one builds the terrain alone, with no world, no pals and
## no scatter, and fires a grid of rays. It caught every hole that test did
## while a fix was in progress, so it is the one to iterate against; run the
## walk test before believing a fix is finished.
##
## Rays are fired from a metre above the CAVE FLOOR, not from the sky. A ray
## from overhead hits the hill's own surface and stops, which is why an
## earlier grid found nothing while the player was falling through: it never
## reached the depth the player walks at.

const TERRAIN := preload("res://scripts/terrain.gd")

var _terrain: Node3D


## Terrain alone, rather than world.tscn. That is the whole speed win: no
## pals to spawn, no seeded scatter, no HUD, and the physics server only has
## the hills and the ground plane in it.
func before_all() -> void:
	_terrain = TERRAIN.new()
	_terrain.grass = load("res://materials/ground.tres")
	_terrain.rock = load("res://materials/rock.tres")
	_terrain.far_land = load("res://materials/far_land.tres")
	add_child(_terrain)
	# The ground plane the island stands on. Without it a hole reads as "no
	# hit at all" rather than "hit the plane four metres down", and the test
	# would pass for the wrong reason on a fall it should catch.
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	add_child(ground)
	await wait_physics_frames(2)


func after_all() -> void:
	_terrain.free()


func _inward() -> Vector3:
	return -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))


func _across() -> Vector3:
	var i := _inward()
	return Vector3(i.z, 0.0, -i.x)


## What the ray under `at` reports, as a height. -INF when it hits nothing.
func _ground_under(at: Vector3) -> float:
	var space := _terrain.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 60.0)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return -INF
	return hit["position"].y


## Every point of the chamber and its approach, floored at the right height.
##
## The height is the assertion, not merely that something was hit: the ground
## plane at y = 0 lies under every point on the map, so a check for "a ray hit
## something" passes at full speed while the player drops four metres past a
## missing floor. That exact assertion shipped green here once already.
func test_the_cave_has_a_floor_at_the_right_height() -> void:
	var inward := _inward()
	var across := _across()
	var mouth: Vector3 = _terrain.mouth_position()
	var floor_y := mouth.y
	var half_w := Tuning.CAVE_WIDTH * 0.5 + Tuning.CAVE_WALL
	var holes: Array[String] = []
	var along := -(Tuning.CAVE_RAMP + Tuning.CAVE_CARVE_MARGIN)
	while along <= Tuning.CAVE_DEPTH:
		var side := -half_w
		while side <= half_w:
			var at := mouth + inward * along + across * side
			at.y = floor_y + 1.0
			var got := _ground_under(at)
			if got < floor_y - 0.5:
				holes.append("along %.1f side %.1f: floor %.2f, want %.2f" % [
					along, side, got, floor_y
				])
			side += 0.5
		along += 0.5
	if not holes.is_empty():
		gut.p("%d holes, first ten:" % holes.size())
		for h in holes.slice(0, 10):
			gut.p("  " + h)
	assert_eq(holes.size(), 0, "cave floor has %d holes" % holes.size())


## The hills themselves are solid, which the cave work has broken twice.
##
## Once by carving the collider and not the mesh, and once by a CSG boolean
## that rendered but generated no collider at all: every hill looked right and
## the player walked through all four. Neither showed up in a cave check,
## because neither was about the cave.
func test_every_hill_is_solid_across_its_face() -> void:
	var misses: Array[String] = []
	var samples := 0
	for i in Tuning.HILLS.size():
		var hill: Array = Tuning.HILLS[i]
		for ring in range(1, 9):
			var r: float = hill[2] * ring / 9.0
			for seg in 12:
				var a := TAU * seg / 12.0
				var x: float = hill[0] + cos(a) * r
				var z: float = hill[1] + sin(a) * r
				# Skip the cave's own footprint: it is a hole on purpose.
				if _in_cave_footprint(x, z):
					continue
				var want := TERRAIN.height_at(x, z)
				samples += 1
				var got := _ground_under(Vector3(x, want + 5.0, z))
				# Only a ray that falls THROUGH the hill is a fault. One that
				# stops high has landed on a boulder or a tree, which is
				# scenery doing its job, and an `abs` here reported exactly
				# that as a missing hill.
				if got < want - 0.5:
					misses.append("hill%d r=%.1f a=%.2f: want %.2f, got %.2f" % [
						i, r, a, want, got
					])
	if not misses.is_empty():
		gut.p("%d of %d samples missed, first ten:" % [misses.size(), samples])
		for m in misses.slice(0, 10):
			gut.p("  " + m)
	assert_eq(
		misses.size(), 0,
		"%d of %d hill samples had no ground under them" % [misses.size(), samples]
	)


## Is a point in the cave's plan, where a missing hill surface is the point?
func _in_cave_footprint(x: float, z: float) -> bool:
	var mouth: Vector3 = _terrain.mouth_position()
	var inward := _inward()
	var across := _across()
	var offset := Vector3(x, mouth.y, z) - mouth
	var along := offset.dot(inward)
	var side := absf(offset.dot(across))
	if along < -(Tuning.CAVE_RAMP + Tuning.CAVE_CARVE_MARGIN):
		return false
	if along > Tuning.CAVE_DEPTH + Tuning.CAVE_WALL:
		return false
	return side <= Tuning.CAVE_WIDTH * 0.5 + Tuning.CAVE_WALL
