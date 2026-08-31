extends GutTest
## A pal walking at an obstacle steers around it rather than into it.
##
## Before this the only recovery was the unstick: jam for PAL_STUCK_TIME,
## then veer off at a random angle for PAL_STUCK_ESCAPE_TIME. That reads as
## walking face-first into a tree and lurching away, and with 260 trees and
## 190 rocks on the island a chase crosses one often.
##
## The assertion is ground covered towards the goal, not whether a collision
## happened. A pal sliding along a trunk collides every frame while making
## perfectly good progress, which is the same reason `_move_towards` measures
## progress rather than `get_slide_collision_count()`.

const PAL := preload("res://scenes/pal_wolf.tscn")

var _world: Node3D


func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(10)


func after_all() -> void:
	_world.free()


## A tree-sized cylinder standing between the pal and where it wants to go.
func _add_obstacle(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.8
	cyl.height = 4.0
	shape.shape = cyl
	body.add_child(shape)
	_world.add_child(body)
	body.global_position = at + Vector3.UP * 2.0
	return body


## Drive a pal at a goal for `seconds` and report how much closer it got.
##
## The pal is parked in IDLE and driven by hand. A pal in any moving state
## runs its own state machine in `_physics_process` as well, so it would be
## stepped twice and every measured speed would read double; IDLE zeroes the
## velocity and slides nowhere, which is what makes hand-driving safe.
func _drive(from: Vector3, goal: Vector3, seconds: float) -> float:
	var pal: Node3D = PAL.instantiate()
	_world.add_child(pal)
	await wait_physics_frames(1)
	pal.global_position = from
	pal.state = pal.State.IDLE
	await wait_physics_frames(2)
	var start_gap := pal.global_position.distance_to(goal)
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var steps := int(seconds / delta)
	for i in steps:
		pal._move_towards(goal, Tuning.PAL_CHASE_SPEED, delta)
		pal.move_and_slide()
		await wait_physics_frames(1)
	var closed: float = start_gap - pal.global_position.distance_to(goal)
	pal.queue_free()
	await wait_physics_frames(1)
	return closed


## The whole point: a trunk on the direct line must not stop the pal.
##
## Six metres of travel is asked for over three seconds at PAL_CHASE_SPEED
## (4.0, so twelve metres unobstructed). Ploughing into the trunk closes
## roughly the two metres up to it and then stalls, so the bar sits well
## above that and well below the clear run.
func test_a_pal_gets_past_a_tree_on_its_line() -> void:
	var from := Vector3(0.0, 1.0, -60.0)
	var goal := Vector3(0.0, 1.0, -48.0)
	var tree := _add_obstacle(Vector3(0.0, 0.0, -57.0))
	await wait_physics_frames(2)
	var closed: float = await _drive(from, goal, 3.0)
	tree.queue_free()
	await wait_physics_frames(1)
	assert_gt(
		closed, 6.0,
		"a pal blocked by a tree closed only %.2f m of a 12 m run" % closed
	)


## Steering must not cost anything on an empty line, or every chase across
## open grass pays for the trees that are not there.
func test_an_unobstructed_pal_still_runs_straight() -> void:
	var from := Vector3(30.0, 1.0, -60.0)
	var goal := Vector3(30.0, 1.0, -48.0)
	var closed: float = await _drive(from, goal, 2.0)
	assert_gt(
		closed, 7.0,
		"a pal on a clear line closed only %.2f m of an 8 m run" % closed
	)
