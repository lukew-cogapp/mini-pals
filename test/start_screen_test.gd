extends GutTest
## Headless start screen assertions, ported from test/start_screen_test.gd.
##
## The failure this guards against is a title screen nobody can leave: a Play
## button pointing at a path that no longer exists, or a menu with nothing
## focused, which a gamepad and the arrow keys cannot drive at all.

var _screen: Node
var _play: Button
var _quit_button: Button


func before_all() -> void:
	var packed := load("res://scenes/start_screen.tscn")
	assert_not_null(packed, "the start scene loads")
	if packed == null:
		return

	_screen = packed.instantiate()
	add_child(_screen)
	await wait_process_frames(1)

	_play = _screen.get_node_or_null("UI/Menu/Play")
	_quit_button = _screen.get_node_or_null("UI/Menu/Quit")


func after_all() -> void:
	if _screen != null:
		_screen.free()


func test_main_scene_is_the_start_screen() -> void:
	var main: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_eq(
		main, "res://scenes/start_screen.tscn", "the start screen is the project's main scene"
	)


func test_menu_buttons_exist_and_are_wired() -> void:
	assert_not_null(_play, "Play exists")
	assert_not_null(_quit_button, "Quit exists")
	if _play == null or _quit_button == null:
		return

	assert_eq(
		_play.pressed.get_connections().size(), 1,
		"Play is wired: connections=%d" % _play.pressed.get_connections().size(),
	)
	assert_eq(
		_quit_button.pressed.get_connections().size(), 1,
		"Quit is wired: connections=%d" % _quit_button.pressed.get_connections().size(),
	)


func test_focus_ring() -> void:
	if _play == null or _quit_button == null:
		return

	# A focus target on load is what makes the screen drivable without a mouse.
	var focused: Control = _screen.get_viewport().gui_get_focus_owner()
	assert_eq(
		focused, _play,
		(
			"something has focus on load, so a pad or the keys can drive it: focused=%s"
			% (focused.name if focused else "<none>")
		),
	)

	# The menu is a ring: every button reachable both ways, or a pad can steer
	# into one of them and never get back out. The chain itself is asserted
	# button by button in debug_start_test.gd, which owns the third one.
	assert_eq(
		_play.find_valid_focus_neighbor(SIDE_TOP), _quit_button,
		"focus wraps up from Play, so the menu is a ring",
	)
	assert_eq(
		_quit_button.find_valid_focus_neighbor(SIDE_BOTTOM), _play,
		"focus wraps down from Quit, so the menu is a ring",
	)
	var child_count: int = _screen.get_node("UI/Menu").get_child_count()
	assert_eq(
		_ring(_play, SIDE_BOTTOM).size(), child_count,
		(
			"every menu button is reachable going down from Play: reached=%d of=%d"
			% [_ring(_play, SIDE_BOTTOM).size(), child_count]
		),
	)
	assert_eq(
		_ring(_play, SIDE_TOP).size(), child_count,
		(
			"every menu button is reachable going up from Play: reached=%d of=%d"
			% [_ring(_play, SIDE_TOP).size(), child_count]
		),
	)


func test_gamepad_input_mapping() -> void:
	if _play == null:
		return

	# ui_down / ui_accept are what a gamepad's stick and A button feed into,
	# so the same assertions cover both input devices.
	assert_true(
		InputMap.has_action("ui_down"), "ui_down is mapped, for stick and arrow navigation"
	)
	assert_true(
		InputMap.has_action("ui_accept"), "ui_accept is mapped, for Enter, Space and the pad's A"
	)
	assert_true(
		_play.focus_mode != Control.FOCUS_NONE and not _play.disabled,
		"Play takes ui_accept when focused",
	)


func test_focus_style_differs_from_normal() -> void:
	if _play == null:
		return

	# The focus style must differ from the normal one, or a pad user cannot
	# see which button they are on and the screen is unnavigable in practice.
	var normal := _play.get_theme_stylebox("normal") as StyleBoxFlat
	var focus := _play.get_theme_stylebox("focus") as StyleBoxFlat
	assert_true(
		focus != null and normal != null and focus.border_color != normal.border_color,
		(
			"the focused button looks different from an unfocused one: normal=%s focus=%s"
			% [
				normal.border_color if normal else "<none>",
				focus.border_color if focus else "<none>",
			]
		),
	)


func test_title_shows_the_game_name() -> void:
	var game_name: String = ProjectSettings.get_setting("application/config/name")
	assert_eq(
		_screen.get_node("UI/Title/Name").text, game_name,
		"the title shows the game's name, not a stale copy of it: title=%s" % game_name,
	)


func test_play_points_at_a_loadable_world() -> void:
	# Play's destination, checked as a real load rather than a path string.
	var target: String = _screen.WORLD
	assert_eq(
		target, "res://scenes/world.tscn", "Play points at the world scene: target=%s" % target
	)
	assert_true(ResourceLoader.exists(target), "the world scene exists")
	var world_packed := load(target)
	assert_not_null(world_packed, "the world scene loads")
	if world_packed != null:
		var world = world_packed.instantiate()
		assert_not_null(world, "the world scene instantiates")
		if world != null:
			world.free()


func test_backdrop_is_not_the_world() -> void:
	# The backdrop must not be the world scene itself: instancing that here
	# would put a full scatter and pal spawn in front of the title.
	assert_true(
		_screen.get_node_or_null("Turntable") != null
		and _screen.get_node_or_null("Island") == null,
		"the backdrop is its own set, not world.tscn",
	)


## The buttons walking the focus chain from `from` reaches, stopping when it
## comes back round. A chain that skips one or dead-ends returns fewer than
## the menu holds.
func _ring(from: Control, side: int) -> Array:
	var seen: Array = [from]
	var at := from
	for i in 16:
		at = at.find_valid_focus_neighbor(side)
		if at == null or at in seen:
			break
		seen.append(at)
	return seen
