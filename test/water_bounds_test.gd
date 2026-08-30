extends SceneTree
## Headless shoreline collision assertions. Run:
##   godot --headless --path . -s test/water_bounds_test.gd

var _fails := 0
var _world: Node3D
var _player: CharacterBody3D


func _init() -> void:
	await process_frame
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	_player = _world.get_node("Player")

	for i in 20:
		await physics_frame

	await _test_player_cannot_walk_between_shore_wall_segments()
	await _test_mount_cannot_walk_between_shore_wall_segments()
	await _test_dismount_picks_an_inland_spot_at_the_shore()
	await _test_rider_cannot_pass_between_shallow_wall_segments()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


## The wall is segmented, so the worst case is halfway between two segments.
func _test_player_cannot_walk_between_shore_wall_segments() -> void:
	var angle := TAU / 48.0
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	_player.global_position = radial * (Tuning.SHORE_WALL_RADIUS - 2.0) + Vector3.UP
	_player.velocity = Vector3.ZERO

	var pivot: Node3D = _player.get_node("CameraPivot")
	pivot.rotation = Vector3(0.0, atan2(radial.x, radial.z), 0.0)

	Input.action_press("move_back")
	for i in 150:
		await physics_frame
	Input.action_release("move_back")

	var radius := Vector2(_player.global_position.x, _player.global_position.z).length()
	_check(
		"player cannot reach visible water between shore wall segments",
		radius < Tuning.ISLAND_RADIUS + Tuning.BEACH_WIDTH - 0.5,
		"radius=%.2f water starts at %.2f pos=%s" % [
			radius,
			Tuning.ISLAND_RADIUS + Tuning.BEACH_WIDTH,
			_player.global_position,
		],
	)


func _test_mount_cannot_walk_between_shore_wall_segments() -> void:
	var angle := TAU / 48.0
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var wolf = load("res://scenes/pal_wolf.tscn").instantiate()
	_world.add_child(wolf)
	await process_frame

	wolf.global_position = radial * (Tuning.SHORE_WALL_RADIUS - 2.0) + Vector3.UP
	wolf.velocity = Vector3.ZERO
	wolf.caught = true
	wolf.state = wolf.State.RIDDEN
	_player.global_position = wolf.seat_position()
	_player.velocity = Vector3.ZERO
	_player.mount = wolf
	_player._set_collision_enabled(false)

	var pivot: Node3D = _player.get_node("CameraPivot")
	pivot.rotation = Vector3(0.0, atan2(radial.x, radial.z), 0.0)

	Input.action_press("move_back")
	for i in 120:
		await physics_frame
	Input.action_release("move_back")

	var radius := Vector2(wolf.global_position.x, wolf.global_position.z).length()
	_check(
		"mounted wolf cannot reach visible water between shore wall segments",
		radius < Tuning.ISLAND_RADIUS + Tuning.BEACH_WIDTH - 0.5,
		"radius=%.2f water starts at %.2f pos=%s" % [
			radius,
			Tuning.ISLAND_RADIUS + Tuning.BEACH_WIDTH,
			wolf.global_position,
		],
	)

	_player.mount = null
	_player._set_collision_enabled(true)
	wolf.queue_free()


func _test_dismount_picks_an_inland_spot_at_the_shore() -> void:
	var angle := TAU / 48.0
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var tangent := Vector3(-radial.z, 0.0, radial.x)
	var wolf = load("res://scenes/pal_wolf.tscn").instantiate()
	_world.add_child(wolf)
	await process_frame

	wolf.global_position = radial * (Tuning.SHORE_WALL_RADIUS - 1.0) + Vector3.UP
	wolf.look_at(wolf.global_position + tangent, Vector3.UP)
	wolf.caught = true
	wolf.state = wolf.State.RIDDEN
	_player.global_position = wolf.seat_position()
	_player.velocity = Vector3.ZERO
	_player.mount = wolf
	_player._set_collision_enabled(false)

	var dismounted: bool = _player._dismount()
	var radius := Vector2(_player.global_position.x, _player.global_position.z).length()
	_check(
		"dismount at the shore lands inside the wall",
		dismounted and radius < Tuning.SHORE_WALL_RADIUS - Tuning.RIDE_DISMOUNT_CLEARANCE,
		"dismounted=%s radius=%.2f pos=%s" % [
			dismounted,
			radius,
			_player.global_position,
		],
	)

	if _player.mount:
		_player.mount = null
		_player._set_collision_enabled(true)
	wolf.queue_free()


## The shallow wall is segmented like the shore wall, so it leaks in the same
## place: halfway between two boxes. Ridden, since a swimmer is the only
## thing that reaches this far out.
func _test_rider_cannot_pass_between_shallow_wall_segments() -> void:
	var angle := TAU / 48.0
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var pal = load("res://scenes/pal_mudwader.tscn").instantiate()
	_world.add_child(pal)
	await process_frame

	pal.global_position = radial * (Tuning.SHALLOW_WALL_RADIUS - 4.0) + Vector3.UP
	pal.velocity = Vector3.ZERO
	pal.caught = true
	pal.state = pal.State.RIDDEN
	_player.global_position = pal.seat_position()
	_player.velocity = Vector3.ZERO
	_player.mount = pal
	_player._set_collision_enabled(false)
	_player._set_shore_wall_enabled(false)

	var pivot: Node3D = _player.get_node("CameraPivot")
	pivot.rotation = Vector3(0.0, atan2(radial.x, radial.z), 0.0)

	Input.action_press("move_back")
	for i in 250:
		await physics_frame
	Input.action_release("move_back")

	var radius := Vector2(pal.global_position.x, pal.global_position.z).length()
	_check(
		"ridden swimmer cannot pass between shallow wall segments",
		radius < Tuning.SHALLOW_WALL_RADIUS + 1.0,
		"radius=%.2f shallow wall at %.2f pos=%s" % [
			radius,
			Tuning.SHALLOW_WALL_RADIUS,
			pal.global_position,
		],
	)

	_player.mount = null
	_player._set_collision_enabled(true)
	_player._set_shore_wall_enabled(true)
	pal.queue_free()
