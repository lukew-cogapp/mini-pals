extends GutTest
## Headless boss-rivalry assertions.
##
## Boss and Demon are both AGGRESSIVE with different display names, so wild
## rivalry treated them as fair targets for each other. With twelve demons
## around the altar and the player more than PAL_AGGRO_RADIUS away, the
## summoned King was softened or killed offscreen by his own guard, spending
## the key on a fight that never happened.

var _world: Node


## Freed in after_all with free rather than by add_child_autofree, which frees
## at the end of the calling test and would leave later tests without a world.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(10)


func after_all() -> void:
	_world.free()


func _spawn(path: String, at: Vector3) -> Node3D:
	var pal: Node3D = load(path).instantiate()
	_world.add_child(pal)
	await wait_physics_frames(1)
	pal.global_position = at
	await wait_physics_frames(1)
	return pal


func test_the_king_and_the_demons_leave_each_other_alone() -> void:
	var boss := await _spawn("res://scenes/pal_boss.tscn", Tuning.ALTAR_POS + Vector3(5, 0, 0))
	boss.level = Tuning.BOSS_LEVEL
	var demon := await _spawn("res://scenes/pal_demon.tscn", Tuning.ALTAR_POS + Vector3(7, 0, 0))

	assert_false(demon._is_rival(boss), "a demon does not treat the King as a rival")
	assert_false(boss._is_rival(demon), "the King does not treat a demon as a rival")

	var before = boss.hp
	await wait_physics_frames(400)
	assert_true(
		boss.hp == before and not boss.dying,
		(
			"the King keeps his health with a demon beside him: hp %d -> %d dying=%s"
			% [before, boss.hp, boss.dying]
		),
	)

	boss.queue_free()
	demon.queue_free()
	await wait_physics_frames(1)


## The exemption must not disarm wild rivalry generally.
func test_demons_still_fight_other_species() -> void:
	var demon := await _spawn("res://scenes/pal_demon.tscn", Vector3(0, 0, -30))
	var wolf := await _spawn("res://scenes/pal_wolf.tscn", Vector3(2, 0, -30))

	assert_true(demon._is_rival(wolf), "a demon still treats a wolf as a rival")

	demon.queue_free()
	wolf.queue_free()
	await wait_physics_frames(1)
