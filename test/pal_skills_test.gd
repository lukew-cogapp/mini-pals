extends GutTest
## Assertions for the two active-pal jobs that change the player's own
## actions, ported from test/pal_skills_test.gd.
##
## Both are read live off Party.active, so the thing worth pinning is that
## swapping the pal out really does put the player back where they started.

## --- Demon: the player hits harder ----------------------------------------

func test_demon_raises_punch_damage() -> void:
	var target = await _spawn("res://scenes/pal_wolf.tscn")
	target.level = 5
	target.max_hp = 40
	target.hp = 40
	var plain: int = _punch_drop(target)

	var demon = await _spawn("res://scenes/pal_demon.tscn")
	demon.level = 5
	_activate(demon)
	target.hp = 40
	var buffed: int = _punch_drop(target)
	_recall()

	assert_true(
		buffed > plain,
		"a demon out makes the player's punch take more hp  plain=%d buffed=%d" % [plain, buffed],
	)


func test_demon_buff_is_capped() -> void:
	var demon = await _spawn("res://scenes/pal_demon.tscn")
	# Well past PAL_LEVEL_MAX, so an uncapped buff would run away.
	demon.level = 50
	_activate(demon)
	var buff: float = Party.buff(&"damage")
	_recall()
	assert_true(
		is_equal_approx(buff, Tuning.DEMON_DAMAGE_BUFF_CAP),
		"the demon damage buff is capped  buff=%.2f cap=%.2f" % [buff, Tuning.DEMON_DAMAGE_BUFF_CAP],
	)


func test_no_demon_means_normal_damage() -> void:
	var target = await _spawn("res://scenes/pal_wolf.tscn")
	target.max_hp = 40
	target.hp = 40
	var drop: int = _punch_drop(target)
	var expected: int = (
		Tuning.PUNCH_DAMAGE
		+ int((Party.player_level - 1) * Tuning.PUNCH_DAMAGE_PER_PLAYER_LEVEL)
	)
	assert_true(
		drop == expected and Party.buff(&"damage") == 0.0,
		"with no demon out the punch is the plain one  drop=%d expected=%d" % [drop, expected],
	)


func _punch_drop(target) -> int:
	var before: int = target.hp
	target.take_hit(Vector3(0.0, 0.0, 10.0))
	return before - target.hp


## --- Mushroom King: throws stop costing cubes ------------------------------

func test_king_throws_are_free() -> void:
	var king = await _spawn("res://scenes/pal_boss.tscn")
	_activate(king)
	Inventory.add("cube", 5)
	var before: int = Inventory.count("cube")
	var player = await _spawn_player()
	player._throw_cube(Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -1.0))
	var after: int = Inventory.count("cube")
	assert_true(
		after == before and Party.infinite_cubes(),
		"with the King out a throw costs no cube  cubes %d -> %d" % [before, after],
	)
	_recall()


func test_throws_without_the_king_cost_a_cube() -> void:
	Inventory.add("cube", 5)
	var before: int = Inventory.count("cube")
	var player = await _spawn_player()
	player._throw_cube(Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -1.0))
	var after: int = Inventory.count("cube")
	assert_true(
		after == before - 1 and not Party.infinite_cubes(),
		"with no King out a throw spends a cube  cubes %d -> %d" % [before, after],
	)


func test_hud_shows_infinity_with_the_king() -> void:
	var plain_stock: int = Inventory.count("cube")
	Hud._refresh()
	var plain: String = Hud._cube_count.text

	var king = await _spawn("res://scenes/pal_boss.tscn")
	_activate(king)
	Hud._refresh()
	var infinite: String = Hud._cube_count.text
	_recall()

	assert_true(
		infinite == Tuning.INFINITE_CUBE_TEXT and plain == str(plain_stock),
		"the HUD cube readout is not a bare zero while the King is out  plain=%s king=%s"
		% [plain, infinite],
	)


## --- Fixtures --------------------------------------------------------------

## Put a pal out without going through a catch, which would also grant XP and
## drops and move the assertions around under us.
## add_child_autofree frees with queue_free, which has not run when GUT counts
## children still parented at the end of the script. One frame drains it.
func after_each() -> void:
	await wait_process_frames(1)


## GUT still reports three unfreed children here, the last test's king and
## player. Extra drain frames do not clear them, so something outlives the
## autofree queue rather than merely sitting in it. Cosmetic: all six
## assertions pass and the run exits 0.
func after_all() -> void:
	await wait_process_frames(1)


func _activate(pal) -> void:
	pal.caught = true
	Party.active = pal


func _recall() -> void:
	Party.active = null


func _spawn(path: String):
	var pal = load(path).instantiate()
	add_child_autofree(pal)
	await wait_process_frames(1)
	pal.global_position = Vector3.ZERO
	pal.set_physics_process(false)
	return pal


## A real player, so the cube spend goes through the shipped throw path.
func _spawn_player():
	var player = load("res://scenes/player.tscn").instantiate()
	add_child_autofree(player)
	await wait_process_frames(1)
	player.set_physics_process(false)
	player.set_process(false)
	return player
