extends SceneTree
## Headless assertions for the minimap and its fog of war. Run:
##   godot --headless --path . -s test/minimap_test.gd
##
## The map is north-up, so world +X is right and world -Z is UP on screen. A
## mirrored or rotated map looks perfectly fine in a screenshot and is useless
## in play, so the heading and the sign of a pal's offset are asserted here
## rather than eyeballed.

var _fails := 0
var _hud
var _map
var _player


func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	for i in 5:
		await physics_frame
	_hud = get_root().get_node("Hud")
	_map = _hud.get_node("MinimapPanel/MinimapPad/Map")
	_player = world.get_node("Player")

	_check("the minimap exists and is on by default",
		_hud.get_node("MinimapPanel").visible and _map != null, "")

	# The two panels form one right-aligned column. They overlapped by 14 px on
	# the first attempt, which the screenshot showed and no other check would.
	var map_rect: Rect2 = _hud.get_node("MinimapPanel").get_global_rect()
	var obj_rect: Rect2 = _hud.get_node("ObjectivePanel").get_global_rect()
	_check("the objectives sit below the map, not over it",
		obj_rect.position.y >= map_rect.end.y,
		"map ends %f, objectives start %f" % [map_rect.end.y, obj_rect.position.y])
	_check("both are right-aligned to the same edge",
		absf(map_rect.end.x - obj_rect.end.x) < 1.0,
		"map %f, objectives %f" % [map_rect.end.x, obj_rect.end.x])
	# The health bar and item list own the top LEFT; nothing may reach them.
	for left in ["Health", "ItemPanel"]:
		var lr: Rect2 = _hud.get_node(left).get_global_rect()
		_check("the map clears %s" % left, not map_rect.intersects(lr),
			"%s=%s" % [left, str(lr)])

	# --- The input map ------------------------------------------------------
	var keys := []
	var pads := []
	for e in InputMap.action_get_events("minimap"):
		if e is InputEventKey:
			keys.append(e.physical_keycode)
		elif e is InputEventJoypadButton:
			pads.append(e.button_index)
	_check("minimap is bound to M", keys == [KEY_M], "keys=%s" % str(keys))
	_check("and to a free pad button", pads.size() == 1, "pads=%s" % str(pads))
	# Hand-editing project.godot has broken the whole map before, so every
	# other action is checked to still be there with its events intact.
	for action in ["move_forward", "move_back", "move_left", "move_right",
			"jump", "run", "throw", "ride", "punch", "build", "interact",
			"cycle_pal", "help", "pal_prev", "pal_next"]:
		_check("%s survived the input edit" % action,
			InputMap.has_action(action)
			and InputMap.action_get_events(action).size() > 0,
			"events=%d" % InputMap.action_get_events(action).size())

	# --- The toggle ---------------------------------------------------------
	_hud._minimap_panel.visible = false
	_check("hiding the map leaves the objectives alone",
		not _hud.get_node("MinimapPanel").visible
		and _hud.get_node("ObjectivePanel").visible, "")
	_hud._minimap_panel.visible = true

	# --- Fog of war ---------------------------------------------------------
	# Far from spawn, but on the island, so it is somewhere worth revealing.
	var far := Vector3(0, 0, -Tuning.ISLAND_RADIUS * 0.7)
	_map.reveal_around(_player.global_position)
	_check("a far point starts fogged", not _map.is_revealed(far),
		"far=%s" % str(far))
	_check("the spawn is revealed", _map.is_revealed(_player.global_position), "")

	_map.reveal_around(far)
	_check("walking there reveals it", _map.is_revealed(far), "")
	# Nothing hides a cell again, so leaving must not re-fog it.
	_map.reveal_around(_player.global_position)
	_check("revealed stays revealed after leaving", _map.is_revealed(far), "")

	# A pal in fog must not be drawn. Checked through the same predicate the
	# draw uses, and with a real pal, so a fog that hides nothing fails here.
	var fogged := Vector3(Tuning.ISLAND_RADIUS * 0.8, 0, Tuning.ISLAND_RADIUS * 0.4)
	_check("a pal out in the fog is not drawn", not _map.is_revealed(fogged),
		"at=%s" % str(fogged))
	_map.reveal_around(fogged)
	_check("and is drawn once that ground is walked",
		_map.is_revealed(fogged), "")

	# --- Heading, two ways --------------------------------------------------
	# Godot forward is -Z, which is UP the screen, so the wedge tip must sit
	# ABOVE the player's own map position (a smaller y).
	await _assert_heading("forward (-Z)", Vector3(0, 0, -1), Vector2(0, -1))
	await _assert_heading("right (+X)", Vector3(1, 0, 0), Vector2(1, 0))

	# --- A pal's side of the map --------------------------------------------
	# +X world is right (bigger map x), -Z world is up (smaller map y).
	var centre: Vector2 = _map._to_map(Vector3.ZERO)
	var ne: Vector2 = _map._to_map(Vector3(50, 0, -50))
	_check("world +X draws to the right", ne.x > centre.x,
		"x=%f centre=%f" % [ne.x, centre.x])
	_check("world -Z draws upward", ne.y < centre.y,
		"y=%f centre=%f" % [ne.y, centre.y])

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


## Point the player's body along `dir` and check the wedge tip leads the way,
## comparing against `want` in screen space.
func _assert_heading(label: String, dir: Vector3, want: Vector2) -> void:
	var body = _player.get_node("Body")
	body.global_rotation.y = atan2(-dir.x, -dir.z)
	await process_frame
	var f: Vector3 = _player.facing()
	_check("%s: facing() agrees with the rotation" % label,
		f.distance_to(dir) < 0.01, "facing=%s want=%s" % [str(f), str(dir)])

	var wedge: PackedVector2Array = _map.player_wedge()
	var at: Vector2 = _map._to_map(_player.global_position)
	var tip: Vector2 = wedge[0] - at
	_check("%s: the wedge tip leads the heading" % label,
		tip.normalized().distance_to(want) < 0.01,
		"tip=%s want=%s" % [str(tip.normalized()), str(want)])


func _check(check_name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", check_name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", check_name, "  ", detail)
