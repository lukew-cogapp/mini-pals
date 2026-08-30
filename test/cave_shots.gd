extends SceneTree
## The cave from eight compass points plus above. A single framed shot at the
## mouth has passed twice while the structure was visibly broken from open
## ground, so this orbits it instead.

func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	for i in 6:
		await physics_frame

	var t = load("res://scripts/terrain.gd")
	var cave = world.find_child("Cave", true, false)
	var at: Vector3 = cave.global_position if cave else Vector3.ZERO
	print("cave at ", at)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true

	var dist := 34.0
	for i in 8:
		var a := TAU * i / 8.0
		var eye := at + Vector3(cos(a) * dist, 0.0, sin(a) * dist)
		# Stand on the ground at that point, at eye height, like a player.
		eye.y = t.height_at(eye.x, eye.z) + 1.7
		cam.global_position = eye
		cam.look_at(at + Vector3(0, 1.0, 0), Vector3.UP)
		for _f in 3:
			await process_frame
		var deg := int(round(rad_to_deg(a)))
		get_root().get_texture().get_image().save_png("res://test/shots/cave_%03d.png" % deg)

	# And from above, to see the roof against the hill.
	cam.global_position = at + Vector3(0, 46, 0.1)
	cam.look_at(at, Vector3.UP)
	for _f in 3:
		await process_frame
	get_root().get_texture().get_image().save_png("res://test/shots/cave_top.png")
	print("SHOTS_DONE")
	quit()
