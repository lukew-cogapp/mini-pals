extends GutTest
## Pal aggro assertions, ported from test/pal_aggro_test.gd.

class HitTarget:
	extends Node3D

	var hits := 0

	func damage(_amount: float, _from_position: Vector3) -> bool:
		hits += 1
		return true


## Party outlives a single suite now that every test shares one process, and
## punch damage scales with player level and the damage buff
## (Pal.player_punch_damage). Left at another script's level, one take_hit
## kills the wolf outright and the give-up timer never gets to run.
func before_all() -> void:
	Party.members.clear()
	Party.active = null
	Party.player_level = 1


func _spawn_pal(pos: Vector3, target: Node3D):
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	add_child_autofree(pal)
	await wait_process_frames(1)
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	pal._player_cache = target
	return pal


func test_pal_gives_up_without_a_hit() -> void:
	var target := HitTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3.ZERO
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 10.0), target)
	pal._aggro = 99.0
	pal._enter_attack()

	for i in 6:
		pal._tick_attack(1.0)

	assert_true(
		pal.state != pal.State.ATTACK and target.hits == 0,
		"pal gives up after five seconds without a hit  state=%s hits=%d"
		% [pal.State.keys()[pal.state], target.hits],
	)


func test_successful_hits_keep_chase_alive() -> void:
	var target := HitTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3.ZERO
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 1.0), target)
	pal._aggro = 99.0
	pal._enter_attack()

	for i in 8:
		pal._tick_attack(1.0)

	assert_true(
		pal.state == pal.State.ATTACK and target.hits > 0,
		"successful hits keep the chase alive  state=%s hits=%d"
		% [pal.State.keys()[pal.state], target.hits],
	)


func test_player_hit_resets_give_up_timer() -> void:
	var target := HitTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3.ZERO
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 10.0), target)
	pal._aggro = 99.0
	pal._enter_attack()

	for i in 4:
		pal._tick_attack(1.0)
	pal.take_hit(Vector3.ZERO)
	for i in 2:
		pal._tick_attack(1.0)

	assert_true(
		pal.state == pal.State.ATTACK,
		"player hit resets the give-up timer  state=%s hits=%d"
		% [pal.State.keys()[pal.state], target.hits],
	)


func test_aggressive_pal_does_not_immediately_reacquire() -> void:
	var target := HitTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3.ZERO
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 8.0), target)
	pal.temperament = pal.Temperament.AGGRESSIVE
	pal._enter_attack()

	for i in 6:
		pal._tick_attack(1.0)

	assert_true(
		pal.state != pal.State.ATTACK and not pal._wants_attack(),
		"aggressive pal suppresses sight aggro after giving up  state=%s"
		% pal.State.keys()[pal.state],
	)

	target.global_position = Vector3(0.0, 0.0, 20.0)
	pal._wants_attack()
	target.global_position = Vector3.ZERO
	assert_true(
		pal._wants_attack(),
		"aggressive pal can reacquire after the player leaves and returns  state=%s"
		% pal.State.keys()[pal.state],
	)
