extends GutTest
## Headless assertions for the start screen's debug option, ported from
## test/debug_start_test.gd.
##
## The option exists to skip a full playthrough, so what matters is that the
## King it hands over is a real party member (caught, active, giving infinite
## cubes) and, above all, that a NORMAL start still gives an empty party. A
## debug shortcut that leaked into Play would be the worst bug in the game.

var _play: Button
var _debug: Button
var _quit_button: Button


func test_debug_button_exists_and_is_wired() -> void:
	var screen: Node = add_child_autofree(load("res://scenes/start_screen.tscn").instantiate())
	await wait_process_frames(1)

	_play = screen.get_node_or_null("UI/Menu/Play")
	_debug = screen.get_node_or_null("UI/Menu/Debug")
	_quit_button = screen.get_node_or_null("UI/Menu/Quit")
	assert_not_null(_debug, "the debug option exists")
	if _debug == null or _play == null or _quit_button == null:
		return

	assert_eq(
		_debug.pressed.get_connections().size(), 1,
		"the debug option is wired: connections=%d" % _debug.pressed.get_connections().size(),
	)
	assert_true(
		_debug.focus_mode != Control.FOCUS_NONE and not _debug.disabled,
		"the debug option can take focus",
	)
	assert_true(
		_debug.text.to_lower().contains("debug"),
		"it says what it is, not just Play: text=%s" % _debug.text,
	)
	# Visually secondary: smaller than Play, or it reads as a second Play.
	assert_lt(
		_debug.get_theme_font_size("font_size"), _play.get_theme_font_size("font_size"),
		(
			"it is smaller than Play: debug=%d play=%d"
			% [_debug.get_theme_font_size("font_size"), _play.get_theme_font_size("font_size")]
		),
	)

	# The focus chain now wraps between three, so every one of them must be
	# reachable in both directions or a pad can steer into a dead end.
	assert_eq(_play.find_valid_focus_neighbor(SIDE_BOTTOM), _debug, "focus goes down Play to Debug")
	assert_eq(
		_debug.find_valid_focus_neighbor(SIDE_BOTTOM), _quit_button,
		"focus goes down Debug to Quit",
	)
	assert_eq(
		_quit_button.find_valid_focus_neighbor(SIDE_BOTTOM), _play,
		"focus wraps down Quit to Play",
	)
	assert_eq(_debug.find_valid_focus_neighbor(SIDE_TOP), _play, "focus goes up Debug to Play")
	assert_eq(
		_quit_button.find_valid_focus_neighbor(SIDE_TOP), _debug, "focus goes up Quit to Debug"
	)
	assert_eq(
		_play.find_valid_focus_neighbor(SIDE_TOP), _quit_button, "focus wraps up Play to Quit"
	)


## The regression that matters: a normal start must give an empty party.
func test_normal_start_leaves_the_party_empty() -> void:
	# Party outlives a single suite now that every test shares one process,
	# so a pal an earlier script caught would read here as one the normal
	# start handed out. Start from the empty party a fresh game gives.
	Party.members.clear()
	Party.active = null

	# current_scene must be a child of root, so this cannot go through
	# add_child_autofree, which parents under the test node instead.
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child(world)
	# change_scene_to_file sets current_scene; the grant reads it to know
	# where to put the pal, so the test has to set it the same way.
	get_tree().current_scene = world
	await wait_process_frames(1)
	await wait_physics_frames(5)

	assert_true(
		Party.members.is_empty(),
		"a normal start leaves the party empty: members=%d" % Party.members.size(),
	)
	assert_true(not Party.infinite_cubes(), "a normal start gives no infinite cubes")

	get_tree().current_scene = null
	world.free()


func test_taking_the_debug_option_grants_the_king() -> void:
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await wait_process_frames(1)
	await wait_physics_frames(5)

	Party.debug_start_king()
	await wait_process_frames(1)

	assert_eq(
		Party.members.size(), 1,
		"the debug start puts one pal in the party: members=%d" % Party.members.size(),
	)
	if Party.members.is_empty():
		get_tree().current_scene = null
		world.free()
		return
	var king = Party.members[0]
	assert_eq(king.display_name, "Mushroom King", "it is the Mushroom King: name=%s" % king.display_name)
	assert_true(
		king.caught, "the King is caught, not a wild one standing in the party: caught=%s" % king.caught
	)
	assert_eq(
		Party.active, king,
		(
			"the King is the active pal: active=%s"
			% (Party.active.display_name if Party.active else "<none>")
		),
	)
	assert_true(king.visible, "the King is out, not stowed: visible=%s" % king.visible)
	# The enum is read off the instance: naming Pal in a -s script fails at
	# compile time before any of this runs (CLAUDE.md).
	assert_eq(
		king.state, king.State.FOLLOW,
		"the King follows the player: state=%d" % king.state,
	)
	assert_eq(
		king.level, Tuning.DEBUG_KING_LEVEL,
		(
			"the King is at the altar's summon level: level=%d want=%d"
			% [king.level, Tuning.DEBUG_KING_LEVEL]
		),
	)
	assert_true(Party.infinite_cubes(), "throws are free with him out")
	assert_true(
		Party.player_level >= Tuning.KEY_UNLOCK_LEVEL,
		"the player is at the level that unlocks the key recipe: level=%d" % Party.player_level,
	)

	get_tree().current_scene = null
	world.free()
