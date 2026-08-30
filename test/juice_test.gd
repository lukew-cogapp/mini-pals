extends GutTest
## Headless game-feel assertions, ported from test/juice_test.gd.
##
## Every one of these is a bug that inspection would miss: a shake that never
## settles leaves the camera crooked forever, a slow-mo timer that respects
## time_scale restores four times late, a hurt flash on a shared ColorRect
## eats the death fade, and a fixed shake count leaks the roll.


## Long enough for SHAKE_DECAY to eat a full-strength kick several times over.
func _settle_frames() -> int:
	return int(60.0 / Tuning.SHAKE_DECAY) + 30


func test_shake_settles_to_zero() -> void:
	var player: Node = add_child_autofree(load("res://scenes/player.tscn").instantiate())
	await wait_process_frames(1)
	player.set_physics_process(false)

	var arm = player.get_node("CameraPivot/SpringArm3D")
	var rest = arm.position
	player.kick(Tuning.SHAKE_HURT)
	await wait_process_frames(2)
	var moved = arm.position.distance_to(rest)
	assert_gt(moved, 0.0, "a kick moves the camera arm: offset=%.4f" % moved)

	await wait_process_frames(_settle_frames())
	var left = arm.position.distance_to(rest)
	assert_eq(
		left, 0.0,
		"shake settles back to the rest position: offset=%.6f rest=%s now=%s"
		% [left, rest, arm.position],
	)

	# Shake writes arm.position every frame. If that had been done by
	# rebuilding the arm or clearing its state, the camera would start
	# colliding with the player's own capsule and snap into the head.
	# There is no getter for the exclusion list, so check the effect: the
	# player's own capsule sits inside the arm's sweep, and without the
	# exclusion the arm would collapse onto it and pull the camera into the
	# head. Shake writes arm.position every frame, so this must survive it.
	await wait_process_frames(4)
	var reach = arm.get_hit_length()
	assert_true(
		is_equal_approx(reach, arm.spring_length),
		(
			"the arm still excludes the player capsule: reach=%.3f spring_length=%.3f"
			% [reach, arm.spring_length]
		),
	)

	# damage() must feed the same shake, and it must settle from there too.
	player.hp = Tuning.PLAYER_MAX_HP
	player.damage(Tuning.PLAYER_MAX_HP * 0.5, player.global_position + Vector3.FORWARD)
	await wait_process_frames(2)
	var hurt_offset = arm.position.distance_to(rest)
	assert_gt(hurt_offset, 0.0, "taking damage shakes the camera: offset=%.4f" % hurt_offset)
	await wait_process_frames(_settle_frames())
	assert_eq(arm.position, rest, "the damage shake settles too: now=%s" % arm.position)


func test_slowmo_restores() -> void:
	var cube: Node = add_child_autofree(load("res://scenes/pal_cube.tscn").instantiate())
	await wait_process_frames(1)
	cube.set_physics_process(false)

	assert_eq(
		Engine.time_scale, 1.0,
		"time_scale is 1.0 before a catch: scale=%.3f" % Engine.time_scale,
	)

	var done := false
	var run := func() -> void:
		await cube._slowmo()
		done = true
	run.call()
	await wait_process_frames(1)
	var during = Engine.time_scale
	assert_lt(during, 1.0, "time_scale drops during the catch: scale=%.3f" % during)

	# Freed mid-slow-mo: the restore must not depend on this node surviving.
	cube.queue_free()
	var waited := 0.0
	while Engine.time_scale != 1.0 and waited < 5.0:
		waited += get_tree().root.get_process_delta_time()
		await wait_process_frames(1)
	assert_eq(
		Engine.time_scale, 1.0,
		(
			"time_scale is exactly 1.0 after the catch, even if the cube was freed: scale=%.6f waited=%.2fs done=%s"
			% [Engine.time_scale, waited, done]
		),
	)


## Presentation only: a loss can break open early, a win never does. The roll
## itself is untouched, which catch_chance_test already pins.
func test_shake_count_hides_the_roll() -> void:
	var cube: Node = add_child_autofree(load("res://scenes/pal_cube.tscn").instantiate())
	await wait_process_frames(1)
	cube.set_physics_process(false)

	var short := 0
	var seen := {}
	for _i in 400:
		var n = cube.shake_count(false)
		seen[n] = true
		if n < Tuning.CATCH_SHAKE_COUNT:
			short += 1
		if n < 1 or n > Tuning.CATCH_SHAKE_COUNT:
			short = -1
			break
	assert_gt(
		short, 0,
		"a failed catch can shake fewer than the full count: short=%d of 400, counts seen=%s"
		% [short, seen.keys()],
	)

	var always := true
	for _i in 400:
		if cube.shake_count(true) != Tuning.CATCH_SHAKE_COUNT:
			always = false
	assert_true(
		always,
		"a successful catch always shakes the full count: count=%d" % Tuning.CATCH_SHAKE_COUNT,
	)


## The red wash borrows the same ColorRect as the death fade. A hit landing
## mid-fade must leave the fade running to black.
func test_hurt_does_not_cancel_death_fade() -> void:
	var fade = Hud.get_node("Fade")
	fade.color = Color(0.0, 0.0, 0.0, 0.0)

	Hud.fade_to(1.0, Tuning.PLAYER_DEATH_TIME)
	await wait_process_frames(2)
	Hud.hurt_flash()
	var at_hit = fade.color.a

	var waited := 0.0
	while waited < Tuning.PLAYER_DEATH_TIME + 0.5:
		waited += get_tree().root.get_process_delta_time()
		await wait_process_frames(1)
	assert_true(
		is_equal_approx(fade.color.a, 1.0) and fade.color.r == 0.0,
		(
			"the death fade still reaches black after a hit lands mid-fade: alpha_at_hit=%.3f final=%s"
			% [at_hit, fade.color]
		),
	)

	Hud.fade_to(0.0, 0.01)
	await wait_process_frames(3)

	# With no fade running the same call must actually wash the screen red.
	Hud.hurt_flash()
	await wait_process_frames(2)
	assert_true(
		fade.color.r > 0.0 and fade.color.a > 0.0,
		"a hit with no fade running washes the screen red: color=%s" % fade.color,
	)
	var settle := 0.0
	while settle < Tuning.HURT_FLASH_TIME + 0.3:
		settle += get_tree().root.get_process_delta_time()
		await wait_process_frames(1)
	assert_eq(fade.color.a, 0.0, "the red wash clears itself: color=%s" % fade.color)
