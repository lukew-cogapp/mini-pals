extends SceneTree
## Renders the title screen to test/shots/27_start_screen.png. Runs WINDOWED:
##   godot --path . -s test/start_shot.gd

func _init() -> void:
	await process_frame
	var screen = load("res://scenes/start_screen.tscn").instantiate()
	get_root().add_child(screen)
	# Enough frames for the glTF props, shadows and the sky to resolve.
	for i in 90:
		await process_frame
	var img := get_root().get_texture().get_image()
	var err := img.save_png("res://test/shots/27_start_screen.png")
	print("SHOT_SAVED=", err == OK)
	quit()
