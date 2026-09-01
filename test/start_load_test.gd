extends GutTest
## Play loads the world across frames rather than in one blocking lump.
##
## change_scene_to_file pays ~300 ms of resource loading at the end of the
## frame it is called in, with nothing drawn meanwhile: on the web that reads
## as the tab hanging and then the game appearing at once. The title screen
## now requests the load and keeps animating while it lands.

var _screen: Node


func before_each() -> void:
	_screen = load("res://scenes/start_screen.tscn").instantiate()
	add_child(_screen)
	await wait_process_frames(1)


func after_each() -> void:
	# Play swaps the scene; only free what is still ours.
	if is_instance_valid(_screen) and _screen.is_inside_tree():
		remove_child(_screen)
	if is_instance_valid(_screen):
		_screen.free()
	ResourceLoader.load_threaded_get_status("res://scenes/world.tscn")


## The frame Play is pressed must stay cheap. A blocking swap spends the
## whole load inside it.
func test_pressing_play_does_not_block_the_frame() -> void:
	var t0 := Time.get_ticks_msec()
	_screen._on_play()
	var cost := Time.get_ticks_msec() - t0
	assert_lt(
		cost, 120,
		"pressing Play blocked for %d ms: the load is not spread over frames" % cost,
	)


func test_the_title_keeps_animating_while_it_loads() -> void:
	_screen._on_play()
	var turntable: Node3D = _screen.get_node("Turntable")
	var before := turntable.rotation.y
	await wait_process_frames(2)
	assert_ne(
		turntable.rotation.y, before,
		"the title froze while loading: _process is not running",
	)


## The player must be told something is happening, or a slow load reads as a
## dead button.
func test_the_wait_is_shown() -> void:
	_screen._on_play()
	await wait_process_frames(2)
	var label: Label = _screen.get_node("UI/Menu/Loading")
	assert_true(label.visible, "no loading message while the world loads")
	assert_false(
		_screen.get_node("UI/Menu/Play").visible,
		"Play still showing while the world loads",
	)
