extends SceneTree
## Headless input-map assertions. Run:
##   godot --headless --path . -s test/input_map_test.gd
##
## Throwing is Q or the right trigger. Left click used to throw as well,
## which meant clicking back into the window after Escape spent a cube.
## player.gd still recaptures the mouse on click; only the binding went.

var _fails := 0

func _init() -> void:
	await process_frame
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
			_check("the key is Q", e.physical_keycode == KEY_Q,
				"keycode=%d" % e.physical_keycode)
		elif e is InputEventJoypadMotion:
			has_pad = true

	_check("left click no longer throws", not has_mouse, "")
	_check("Q still throws", has_key, "")
	_check("the trigger still throws", has_pad, "")
	# Clicking to recapture the mouse must still work in player.gd.
	_check("punch is untouched", InputMap.action_get_events("punch").size() == 2,
		"events=%d" % InputMap.action_get_events("punch").size())

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)
