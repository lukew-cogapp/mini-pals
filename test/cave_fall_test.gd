extends GutTest
## Walking into the cave must never drop the player through the world.
##
## The owner's screenshot showed the player standing on the UNDERSIDE of the
## terrain outside the cave, looking up at the Grottolos. Downward rays from
## above all hit ground, so the hole is not visible from overhead; this drives
## a real CharacterBody3D down the approach at every speed the game allows and
## watches its Y, which is the only thing that reproduces it.
##
## The bound is the cave floor, not `height_at`: the approach is a cutting
## sunk CAVE_SINK below the grass, so a walker there is legitimately below the
## hill surface. Below the FLOOR, though, is the void.

const TERRAIN := preload("res://scripts/terrain.gd")

var _world: Node3D
var _terrain: Node3D
var _cave: Node3D
var _player: CharacterBody3D


func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(2)
	_terrain = _world.get_node("Terrain")
	_cave = _terrain.get_node("Cave")
	_player = _world.get_node("Player")


func after_all() -> void:
	_world.free()


## Unit vector pointing from the mouth into the hill.
func _inward() -> Vector3:
	return -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))


## Across the cave axis, right-handed with `_inward`.
func _across() -> Vector3:
	var i := _inward()
	return Vector3(i.z, 0.0, -i.x)


## The chamber floor's top surface, in world Y. Everything walkable in and
## around the cave sits on this plane or above it.
func _floor_y() -> float:
	return _cave.global_position.y


## The walkable surface under a point: the cutting or chamber floor inside
## the cut's footprint, the hill grass everywhere else. The walks start out
## on open hillside where the grass is under a metre high, so one global
## floor bound would fail a player standing correctly on the ground there.
func _floor_under(at: Vector3) -> float:
	var flat := at - _cave.global_position
	flat.y = 0.0
	var along := flat.dot(_inward())
	var across := absf(flat.dot(_across()))
	var half_w: float = (Tuning.CAVE_WIDTH + Tuning.CAVE_WALL * 2.0) * 0.5
	var in_cut := (
		across <= half_w + Tuning.CAVE_SLAB_OVERLAP
		and along >= -(Tuning.CAVE_RAMP + Tuning.CAVE_CARVE_MARGIN)
		and along <= Tuning.CAVE_DEPTH
	)
	if in_cut:
		return _floor_y()
	return TERRAIN.height_at(at.x, at.z)


## Drive the player from a start to a target at a fixed speed, stepping
## physics by hand, and return the deepest it ever sank below the walkable
## surface under it.
##
## Velocity is set directly rather than through Input: the test needs an exact
## speed along an exact bearing, and faking held keys through the camera basis
## adds two transforms that can only introduce error.
func _walk(from: Vector3, heading: Vector3, speed: float, steps: int) -> Dictionary:
	_player.mount = null
	_player.velocity = Vector3.ZERO
	_player.global_position = from
	await wait_physics_frames(2)
	var deepest := 0.0
	var deepest_at := _player.global_position
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	for i in steps:
		_player.velocity.x = heading.x * speed
		_player.velocity.z = heading.z * speed
		if not _player.is_on_floor():
			_player.velocity.y += _player.get_gravity().y * delta
		else:
			_player.velocity.y = 0.0
		_player.move_and_slide()
		await wait_physics_frames(1)
		var below := _player.global_position.y - _floor_under(_player.global_position)
		if below < deepest:
			deepest = below
			deepest_at = _player.global_position
	return {"deepest": deepest, "at": deepest_at, "end": _player.global_position}


## Every approach a player can actually take, at every speed the game allows.
##
## The start is out beyond the cutting's outer end on open hillside, and the
## walk runs past the mouth to the back wall, so a fall anywhere along the
## approach, in the doorway or inside the chamber is caught by the same run.
func test_walking_in_never_drops_below_the_cave_floor() -> void:
	var inward := _inward()
	var across := _across()
	var mouth := _cave.global_position
	var floor_y := _floor_y()
	# A body has width, so approaches offset across the axis matter as much as
	# the centre line: the carve and the ramp slab are not the same width, and
	# only an off-centre walk crosses the difference.
	var offsets := [0.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0]
	var speeds := [
		Tuning.PLAYER_SPEED,
		Tuning.PLAYER_RUN_SPEED,
		Tuning.RIDE_SPEED,
	]
	var worst := INF
	var worst_desc := ""
	for offset: float in offsets:
		for speed: float in speeds:
			# Start well outside the cutting, on intact hillside.
			var start_along := -(Tuning.CAVE_RAMP + 6.0)
			var start := (
				mouth
				+ inward * start_along
				+ across * offset
			)
			start.y = TERRAIN.height_at(start.x, start.z) + 1.0
			var steps := int(ceil(
				(start_along * -1.0 + Tuning.CAVE_DEPTH)
				/ speed * Engine.physics_ticks_per_second
			)) + 30
			var result: Dictionary = await _walk(start, inward, speed, steps)
			var deep: float = result["deepest"]
			if deep < worst:
				worst = deep
				worst_desc = "offset %.1f speed %.1f sank %.3f below at %s" % [
					offset, speed, -deep, result["at"]
				]
	gut.p("worst drop: %s (floor y %.3f)" % [worst_desc, floor_y])
	assert_gt(
		worst,
		-2.0,
		"player fell below the walkable surface walking in: %s" % worst_desc
	)


## Jumping in, and arriving down the slope from above.
##
## Downward speed is what a tunnelling body needs, and neither a walk nor a
## sprint has any. A jump lands with PLAYER_JUMP_STRENGTH of it and a run off
## the hillside above the mouth has a full fall's worth.
func test_arriving_from_above_never_drops_through() -> void:
	var inward := _inward()
	var mouth := _cave.global_position
	var floor_y := _floor_y()
	var worst := INF
	var worst_desc := ""
	for drop: float in [2.0, 6.0, 14.0]:
		for along: float in [-8.0, -5.0, -2.0, 0.0, 3.0, 7.0]:
			var start := mouth + inward * along
			start.y = maxf(
				TERRAIN.height_at(start.x, start.z), floor_y
			) + drop
			var result: Dictionary = await _walk(
				start, inward, Tuning.PLAYER_RUN_SPEED, 90
			)
			var deep: float = result["deepest"]
			if deep < worst:
				worst = deep
				worst_desc = "drop %.1f along %.1f sank %.3f below at %s" % [
					drop, along, -deep, result["at"]
				]
	gut.p("worst fall-in: %s (floor y %.3f)" % [worst_desc, floor_y])
	assert_gt(
		worst,
		-2.0,
		"player fell through arriving from above: %s" % worst_desc
	)


## The collider under every point of the cutting and the chamber, measured
## from just above the floor rather than from the sky.
##
## A ray from 40 m up hits the hill's own surface and stops, which is why the
## grid of downward rays from overhead found nothing: it never reaches the
## depth the player walks at. Firing from a metre above the floor asks the
## question the player asks.
func test_the_cutting_has_a_floor_under_every_point() -> void:
	var inward := _inward()
	var across := _across()
	var mouth := _cave.global_position
	var floor_y := _floor_y()
	var space := _player.get_world_3d().direct_space_state
	var holes: Array[String] = []
	# The full span the cutting's floor claims, so the scan cannot stop short
	# of a hole or run out past the floor onto intact hill and call that one.
	var along := -(Tuning.CAVE_RAMP + Tuning.CAVE_CARVE_MARGIN)
	while along <= Tuning.CAVE_DEPTH:
		var side := -(Tuning.CAVE_WIDTH * 0.5 + Tuning.CAVE_WALL)
		while side <= Tuning.CAVE_WIDTH * 0.5 + Tuning.CAVE_WALL:
			var at := mouth + inward * along + across * side
			at.y = floor_y + 1.0
			var query := PhysicsRayQueryParameters3D.create(
				at, at + Vector3.DOWN * 60.0
			)
			var hit := space.intersect_ray(query)
			# Assert the HEIGHT hit, not merely that something was hit. The
			# island's WorldBoundaryShape3D at y=0 lies under every point on
			# the map, so "a ray hit something" passes at full speed while
			# the player is falling four metres past the missing floor.
			if hit.is_empty():
				holes.append("along %.1f side %.1f: nothing under it" % [
					along, side
				])
			elif hit["position"].y < floor_y - 0.5:
				holes.append("along %.1f side %.1f: floor is %.2f, want %.2f" % [
					along, side, hit["position"].y, floor_y
				])
			side += 0.5
		along += 0.5
	if not holes.is_empty():
		gut.p("holes found: %d, first ten:" % holes.size())
		for h in holes.slice(0, 10):
			gut.p("  " + h)
	assert_eq(holes.size(), 0, "cutting has %d points with no floor" % holes.size())
