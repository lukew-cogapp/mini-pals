extends GutTest
## Pal unstick assertions, ported from test/pal_stuck_test.gd.
##
## A pal walked into a wall must stop pushing into it and end up somewhere
## else; a pal walking freely must NEVER trigger the unstick, which is the
## regression that matters, since a false positive turns every pal in the
## world into a drunk.

var _ground: StaticBody3D


## Without a floor the pals fall away from the wall before they ever reach it.
func before_all() -> void:
	_ground = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	_ground.add_child(shape)
	add_child(_ground)


func after_all() -> void:
	_ground.free()


## A static box the pal cannot walk through, on the pals' own layer so their
## collider actually meets it.
func _wall(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 4.0, 1.0)
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = at
	return body


func _spawn_pal(pos: Vector3):
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	add_child_autofree(pal)
	await wait_process_frames(1)
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	return pal


func test_walled_pal_escapes() -> void:
	var wall := _wall(Vector3(0.0, 1.0, -3.0))
	var pal = await _spawn_pal(Vector3.ZERO)
	pal.state = pal.State.WANDER
	# Straight through the wall, so pushing into it is the only way there.
	pal._target = Vector3(0.0, 0.0, -20.0)

	var escaped := false
	var pressed_late := 0.0
	for i in 180:
		await wait_physics_frames(1)
		if pal._escape_time > 0.0:
			escaped = true
		if i > 120:
			pressed_late = maxf(pressed_late, -pal.velocity.z)

	var moved := Vector2(pal.global_position.x, pal.global_position.z).length()
	assert_true(
		escaped,
		"a walled pal notices it is stuck  escape never fired, pos=%s" % pal.global_position,
	)
	assert_true(
		pressed_late < Tuning.PAL_WALK_SPEED * 0.9,
		"a walled pal stops driving into the wall  late forward push=%.2f" % pressed_late,
	)
	assert_true(
		moved > 1.0,
		"a walled pal ends up somewhere else  moved=%.2f pos=%s" % [moved, pal.global_position],
	)


func test_free_pal_never_unsticks() -> void:
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 0.0))
	pal.state = pal.State.WANDER
	pal._target = Vector3(0.0, 0.0, -60.0)

	var tripped := false
	for i in 180:
		await wait_physics_frames(1)
		# Keep the goal ahead of it, so it is always genuinely walking.
		pal._target = pal.global_position + Vector3(0.0, 0.0, -20.0)
		if pal._escape_time > 0.0:
			tripped = true

	assert_true(
		not tripped,
		"a freely walking pal never unsticks  escape fired at pos=%s" % pal.global_position,
	)


func test_fleeing_pal_stays_fleeing() -> void:
	# Wall and threat close together, so the pal is walled in while still
	# inside PAL_FLEE_DISTANCE and cannot simply outrun the fear.
	var threat := Node3D.new()
	add_child_autofree(threat)
	threat.global_position = Vector3(0.0, 0.0, 2.0)
	var wall := _wall(Vector3(0.0, 1.0, -2.0))
	var pal = await _spawn_pal(Vector3.ZERO)
	pal._player_cache = threat
	pal.state = pal.State.FLEE

	# Sampled while the escape is running, not at the end: once it has slid
	# clear of the wall it is out of PAL_FLEE_DISTANCE and idles for good
	# reasons of its own, which says nothing about the unstick.
	var escaped := false
	var state_during := -1
	for i in 180:
		await wait_physics_frames(1)
		if pal._escape_time > 0.0:
			escaped = true
			state_during = pal.state

	assert_true(
		escaped,
		"a fleeing pal unsticks  never triggered, pos=%s" % pal.global_position,
	)
	assert_true(
		state_during == pal.State.FLEE,
		"a fleeing pal is still fleeing while it unsticks  state=%s"
		% ("none" if state_during < 0 else pal.State.keys()[state_during]),
	)


## A follower jostling against the player it has already reached moves almost
## nowhere every frame, which is exactly what the stuck check looks for. It
## must not fire.
func test_arrived_follower_is_not_stuck() -> void:
	var player := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.5
	shape.shape = caps
	player.add_child(shape)
	add_child_autofree(player)
	player.global_position = Vector3.ZERO

	var pal = await _spawn_pal(Vector3(0.0, 0.0, 0.6))
	pal.caught = true
	pal._player_cache = player
	pal.state = pal.State.FOLLOW

	var tripped := false
	for i in 180:
		await wait_physics_frames(1)
		if pal._escape_time > 0.0:
			tripped = true

	assert_true(
		not tripped,
		"a follower pressed against the player is not stuck  escape fired, pos=%s" % pal.global_position,
	)
