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


## A static box the pal cannot walk through.
##
## Deliberately NOT on layer 1, which is what the steering whiskers look at.
## The whiskers would see this wall and steer along it, and the pal would
## never become stuck at all, which is the whiskers doing their job but
## leaves the unstick untested. The unstick exists for what a forward ray
## cannot see, so the wall here is invisible to the rays and solid to the
## body, which is exactly that case.
func _wall(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 4
	# The pal's body has to meet it even though the rays do not, so widen the
	# pal's own mask where it is spawned rather than putting the wall on the
	# layer the whiskers read.
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
	# Sees the test wall (layer 5) as well as the world it normally collides
	# with. The steering whiskers read layer 1 only, so the wall stops the
	# body without the rays ever noticing it.
	pal.collision_mask |= 1 << 4
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

	# Sampled over the whole run, never on one frame. The escape picks a
	# random turn and then re-wanders to a random target, so on an unlucky
	# roll the pal is heading back at the wall on any given late frame while
	# having escaped perfectly well in between. Asserting where it happens to
	# be at frame 180 is what made this suite flake under load.
	var escaped := false
	var eased_off := false
	var furthest := 0.0
	for _i in 180:
		await wait_physics_frames(1)
		if pal._escape_time > 0.0:
			escaped = true
		# Only once it has noticed, and only while it is actually moving:
		# before the escape fires it is jammed at the wall by construction,
		# and a zero velocity would pass this without meaning anything.
		if escaped and pal.velocity.length() > 0.1:
			if -pal.velocity.z < Tuning.PAL_WALK_SPEED * 0.9:
				eased_off = true
		furthest = maxf(
			furthest, Vector2(pal.global_position.x, pal.global_position.z).length()
		)

	assert_true(
		escaped,
		"a walled pal notices it is stuck  escape never fired, pos=%s" % pal.global_position,
	)
	assert_true(
		eased_off,
		"a walled pal stops driving into the wall  never eased off in 180 frames",
	)
	assert_true(
		furthest > 1.0,
		"a walled pal gets away from the wall  furthest=%.2f pos=%s"
		% [furthest, pal.global_position],
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
