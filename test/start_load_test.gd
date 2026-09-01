extends GutTest
## Play loads the world across frames rather than in one blocking lump.
##
## change_scene_to_file pays ~300 ms of resource loading at the end of the
## frame it is called in, with nothing drawn meanwhile: on the web that reads
## as the tab hanging and then the game appearing at once. The title screen
## now requests the load and keeps animating while it lands.
##
## No test here lets the load COMPLETE. Finishing it swaps the scene tree out
## from under GUT, which takes the world other suites are holding with it:
## that failed twenty-four tests across a dozen unrelated files while every
## one of them passed run on its own. `_loading_world` is cleared by hand
## before each test ends, so the poll in _process never reaches the swap.

var _screen: Node


func before_each() -> void:
	_screen = load("res://scenes/start_screen.tscn").instantiate()
	add_child(_screen)
	await wait_process_frames(1)


func after_each() -> void:
	# Stop the poll before anything can swap the tree, then drop the request.
	_screen._loading_world = false
	ResourceLoader.load_threaded_get_status("res://scenes/world.tscn")
	_screen.free()
	await wait_process_frames(1)


## The frame Play is pressed must stay cheap. A blocking swap spends the
## whole load inside it.
func test_pressing_play_does_not_block_the_frame() -> void:
	var t0 := Time.get_ticks_msec()
	_screen._on_play()
	var cost := Time.get_ticks_msec() - t0
	_screen._loading_world = false
	assert_lt(
		cost, 120,
		"pressing Play blocked for %d ms: the load is not spread over frames" % cost,
	)


func test_pressing_play_starts_a_load_rather_than_swapping() -> void:
	_screen._on_play()
	assert_true(_screen._loading_world, "Play did not start a background load")
	assert_true(
		_screen.is_inside_tree(),
		"the title was torn down inside the Play frame: that is the blocking swap",
	)
	_screen._loading_world = false


func test_the_title_keeps_animating_while_it_loads() -> void:
	_screen._on_play()
	var turntable: Node3D = _screen.get_node("Turntable")
	var before := turntable.rotation.y
	await wait_process_frames(2)
	_screen._loading_world = false
	assert_ne(
		turntable.rotation.y, before,
		"the title froze while loading: _process is not running",
	)


## The player must be told something is happening, or a slow load reads as a
## dead button.
func test_the_wait_is_shown() -> void:
	_screen._on_play()
	await wait_process_frames(1)
	_screen._loading_world = false
	assert_true(
		_screen.get_node("UI/Menu/Loading").visible,
		"no loading message while the world loads",
	)
	assert_false(
		_screen.get_node("UI/Menu/Play").visible,
		"Play still showing while the world loads",
	)
