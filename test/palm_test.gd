extends GutTest
## Palm assertions, ported from test/palm_test.gd.
##
## Palms were shore dressing with no collider at all, so the player walked
## through them while every other tree blocked. These pin both halves of
## the fix: they stop you, and they give wood.

var _world: Node
var _player: Node


func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	_player = _world.get_node("Player")
	await wait_physics_frames(20)


func after_all() -> void:
	_world.free()


func test_a_palm_blocks_the_player() -> void:
	var palm = load("res://scenes/models/palm.tscn").instantiate()
	_world.add_child(palm)
	palm.global_position = Vector3(0, 0, -6)
	await wait_physics_frames(1)

	assert_true(
		palm is StaticBody3D and palm.get_node_or_null("Collision") != null,
		"a palm is a body with a shape type=%s" % palm.get_class(),
	)

	_player.global_position = Vector3(0, 1, 0)
	_player.velocity = Vector3.ZERO
	await wait_physics_frames(1)
	for i in 120:
		_player.velocity.x = 0.0
		_player.velocity.z = -6.0
		_player.move_and_slide()
		await wait_physics_frames(1)

	var z = _player.global_position.z
	assert_true(
		z > -5.5,
		"the player is stopped in front of the palm player z=%.2f, palm at z=-6.0" % z,
	)
	palm.queue_free()
	await wait_physics_frames(1)


func test_a_palm_gives_wood() -> void:
	var palm = load("res://scenes/models/palm.tscn").instantiate()
	# Scenery scatters palms at a random scale; the hit tween must respect it.
	palm.scale = Vector3.ONE * 1.2
	_world.add_child(palm)
	palm.global_position = Vector3(0, 0, -2)
	await wait_physics_frames(1)

	assert_true(
		palm.is_in_group("resource_node") and palm.has_method("punch"),
		"a palm is a gatherable resource node groups=%s" % str(palm.get_groups()),
	)
	assert_true(
		palm._base_scale.is_equal_approx(Vector3.ONE * 1.2),
		"it keeps the scale scenery gave it base_scale=%s" % palm._base_scale,
	)

	var before = Inventory.count("wood")
	_player.global_position = Vector3(0, 1, 0)
	_player.get_node("CameraPivot").rotation = Vector3.ZERO  # Face -Z, at the palm.
	await wait_physics_frames(1)
	_player._punch()
	await wait_physics_frames(1)
	assert_true(
		Inventory.count("wood") > before,
		"biting a palm yields wood wood %d -> %d" % [before, Inventory.count("wood")],
	)

	for i in Tuning.GATHER_HITS:
		_player._punch()
		await wait_physics_frames(1)
	assert_true(not palm.is_available(), "it depletes like any other tree available=%s" % palm.is_available())
