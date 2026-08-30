extends SceneTree
## Headless pal aggro assertions. Run:
##   godot --headless --path . -s test/pal_aggro_test.gd

class HitTarget:
	extends Node3D

	var hits := 0

	func damage(_amount: float, _from_position: Vector3) -> bool:
		hits += 1
		return true


var _fails := 0


func _init() -> void:
	await process_frame

	await _test_pal_gives_up_without_a_hit()
	await _test_successful_hits_keep_chase_alive()
	await _test_player_hit_resets_give_up_timer()
	await _test_aggressive_pal_does_not_immediately_reacquire()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _test_pal_gives_up_without_a_hit() -> void:
	var target := HitTarget.new()
	get_root().add_child(target)
	target.global_position = Vector3.ZERO
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 10.0), target)
	pal._aggro = 99.0
	pal._enter_attack()

	for i in 6:
		pal._tick_attack(1.0)

	_check(
		"pal gives up after five seconds without a hit",
		pal.state != pal.State.ATTACK and target.hits == 0,
		"state=%s hits=%d" % [pal.State.keys()[pal.state], target.hits],
	)
	pal.queue_free()
	target.queue_free()


func _test_successful_hits_keep_chase_alive() -> void:
	var target := HitTarget.new()
	get_root().add_child(target)
	target.global_position = Vector3.ZERO
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 1.0), target)
	pal._aggro = 99.0
	pal._enter_attack()

	for i in 8:
		pal._tick_attack(1.0)

	_check(
		"successful hits keep the chase alive",
		pal.state == pal.State.ATTACK and target.hits > 0,
		"state=%s hits=%d" % [pal.State.keys()[pal.state], target.hits],
	)
	pal.queue_free()
	target.queue_free()


func _test_player_hit_resets_give_up_timer() -> void:
	var target := HitTarget.new()
	get_root().add_child(target)
	target.global_position = Vector3.ZERO
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 10.0), target)
	pal._aggro = 99.0
	pal._enter_attack()

	for i in 4:
		pal._tick_attack(1.0)
	pal.take_hit(Vector3.ZERO)
	for i in 2:
		pal._tick_attack(1.0)

	_check(
		"player hit resets the give-up timer",
		pal.state == pal.State.ATTACK,
		"state=%s hits=%d" % [pal.State.keys()[pal.state], target.hits],
	)
	pal.queue_free()
	target.queue_free()


func _test_aggressive_pal_does_not_immediately_reacquire() -> void:
	var target := HitTarget.new()
	get_root().add_child(target)
	target.global_position = Vector3.ZERO
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 8.0), target)
	pal.aggressive = true
	pal._enter_attack()

	for i in 6:
		pal._tick_attack(1.0)

	_check(
		"aggressive pal suppresses sight aggro after giving up",
		pal.state != pal.State.ATTACK and not pal._wants_attack(),
		"state=%s" % pal.State.keys()[pal.state],
	)

	target.global_position = Vector3(0.0, 0.0, 20.0)
	pal._wants_attack()
	target.global_position = Vector3.ZERO
	_check(
		"aggressive pal can reacquire after the player leaves and returns",
		pal._wants_attack(),
		"state=%s" % pal.State.keys()[pal.state],
	)
	pal.queue_free()
	target.queue_free()


func _spawn_pal(pos: Vector3, target: Node3D):
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	get_root().add_child(pal)
	await process_frame
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	pal._player_cache = target
	return pal
