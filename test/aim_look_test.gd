extends GutTest
## Turning the camera, and clicking, while the aim reticule is up.
##
## The reticule's five crosshair ColorRects defaulted to MOUSE_FILTER_STOP.
## Godot hit-tests children before it consults the parent's IGNORE, so the
## 8x8 Dot sitting exactly on the viewport centre, which is where a captured
## pointer is parked, swallowed every motion and click at the GUI stage and
## `_unhandled_input` never ran. Holding Q froze the camera, and left and
## middle click died with it.
##
## The events go through `get_viewport().push_input`, NOT straight into
## `_unhandled_input`: calling the handler directly skips the GUI stage that
## eats them, which is how this shipped green the first time.

var _player: Node3D
var _pivot: Node3D
var _hud: Node


func before_all() -> void:
	_player = load("res://scenes/player.tscn").instantiate()
	add_child(_player)
	await wait_process_frames(1)
	_pivot = _player.get_node("CameraPivot")
	_hud = get_tree().get_root().get_node("Hud")
	# Headless never delivers a mouse-enter, and without one the GUI stage
	# skips hit-testing entirely: every case passes whatever the filters say.
	get_viewport().notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)


func after_all() -> void:
	_hud.set_reticule(false)
	_player.free()


## Local coords: the headless window is 64x64 under a content-scale
## transform, so a viewport-centre point in global coords maps far off screen
## and misses every Control.
func _push_motion(by: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_viewport().get_visible_rect().size * 0.5
	event.relative = by
	get_viewport().push_input(event, true)


func _turn_by_motion() -> float:
	var before := _pivot.rotation.y
	_push_motion(Vector2(100.0, 0.0))
	return _pivot.rotation.y - before


func test_the_camera_turns_with_the_reticule_up() -> void:
	_hud.set_reticule(false)
	var clear := _turn_by_motion()
	assert_almost_ne(clear, 0.0, 0.0001, "camera did not turn with no reticule")

	_hud.set_reticule(true, "Wolf 40%", true)
	await wait_process_frames(1)
	assert_almost_eq(
		_turn_by_motion(), clear, 0.0001,
		"the reticule swallowed the motion: a crosshair rect is not IGNORE",
	)
	_hud.set_reticule(false)


## Aiming with right mouse leaves the reticule up while the player bites and
## commands, so those clicks have to survive it too.
func test_clicks_still_reach_the_player_with_the_reticule_up() -> void:
	_hud.set_reticule(true, "Wolf 40%", true)
	await wait_process_frames(1)
	_player._bite_left = 0.0

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = get_viewport().get_visible_rect().size * 0.5
	get_viewport().push_input(click, true)

	assert_gt(
		_player._bite_left, 0.0,
		"the reticule swallowed a left click, so biting while aiming is dead",
	)
	_hud.set_reticule(false)
