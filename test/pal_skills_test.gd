extends SceneTree
## Headless assertions for the two active-pal jobs that change the player's
## own actions. Run:
##   godot --headless --path . -s test/pal_skills_test.gd
##
## Both are read live off Party.active, so the thing worth pinning is that
## swapping the pal out really does put the player back where they started.

var _fails := 0


func _init() -> void:
	await process_frame

	await _test_demon_raises_punch_damage()
	await _test_demon_buff_is_capped()
	await _test_no_demon_means_normal_damage()
	await _test_king_throws_are_free()
	await _test_throws_without_the_king_cost_a_cube()
	await _test_hud_shows_infinity_with_the_king()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


## --- Demon: the player hits harder ----------------------------------------

func _test_demon_raises_punch_damage() -> void:
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

	_check(
		"a demon out makes the player's punch take more hp",
		buffed > plain,
		"plain=%d buffed=%d" % [plain, buffed],
	)
	target.queue_free()
	demon.queue_free()


func _test_demon_buff_is_capped() -> void:
	var demon = await _spawn("res://scenes/pal_demon.tscn")
	# Well past PAL_LEVEL_MAX, so an uncapped buff would run away.
	demon.level = 50
	_activate(demon)
	var buff: float = _party().buff(&"damage")
	_recall()
	_check(
		"the demon damage buff is capped",
		is_equal_approx(buff, Tuning.DEMON_DAMAGE_BUFF_CAP),
		"buff=%.2f cap=%.2f" % [buff, Tuning.DEMON_DAMAGE_BUFF_CAP],
	)
	demon.queue_free()


func _test_no_demon_means_normal_damage() -> void:
	var target = await _spawn("res://scenes/pal_wolf.tscn")
	target.max_hp = 40
	target.hp = 40
	var drop: int = _punch_drop(target)
	var expected: int = (
		Tuning.PUNCH_DAMAGE
		+ int((_party().player_level - 1) * Tuning.PUNCH_DAMAGE_PER_PLAYER_LEVEL)
	)
	_check(
		"with no demon out the punch is the plain one",
		drop == expected and _party().buff(&"damage") == 0.0,
		"drop=%d expected=%d" % [drop, expected],
	)
	target.queue_free()


func _punch_drop(target) -> int:
	var before: int = target.hp
	target.take_hit(Vector3(0.0, 0.0, 10.0))
	return before - target.hp


## --- Mushroom King: throws stop costing cubes ------------------------------

func _test_king_throws_are_free() -> void:
	var king = await _spawn("res://scenes/pal_boss.tscn")
	_activate(king)
	var inv = get_root().get_node("Inventory")
	inv.add("cube", 5)
	var before: int = inv.count("cube")
	var player = await _spawn_player()
	player._throw_cube(Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -1.0))
	var after: int = inv.count("cube")
	_check(
		"with the King out a throw costs no cube",
		after == before and _party().infinite_cubes(),
		"cubes %d -> %d" % [before, after],
	)
	_recall()
	player.queue_free()
	king.queue_free()


func _test_throws_without_the_king_cost_a_cube() -> void:
	var inv = get_root().get_node("Inventory")
	inv.add("cube", 5)
	var before: int = inv.count("cube")
	var player = await _spawn_player()
	player._throw_cube(Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -1.0))
	var after: int = inv.count("cube")
	_check(
		"with no King out a throw spends a cube",
		after == before - 1 and not _party().infinite_cubes(),
		"cubes %d -> %d" % [before, after],
	)
	player.queue_free()


func _test_hud_shows_infinity_with_the_king() -> void:
	var inv = get_root().get_node("Inventory")
	var hud = get_root().get_node("Hud")
	var plain_stock: int = inv.count("cube")
	hud._refresh()
	var plain: String = hud._cube_count.text

	var king = await _spawn("res://scenes/pal_boss.tscn")
	_activate(king)
	hud._refresh()
	var infinite: String = hud._cube_count.text
	_recall()

	_check(
		"the HUD cube readout is not a bare zero while the King is out",
		infinite == Tuning.INFINITE_CUBE_TEXT and plain == str(plain_stock),
		"plain=%s king=%s" % [plain, infinite],
	)
	king.queue_free()


## --- Fixtures --------------------------------------------------------------

func _party():
	return get_root().get_node("Party")


## Put a pal out without going through a catch, which would also grant XP and
## drops and move the assertions around under us.
func _activate(pal) -> void:
	pal.caught = true
	_party().active = pal


func _recall() -> void:
	_party().active = null


func _spawn(path: String):
	var pal = load(path).instantiate()
	get_root().add_child(pal)
	await process_frame
	pal.global_position = Vector3.ZERO
	pal.set_physics_process(false)
	return pal


## A real player, so the cube spend goes through the shipped throw path.
func _spawn_player():
	var player = load("res://scenes/player.tscn").instantiate()
	get_root().add_child(player)
	await process_frame
	player.set_physics_process(false)
	player.set_process(false)
	return player
