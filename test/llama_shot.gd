extends SceneTree
## Renders the Llama and a wad of its spit in flight, to test/shots/.
##
## Must run WINDOWED. Under --headless the dummy renderer writes blank images:
##
##   godot --path . -s test/llama_shot.gd
##
## Its own script rather than more cases in screenshot.gd, because the two
## things worth looking at here are a recolour and a projectile, and both need
## the camera parked somewhere the walkthrough never goes. Shots 40 to 44.
##
## The recolour is why this exists at all. The atlas the Alpaking samples is
## five texels of one row, and a paint that missed them, or caught a column
## another monster uses, would look completely correct in every number the
## engine can report. Render it and look.

const OUT := "res://test/shots/"
## Pink only. A rainbow was painted and rendered first: the five texels the
## model samples do not divide it into bands, they land on the body, the ears
## and the muzzle, so five hues came out as a red animal with mint ears rather
## than as a rainbow. It was dropped rather than kept, and this is the note
## that stops it being retried.
const SKINS := {"pink": "res://materials/llama_pink.tres"}

var _world: Node3D
var _cam: Camera3D
var _written: Array[String] = []


func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_cam.current = true
	for i in 30:
		await physics_frame

	var llama = _find_llama()
	if llama == null:
		printerr("no Llama in the world")
		quit(1)
		return

	# Off the crowded band and onto flat open ground, so nothing stands
	# between the camera and the model.
	llama.global_position = Vector3(-55.0, 0.5, 20.0)
	llama.state = llama.State.IDLE
	llama.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame

	await _skins(llama)
	await _spit_in_flight(llama)
	await _mounted_spit(llama)

	print("SHOTS_WRITTEN=", _written.size())
	for name in _written:
		print("  ", name)
	quit()


## The same pose under each recolour. Three quarters from the front, which is
## where the fleece, the muzzle and the legs are all visible at once, so a
## painted texel that landed on the wrong part of the body shows.
func _skins(llama: Node3D) -> void:
	for skin in SKINS:
		_apply(llama, load(SKINS[skin]))
		await _at("4%d_llama_%s" % [SKINS.keys().find(skin), skin], llama, Vector3(5.0, 3.0, -6.5))
	# And the pink one from the side, full length: a llama is long, and the
	# three quarter shot foreshortens most of its body away.
	_apply(llama, load(SKINS["pink"]))
	await _at("42_llama_pink_side", llama, Vector3(8.5, 2.4, 0.0))


## A wad mid-flight, framed side on so the arc and the gap between shooter and
## target are both in frame. This is the shot that would show a wad spawning
## inside the llama's own head, or leaving at the feet.
func _spit_in_flight(llama: Node3D) -> void:
	var mark := CharacterBody3D.new()
	mark.collision_layer = 1
	mark.add_to_group("player")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 1.8
	shape.shape = capsule
	mark.add_child(shape)
	_world.add_child(mark)
	mark.global_position = llama.global_position + Vector3(0.0, 0.0, -Tuning.SPIT_RANGE)
	await physics_frame

	llama.look_at(mark.global_position, Vector3.UP)
	llama._fire_spit(mark, 0)  # Spit.Mode.PLAYER
	# Part way across, so the wad is clear of both ends of its flight.
	for i in 12:
		await physics_frame
	var mid := llama.global_position.lerp(mark.global_position, 0.5)
	await _free_shot("43_spit_in_flight", mid + Vector3(6.5, 1.6, 0.0), mid + Vector3(0, 1.0, 0))
	await _free_shot(
		"44_spit_from_behind",
		llama.global_position + Vector3(0.0, 2.6, 4.0),
		mark.global_position + Vector3(0, 1.0, 0),
	)


## The player in the saddle, firing. Shot from the gameplay camera, because
## the thing worth checking is that the wad leaves along the crosshair and
## clears the mount's own head, and only the real rig shows that.
func _mounted_spit(llama: Node3D) -> void:
	var player = _world.get_node("Player")
	player.global_position = llama.seat_position()
	llama.caught = true
	player.mount = llama
	llama.state = 4  # Pal.State.RIDDEN
	await physics_frame

	var rig: Camera3D = player.get_node("CameraPivot/SpringArm3D/Camera3D")
	rig.current = true
	player._punch()
	for i in 10:
		await physics_frame
	await _capture("45_mounted_spit")
	_cam.current = true


func _apply(llama: Node3D, material: Material) -> void:
	_paint(llama, material)


func _paint(n: Node, material: Material) -> void:
	if n is MeshInstance3D:
		for i in n.get_surface_override_material_count():
			n.set_surface_override_material(i, material)
	for c in n.get_children():
		_paint(c, material)


func _find_llama() -> Node3D:
	for node in get_nodes_in_group("pal"):
		if node.get("display_name") == "Llama":
			return node
	return null


func _at(name: String, target: Node3D, offset: Vector3) -> void:
	_cam.global_position = target.global_position + offset
	_cam.look_at(target.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	await _capture(name)


func _free_shot(name: String, at: Vector3, look: Vector3) -> void:
	_cam.global_position = at
	_cam.look_at(look, Vector3.UP)
	await _capture(name)


func _capture(name: String) -> void:
	# Two frames, so the camera move and the animation are both drawn.
	await process_frame
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := OUT + name + ".png"
	var err := img.save_png(path)
	if err != OK:
		printerr("save failed err=%d for %s" % [err, path])
		return
	_written.append(name)
