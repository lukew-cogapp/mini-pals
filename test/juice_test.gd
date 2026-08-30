extends SceneTree
## Headless game-feel assertions. Run:
##   godot --headless --path . -s test/juice_test.gd
##
## Every one of these is a bug that inspection would miss: a shake that never
## settles leaves the camera crooked forever, a slow-mo timer that respects
## time_scale restores four times late, a hurt flash on a shared ColorRect
## eats the death fade, and a fixed shake count leaks the roll.
##
## Untyped on purpose, like pal_aggro_test: naming a class_name here pulls it
## in for compilation before the autoloads register.

var _fails := 0


func _init() -> void:
	await process_frame

	await _test_shake_settles_to_zero()
	await _test_slowmo_restores()
	await _test_shake_count_hides_the_roll()
	await _test_hurt_does_not_cancel_death_fade()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name, ok, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


## Long enough for SHAKE_DECAY to eat a full-strength kick several times over.
func _settle_frames() -> int:
	return int(60.0 / Tuning.SHAKE_DECAY) + 30


func _test_shake_settles_to_zero() -> void:
	var player = load("res://scenes/player.tscn").instantiate()
	get_root().add_child(player)
	await process_frame
	player.set_physics_process(false)

	var arm = player.get_node("CameraPivot/SpringArm3D")
	var rest = arm.position
	player.kick(Tuning.SHAKE_HURT)
	await process_frame
	await process_frame
	var moved = arm.position.distance_to(rest)
	_check("a kick moves the camera arm", moved > 0.0, "offset=%.4f" % moved)

	for _i in _settle_frames():
		await process_frame
	var left = arm.position.distance_to(rest)
	_check("shake settles back to the rest position", left == 0.0,
		"offset=%.6f rest=%s now=%s" % [left, rest, arm.position])

	# Shake writes arm.position every frame. If that had been done by
	# rebuilding the arm or clearing its state, the camera would start
	# colliding with the player's own capsule and snap into the head.
	# There is no getter for the exclusion list, so check the effect: the
	# player's own capsule sits inside the arm's sweep, and without the
	# exclusion the arm would collapse onto it and pull the camera into the
	# head. Shake writes arm.position every frame, so this must survive it.
	for _i in 4:
		await process_frame
	var reach = arm.get_hit_length()
	_check("the arm still excludes the player capsule",
		is_equal_approx(reach, arm.spring_length),
		"reach=%.3f spring_length=%.3f" % [reach, arm.spring_length])

	# damage() must feed the same shake, and it must settle from there too.
	player.hp = Tuning.PLAYER_MAX_HP
	player.damage(Tuning.PLAYER_MAX_HP * 0.5, player.global_position + Vector3.FORWARD)
	await process_frame
	await process_frame
	var hurt_offset = arm.position.distance_to(rest)
	_check("taking damage shakes the camera", hurt_offset > 0.0,
		"offset=%.4f" % hurt_offset)
	for _i in _settle_frames():
		await process_frame
	_check("the damage shake settles too", arm.position == rest, "now=%s" % arm.position)

	player.queue_free()
	await process_frame


func _test_slowmo_restores() -> void:
	var cube = load("res://scenes/pal_cube.tscn").instantiate()
	get_root().add_child(cube)
	await process_frame
	cube.set_physics_process(false)

	_check("time_scale is 1.0 before a catch", Engine.time_scale == 1.0,
		"scale=%.3f" % Engine.time_scale)

	var done := false
	var run := func() -> void:
		await cube._slowmo()
		done = true
	run.call()
	await process_frame
	var during = Engine.time_scale
	_check("time_scale drops during the catch", during < 1.0, "scale=%.3f" % during)

	# Freed mid-slow-mo: the restore must not depend on this node surviving.
	cube.queue_free()
	var waited := 0.0
	while Engine.time_scale != 1.0 and waited < 5.0:
		waited += get_root().get_process_delta_time()
		await process_frame
	_check("time_scale is exactly 1.0 after the catch, even if the cube was freed",
		Engine.time_scale == 1.0, "scale=%.6f waited=%.2fs done=%s" % [
			Engine.time_scale, waited, done])


## Presentation only: a loss can break open early, a win never does. The roll
## itself is untouched, which catch_chance_test already pins.
func _test_shake_count_hides_the_roll() -> void:
	var cube = load("res://scenes/pal_cube.tscn").instantiate()
	get_root().add_child(cube)
	await process_frame
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
	_check("a failed catch can shake fewer than the full count",
		short > 0, "short=%d of 400, counts seen=%s" % [short, seen.keys()])

	var always := true
	for _i in 400:
		if cube.shake_count(true) != Tuning.CATCH_SHAKE_COUNT:
			always = false
	_check("a successful catch always shakes the full count", always,
		"count=%d" % Tuning.CATCH_SHAKE_COUNT)

	cube.queue_free()
	await process_frame


## The red wash borrows the same ColorRect as the death fade. A hit landing
## mid-fade must leave the fade running to black.
func _test_hurt_does_not_cancel_death_fade() -> void:
	# Hud is a scene autoload, so the name is not a compile-time identifier
	# here the way Tuning is; reach it by node path once the tree is up.
	var hud = get_root().get_node("Hud")
	var fade = hud.get_node("Fade")
	fade.color = Color(0.0, 0.0, 0.0, 0.0)

	hud.fade_to(1.0, Tuning.PLAYER_DEATH_TIME)
	await process_frame
	await process_frame
	hud.hurt_flash()
	var at_hit = fade.color.a

	var waited := 0.0
	while waited < Tuning.PLAYER_DEATH_TIME + 0.5:
		waited += get_root().get_process_delta_time()
		await process_frame
	_check("the death fade still reaches black after a hit lands mid-fade",
		is_equal_approx(fade.color.a, 1.0) and fade.color.r == 0.0,
		"alpha_at_hit=%.3f final=%s" % [at_hit, fade.color])

	hud.fade_to(0.0, 0.01)
	await process_frame
	await process_frame
	await process_frame

	# With no fade running the same call must actually wash the screen red.
	hud.hurt_flash()
	await process_frame
	await process_frame
	_check("a hit with no fade running washes the screen red",
		fade.color.r > 0.0 and fade.color.a > 0.0, "color=%s" % fade.color)
	var settle := 0.0
	while settle < Tuning.HURT_FLASH_TIME + 0.3:
		settle += get_root().get_process_delta_time()
		await process_frame
	_check("the red wash clears itself", fade.color.a == 0.0, "color=%s" % fade.color)
