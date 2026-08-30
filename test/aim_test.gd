extends GutTest
## Headless aim-and-throw assertions.
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

var _world: Node
var _player: Node3D


## Freed in after_all with free rather than by add_child_autofree, which frees
## at the end of the calling test and would leave later tests without a world.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(10)
	_player = get_tree().get_first_node_in_group("player")
	assert_not_null(_player, "world.tscn has a player")


func after_all() -> void:
	_world.free()


## A clean slate: mouse captured, nothing aiming, and a known cube count.
func _reset(cubes: int) -> void:
	_player._aim_held = false
	_player._aiming_throw = false
	_player.locked_pal = null
	_player._mouse_free = false
	Inventory._counts["cube"] = cubes


func _cubes() -> int:
	return Inventory.count("cube")


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
	await wait_physics_frames(1)


func test_aim_shows_the_reticule_and_spends_nothing() -> void:
	_reset(5)
	await _send(_mouse(MOUSE_BUTTON_RIGHT, true))
	var aiming: bool = _player._aiming_throw and _player._aim_held
	var during: int = _cubes()
	await _send(_mouse(MOUSE_BUTTON_RIGHT, false))
	assert_true(
		aiming and not _player._aiming_throw and during == 5 and _cubes() == 5,
		(
			"right click aims and releasing it cancels without spending a cube: "
			+ "aiming=%s after=%s cubes=%d"
			% [aiming, _player._aiming_throw, _cubes()]
		),
	)


func test_aim_then_q_throws_one() -> void:
	_reset(5)
	await _send(_mouse(MOUSE_BUTTON_RIGHT, true))
	await _send(_key(KEY_Q, true))
	var after_throw: int = _cubes()
	var still_aiming: bool = _player._aiming_throw
	# Releasing Q must not throw a second: the press already fired.
	await _send(_key(KEY_Q, false))
	var after_release: int = _cubes()
	await _send(_mouse(MOUSE_BUTTON_RIGHT, false))
	assert_true(
		after_throw == 4 and after_release == 4 and still_aiming,
		(
			"Q while right mouse is held throws exactly one cube and stays aimed: "
			+ "after_throw=%d after_release=%d aiming=%s"
			% [after_throw, after_release, still_aiming]
		),
	)
	assert_eq(
		_cubes(),
		4,
		"letting go of right mouse after a throw does not spend another",
	)


## The flow that shipped first. Nobody's muscle memory breaks.
func test_hold_q_and_release_still_throws_one() -> void:
	_reset(5)
	await _send(_key(KEY_Q, true))
	var aiming: bool = _player._aiming_throw
	var during: int = _cubes()
	await _send(_key(KEY_Q, false))
	assert_true(
		aiming and during == 5 and _cubes() == 4,
		(
			"holding Q alone aims, and releasing it throws exactly one cube: "
			+ "aiming=%s during=%d after=%d" % [aiming, during, _cubes()]
		),
	)


func test_q_with_nothing_aiming_starts_an_aim() -> void:
	_reset(5)
	await _send(_key(KEY_Q, true))
	assert_true(
		_player._aiming_throw and not _player._aim_held and _cubes() == 5,
		(
			"Q pressed with nothing aiming begins an aim rather than throwing: "
			+ "aiming=%s held=%s cubes=%d"
			% [_player._aiming_throw, _player._aim_held, _cubes()]
		),
	)
	_player._cancel_throw_aim()


## Looking is free: reading a pal's catch odds is worth doing before you have
## a cube to act on it, and the throw itself still says why nothing flew.
func test_aim_with_no_cubes_still_aims() -> void:
	_reset(0)
	await _send(_mouse(MOUSE_BUTTON_RIGHT, true))
	var aimed: bool = _player._aiming_throw
	await _send(_key(KEY_Q, true))
	var spent: int = _cubes()
	await _send(_mouse(MOUSE_BUTTON_RIGHT, false))
	assert_true(
		aimed and spent == 0,
		(
			"aiming with an empty pouch still shows the reticule and throws nothing: "
			+ "aimed=%s cubes=%d" % [aimed, spent]
		),
	)
	# And Q on its own with no cubes still refuses, as it always did.
	_reset(0)
	await _send(_key(KEY_Q, true))
	assert_false(
		_player._aiming_throw,
		"Q alone with no cubes refuses to start an aim",
	)


## The bug removed from throwing in ad79a40, on three buttons at once: a
## click that only restores mouse capture must not aim, throw, bite or
## command a pal.
func test_recapture_click_does_nothing_else() -> void:
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_reset(5)
		_player._mouse_free = true
		var bites_before: int = _bite_count()
		await _send(_mouse(button, true))
		assert_true(
			(
				not _player._mouse_free
				and not _player._aiming_throw
				and _cubes() == 5
				and _bite_count() == bites_before
			),
			(
				"a mouse button %d click that recaptures the mouse does nothing else: "
				% button
				+ "free=%s aiming=%s cubes=%d"
				% [_player._mouse_free, _player._aiming_throw, _cubes()]
			),
		)


## Swings are only visible through the audio log: every bite plays a cue,
## whether or not it reached anything.
func _bite_count() -> int:
	var n := 0
	for cue in Audio.played:
		if cue == "bite" or cue == "whiff":
			n += 1
	return n
