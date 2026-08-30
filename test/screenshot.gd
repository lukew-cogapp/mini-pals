extends SceneTree
## Renders the game to PNGs so changes can be reviewed without playing.
## Runs windowed (NOT --headless): the dummy renderer produces blank images.
##
##   godot --path . -s test/screenshot.gd --quit-after 400

const OUT := "res://test/shots/"

var _world: Node3D
var _player: CharacterBody3D
var _cam: Camera3D
var _shots: Array[Dictionary] = []


func _init() -> void:
	await process_frame
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	_player = _world.get_node("Player")

	# A free camera, so shots do not depend on the gameplay rig.
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_cam.current = true
	await physics_frame

	# Let the player settle onto the ground first.
	for i in 20:
		await physics_frame

	await _shoot("01_front", Vector3(0, 1.2, 3.5), Vector3(0, 0.9, 0))
	await _shoot("02_side", Vector3(3.5, 1.2, 0), Vector3(0, 0.9, 0))
	await _shoot("03_back", Vector3(0, 1.2, -3.5), Vector3(0, 0.9, 0))
	await _shoot("04_above", Vector3(0.1, 4.0, 0.1), Vector3(0, 0.5, 0))

	await _hold("move_forward", 25)
	await _shoot("05_walking_side", Vector3(3.5, 1.2, 0), Vector3(0, 0.9, 0), false)
	await _shoot("06_walking_front", Vector3(0, 1.4, 3.5), Vector3(0, 0.9, 0), false)
	_release("move_forward")

	await _hold("jump", 1)
	for i in 8:
		await physics_frame
	await _shoot("07_jumping", Vector3(3.5, 1.5, 0), Vector3(0, 1.2, 0), false)
	_release("jump")

	# Wide shot of the world itself.
	await _shoot("08_world", Vector3(10, 6, 12), Vector3(0, 0, 0))

	# A wolf, for comparison.
	var pal = get_nodes_in_group("pal")[0]
	await _shoot_at("09_wolf", pal, Vector3(2.5, 1.2, 2.5))

	print("SHOTS_WRITTEN=", _shots.size())
	for s in _shots:
		print("  ", s.name)
	quit()


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await physics_frame


func _release(action: String) -> void:
	Input.action_release(action)


func _shoot(name: String, offset: Vector3, look_at: Vector3, recentre := true) -> void:
	var base := _player.global_position
	if recentre:
		base = _player.global_position
	_cam.global_position = base + offset
	_cam.look_at(base + look_at - Vector3(0, 0, 0) + Vector3.ZERO, Vector3.UP)
	_cam.look_at(base + Vector3(0, 0.9, 0), Vector3.UP)
	await _capture(name)


func _shoot_at(name: String, target: Node3D, offset: Vector3) -> void:
	_cam.global_position = target.global_position + offset
	_cam.look_at(target.global_position + Vector3(0, 0.6, 0), Vector3.UP)
	await _capture(name)


func _capture(name: String) -> void:
	# Two frames so the camera move and any animation are actually drawn.
	await process_frame
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := OUT + name + ".png"
	var err := img.save_png(path)
	if err != OK:
		printerr("save failed: ", path, " err=", err)
	else:
		_shots.append({"name": name, "path": path})
