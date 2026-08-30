extends SceneTree
## Headless mushroom-throw assertions. Run:
##   godot --headless --path . -s test/mushroom_throw_test.gd
##
## The King's job is free throws, so what leaves your hand while he is out is
## one of his mushrooms rather than a crafted cube. Both meshes live in the
## scene and throw() picks one: a runtime load would stutter the first throw.

var _fails := 0

func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	var party = get_root().get_node("Party")
	var tuning = get_root().get_node("Tuning")
	for i in 10:
		await physics_frame

	# No King: a cube.
	var c1 = load("res://scenes/pal_cube.tscn").instantiate()
	world.add_child(c1)
	await physics_frame
	c1.throw(Vector3(0, 5, 0), Vector3.ZERO)
	await physics_frame
	_check("without the King a cube is thrown",
		c1._cube.visible and not c1._mushroom.visible,
		"cube=%s mushroom=%s" % [c1._cube.visible, c1._mushroom.visible])
	c1.queue_free()

	# King out.
	var king = load("res://scenes/pal_boss.tscn").instantiate()
	world.add_child(king)
	await physics_frame
	king.level = tuning.BOSS_LEVEL
	king.caught = true
	party.store(king)
	await physics_frame
	_check("the King counts as out", party.infinite_cubes(),
		"active=%s" % (party.active.display_name if party.active else "<none>"))

	var c2 = load("res://scenes/pal_cube.tscn").instantiate()
	world.add_child(c2)
	await physics_frame
	c2.throw(Vector3(0, 5, 0), Vector3.ZERO)
	await physics_frame
	_check("with the King out a mushroom is thrown",
		c2._mushroom.visible and not c2._cube.visible,
		"cube=%s mushroom=%s" % [c2._cube.visible, c2._mushroom.visible])
	_check("the pop tween scales the mushroom, not the cube",
		c2._mesh == c2._mushroom, "mesh=%s" % c2._mesh.name)

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)
