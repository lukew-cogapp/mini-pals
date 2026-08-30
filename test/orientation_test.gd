extends GutTest
## Orientation assertions, ported from test/orientation_test.gd.
##
## Covers: camera behind the player, turn maths for all four inputs, thrown
## cubes hitting a pal ahead, punch facing check.
##
## Reasoning about facing has been wrong here four times, so these run the
## real bodies and read the real numbers rather than inspecting anything.
##
## One world for the whole script, in the original order: before_all parks
## every wild pal far away so only what each test places matters, and
## test_cube_hits reads the first of those parked pals.

var _world: Node3D
var _player: CharacterBody3D
var _pals: Array


## Freed in after_all, not by add_child_autofree, which frees at the end of
## the test that called it rather than at the end of the script. free, not
## queue_free: GUT counts children still parented when the script ends.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	_player = _world.get_node("Player")

	# Park every wild pal far away so only what each test places matters.
	_pals = get_tree().get_nodes_in_group("pal")
	for pal in _pals:
		pal.set_physics_process(false)
		pal.global_position = Vector3(200, 1, 200)
	await wait_physics_frames(20)  # Let the player settle onto the ground.


func after_all() -> void:
	_world.free()


## The spring arm must extend to +Z of the pivot (behind a -Z-facing body),
## not collapse against the player's own capsule.
func test_camera_behind() -> void:
	var pivot: Node3D = _player.get_node("CameraPivot")
	var cam: Camera3D = _player.get_node("CameraPivot/SpringArm3D/Camera3D")
	var offset := cam.global_position - pivot.global_position
	assert_true(
		offset.dot(pivot.global_transform.basis.z) > 4.0,
		"camera sits behind (+Z of pivot) at arm length  offset=%s" % offset,
	)
	var look := -cam.global_transform.basis.z
	assert_true(
		look.dot(_player.facing()) > 0.9,
		"camera looks the way the body faces  look=%s facing=%s" % [look, _player.facing()],
	)


func test_turn_maths() -> void:
	var cases := [
		["move_forward", Vector3(0, 0, -1)],
		["move_back", Vector3(0, 0, 1)],
		["move_left", Vector3(-1, 0, 0)],
		["move_right", Vector3(1, 0, 0)],
	]
	for case in cases:
		_player.global_position = Vector3(0, 1, 0)
		_player.velocity = Vector3.ZERO
		Input.action_press(case[0])
		await wait_physics_frames(40)
		var vel: Vector3 = _player.velocity
		Input.action_release(case[0])
		vel.y = 0.0
		vel = vel.normalized()
		var facing: Vector3 = _player.facing()
		assert_true(
			vel.dot(case[1]) > 0.95,
			"%s: travel matches camera intent  vel=%s want=%s" % [case[0], vel, case[1]],
		)
		assert_true(
			facing.dot(vel) > 0.95,
			"%s: face leads travel  facing=%s vel=%s" % [case[0], facing, vel],
		)
		await wait_physics_frames(10)


## A cube lobbed with the crosshair on a pal must hit it at each distance.
func test_cube_hits() -> void:
	var _target: Node3D = _pals[0]
	_player.global_position = Vector3(0, 1, 0)
	_player.velocity = Vector3.ZERO
	var pivot: Node3D = _player.get_node("CameraPivot")
	await wait_physics_frames(30)  # Settle onto the ground; throws sample position.
	var cases := [
		["3m ahead", Vector3(0.0, 0.02, -3.0)],
		["5m ahead", Vector3(0.0, 0.02, -5.0)],
		["8m ahead", Vector3(0.0, 0.02, -8.0)],
		["11m ahead", Vector3(0.0, 0.02, -11.0)],
		["14m ahead", Vector3(0.0, 0.02, -14.0)],
		["6m ahead right", Vector3(1.6, 0.02, -6.0)],
		["6m ahead left", Vector3(-1.6, 0.02, -6.0)],
	]
	for case in cases:
		Party.members.clear()
		Party.active = null
		var target: Node3D = load("res://scenes/pal_wolf.tscn").instantiate()
		_world.add_child(target)
		await wait_process_frames(1)
		target.set_physics_process(false)
		# A settled pal rests with its capsule bottom on the ground (root y=0),
		# so its centre is the collider's local offset above that.
		target.global_position = case[1]
		await wait_physics_frames(1)
		var centre: Vector3 = target.get_node("Collision").global_position
		pivot.look_at(centre, Vector3.UP)  # Crosshair on the pal.
		await wait_physics_frames(1)
		var info: Dictionary = _player._current_throw_aim()
		var reticule_origin: Vector3 = info.origin
		var reticule_aim: Vector3 = info.aim
		var to_reticule: Vector3 = centre - reticule_origin
		var along_reticule: float = to_reticule.dot(reticule_aim)
		var off_reticule: float = (to_reticule - reticule_aim * along_reticule).length()
		var lock_radius: float = (
			Tuning.CUBE_AIM_ASSIST_RADIUS + along_reticule * Tuning.CUBE_AIM_ASSIST_GROWTH
		)
		assert_true(
			info.pal == target,
			(
				"reticule locks %s  pal=%s off=%.2f lock=%.2f along=%.2f target=%s"
				% [
					case[0],
					info.pal,
					off_reticule,
					lock_radius,
					along_reticule,
					info.target,
				]
			),
		)
		var cube: Area3D = load("res://scenes/pal_cube.tscn").instantiate()
		_world.add_child(cube)
		var hit := [false]
		cube.resolved.connect(
			func(pal: Node, _success: bool) -> void:
				if pal == target:
					hit[0] = true
		)
		# The same maths _throw_cube uses, minus inventory and cinematics.
		var aim: Vector3 = info.aim
		var from: Vector3 = (
			_player.global_position
			+ Vector3.UP * Tuning.CUBE_SPAWN_HEIGHT
			+ aim * Tuning.CUBE_SPAWN_FORWARD
			+ pivot.global_transform.basis.x * Tuning.CUBE_SPAWN_SIDE
		)
		var goal: Vector3 = info.target
		cube.throw(from, _player._lob_velocity(from, goal))
		var closest := INF
		for i in 240:
			await wait_physics_frames(1)
			if hit[0]:
				break
			if is_instance_valid(cube):
				closest = minf(closest, cube.global_position.distance_to(centre))
		assert_true(hit[0], "cube hits pal %s  closest approach %.2fm" % [case[0], closest])
		if is_instance_valid(cube):
			cube.queue_free()
		if is_instance_valid(target):
			target.queue_free()
		await wait_physics_frames(1)
	pivot.rotation = Vector3.ZERO


func test_punch_facing() -> void:
	_player.global_position = Vector3(0, 1, 0)
	_player.velocity = Vector3.ZERO
	var pivot: Node3D = _player.get_node("CameraPivot")
	pivot.rotation = Vector3.ZERO  # Look along world -Z.

	var ahead: StaticBody3D = load("res://scenes/models/commontree_1.tscn").instantiate()
	var behind: StaticBody3D = load("res://scenes/models/commontree_1.tscn").instantiate()
	_world.add_child(ahead)
	_world.add_child(behind)
	ahead.global_position = Vector3(0, 0, -2)
	behind.global_position = Vector3(0, 0, 2)
	await wait_physics_frames(1)

	_player._punch()
	await wait_physics_frames(1)
	assert_true(ahead._hits == 1, "punch hits the tree ahead  ahead._hits=%d" % ahead._hits)
	assert_true(behind._hits == 0, "punch spares the tree behind  behind._hits=%d" % behind._hits)

	ahead.queue_free()
	await wait_physics_frames(1)
	_player._punch()
	await wait_physics_frames(1)
	assert_true(
		behind._hits == 0,
		"punch finds nothing with only a tree behind  behind._hits=%d" % behind._hits,
	)
	behind.queue_free()
