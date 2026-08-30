extends GutTest
## Input-map assertions, ported from test/input_map_test.gd.
##
## Throwing is Q or the right trigger. Left click used to throw as well,
## which meant clicking back into the window after Escape spent a cube.
## player.gd still recaptures the mouse on click; only the binding went.

func test_throw_is_key_and_pad_only() -> void:
	var kinds := []
	for e in InputMap.action_get_events("throw"):
		kinds.append(e.get_class())
	print("throw bound to: ", kinds)

	var has_mouse := false
	var has_key := false
	var has_pad := false
	for e in InputMap.action_get_events("throw"):
		if e is InputEventMouseButton:
			has_mouse = true
		elif e is InputEventKey:
			has_key = true
			assert_true(e.physical_keycode == KEY_Q, "the key is Q keycode=%d" % e.physical_keycode)
		elif e is InputEventJoypadMotion:
			has_pad = true

	assert_true(not has_mouse, "left click no longer throws ")
	assert_true(has_key, "Q still throws ")
	assert_true(has_pad, "the trigger still throws ")


func test_punch_is_untouched() -> void:
	# Clicking to recapture the mouse must still work in player.gd.
	assert_true(
		InputMap.action_get_events("punch").size() == 2,
		"punch is untouched events=%d" % InputMap.action_get_events("punch").size(),
	)
