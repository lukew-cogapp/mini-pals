extends SceneTree
func _init() -> void:
	var w = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(w)
	await physics_frame
	var wolf = get_nodes_in_group("pal")[0]
	wolf.set_physics_process(false)
	wolf.global_position = Vector3(0, 0, -4)
	await physics_frame
	var s2 = load("res://scenes/catch_sphere.tscn").instantiate()
	w.add_child(s2)
	s2.set_physics_process(false)
	s2.global_position = wolf.global_position + Vector3.UP * 0.6
	await physics_frame
	await physics_frame
	print("RESULT wolf_layer=%d sphere_mask=%d overlaps=%d" % [
		wolf.collision_layer, s2.collision_mask, s2.get_overlapping_bodies().size()])
	quit()
