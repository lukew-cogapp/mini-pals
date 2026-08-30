extends SceneTree
## One shot: the facing gate on the pal health bar. Runs WINDOWED.
##
##   godot --path . -s test/bar_shot.gd
##
## Renders from the player's OWN rig camera, not a free one, because the bar
## gates on the CameraPivot's heading: a free camera looking at the pair would
## show whatever the player happened to be facing instead.
##
## Three frames, all with two pals side by side, one damaged and one whole:
##   31  both in front, so both bars show and only the fill differs
##   32  the player turned away, so neither shows
##   33  turned back with the pair off to one side, so the cone is doing work

const OUT := "res://test/shots/"


func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	var player = world.get_node("Player")
	var pivot = player.get_node("CameraPivot")
	var cam: Camera3D = player.get_node("CameraPivot/SpringArm3D/Camera3D")
	cam.current = true
	for _i in 20:
		await physics_frame

	# Clear the neighbourhood, so no third pal wanders into frame and muddies
	# which bar belongs to which body.
	var origin = player.global_position
	for node in get_nodes_in_group("pal"):
		if node.global_position.distance_to(origin) < 40.0:
			node.queue_free()
	await process_frame

	# The player idles facing -Z, so the pair goes in front of them at -Z,
	# far enough apart to read as two and inside PAL_HEALTH_BAR_DISTANCE.
	var hurt = await _place(world, origin + Vector3(-1.1, 0.0, -4.5))
	var whole = await _place(world, origin + Vector3(1.1, 0.0, -4.5))
	hurt.max_hp = 6
	hurt.hp = 2
	hurt._refresh_bar()
	whole.max_hp = 6
	whole.hp = 6
	whole._refresh_bar()

	pivot.rotation.y = 0.0
	await _settle(hurt, whole)
	await _capture("31_bars_faced")

	pivot.rotation.y = PI
	await _settle(hurt, whole)
	await _capture("32_bars_turned_away")

	# Ninety degrees off: the pair is beside the player, well outside the
	# cone, so neither bar should be drawn even though both are still close.
	pivot.rotation.y = PI * 0.5
	await _settle(hurt, whole)
	await _capture("33_bars_off_to_one_side")

	print("done")
	quit()


func _place(world, at: Vector3):
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	world.add_child(pal)
	await process_frame
	pal.global_position = at
	# Idle and stationary, or they wander out of frame between shots.
	pal.state = pal.State.IDLE
	pal._timer = 1000.0
	pal.velocity = Vector3.ZERO
	pal.set_physics_process(false)
	return pal


## Re-sample both bars now rather than waiting on the check interval, then
## give the renderer frames to draw the result.
func _settle(a, b) -> void:
	for pal in [a, b]:
		pal._bar_check = 0.0
		pal._tick_health_bar()
	for _i in 4:
		await process_frame


func _capture(name: String) -> void:
	await process_frame
	await process_frame
	var img := get_root().get_texture().get_image()
	var err := img.save_png(OUT + name + ".png")
	if err != OK:
		printerr("save failed: ", name, " err=", err)
	else:
		print("saved ", name)
