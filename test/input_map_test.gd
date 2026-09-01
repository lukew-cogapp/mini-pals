extends GutTest
## Headless input-map assertions. Run:
##   godot --headless --path . -s test/input_map_test.gd
##
## project.godot's [input] block is hand-edited, and a bad edit has removed
## the `"events": [` that opened an array and taken every binding in the file
## with it. So this asserts the whole map, not only the action last touched:
## every action, its exact event count, and the bindings that have moved.
##
## Two of those bindings are scars. Left click used to throw, which meant
## clicking back into the window after Escape spent a cube; only the binding
## went, and player.gd still recaptures on click. Left click now bites
## instead, and the same trap applies, so player.gd checks the recapture
## before any action branch. `test/pal_command_test.gd` covers the command
## itself; the ordering assertion is below.

## Every action and how many events it carries. A count is enough to catch
## the failure that actually happens here, which is a whole array vanishing.
const EXPECTED := {
	"move_forward": 3,
	"move_back": 3,
	"move_left": 3,
	"move_right": 3,
	"jump": 2,
	"run": 2,
	"throw": 2,
	"ride": 2,
	"punch": 3,
	"build": 2,
	"interact": 2,
	"cycle_pal": 2,
	"help": 2,
	"minimap": 2,
	"pal_prev": 1,
	"pal_next": 1,
	# Middle click, T, and RB.
	"pal_attack": 3,
	"aim": 2,
	# Right stick, one axis direction each.
	"look_left": 1,
	"look_right": 1,
	"look_up": 1,
	"look_down": 1,
}


func test_every_action_keeps_its_events() -> void:
	for action in EXPECTED:
		var here := InputMap.has_action(action)
		var n := InputMap.action_get_events(action).size() if here else -1
		assert_true(here and n == EXPECTED[action], "%s still has %d events" % [action, EXPECTED[action]])


## What the map has that EXPECTED does not, ignoring Godot's own ui_* actions.
func test_no_pad_button_is_double_booked() -> void:
	var seen := {}
	var clash := ""
	for action in EXPECTED:
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton:
				if seen.has(e.button_index):
					clash = "%d: %s and %s" % [e.button_index, seen[e.button_index], action]
				seen[e.button_index] = action
	assert_true(clash == "", "no gamepad button is bound to two actions")


func test_throw() -> void:
	var has_mouse := false
	var has_key := false
	var has_pad := false
	for e in InputMap.action_get_events("throw"):
		if e is InputEventMouseButton:
			has_mouse = true
		elif e is InputEventKey:
			has_key = true
			assert_true(e.physical_keycode == KEY_Q, "the throw key is Q")
		elif e is InputEventJoypadMotion:
			has_pad = true
	assert_true(not has_mouse, "no mouse button throws")
	assert_true(has_key, "Q still throws")
	assert_true(has_pad, "the trigger still throws")


## Left click, F and pad Y all bite. The verb is "bite" everywhere the player
## can see; `punch` is the action's legacy name.
func test_punch() -> void:
	var left := false
	var f_key := false
	var pad := false
	for e in InputMap.action_get_events("punch"):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			left = true
		elif e is InputEventKey and e.physical_keycode == KEY_F:
			f_key = true
		elif e is InputEventJoypadButton and e.button_index == 3:
			pad = true
	assert_true(left, "left click bites")
	assert_true(f_key, "F still bites")
	assert_true(pad, "pad button 3 still bites")


func test_pal_attack() -> void:
	var middle := false
	var pad := false
	for e in InputMap.action_get_events("pal_attack"):
		if e is InputEventMouseButton:
			middle = e.button_index == MOUSE_BUTTON_MIDDLE
		elif e is InputEventJoypadButton:
			pad = true
	assert_true(middle, "middle click commands the active pal to attack")
	var t_key := false
	for e in InputMap.action_get_events("pal_attack"):
		if e is InputEventKey and e.physical_keycode == KEY_T:
			t_key = true
	assert_true(t_key, "T also commands the active pal to attack")
	assert_true(pad, "pal_attack has a gamepad button too")


## Right mouse aims; Q fires while it is held, and releasing right mouse
## cancels without spending a cube. The left trigger is the pad mirror of
## throw's right trigger.
func test_aim() -> void:
	var right := false
	var pad := false
	for e in InputMap.action_get_events("aim"):
		if e is InputEventMouseButton:
			right = e.button_index == MOUSE_BUTTON_RIGHT
		elif e is InputEventJoypadMotion:
			pad = e.axis == 4
	assert_true(right, "right click aims")
	assert_true(pad, "the left trigger aims")
	assert_true(InputMap.action_get_events("aim") != InputMap.action_get_events("throw"), "aim and throw are different actions")


## The regression the throw binding was removed for, now on the other button:
## the click that restores mouse capture must not also bite or command. In
## player.gd's `elif` chain that is purely a matter of order, so the source is
## what is asserted.
func test_recapture_is_checked_before_the_action_branches() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/player.gd")
	# The branch itself. player.gd tracks `_mouse_free` rather than reading
	# Input.mouse_mode back, which is not settable under the headless
	# renderer and would report the mouse free forever.
	var recapture := src.find("elif event is InputEventMouseButton and _mouse_free:")
	var punch := src.find('is_action_pressed("punch")')
	var command := src.find('is_action_pressed("pal_attack")')
	var aim := src.find('is_action_pressed("aim")')
	assert_true(
		recapture > 0 and punch > recapture and command > recapture and aim > recapture,
		"the mouse recapture branch is checked before aim, punch and pal_attack: recapture=%d aim=%d punch=%d command=%d" % [recapture, aim, punch, command],
	)
