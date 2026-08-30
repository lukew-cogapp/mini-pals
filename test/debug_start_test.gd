extends SceneTree
## Headless assertions for the start screen's debug option. Run:
##   godot --headless --path . -s test/debug_start_test.gd
##
## The option exists to skip a full playthrough, so what matters is that the
## King it hands over is a real party member (caught, active, giving infinite
## cubes) and, above all, that a NORMAL start still gives an empty party. A
## debug shortcut that leaked into Play would be the worst bug in the game.

var _fails := 0
var _party


func _init() -> void:
	await process_frame
	_party = get_root().get_node("Party")

	var screen = load("res://scenes/start_screen.tscn").instantiate()
	get_root().add_child(screen)
	await process_frame

	# --- The option exists and a pad can reach it --------------------------

	var play: Button = screen.get_node_or_null("UI/Menu/Play")
	var debug: Button = screen.get_node_or_null("UI/Menu/Debug")
	var quit_button: Button = screen.get_node_or_null("UI/Menu/Quit")
	_check("the debug option exists", debug != null)
	if debug == null or play == null or quit_button == null:
		_report()
		return

	_check("the debug option is wired", debug.pressed.get_connections().size() == 1,
		"connections=%d" % debug.pressed.get_connections().size())
	_check("the debug option can take focus",
		debug.focus_mode != Control.FOCUS_NONE and not debug.disabled)
	_check("it says what it is, not just Play",
		debug.text.to_lower().contains("debug"), "text=%s" % debug.text)
	# Visually secondary: smaller than Play, or it reads as a second Play.
	_check("it is smaller than Play",
		debug.get_theme_font_size("font_size") < play.get_theme_font_size("font_size"),
		"debug=%d play=%d" % [debug.get_theme_font_size("font_size"),
			play.get_theme_font_size("font_size")])

	# The focus chain now wraps between three, so every one of them must be
	# reachable in both directions or a pad can steer into a dead end.
	_check("focus goes down Play to Debug",
		play.find_valid_focus_neighbor(SIDE_BOTTOM) == debug)
	_check("focus goes down Debug to Quit",
		debug.find_valid_focus_neighbor(SIDE_BOTTOM) == quit_button)
	_check("focus wraps down Quit to Play",
		quit_button.find_valid_focus_neighbor(SIDE_BOTTOM) == play)
	_check("focus goes up Debug to Play",
		debug.find_valid_focus_neighbor(SIDE_TOP) == play)
	_check("focus goes up Quit to Debug",
		quit_button.find_valid_focus_neighbor(SIDE_TOP) == debug)
	_check("focus wraps up Play to Quit",
		play.find_valid_focus_neighbor(SIDE_TOP) == quit_button)

	screen.free()
	await process_frame

	# --- A normal start: the regression that matters -----------------------

	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	# change_scene_to_file sets current_scene; the grant reads it to know
	# where to put the pal, so the test has to set it the same way.
	current_scene = world
	await process_frame
	for i in 5:
		await physics_frame

	_check("a normal start leaves the party empty", _party.members.is_empty(),
		"members=%d" % _party.members.size())
	_check("a normal start gives no infinite cubes", not _party.infinite_cubes())

	# --- Taking the debug option -------------------------------------------

	_party.debug_start_king()
	await process_frame

	_check("the debug start puts one pal in the party",
		_party.members.size() == 1, "members=%d" % _party.members.size())
	if _party.members.is_empty():
		_report()
		return
	var king = _party.members[0]
	_check("it is the Mushroom King", king.display_name == "Mushroom King",
		"name=%s" % king.display_name)
	_check("the King is caught, not a wild one standing in the party",
		king.caught, "caught=%s" % king.caught)
	_check("the King is the active pal", _party.active == king,
		"active=%s" % (_party.active.display_name if _party.active else "<none>"))
	_check("the King is out, not stowed", king.visible, "visible=%s" % king.visible)
	# The enum is read off the instance: naming Pal in a -s script fails at
	# compile time before any of this runs (CLAUDE.md).
	_check("the King follows the player", king.state == king.State.FOLLOW,
		"state=%d" % king.state)
	_check("the King is at the altar's summon level",
		king.level == Tuning.DEBUG_KING_LEVEL,
		"level=%d want=%d" % [king.level, Tuning.DEBUG_KING_LEVEL])
	_check("throws are free with him out", _party.infinite_cubes())
	_check("the player is at the level that unlocks the key recipe",
		_party.player_level >= Tuning.KEY_UNLOCK_LEVEL,
		"level=%d" % _party.player_level)

	_report()


func _report() -> void:
	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(check_name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", check_name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", check_name, "  ", detail)
