extends SceneTree
## Renders the contextual key prompt to test/shots/28_prompt.png. Runs
## WINDOWED, since the headless dummy renderer writes a blank image:
##   godot --path . -s test/prompt_shot.gd
##
## The prompt is the one HUD element that has to sit clear of five others, and
## a rect assertion cannot say whether it reads. Look at the image.

func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	for i in 20:
		await physics_frame

	# A workbench right beside the player, so the bench prompt is the one on
	# screen rather than whatever the scatter happened to put nearby.
	var player = get_first_node_in_group("player")
	var bench = load("res://scenes/workbench.tscn").instantiate()
	world.add_child(bench)
	bench.global_position = player.global_position + Vector3(1.5, 0.0, 0.0)

	# Something in every other panel too, or the shot proves nothing about
	# what the prompt sits next to.
	var inv = get_root().get_node("Inventory")
	inv.add("wood", 7)
	inv.add("stone", 4)
	get_root().get_node("Hud").flash("A message, to prove the two do not collide.")

	for i in 40:
		await process_frame
	var img := get_root().get_texture().get_image()
	print("SHOT_SAVED=", img.save_png("res://test/shots/28_prompt.png") == OK)
	quit()
