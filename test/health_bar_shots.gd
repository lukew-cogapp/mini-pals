extends SceneTree
## Renders the floating health bar against both grounds it has to read
## against, at full, half and nearly-dead health. Runs WINDOWED; the headless
## dummy renderer writes blank images.
##
##   godot --path . -s test/health_bar_shots.gd

const OUT := "res://test/shots/"
const GROUND_MATERIALS := [
	"res://materials/ground.tres",
	"res://materials/ash.tres",
]

var _world: Node3D
var _player: CharacterBody3D
var _cam: Camera3D


func _init() -> void:
	await process_frame
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	_player = _world.get_node("Player")
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_cam.current = true
	for i in 30:
		await physics_frame
	await _await_textures()

	# Grass, near the spawn. Ash, out at the altar in the scorched blob.
	var grass := Vector3(0.0, 0.0, 0.0)
	var ash := Vector3(Tuning.ALTAR_POS.x - 12.0, 0.0, Tuning.ALTAR_POS.z)
	await _shoot_set("grass", grass)
	await _shoot_set("ash", ash)

	print("SHOTS DONE")
	quit()


func _await_textures() -> void:
	for mat_path in GROUND_MATERIALS:
		var mat: StandardMaterial3D = load(mat_path)
		for prop in ["albedo_texture", "emission_texture", "roughness_texture"]:
			var tex := mat.get(prop) as NoiseTexture2D
			if tex == null:
				continue
			var waited := 0
			while tex.get_image() == null and waited < 600:
				await process_frame
				waited += 1


## One trio of shots on one ground: three wolves side by side at full, half
## and nearly-dead health, then a close-up of each.
func _shoot_set(ground: String, at: Vector3) -> void:
	_player.global_position = at + Vector3(0.0, 1.0, 6.0)
	var pals := []
	var levels := [{"n": "full", "hp": 6}, {"n": "half", "hp": 3}, {"n": "low", "hp": 1}]
	for i in levels.size():
		var pal = load("res://scenes/pal_wolf.tscn").instantiate()
		_world.add_child(pal)
		await process_frame
		pal.global_position = at + Vector3(float(i) * 2.2 - 2.2, 0.5, 0.0)
		pal.max_hp = 6
		pal.hp = levels[i]["hp"]
		pal.state = pal.State.IDLE
		pal._bar_check = 0.0
		pal._tick_health_bar()
		pals.append(pal)
	for i in 20:
		await physics_frame
	for pal in pals:
		pal._bar_check = 0.0
		pal._tick_health_bar()

	# All three together, which is the only way to compare the colour ramp.
	_cam.global_position = at + Vector3(0.0, 2.6, 6.5)
	_cam.look_at(at + Vector3(0.0, 2.0, 0.0), Vector3.UP)
	await _capture("hb_%s_row" % ground)

	# One close-up per health level, at the sort of range a player fights at.
	for i in levels.size():
		var pal = pals[i]
		_cam.global_position = pal.global_position + Vector3(0.6, 1.8, 2.6)
		_cam.look_at(pal.global_position + Vector3(0.0, 2.1, 0.0), Vector3.UP)
		await _capture("hb_%s_%s" % [ground, levels[i]["n"]])

	for pal in pals:
		pal.queue_free()
	await process_frame


func _capture(name: String) -> void:
	await process_frame
	await process_frame
	var img := get_root().get_texture().get_image()
	var err := img.save_png(OUT + name + ".png")
	if err != OK:
		printerr("save failed: ", name, " err=", err)
	else:
		print("wrote ", name)
