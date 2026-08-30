extends SceneTree
## Headless start screen assertions. Run:
##   godot --headless --path . -s test/start_screen_test.gd
##
## The failure this guards against is a title screen nobody can leave: a Play
## button pointing at a path that no longer exists, or a menu with nothing
## focused, which a gamepad and the arrow keys cannot drive at all.

var _fails := 0


func _init() -> void:
	await process_frame

	var main: String = ProjectSettings.get_setting("application/run/main_scene")
	_check("the start screen is the project's main scene",
		main == "res://scenes/start_screen.tscn", "main_scene=%s" % main)

	var packed := load("res://scenes/start_screen.tscn")
	_check("the start scene loads", packed != null)
	if packed == null:
		_report()
		return

	var screen = packed.instantiate()
	get_root().add_child(screen)
	await process_frame

	var play: Button = screen.get_node_or_null("UI/Menu/Play")
	var quit_button: Button = screen.get_node_or_null("UI/Menu/Quit")
	_check("Play exists", play != null)
	_check("Quit exists", quit_button != null)
	if play == null or quit_button == null:
		_report()
		return

	_check("Play is wired", play.pressed.get_connections().size() == 1,
		"connections=%d" % play.pressed.get_connections().size())
	_check("Quit is wired", quit_button.pressed.get_connections().size() == 1,
		"connections=%d" % quit_button.pressed.get_connections().size())

	# A focus target on load is what makes the screen drivable without a mouse.
	var focused: Control = screen.get_viewport().gui_get_focus_owner()
	_check("something has focus on load, so a pad or the keys can drive it",
		focused == play, "focused=%s" % (focused.name if focused else "<none>"))

	# Both buttons must be reachable in both directions, or a pad can steer
	# into one of them and never get back out.
	_check("focus moves down from Play to Quit",
		play.find_valid_focus_neighbor(SIDE_BOTTOM) == quit_button)
	_check("focus moves up from Play to Quit",
		play.find_valid_focus_neighbor(SIDE_TOP) == quit_button)
	_check("focus moves down from Quit to Play",
		quit_button.find_valid_focus_neighbor(SIDE_BOTTOM) == play)
	_check("focus moves up from Quit to Play",
		quit_button.find_valid_focus_neighbor(SIDE_TOP) == play)

	# ui_down / ui_accept are what a gamepad's stick and A button feed into,
	# so the same assertions cover both input devices.
	_check("ui_down is mapped, for stick and arrow navigation",
		InputMap.has_action("ui_down"))
	_check("ui_accept is mapped, for Enter, Space and the pad's A",
		InputMap.has_action("ui_accept"))
	_check("Play takes ui_accept when focused",
		play.focus_mode != Control.FOCUS_NONE and not play.disabled)

	# The focus style must differ from the normal one, or a pad user cannot
	# see which button they are on and the screen is unnavigable in practice.
	var normal := play.get_theme_stylebox("normal") as StyleBoxFlat
	var focus := play.get_theme_stylebox("focus") as StyleBoxFlat
	_check("the focused button looks different from an unfocused one",
		focus != null and normal != null and focus.border_color != normal.border_color,
		"normal=%s focus=%s" % [normal.border_color if normal else "<none>",
			focus.border_color if focus else "<none>"])

	var game_name: String = ProjectSettings.get_setting("application/config/name")
	_check("the title shows the game's name, not a stale copy of it",
		screen.get_node("UI/Title/Name").text == game_name, "title=%s" % game_name)

	# Play's destination, checked as a real load rather than a path string.
	var target: String = screen.WORLD
	_check("Play points at the world scene", target == "res://scenes/world.tscn",
		"target=%s" % target)
	_check("the world scene exists", ResourceLoader.exists(target))
	var world_packed := load(target)
	_check("the world scene loads", world_packed != null)
	if world_packed != null:
		var world = world_packed.instantiate()
		_check("the world scene instantiates", world != null)
		if world != null:
			world.free()

	# The backdrop must not be the world scene itself: instancing that here
	# would put a full scatter and pal spawn in front of the title.
	_check("the backdrop is its own set, not world.tscn",
		screen.get_node_or_null("Turntable") != null
			and screen.get_node_or_null("Island") == null)

	_report()


func _report() -> void:
	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)
