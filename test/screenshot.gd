extends SceneTree
## Renders the game to PNGs so changes can be reviewed without playing.
## Runs windowed (NOT --headless): the dummy renderer produces blank images.
##
##   godot --path . -s test/screenshot.gd --quit-after 400

const OUT := "res://test/shots/"
## The generated ground materials, whose noise must finish before any shot.
const GROUND_MATERIALS := [
	"res://materials/ground.tres",
	"res://materials/ash.tres",
	"res://materials/sand.tres",
	"res://materials/water.tres",
]

var _world: Node3D
var _player: CharacterBody3D
var _cam: Camera3D
var _shots: Array[Dictionary] = []
var _textures_ready := false


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

	# The demon biome from above. Framed on the blob rather than the whole
	# island: the world's fog is dense enough that a shot from far enough out
	# to see all 220 m washes the ground to one orange haze.
	var altar_flat := Vector3(Tuning.ALTAR_POS.x, 0, Tuning.ALTAR_POS.z)
	await _shoot_free(
		"21_biome",
		altar_flat + Vector3(0, 78, Tuning.ASH_RADIUS * 1.5),
		altar_flat,
	)
	# Standing on the ash at eye height, looking down at it across the blob.
	# Aimed away from the altar: standing next to it fills half the frame with
	# its plinth and shows none of the ground this shot exists to check.
	var eye := altar_flat + Vector3(Tuning.ASH_RADIUS * 0.45, 1.7, Tuning.ASH_RADIUS * 0.1)
	await _shoot_free("22_biome_ground", eye, eye + Vector3(-14, -5.5, -3))

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

	await _shoot_shallows()

	await _shoot_pal_gathering()

	await _shoot_ui()

	await _shoot_hud()

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
	# Early in flight: the aim follows the camera's downward pitch, so the
	# cube lands within a dozen frames.
	for i in 6:
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

	# The item list carrying every drop at once, which is the case that used
	# to run off the end of the bottom bar.
	inv.add("wood", 42)
	inv.add("stone", 17)
	inv.add("pelt", 5)
	inv.add("cactus_fruit", 3)
	inv.add("demon_horn", 8)
	inv.add("altar_key", 1)
	await process_frame
	_cam.global_position = bench.global_position + Vector3(2.5, 2.0, 3.5)
	_cam.look_at(bench.global_position + Vector3(0, 0.5, 0), Vector3.UP)
	await _capture("23_items")


## The top-right HUD column, part way along the objective chain: the panel is
## a moving window, so a shot of a fresh game shows only its first row.
func _shoot_hud() -> void:
	var inv = get_root().get_node("Inventory")
	var party = get_root().get_node("Party")
	party.player_level = Tuning.KEY_UNLOCK_LEVEL
	party.changed.emit()
	inv.add("pelt", 3)
	inv.add("cactus_fruit", 1)
	await process_frame

	# Walk a short trail first, so the minimap shows PARTIAL fog. A shot from
	# the spawn alone reveals one blob and demonstrates nothing.
	var map = get_root().get_node("Hud").get_node("MinimapPanel/MinimapPad/Map")
	for step in [Vector3(0, 0, -40), Vector3(25, 0, -55), Vector3(40, 0, -40),
			Vector3(20, 0, -15), Vector3(0, 0, 0)]:
		_player.global_position = Vector3(step.x, _player.global_position.y, step.z)
		await process_frame
		await process_frame
	await physics_frame

	# The player is at the bench from _shoot_ui; frame the world behind them so
	# the panels are read against the game rather than a wall.
	_cam.global_position = _player.global_position + Vector3(6, 3.5, 8)
	_cam.look_at(_player.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	await _capture("30_hud")


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


## World-space camera, for anything too far out for a player-relative shot.
## NoiseTexture2D builds its image on a worker thread, so a material can be
## assigned and drawn before its noise exists. Two frames is enough for a
## camera move but not for that, and a shot taken early renders the ground as
## untextured albedo, which is exactly the flat colour these shots exist to
## catch. Waited once: the images are cached after the first shot.
func _await_textures() -> void:
	if _textures_ready:
		return
	for mat_path in GROUND_MATERIALS:
		var mat: StandardMaterial3D = load(mat_path)
		for prop in ["albedo_texture", "emission_texture", "roughness_texture", "normal_texture"]:
			var tex := mat.get(prop) as NoiseTexture2D
			if tex == null:
				continue
			var waited := 0
			while tex.get_image() == null and waited < 600:
				await process_frame
				waited += 1
			if tex.get_image() == null:
				printerr("noise texture never generated: ", mat_path, " ", prop)
	_textures_ready = true


func _shoot_free(name: String, at: Vector3, look: Vector3) -> void:
	_cam.global_position = at
	_cam.look_at(look, Vector3.UP)
	await _capture(name)


func _shoot_at(name: String, target: Node3D, offset: Vector3) -> void:
	_cam.global_position = target.global_position + offset
	_cam.look_at(target.global_position + Vector3(0, 0.6, 0), Vector3.UP)
	await _capture(name)


func _capture(name: String) -> void:
	# Two frames so the camera move and any animation are actually drawn.
	await process_frame
	await process_frame
	await _await_textures()
	var img := get_root().get_texture().get_image()
	var path := OUT + name + ".png"
	var err := img.save_png(path)
	if err != OK:
		printerr("save failed: ", path, " err=", err)
	else:
		_shots.append({"name": name, "path": path})


## A Cactoro working a tree, which is the only way to see whether the pal
## stands at the trunk and swings or clips through the canopy.
func _shoot_pal_gathering() -> void:
	var tree: Node3D = null
	var best := 1e9
	for node in get_nodes_in_group("tree"):
		if not node.is_available():
			continue
		var d: float = node.global_position.distance_to(_player.global_position)
		if d < best:
			best = d
			tree = node

	if tree == null:
		printerr("no available tree to shoot a gathering pal at")
		return

	# The player stands beside the tree, because the search is centred on
	# them and the leash is measured from them.
	_player.global_position = tree.global_position + Vector3(7.0, 1.0, 0.0)

	var pal = load("res://scenes/pal_cactoro.tscn").instantiate()
	_world.add_child(pal)
	await process_frame
	pal.global_position = tree.global_position + Vector3(6.0, 0.5, 2.0)
	pal.caught = true
	pal.state = pal.State.FOLLOW
	var party = get_root().get_node("Party")
	party.active = pal

	# Long enough for it to pick the job and walk in, but stopped short of
	# the third bite, which would deplete the tree and end the shot.
	for i in 90:
		await physics_frame
		if pal.state == pal.State.GATHER and pal._gather_cooldown > 0.0:
			break

	await _shoot_at("27_pal_gathering", pal, Vector3(9.0, 5.0, 9.0))
	await _shoot_at("28_pal_gathering_low", pal, Vector3(-8.0, 2.5, 6.0))

	party.active = null
	pal.queue_free()


## The shallows: fish out in the water, and the amphibian mount wading in it.
## Nothing else in the harness reaches this far out, and the two things worth
## looking at here are whether the fish read as being in water and whether a
## ridden swimmer looks submerged rather than floating on top.
func _shoot_shallows() -> void:
	var fish: Node3D = null
	for node in get_nodes_in_group("pal"):
		if node.water_only:
			fish = node
			break
	if fish:
		# Low and close, so the waterline crosses the body in frame.
		await _shoot_at("23_shallows_fish", fish, Vector3(6.0, 2.0, 6.0))
		# Wide, to show shallow against deep with the shore behind.
		var out: Vector3 = fish.global_position
		await _shoot_free(
			"24_shallows_wide",
			out.normalized() * (Tuning.SHALLOW_WALL_RADIUS + 40.0) + Vector3.UP * 30.0,
			Vector3(out.x * 0.7, 0.0, out.z * 0.7),
		)

	# Ride an amphibian out past the shore wall and shoot it in the water.
	var pal = load("res://scenes/pal_mudwader.tscn").instantiate()
	_world.add_child(pal)
	await process_frame
	var radial := Vector3(1.0, 0.0, 0.0)
	pal.global_position = radial * (Tuning.SHORE_WALL_RADIUS + 12.0) + Vector3.UP
	pal.caught = true
	pal.state = pal.State.RIDDEN
	_player.global_position = pal.seat_position()
	_player.mount = pal
	_player._set_collision_enabled(false)
	_player._set_shore_wall_enabled(false)
	# A few frames of riding, so _ride applies the sink before the shot.
	for i in 20:
		await physics_frame
	await _shoot_at("25_riding_in_water", pal, Vector3(5.0, 2.0, 5.0))
	await _shoot_at("26_riding_in_water_low", pal, Vector3(4.0, 0.9, 0.0))

	_player.mount = null
	_player._set_collision_enabled(true)
	_player._set_shore_wall_enabled(true)
