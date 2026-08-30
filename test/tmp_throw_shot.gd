extends SceneTree
## TEMP: rig-camera throw-at-wolf shots to private dir. Delete me.
const OUT := "/private/tmp/claude-501/-Users-lukew-git/cdef92a8-7d7e-40a6-ad77-1b8685480828/scratchpad/shots2/"
func _init() -> void:
	await process_frame
	var world: Node3D = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	var player: CharacterBody3D = world.get_node("Player")
	for i in 25:
		await physics_frame
	# A wolf parked in the crosshair line, 6m ahead.
	var wolf = get_nodes_in_group("pal")[0]
	wolf.set_physics_process(false)
	wolf.global_position = player.global_position + Vector3(0, 0.02, -6.0)
	await physics_frame
	var rig_cam: Camera3D = player.get_node("CameraPivot/SpringArm3D/Camera3D")
	rig_cam.current = true
	get_root().get_node("Inventory").add("cube", 1)
	player._throw_cube()
	for i in 5:
		await physics_frame
	await _capture("lob_f05")
	for i in 8:
		await physics_frame
	await _capture("lob_f13")
	for i in 10:
		await physics_frame
	await _capture("lob_f23")
	for i in 35:
		await physics_frame
	await _capture("lob_f58_capture")
	quit()
func _capture(name: String) -> void:
	await process_frame
	await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("SHOT ", name)
