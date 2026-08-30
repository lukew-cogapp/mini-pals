extends SceneTree
## TEMP probe: renders raw, unrotated glTF models from the +Z and -Z sides,
## so we can see which side the face is on. Run WINDOWED. Delete me.

const OUT := "res://test/shots/"

var _cam: Camera3D


func _init() -> void:
	await process_frame
	var root := Node3D.new()
	get_root().add_child(root)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.6, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)

	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true

	for path in ["res://assets/monsters/Blob/Cat.gltf", "res://assets/monsters/Blob/Dog.gltf"]:
		var m: Node3D = load(path).instantiate()
		root.add_child(m)
		await process_frame
		var stem: String = path.get_file().get_basename().to_lower()
		await _shot("raw_%s_from_plusZ" % stem, Vector3(0, 1.2, 3.0))
		await _shot("raw_%s_from_minusZ" % stem, Vector3(0, 1.2, -3.0))
		m.queue_free()
		await process_frame
	quit()


func _shot(name: String, cam_pos: Vector3) -> void:
	_cam.global_position = cam_pos
	_cam.look_at(Vector3(0, 0.8, 0), Vector3.UP)
	await process_frame
	await process_frame
	var img := get_root().get_texture().get_image()
	var err := img.save_png(OUT + name + ".png")
	print("SHOT ", name, " err=", err)
