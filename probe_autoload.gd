extends SceneTree
func _init() -> void:
	await process_frame
	print("root children:")
	for c in get_root().get_children():
		print("  - ", c.name)
	quit()
