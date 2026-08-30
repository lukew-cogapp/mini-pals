extends SceneTree
## TEMP probe: prints camera rig geometry and glTF model bounds. Delete me.


func _init() -> void:
	await process_frame

	# --- SpringArm3D extension direction, from a minimal rig ---
	var pivot := Node3D.new()
	var arm := SpringArm3D.new()
	arm.spring_length = 5.0
	var cam := Camera3D.new()
	arm.add_child(cam)
	pivot.add_child(arm)
	get_root().add_child(pivot)
	await process_frame
	await physics_frame
	await process_frame
	print("PROBE springarm: pivot at ", pivot.global_position,
		" camera at ", cam.global_position,
		" camera_look(-basis.z)=", -cam.global_transform.basis.z)
	pivot.queue_free()

	# --- Player scene rig as it stands on disk ---
	var player: Node3D = load("res://scenes/player.tscn").instantiate()
	get_root().add_child(player)
	await process_frame
	await physics_frame
	var p_pivot: Node3D = player.get_node("CameraPivot")
	var p_cam: Camera3D = player.get_node("CameraPivot/SpringArm3D/Camera3D")
	print("PROBE player rig: pivot.basis.z=", p_pivot.global_transform.basis.z,
		" camera at ", p_cam.global_position,
		" camera_look=", -p_cam.global_transform.basis.z)
	player.queue_free()

	# --- Quaternius model AABBs: where is the mesh offset? ---
	for path in ["res://assets/monsters/Blob/Cat.gltf", "res://assets/monsters/Blob/Dog.gltf"]:
		var m: Node3D = load(path).instantiate()
		get_root().add_child(m)
		await process_frame
		var aabb := _merged_aabb(m)
		print("PROBE ", path.get_file(), " aabb pos=", aabb.position, " size=", aabb.size)
		m.queue_free()
	quit()


func _merged_aabb(n: Node) -> AABB:
	var total := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while stack:
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D or cur is ImporterMeshInstance3D:
			var mi := cur as GeometryInstance3D
			var world: AABB = mi.global_transform * mi.get_aabb()
			total = world if first else total.merge(world)
			first = false
		stack.append_array(cur.get_children())
	return total
