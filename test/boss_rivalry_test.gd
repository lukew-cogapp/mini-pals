extends SceneTree
## Headless boss-rivalry assertions. Run:
##   godot --headless --path . -s test/boss_rivalry_test.gd
##
## Boss and Demon are both AGGRESSIVE with different display names, so wild
## rivalry treated them as fair targets for each other. With twelve demons
## around the altar and the player more than PAL_AGGRO_RADIUS away, the
## summoned King was softened or killed offscreen by his own guard, spending
## the key on a fight that never happened.

var _fails := 0
var _world
var _tuning


func _init() -> void:
	await process_frame
	_tuning = get_root().get_node("Tuning")
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	for i in 10:
		await physics_frame

	await _test_the_king_and_the_demons_leave_each_other_alone()
	await _test_demons_still_fight_other_species()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _spawn(path: String, at: Vector3):
	var pal = load(path).instantiate()
	_world.add_child(pal)
	await physics_frame
	pal.global_position = at
	await physics_frame
	return pal


func _test_the_king_and_the_demons_leave_each_other_alone() -> void:
	var boss = await _spawn("res://scenes/pal_boss.tscn", _tuning.ALTAR_POS + Vector3(5, 0, 0))
	boss.level = _tuning.BOSS_LEVEL
	var demon = await _spawn("res://scenes/pal_demon.tscn", _tuning.ALTAR_POS + Vector3(7, 0, 0))

	_check("a demon does not treat the King as a rival", not demon._is_rival(boss),
		"is_rival=%s" % demon._is_rival(boss))
	_check("the King does not treat a demon as a rival", not boss._is_rival(demon),
		"is_rival=%s" % boss._is_rival(demon))

	var before = boss.hp
	for i in 400:
		await physics_frame
	_check("the King keeps his health with a demon beside him",
		boss.hp == before and not boss.dying,
		"hp %d -> %d dying=%s" % [before, boss.hp, boss.dying])

	boss.queue_free()
	demon.queue_free()
	await physics_frame


## The exemption must not disarm wild rivalry generally.
func _test_demons_still_fight_other_species() -> void:
	var demon = await _spawn("res://scenes/pal_demon.tscn", Vector3(0, 0, -30))
	var wolf = await _spawn("res://scenes/pal_wolf.tscn", Vector3(2, 0, -30))

	_check("a demon still treats a wolf as a rival", demon._is_rival(wolf),
		"is_rival=%s" % demon._is_rival(wolf))

	demon.queue_free()
	wolf.queue_free()
	await physics_frame
