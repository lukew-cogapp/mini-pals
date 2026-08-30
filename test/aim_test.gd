extends SceneTree
## Headless aim-and-throw assertions. Run:
##   godot --headless --path . -s test/aim_test.gd
##
## Aiming and firing used to be one action: hold Q, and letting go always
## spent a cube, so you could not read a pal's catch odds and think better
## of it. Right mouse now aims for free, Q fires while it is held, and
## letting go of right mouse cancels. Holding Q alone still throws on
## release, which is the flow that shipped first and the regression that
## matters most here.
##
## Events are fed to _unhandled_input directly rather than through
## Input.parse_input_event: this is headless, there is no window, and the
## point under test is the branch order in that function.

var _fails := 0
var _world
var _player
var _inventory


func _init() -> void:
	await process_frame
	_inventory = get_root().get_node("Inventory")
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	for i in 10:
		await physics_frame
	_player = get_root().get_tree().get_first_node_in_group("player")
	if _player == null:
		print("FAIL no player in world.tscn")
		print("FAILURES=1")
		quit(1)
		return

	await _test_aim_shows_the_reticule_and_spends_nothing()
	await _test_aim_then_q_throws_one()
	await _test_hold_q_and_release_still_throws_one()
	await _test_q_with_nothing_aiming_starts_an_aim()
	await _test_aim_with_no_cubes_still_aims()
	await _test_recapture_click_does_nothing_else()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


## A clean slate: mouse captured, nothing aiming, and a known cube count.
func _reset(cubes: int) -> void:
	_player._aim_held = false
	_player._aiming_throw = false
	_player.locked_pal = null
	_player._mouse_free = false
	_inventory._counts["cube"] = cubes


func _cubes() -> int:
	return _inventory.count("cube")


func _mouse(button: int, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	return e


func _key(code: int, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = pressed
	return e


func _send(event: InputEvent) -> void:
	_player._unhandled_input(event)
	await physics_frame


func _test_aim_shows_the_reticule_and_spends_nothing() -> void:
	_reset(5)
	await _send(_mouse(MOUSE_BUTTON_RIGHT, true))
	var aiming: bool = _player._aiming_throw and _player._aim_held
	var during: int = _cubes()
	await _send(_mouse(MOUSE_BUTTON_RIGHT, false))
	_check(
		"right click aims and releasing it cancels without spending a cube",
		aiming and not _player._aiming_throw and during == 5 and _cubes() == 5,
		"aiming=%s after=%s cubes=%d" % [aiming, _player._aiming_throw, _cubes()],
	)


func _test_aim_then_q_throws_one() -> void:
	_reset(5)
	await _send(_mouse(MOUSE_BUTTON_RIGHT, true))
	await _send(_key(KEY_Q, true))
	var after_throw: int = _cubes()
	var still_aiming: bool = _player._aiming_throw
	# Releasing Q must not throw a second: the press already fired.
	await _send(_key(KEY_Q, false))
	var after_release: int = _cubes()
	await _send(_mouse(MOUSE_BUTTON_RIGHT, false))
	_check(
		"Q while right mouse is held throws exactly one cube and stays aimed",
		after_throw == 4 and after_release == 4 and still_aiming,
		"after_throw=%d after_release=%d aiming=%s"
		% [after_throw, after_release, still_aiming],
	)
	_check(
		"letting go of right mouse after a throw does not spend another",
		_cubes() == 4,
		"cubes=%d" % _cubes(),
	)


## The flow that shipped first. Nobody's muscle memory breaks.
func _test_hold_q_and_release_still_throws_one() -> void:
	_reset(5)
	await _send(_key(KEY_Q, true))
	var aiming: bool = _player._aiming_throw
	var during: int = _cubes()
	await _send(_key(KEY_Q, false))
	_check(
		"holding Q alone aims, and releasing it throws exactly one cube",
		aiming and during == 5 and _cubes() == 4,
		"aiming=%s during=%d after=%d" % [aiming, during, _cubes()],
	)


func _test_q_with_nothing_aiming_starts_an_aim() -> void:
	_reset(5)
	await _send(_key(KEY_Q, true))
	_check(
		"Q pressed with nothing aiming begins an aim rather than throwing",
		_player._aiming_throw and not _player._aim_held and _cubes() == 5,
		"aiming=%s held=%s cubes=%d"
		% [_player._aiming_throw, _player._aim_held, _cubes()],
	)
	_player._cancel_throw_aim()


## Looking is free: reading a pal's catch odds is worth doing before you have
## a cube to act on it, and the throw itself still says why nothing flew.
func _test_aim_with_no_cubes_still_aims() -> void:
	_reset(0)
	await _send(_mouse(MOUSE_BUTTON_RIGHT, true))
	var aimed: bool = _player._aiming_throw
	await _send(_key(KEY_Q, true))
	var spent: int = _cubes()
	await _send(_mouse(MOUSE_BUTTON_RIGHT, false))
	_check(
		"aiming with an empty pouch still shows the reticule and throws nothing",
		aimed and spent == 0,
		"aimed=%s cubes=%d" % [aimed, spent],
	)
	# And Q on its own with no cubes still refuses, as it always did.
	_reset(0)
	await _send(_key(KEY_Q, true))
	_check(
		"Q alone with no cubes refuses to start an aim",
		not _player._aiming_throw,
		"aiming=%s" % _player._aiming_throw,
	)


## The bug removed from throwing in ad79a40, on three buttons at once: a
## click that only restores mouse capture must not aim, throw, bite or
## command a pal.
func _test_recapture_click_does_nothing_else() -> void:
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_reset(5)
		_player._mouse_free = true
		var bites_before: int = _bite_count()
		await _send(_mouse(button, true))
		_check(
			"a mouse button %d click that recaptures the mouse does nothing else" % button,
			not _player._mouse_free
				and not _player._aiming_throw
				and _cubes() == 5
				and _bite_count() == bites_before,
			"free=%s aiming=%s cubes=%d"
			% [_player._mouse_free, _player._aiming_throw, _cubes()],
		)


## Swings are only visible through the audio log: every bite plays a cue,
## whether or not it reached anything.
func _bite_count() -> int:
	var audio = get_root().get_node("Audio")
	var n := 0
	for cue in audio.played:
		if cue == "bite" or cue == "whiff":
			n += 1
	return n
