extends SceneTree
## Renders the real biome in both lighting states, since test/screenshot.gd
## only ever shoots it in daylight and the boss fight is where the ash has to
## carry the frame. Writes sandbox/shots/biome_day.png and biome_dark.png.
##
## Run WINDOWED (the headless dummy renderer writes blank images):
##   godot --path . -s sandbox/ash_in_dark.gd

const OUT := "res://sandbox/shots/"


func _init() -> void:
	await process_frame
	var world: Node3D = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	var hud := get_root().get_node_or_null("Hud")
	if hud:
		hud.visible = false

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	for i in 30:
		await physics_frame

	# The framing test/screenshot.gd uses for 22_biome_ground.
	var flat := Vector3(Tuning.ALTAR_POS.x, 0, Tuning.ALTAR_POS.z)
	var eye := flat + Vector3(Tuning.ASH_RADIUS * 0.45, 1.7, Tuning.ASH_RADIUS * 0.1)
	cam.global_position = eye
	cam.look_at(eye + Vector3(-14, -5.5, -3), Vector3.UP)

	await _capture("biome_day")
	_darken(world)
	await _capture("biome_dark")
	print("DONE")
	quit()


## The same environment changes altar.gd makes when the boss is summoned.
func _darken(world: Node3D) -> void:
	var sun: DirectionalLight3D = world.get_node("Sun")
	sun.light_energy = Tuning.BOSS_DARK_SUN_ENERGY
	sun.light_color = Tuning.BOSS_DARK_SUN_COLOR
	var env: Environment = world.get_node("WorldEnvironment").environment
	env.ambient_light_energy = Tuning.BOSS_DARK_AMBIENT_ENERGY
	env.fog_density = Tuning.BOSS_DARK_FOG_DENSITY
	env.fog_light_color = Tuning.BOSS_DARK_FOG_COLOR


func _capture(name: String) -> void:
	for i in 8:
		await process_frame
	var err := get_root().get_texture().get_image().save_png(OUT + name + ".png")
	print(name, " err=", err)
