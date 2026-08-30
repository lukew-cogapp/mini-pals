extends SceneTree
## Renders each rideable pal from the side and from above, empty and with the
## player in the saddle, so seat placement can be SEEN rather than reasoned
## about. Shots 50 to 61.
##
##   godot --path . -s test/seat_shot.gd
##
## Must run WINDOWED, like every renderer here: under --headless the dummy
## renderer writes blank images.
##
## This exists because a seat is a marker with no visual, so every number in
## the scene file reads as correct whether the rider ends up on the back, on
## the neck or in the air. The AABBs make all three of these animals wider on
## X than long on Z, which for a quadruped is not credible and is why the
## question is settled by looking.
##
## A bare stage rather than world.tscn: the island's dusk lighting, its scatter
## and its HUD all sat between the camera and the silhouette, and none of them
## say anything about where a seat goes.
##
## Every pal is turned to face -Z, the convention the whole project uses. So:
##   side shot, camera on +X   nose LEFT, tail right
##   top shot,  camera on +Y   nose UP the screen, tail down
## A blue post marks the pal's own origin and a red post marks the Seat, both
## thin enough to read against the body.

const OUT := "res://test/shots/"

## name, scene, the shot number its four images start at.
const SUBJECTS := [
	["llama", "res://scenes/pal_llama.tscn", 50],
	["mudwader", "res://scenes/pal_mudwader.tscn", 54],
	["wolf", "res://scenes/pal_wolf.tscn", 58],
]

var _stage: Node3D
var _cam: Camera3D
var _written: Array[String] = []


func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_stage = Node3D.new()
	get_root().add_child(_stage)

	var sun := DirectionalLight3D.new()
	_stage.add_child(sun)
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.3

	var fill := DirectionalLight3D.new()
	_stage.add_child(fill)
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(200.0), 0.0)
	fill.light_energy = 0.6

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.2, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	e.ambient_light_energy = 0.7
	env.environment = e
	_stage.add_child(env)

	_cam = Camera3D.new()
	_stage.add_child(_cam)
	_cam.current = true
	await process_frame

	for subject in SUBJECTS:
		await _shots(subject[0], subject[1], subject[2])

	print("SHOTS_WRITTEN=", _written.size())
	for shot_name in _written:
		print("  ", shot_name)
	quit()


## One animal: side and top, then the same two with the PLAYER on the seat.
##
## The real player model, not a stand-in box: a box 0.8 m tall reads as
## floating over any of these animals whatever the seat does, which sent this
## round in circles once already. The cat is the thing that will actually be
## sitting there.
func _shots(label: String, path: String, first: int) -> void:
	var pal = load(path).instantiate()
	_stage.add_child(pal)
	pal.global_position = Vector3.ZERO
	pal.rotation.y = 0.0
	await process_frame
	pal.state = pal.State.IDLE
	pal.velocity = Vector3.ZERO
	# The name plate billboards over the head at exactly the angle that shows
	# whether the head IS there, which is the one thing these shots are for.
	_hide_overlays(pal)
	await process_frame

	_post(Vector3.ZERO, Color(0.2, 0.45, 1.0), 2.6)
	# Unambiguous ruler. GREEN stands one metre along the pal's forward (-Z),
	# WHITE one metre behind it (+Z), so no shot has to be reasoned about: the
	# end of the animal nearest the green post is its front.
	_post(Vector3(0.0, 0.0, -1.0), Color(0.2, 0.9, 0.3), 1.6)
	_post(Vector3(0.0, 0.0, 1.0), Color(0.95, 0.95, 0.95), 1.6)
	var seat: Vector3 = pal.seat_position()
	_post(Vector3(seat.x, 0.0, seat.z), Color(1.0, 0.2, 0.2), 2.6)

	var centre := Vector3(0.0, 1.0, 0.0)
	await _free_shot("%d_%s_side" % [first, label], Vector3(4.5, 1.4, 0.0), centre)
	# From -Z and from +Z. Whichever of the two shows a face is the front, and
	# that is the only reliable way to tell: the AABB and the silhouette have
	# both given the wrong answer in this project.
	await _free_shot("%s_%s_from_minus_z" % [first, label], Vector3(2.6, 1.6, -3.4), centre)
	await _free_shot("%s_%s_from_plus_z" % [first, label], Vector3(2.6, 1.6, 3.4), centre)
	await _top_shot("%d_%s_top" % [first + 1, label])

	var rider := _rider(seat)
	await _free_shot("%d_%s_ridden_side" % [first + 2, label], Vector3(4.5, 1.4, 0.0), centre)
	# High front quarter. The side view is blocked by the near fleece, which
	# swallowed a whole ladder of test markers; from above and in front the
	# back is actually visible and so is the gap under a rider.
	await _free_shot("%d_%s_ridden_quarter" % [first + 2, label], Vector3(2.8, 3.0, -2.8), centre)
	await _top_shot("%d_%s_ridden_top" % [first + 3, label])

	rider.free()
	pal.free()
	for child in _stage.get_children():
		if child.is_in_group("seat_marker"):
			child.free()
	await process_frame


## Label3D and the health bar sprites, off. Every one of them faces the camera
## and sits above the animal, so they cover the head in every angle worth
## taking.
func _hide_overlays(node: Node) -> void:
	if node is Label3D or node is Sprite3D:
		node.visible = false
	for child in node.get_children():
		_hide_overlays(child)


## A thin vertical post at `at`, so the origin and the seat's ground track are
## both visible in the side and the top shot at once.
func _post(at: Vector3, colour: Color, height: float) -> MeshInstance3D:
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, height, 0.06)
	post.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	post.material_override = mat
	post.add_to_group("seat_marker")
	_stage.add_child(post)
	post.global_position = at + Vector3.UP * height * 0.5
	return post


func _rider(seat: Vector3) -> Node3D:
	var rider := load("res://scenes/models/player_model.tscn").instantiate() as Node3D
	_stage.add_child(rider)
	rider.global_position = seat
	return rider


## Straight down, with the up vector pinned to -Z so the pal's own forward
## runs UP the screen. `look_at` from directly above with the default up is
## degenerate and picks its own roll, which would make a top shot unreadable
## as a fore-aft check, which is the only thing it is for.
func _top_shot(shot_name: String) -> void:
	_cam.global_position = Vector3(0.0, 5.0, 0.0)
	_cam.look_at(Vector3.ZERO, Vector3.FORWARD)
	await _capture(shot_name)


func _free_shot(shot_name: String, at: Vector3, look: Vector3) -> void:
	_cam.global_position = at
	_cam.look_at(look, Vector3.UP)
	await _capture(shot_name)


func _capture(shot_name: String) -> void:
	await process_frame
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := OUT + shot_name + ".png"
	var err := img.save_png(path)
	if err != OK:
		printerr("save failed err=%d for %s" % [err, path])
		return
	_written.append(shot_name)
