extends SceneTree
## Headless palm assertions. Run:
##   godot --headless --path . -s test/palm_test.gd
##
## Palms were shore dressing with no collider at all, so the player walked
## through them while every other tree blocked. These pin both halves of
## the fix: they stop you, and they give wood.

var _fails := 0
var _world
var _player


func _init() -> void:
	await process_frame
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	_player = _world.get_node("Player")
	for i in 20:
		await physics_frame

	await _test_a_palm_blocks_the_player()
	await _test_a_palm_gives_wood()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _test_a_palm_blocks_the_player() -> void:
	var palm = load("res://scenes/models/palm.tscn").instantiate()
	_world.add_child(palm)
	palm.global_position = Vector3(0, 0, -6)
	await physics_frame

	_check("a palm is a body with a shape",
		palm is StaticBody3D and palm.get_node_or_null("Collision") != null,
		"type=%s" % palm.get_class())

	_player.global_position = Vector3(0, 1, 0)
	_player.velocity = Vector3.ZERO
	await physics_frame
	for i in 120:
		_player.velocity.x = 0.0
		_player.velocity.z = -6.0
		_player.move_and_slide()
		await physics_frame

	var z = _player.global_position.z
	_check("the player is stopped in front of the palm", z > -5.5,
		"player z=%.2f, palm at z=-6.0" % z)
	palm.queue_free()
	await physics_frame


func _test_a_palm_gives_wood() -> void:
	var inv = get_root().get_node("Inventory")
	var tuning = get_root().get_node("Tuning")
	var palm = load("res://scenes/models/palm.tscn").instantiate()
	# Scenery scatters palms at a random scale; the hit tween must respect it.
	palm.scale = Vector3.ONE * 1.2
	_world.add_child(palm)
	palm.global_position = Vector3(0, 0, -2)
	await physics_frame

	_check("a palm is a gatherable resource node",
		palm.is_in_group("resource_node") and palm.has_method("punch"),
		"groups=%s" % str(palm.get_groups()))
	_check("it keeps the scale scenery gave it",
		palm._base_scale.is_equal_approx(Vector3.ONE * 1.2),
		"base_scale=%s" % palm._base_scale)

	var before = inv.count("wood")
	_player.global_position = Vector3(0, 1, 0)
	_player.get_node("CameraPivot").rotation = Vector3.ZERO  # Face -Z, at the palm.
	await physics_frame
	_player._punch()
	await physics_frame
	_check("biting a palm yields wood", inv.count("wood") > before,
		"wood %d -> %d" % [before, inv.count("wood")])

	for i in tuning.GATHER_HITS:
		_player._punch()
		await physics_frame
	_check("it depletes like any other tree", not palm.is_available(),
		"available=%s" % palm.is_available())
