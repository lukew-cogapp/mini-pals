extends SceneTree
## Throwaway lava-glow rig for materials/ash.tres. Renders a grid of variants
## to sandbox/shots/, in daylight and in boss-fight dark, so a whole sweep can
## be judged in one run instead of one value per launch.
##
## Run WINDOWED (the headless dummy renderer writes blank images):
##   godot --path . -s sandbox/ash_grid.gd
##
## Then montage sandbox/shots/*.png and look at them.

const OUT := "res://sandbox/shots/"

## Sweep axes.
## crust: multiplier on the albedo ramp's crust stops.
## band: where the glow ramp falls to black, as a noise value. The crack is
##       the low tail of DISTANCE2_SUB, so a narrow band means a thin hot line.
## energy: emission_energy_multiplier.
## The shipped values are crust 4.0, band 0.06, energy 2.0, tile 1/16.
var CRUSTS := [2.6, 4.0]
var BANDS := [0.06]
var ENERGIES := [1.2, 2.0, 3.0]
## World units per texture tile, as 1.0 / metres. The shipped 0.5 puts a
## crack cell at about 6 cm, which mips to flat grey at eye height and is why
## raising emission washed the whole biome instead of lighting the cracks.
var TILES := [1.0 / 16.0]

var _cam: Camera3D
var _plane: MeshInstance3D
var _sun: DirectionalLight3D
var _env: Environment
var _crack_noise: FastNoiseLite
var _soot_tex: NoiseTexture2D


func _init() -> void:
	await process_frame
	_build_scene()
	# Same viewpoint as test/shots/22_biome_ground.png: eye height, looking
	# down and away across the ground.
	var eye := Vector3(0, 1.7, 0)
	_cam.global_position = eye
	_cam.look_at(eye + Vector3(-14, -5.5, -3), Vector3.UP)
	# The autoloaded HUD draws over every shot; this is a material rig.
	var hud := get_root().get_node_or_null("Hud")
	if hud:
		hud.visible = false

	for dark in [false, true]:
		_set_lighting(dark)
		for crust in CRUSTS:
			for band in BANDS:
				for tile in TILES:
					for energy in ENERGIES:
						_plane.material_override = _variant(crust, band, energy, tile)
						var tag := "%s_crust%0.1f_band%0.2f_em%0.1f" % [
							"dark" if dark else "day", crust, band, energy
						]
						await _capture(tag)

	print("DONE")
	quit()


func _build_scene() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var we := WorldEnvironment.new()
	_env = Environment.new()
	# Copied from scenes/world.tscn SubResource("5"). Tonemap and fog are why
	# earlier eyeballing of emission misread.
	_env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.17, 0.29, 0.55)
	sky_mat.sky_horizon_color = Color(0.94, 0.66, 0.45)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.25, 0.22, 0.24)
	sky_mat.ground_horizon_color = Color(0.94, 0.66, 0.45)
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env.sky = sky
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.42, 0.5)
	_env.ambient_light_energy = 0.45
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.85, 0.62, 0.48)
	_env.fog_density = 0.0018
	_env.fog_sky_affect = 0.0
	we.environment = _env
	root.add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.transform = Transform3D(
		Vector3(0.77, -0.5, 0.4),
		Vector3(0, 0.62, 0.78),
		Vector3(-0.64, -0.6, 0.48),
		Vector3(0, 8, 0)
	)
	_sun.shadow_enabled = true
	root.add_child(_sun)

	# Built by hand rather than as a PlaneMesh: island.gd sets the ash UVs in
	# world units, and a PlaneMesh's 0..1 UVs put one crack cell across the
	# whole 120 m, which reads as a flat sheet no matter what the ramps say.
	_plane = MeshInstance3D.new()
	_plane.mesh = _ground_mesh(45.0)
	root.add_child(_plane)

	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true

	# One noise instance shared by every variant, so only the ramps change.
	_crack_noise = FastNoiseLite.new()
	_crack_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	_crack_noise.frequency = 0.02
	_crack_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	_crack_noise.cellular_jitter = 1.0
	_crack_noise.fractal_octaves = 1

	var soot := FastNoiseLite.new()
	soot.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	soot.frequency = 0.02
	soot.fractal_octaves = 3
	_soot_tex = NoiseTexture2D.new()
	_soot_tex.width = 256
	_soot_tex.height = 256
	_soot_tex.seamless = true
	_soot_tex.noise = soot


## A flat square with UVs in world units, matching island.gd's ash blob.
func _ground_mesh(half: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [
		Vector3(-half, 0, -half),
		Vector3(half, 0, -half),
		Vector3(half, 0, half),
		Vector3(-half, 0, half),
	]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for i in tri:
			var v: Vector3 = corners[i]
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _set_lighting(dark: bool) -> void:
	if dark:
		_sun.light_energy = Tuning.BOSS_DARK_SUN_ENERGY
		_sun.light_color = Tuning.BOSS_DARK_SUN_COLOR
		_env.ambient_light_energy = Tuning.BOSS_DARK_AMBIENT_ENERGY
		_env.fog_density = Tuning.BOSS_DARK_FOG_DENSITY
		_env.fog_light_color = Tuning.BOSS_DARK_FOG_COLOR
	else:
		_sun.light_energy = 1.15
		_sun.light_color = Color(1, 0.79, 0.56)
		_env.ambient_light_energy = 0.45
		_env.fog_density = 0.0018
		_env.fog_light_color = Color(0.85, 0.62, 0.48)


func _ramp(offsets: PackedFloat32Array, colors: PackedColorArray) -> Gradient:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	return g


func _tex(ramp: Gradient) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = _crack_noise
	t.color_ramp = ramp
	return t


func _variant(crust: float, band: float, energy: float, tile: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.render_priority = 1
	mat.roughness = 1.0
	mat.roughness_texture = _soot_tex
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.uv1_scale = Vector3(tile, tile, 1)

	# Albedo: black in the crack, crust colour above it. The crust stops are
	# what `crust` scales; the crack stays near black either way.
	var c1 := Color(0.10 * crust, 0.055 * crust, 0.035 * crust)
	var c2 := Color(0.17 * crust, 0.10 * crust, 0.065 * crust)
	var c3 := Color(0.22 * crust, 0.135 * crust, 0.09 * crust)
	mat.albedo_texture = _tex(_ramp(
		PackedFloat32Array([0.0, 0.03, 0.10, 0.45, 1.0]),
		PackedColorArray([
			Color(0.03, 0.012, 0.006), Color(0.05, 0.02, 0.01), c1, c2, c3
		])
	))

	# Emission: hot orange in the crack, black by `band`.
	mat.emission_enabled = true
	# emission_operator defaults to ADD, where emission_texture is ADDED to
	# the emission colour, so a white emission colour lights the whole surface
	# and the mask does nothing. MULTIPLY is what makes the texture a mask.
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = energy
	mat.emission_texture = _tex(_ramp(
		PackedFloat32Array([0.0, band * 0.4, band, 1.0]),
		PackedColorArray([
			Color(1.0, 0.45, 0.10), Color(0.9, 0.22, 0.02),
			Color(0, 0, 0), Color(0, 0, 0)
		])
	))
	return mat


func _capture(tag: String) -> void:
	await process_frame
	await process_frame
	await _await_noise()
	await process_frame
	var img := get_root().get_texture().get_image()
	var err := img.save_png(OUT + tag + ".png")
	if err != OK:
		printerr("save failed: ", tag, " err=", err)
	else:
		print("shot ", tag)


func _await_noise() -> void:
	var mat: StandardMaterial3D = _plane.material_override
	for prop in ["albedo_texture", "emission_texture", "roughness_texture"]:
		var tex := mat.get(prop) as NoiseTexture2D
		if tex == null:
			continue
		var waited := 0
		while tex.get_image() == null and waited < 600:
			await process_frame
			waited += 1
