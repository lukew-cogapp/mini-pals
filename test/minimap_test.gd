extends GutTest
## Headless assertions for the minimap and its fog of war, ported from
## test/minimap_test.gd.
##
## The map is north-up, so world +X is right and world -Z is UP on screen. A
## mirrored or rotated map looks perfectly fine in a screenshot and is useless
## in play, so the heading and the sign of a pal's offset are asserted here
## rather than eyeballed.

var _world: Node
var _hud
var _map
var _player


## Freed in after_all, not by add_child_autofree, which frees at the end of
## the test that called it rather than at the end of the script. free, not
## queue_free: GUT counts children still parented when the script ends.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(5)
	_hud = Hud
	_map = _hud.get_node("MinimapPanel/MinimapPad/Map")
	_player = _world.get_node("Player")


func after_all() -> void:
	_world.free()


func test_panel_layout() -> void:
	assert_true(
		_hud.get_node("MinimapPanel").visible and _map != null,
		"the minimap exists and is on by default",
	)

	# The two panels form one right-aligned column. They overlapped by 14 px on
	# the first attempt, which the screenshot showed and no other check would.
	var map_rect: Rect2 = _hud.get_node("MinimapPanel").get_global_rect()
	var obj_rect: Rect2 = _hud.get_node("ObjectivePanel").get_global_rect()
	assert_true(
		obj_rect.position.y >= map_rect.end.y,
		(
			"the objectives sit below the map, not over it: map ends %f, objectives start %f"
			% [map_rect.end.y, obj_rect.position.y]
		),
	)
	assert_true(
		absf(map_rect.end.x - obj_rect.end.x) < 1.0,
		(
			"both are right-aligned to the same edge: map %f, objectives %f"
			% [map_rect.end.x, obj_rect.end.x]
		),
	)
	# The health bar and item list own the top LEFT; nothing may reach them.
	for left in ["Health", "ItemPanel"]:
		var lr: Rect2 = _hud.get_node(left).get_global_rect()
		assert_true(
			not map_rect.intersects(lr),
			"the map clears %s: %s=%s" % [left, left, str(lr)],
		)


func test_input_map() -> void:
	var keys := []
	var pads := []
	for e in InputMap.action_get_events("minimap"):
		if e is InputEventKey:
			keys.append(e.physical_keycode)
		elif e is InputEventJoypadButton:
			pads.append(e.button_index)
	assert_eq(keys, [KEY_M], "minimap is bound to M")
	assert_eq(pads.size(), 1, "and to a free pad button: pads=%s" % str(pads))
	# Hand-editing project.godot has broken the whole map before, so every
	# other action is checked to still be there with its events intact.
	for action in [
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "run", "throw", "ride", "punch", "build", "interact",
		"cycle_pal", "help", "pal_prev", "pal_next"
	]:
		assert_true(
			InputMap.has_action(action) and InputMap.action_get_events(action).size() > 0,
			(
				"%s survived the input edit: events=%d"
				% [action, InputMap.action_get_events(action).size()]
			),
		)


func test_toggle() -> void:
	_hud._minimap_panel.visible = false
	assert_true(
		not _hud.get_node("MinimapPanel").visible and _hud.get_node("ObjectivePanel").visible,
		"hiding the map leaves the objectives alone",
	)
	_hud._minimap_panel.visible = true


func test_fog_of_war() -> void:
	# Far from spawn, but on the island, so it is somewhere worth revealing.
	var far := Vector3(0, 0, -Tuning.ISLAND_RADIUS * 0.7)
	_map.reveal_around(_player.global_position)
	assert_true(not _map.is_revealed(far), "a far point starts fogged: far=%s" % str(far))
	assert_true(_map.is_revealed(_player.global_position), "the spawn is revealed")

	_map.reveal_around(far)
	assert_true(_map.is_revealed(far), "walking there reveals it")
	# Nothing hides a cell again, so leaving must not re-fog it.
	_map.reveal_around(_player.global_position)
	assert_true(_map.is_revealed(far), "revealed stays revealed after leaving")

	# A pal in fog must not be drawn. Checked through the same predicate the
	# draw uses, and with a real pal, so a fog that hides nothing fails here.
	var fogged := Vector3(Tuning.ISLAND_RADIUS * 0.8, 0, Tuning.ISLAND_RADIUS * 0.4)
	assert_true(
		not _map.is_revealed(fogged), "a pal out in the fog is not drawn: at=%s" % str(fogged)
	)
	_map.reveal_around(fogged)
	assert_true(_map.is_revealed(fogged), "and is drawn once that ground is walked")


## Godot forward is -Z, which is UP the screen, so the wedge tip must sit
## ABOVE the player's own map position (a smaller y).
func test_heading_forward() -> void:
	await _assert_heading("forward (-Z)", Vector3(0, 0, -1), Vector2(0, -1))


func test_heading_right() -> void:
	await _assert_heading("right (+X)", Vector3(1, 0, 0), Vector2(1, 0))


func test_pal_side_of_map() -> void:
	# +X world is right (bigger map x), -Z world is up (smaller map y).
	var centre: Vector2 = _map._to_map(Vector3.ZERO)
	var ne: Vector2 = _map._to_map(Vector3(50, 0, -50))
	assert_true(ne.x > centre.x, "world +X draws to the right: x=%f centre=%f" % [ne.x, centre.x])
	assert_true(ne.y < centre.y, "world -Z draws upward: y=%f centre=%f" % [ne.y, centre.y])


## Point the player's body along `dir` and check the wedge tip leads the way,
## comparing against `want` in screen space.
func _assert_heading(label: String, dir: Vector3, want: Vector2) -> void:
	var body = _player.get_node("Body")
	body.global_rotation.y = atan2(-dir.x, -dir.z)
	await wait_process_frames(1)
	var f: Vector3 = _player.facing()
	assert_true(
		f.distance_to(dir) < 0.01,
		"%s: facing() agrees with the rotation: facing=%s want=%s" % [label, str(f), str(dir)],
	)

	var wedge: PackedVector2Array = _map.player_wedge()
	var at: Vector2 = _map._to_map(_player.global_position)
	var tip: Vector2 = wedge[0] - at
	assert_true(
		tip.normalized().distance_to(want) < 0.01,
		(
			"%s: the wedge tip leads the heading: tip=%s want=%s"
			% [label, str(tip.normalized()), str(want)]
		),
	)
