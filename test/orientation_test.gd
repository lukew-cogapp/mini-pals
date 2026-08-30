extends SceneTree
## Headless orientation assertions. Run:
##   godot --headless --path . -s test/orientation_test.gd
## Exits 1 on any failure. Covers: camera behind the player, turn maths for
## all four inputs, thrown cubes hitting a pal ahead, punch facing check.

var _fails := 0
var _world: Node3D
var _player: CharacterBody3D


func _init() -> void:
	await process_frame
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	_player = _world.get_node("Player")

	# Park every wild pal far away so only what each test places matters.
	var pals := get_nodes_in_group("pal")
	for pal in pals:
		pal.set_physics_process(false)
		pal.global_position = Vector3(200, 1, 200)
	for i in 20:
		await physics_frame  # Let the player settle onto the ground.

	await _test_camera_behind()
	await _test_turn_maths()
	await _test_cube_hits(pals[0])
	await _test_punch_facing()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


## The spring arm must extend to +Z of the pivot (behind a -Z-facing body),
## not collapse against the player's own capsule.
func _test_camera_behind() -> void:
	var pivot: Node3D = _player.get_node("CameraPivot")
	var cam: Camera3D = _player.get_node("CameraPivot/SpringArm3D/Camera3D")
	var offset := cam.global_position - pivot.global_position
	_check(
		"camera sits behind (+Z of pivot) at arm length",
		offset.dot(pivot.global_transform.basis.z) > 4.0,
		"offset=%s" % offset,
	)
	var look := -cam.global_transform.basis.z
	_check(
		"camera looks the way the body faces",
		look.dot(_player.facing()) > 0.9,
		"look=%s facing=%s" % [look, _player.facing()],
	)


func _test_turn_maths() -> void:
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
		for i in 40:
			await physics_frame
		var vel: Vector3 = _player.velocity
		Input.action_release(case[0])
		vel.y = 0.0
		vel = vel.normalized()
		var facing: Vector3 = _player.facing()
		_check(
			"%s: travel matches camera intent" % case[0],
			vel.dot(case[1]) > 0.95,
			"vel=%s want=%s" % [vel, case[1]],
		)
		_check(
			"%s: face leads travel" % case[0],
			facing.dot(vel) > 0.95,
			"facing=%s vel=%s" % [facing, vel],
		)
		for i in 10:
			await physics_frame


## A cube lobbed with the crosshair on a pal must hit it at each distance.
func _test_cube_hits(_target: Node3D) -> void:
	_player.global_position = Vector3(0, 1, 0)
	_player.velocity = Vector3.ZERO
	var pivot: Node3D = _player.get_node("CameraPivot")
	for i in 30:
		await physics_frame  # Settle onto the ground; throws sample position.
	var cases := [
		["3m ahead", Vector3(0.0, 0.02, -3.0)],
		["5m ahead", Vector3(0.0, 0.02, -5.0)],
		["8m ahead", Vector3(0.0, 0.02, -8.0)],
		["11m ahead", Vector3(0.0, 0.02, -11.0)],
		["14m ahead", Vector3(0.0, 0.02, -14.0)],
		["6m ahead right", Vector3(1.6, 0.02, -6.0)],
		["6m ahead left", Vector3(-1.6, 0.02, -6.0)],
	]
	var party := get_root().get_node("Party")
	for case in cases:
		party.members.clear()
		party.active = null
		var target: Node3D = load("res://scenes/pal_wolf.tscn").instantiate()
		_world.add_child(target)
		await process_frame
		target.set_physics_process(false)
		# A settled pal rests with its capsule bottom on the ground (root y=0),
		# so its centre is the collider's local offset above that.
		target.global_position = case[1]
		await physics_frame
		var centre: Vector3 = target.get_node("Collision").global_position
		pivot.look_at(centre, Vector3.UP)  # Crosshair on the pal.
		await physics_frame
		var info: Dictionary = _player._current_throw_aim()
		var reticule_origin: Vector3 = info.origin
		var reticule_aim: Vector3 = info.aim
		var to_reticule: Vector3 = centre - reticule_origin
		var along_reticule: float = to_reticule.dot(reticule_aim)
		var off_reticule: float = (to_reticule - reticule_aim * along_reticule).length()
		var lock_radius: float = Tuning.CUBE_AIM_ASSIST_RADIUS \
			+ along_reticule * Tuning.CUBE_AIM_ASSIST_GROWTH
		_check("reticule locks %s" % case[0], info.pal == target,
			"pal=%s off=%.2f lock=%.2f along=%.2f target=%s" % [
				info.pal,
				off_reticule,
				lock_radius,
				along_reticule,
				info.target,
			])
		var cube: Area3D = load("res://scenes/pal_cube.tscn").instantiate()
		_world.add_child(cube)
		var hit := [false]
		cube.resolved.connect(func(pal: Node, _success: bool) -> void:
			if pal == target:
				hit[0] = true)
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
			await physics_frame
			if hit[0]:
				break
			if is_instance_valid(cube):
				closest = minf(closest, cube.global_position.distance_to(centre))
		_check("cube hits pal %s" % case[0], hit[0],
			"closest approach %.2fm" % closest)
		if is_instance_valid(cube):
			cube.queue_free()
		if is_instance_valid(target):
			target.queue_free()
		await physics_frame
	pivot.rotation = Vector3.ZERO


func _test_punch_facing() -> void:
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
	await physics_frame

	_player._punch()
	await physics_frame
	_check("punch hits the tree ahead", ahead._hits == 1,
		"ahead._hits=%d" % ahead._hits)
	_check("punch spares the tree behind", behind._hits == 0,
		"behind._hits=%d" % behind._hits)

	ahead.queue_free()
	await physics_frame
	_player._punch()
	await physics_frame
	_check("punch finds nothing with only a tree behind", behind._hits == 0,
		"behind._hits=%d" % behind._hits)
	behind.queue_free()
