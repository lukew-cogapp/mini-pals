extends SceneTree
## Headless cube-catch assertions. Run:
##   godot --headless --path . -s test/cube_hit_test.gd
##
## Throws are lobs, so a throw the player reads as on target often lands a
## step short. The sweep used to be a zero-radius ray and the landing had no
## grab at all, so those visibly-close throws counted as misses.

var _fails := 0
var _world
var _tuning

func _init() -> void:
	await process_frame
	_tuning = get_root().get_node("Tuning")
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	for i in 10:
		await physics_frame

	# Straight down beside a pal: the old ray never touched its capsule.
	await _drop("lands a step to the side", Vector3(1.1, 0, 0), true)
	await _drop("lands right on it", Vector3(0.0, 0, 0), true)
	await _drop("lands well away", Vector3(6.0, 0, 0), false)

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _drop(name: String, offset: Vector3, want_hit: bool) -> void:
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	_world.add_child(pal)
	await physics_frame
	pal.global_position = Vector3(0, 0, -20)
	pal.set_physics_process(false)
	await physics_frame

	var cube = load("res://scenes/pal_cube.tscn").instantiate()
	_world.add_child(cube)
	var got := [false]
	cube.resolved.connect(func(p, _ok): got[0] = (p == pal))
	# Dropped from above, so only the landing logic decides it.
	cube.throw(pal.global_position + offset + Vector3.UP * 5.0, Vector3.ZERO)

	for i in 200:
		await physics_frame
		if not is_instance_valid(cube):
			break

	_check("%s -> %s" % [name, "caught" if want_hit else "missed"],
		got[0] == want_hit, "hit=%s wanted=%s" % [got[0], want_hit])
	if is_instance_valid(pal):
		pal.queue_free()
	await physics_frame


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)
