extends GutTest
## Right-stick camera look.
##
## Camera look was mouse-only: `InputEventMouseMotion` was the sole path into
## the pivot, so a pad could walk but never turn, and since aim is the camera
## the throw was unusable too. A held stick reports a constant deflection and
## emits no further events, so this drives frames rather than sending one
## event and reading the result.

var _player: Node3D
var _pivot: Node3D


func before_all() -> void:
	_player = load("res://scenes/player.tscn").instantiate()
	add_child(_player)
	await wait_process_frames(1)
	_pivot = _player.get_node("CameraPivot")


func after_all() -> void:
	_player.free()


## Godot reads a stick through the action's axis events, so a test drives it
## with action strengths rather than a fabricated InputEventJoypadMotion.
func _hold(action: String, frames: int) -> void:
	Input.action_press(action, 1.0)
	await wait_process_frames(frames)
	Input.action_release(action)
	await wait_process_frames(1)


func test_right_stick_turns_the_camera() -> void:
	var before := _pivot.rotation.y
	await _hold("look_right", 6)
	assert_ne(_pivot.rotation.y, before, "look_right did not turn the camera")


## Yaw sign, so the camera cannot end up mirrored. Pushing the stick right
## turns the view right, which is a decreasing yaw under Godot's -Z forward.
func test_left_and_right_turn_opposite_ways() -> void:
	var start := _pivot.rotation.y
	await _hold("look_right", 6)
	var right_delta := _pivot.rotation.y - start

	start = _pivot.rotation.y
	await _hold("look_left", 6)
	var left_delta := _pivot.rotation.y - start

	assert_lt(right_delta, 0.0, "right should decrease yaw")
	assert_gt(left_delta, 0.0, "left should increase yaw")


## A held stick must keep turning. An event-driven version turns on the frame
## the stick moves and then stops, which is the bug this guards.
func test_holding_the_stick_keeps_turning() -> void:
	Input.action_press("look_right", 1.0)
	await wait_process_frames(4)
	var after_four := _pivot.rotation.y
	await wait_process_frames(8)
	var after_twelve := _pivot.rotation.y
	Input.action_release("look_right")
	await wait_process_frames(1)
	assert_lt(
		after_twelve, after_four,
		"camera stopped turning while the stick was still held",
	)


func test_pitch_stays_inside_the_mouse_limits() -> void:
	await _hold("look_up", 240)
	assert_almost_eq(
		_pivot.rotation.x, Tuning.CAMERA_PITCH_MAX, 0.001,
		"pitch passed the up limit",
	)
	await _hold("look_down", 240)
	assert_almost_eq(
		_pivot.rotation.x, Tuning.CAMERA_PITCH_MIN, 0.001,
		"pitch passed the down limit",
	)
