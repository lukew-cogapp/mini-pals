extends SceneTree
## Renders the game to PNGs so changes can be reviewed without playing.
## Runs windowed (NOT --headless): the dummy renderer produces blank images.
##
##   godot --path . -s test/screenshot.gd --quit-after 400

const OUT := "/private/tmp/claude-501/-Users-lukew-git/cdef92a8-7d7e-40a6-ad77-1b8685480828/scratchpad/shots2/"

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

	# The body idles facing -Z (Godot forward), so its front is the -Z side.
	await _shoot("01_front", Vector3(0, 1.2, -3.5), Vector3(0, 0.9, 0))
	await _shoot("02_side", Vector3(3.5, 1.2, 0), Vector3(0, 0.9, 0))
	await _shoot("03_back", Vector3(0, 1.2, 3.5), Vector3(0, 0.9, 0))
	await _shoot("04_above", Vector3(0.1, 4.0, 0.1), Vector3(0, 0.5, 0))

	await _hold("move_forward", 25)
	await _shoot("05_walking_side", Vector3(3.5, 1.2, 0), Vector3(0, 0.9, 0), false)
	await _shoot("06_walking_front", Vector3(0, 1.4, -3.5), Vector3(0, 0.9, 0), false)
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

	# Facing: shoot from ahead of travel for each input. Expect the face.
	await _walk_shot("14_face_forward", "move_forward", Vector3(0, 1.2, -3.5))
	await _walk_shot("15_face_back", "move_back", Vector3(0, 1.2, 3.5))
	await _walk_shot("16_face_left", "move_left", Vector3(-3.5, 1.2, 0))
	await _walk_shot("17_face_right", "move_right", Vector3(3.5, 1.2, 0))

	await _shoot_rig_and_throw()
	await _shoot_wolf_walking()

	await _shoot_ui()

	print("SHOTS_WRITTEN=", _shots.size())
	for s in _shots:
		print("  ", s.name)
	quit()


## Walk in a direction, then shoot from ahead of the travel so the face
## shows if (and only if) the model leads with it.
func _walk_shot(name: String, action: String, offset: Vector3) -> void:
	await _hold(action, 30)
	await _shoot(name, offset, Vector3(0, 0.9, 0), false)
	_release(action)
	for i in 10:
		await physics_frame


## The gameplay rig: the camera must sit behind the player (back of head and
## ears), and a thrown cube must fly away from it, into the scene.
func _shoot_rig_and_throw() -> void:
	await _hold("move_forward", 20)
	_release("move_forward")
	for i in 15:
		await physics_frame
	var rig_cam: Camera3D = _player.get_node("CameraPivot/SpringArm3D/Camera3D")
	rig_cam.current = true
	await _capture("18_rig_view")

	get_root().get_node("Inventory").add("cube", 1)
	_player._throw_cube()
	for i in 12:
		await physics_frame
	await _capture("19_rig_throw")
	_cam.current = true
	for i in 60:
		await physics_frame  # Let the cube land and free itself.


## A wandering wolf must face its travel direction.
func _shoot_wolf_walking() -> void:
	# Untyped: naming Pal here would compile pal.gd before autoloads
	# register (see CLAUDE.md), and its Audio reference then fails to resolve.
	var wolf = get_nodes_in_group("pal")[0]
	# Out of the player's flee radius, so WANDER sticks.
	wolf.global_position = _player.global_position + Vector3(25, 0.5, 0)
	await physics_frame
	wolf.state = wolf.State.WANDER
	wolf._target = wolf.global_position + Vector3(8, 0, 0)
	for i in 40:
		await physics_frame
	# From ahead of the travel direction (+X), so we should see its face.
	await _shoot_at("20_wolf_walking", wolf, Vector3(3.0, 1.0, 0))


## The workbench and its menu, which no camera angle would otherwise show.
func _shoot_ui() -> void:
	var bench = get_nodes_in_group("workbench")[0]
	_player.global_position = bench.global_position + Vector3(0, 0.5, 2.0)
	await physics_frame
	_cam.global_position = bench.global_position + Vector3(2.5, 2.0, 3.5)
	_cam.look_at(bench.global_position + Vector3(0, 0.5, 0), Vector3.UP)
	await _capture("10_workbench")

	# Some stock, so the menu shows both affordable and not.
	var inv = get_root().get_node("Inventory")
	inv.add("wood", 3)
	inv.add("stone", 2)
	var menu = _world.get_node_or_null("BuildMenu")
	if menu == null:
		printerr("no BuildMenu in world")
		return
	menu._open()
	await process_frame
	await _capture("11_build_menu")

	# And with nothing, to check the refused state.
	inv.remove("wood", inv.count("wood"))
	inv.remove("stone", inv.count("stone"))
	menu._refresh()
	await process_frame
	await _capture("12_build_menu_broke")
	menu._close()

	# Help overlay, and a party message.
	var hud = get_root().get_node_or_null("Hud")
	if hud:
		hud._help.visible = true
		hud.flash("Caught Wolf!")
		await process_frame
		await _capture("13_help")
		hud._help.visible = false


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
