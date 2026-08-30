class_name Terrain
extends Node3D
## Hand-placed mounds and one cave, sitting on the island's flat ground plane.
##
## The plane stays. Every mound is a dome of its own with its own trimesh
## collider, so the shore wall, the zones, the swim sink and the seeded
## scatter all still work against a flat y = 0 world and only the things that
## actually stand on a slope have to know about one.
##
## `height_at` is the interface the rest of the game uses. It is arithmetic
## on Tuning.HILLS rather than a raycast, because the world is built inside
## _ready, before the physics server has seen a single collider, so a ray
## fired during scatter would report empty space and bury every prop.

@export var grass: Material
@export var rock: Material
@export var far_land: Material

## Loaded at runtime rather than preloaded. A preload is resolved when this
## script compiles, which drags resource_node.gd (and the autoloads it names)
## into the compile unit of any `-s` test script that touches Terrain, where
## autoloads do not exist yet and the whole thing fails to compile.
const ROCK_SCENE_PATH := "res://scenes/models/rock_medium_2.tscn"


## Ground height at a point, as the maximum over every mound covering it.
##
## Max rather than a sum: two mounds that overlap should read as one ridge at
## the height of the taller, not as a spike where they cross.
static func height_at(x: float, z: float) -> float:
	var high := 0.0
	for hill in Tuning.HILLS:
		high = maxf(high, _dome_height(hill, x, z))
	return high


## One mound's contribution: a raised cosine, zero at the rim and `height` at
## the centre. Chosen over a cone or a sphere cap because its slope is zero at
## both ends, so the player walks onto the skirt without a lip to step over
## and over the summit without a ridge to trip on.
static func _dome_height(hill: Array, x: float, z: float) -> float:
	var dx: float = x - hill[0]
	var dz: float = z - hill[1]
	var radius: float = hill[2]
	var dist := sqrt(dx * dx + dz * dz)
	if dist >= radius:
		return 0.0
	return hill[3] * 0.5 * (1.0 + cos(PI * dist / radius))


func _ready() -> void:
	for i in Tuning.HILLS.size():
		_mound(i, Tuning.HILLS[i])
	_cave()
	_distant_islands()


## One mound, as a mesh and a matching trimesh body.
##
## The collider is built from the same vertices as the mesh rather than from
## a primitive, so what the player walks on is exactly what they see. Trimesh
## is the slowest 3D shape in Godot and static-only, which is fine here: a
## mound is level geometry and never moves.
func _mound(index: int, hill: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius: float = hill[2] * Tuning.HILL_SKIRT
	var centre := Vector3(hill[0], 0.0, hill[1])

	for ring in Tuning.HILL_RINGS:
		var r0 := radius * float(ring) / Tuning.HILL_RINGS
		var r1 := radius * float(ring + 1) / Tuning.HILL_RINGS
		for seg in Tuning.HILL_SEGMENTS:
			var a0 := TAU * seg / Tuning.HILL_SEGMENTS
			var a1 := TAU * (seg + 1) / Tuning.HILL_SEGMENTS
			var quad := [
				_surface_point(centre, r0, a0),
				_surface_point(centre, r1, a0),
				_surface_point(centre, r1, a1),
				_surface_point(centre, r0, a1),
			]
			# Two triangles, wound so the dome faces up. The other winding
			# leaves the hill invisible from anywhere a player stands.
			for v in [quad[0], quad[2], quad[1]]:
				_vertex(st, v)
			for v in [quad[0], quad[3], quad[2]]:
				_vertex(st, v)

	st.generate_normals()
	var mesh := st.commit()

	var node := MeshInstance3D.new()
	node.name = "Hill%d" % index
	node.mesh = mesh
	if grass:
		node.material_override = grass
	add_child(node)

	var body := StaticBody3D.new()
	body.name = "HillBody%d" % index
	var trimesh := mesh.create_trimesh_shape()
	# A trimesh is one-sided: a downward ray passes straight through a face
	# whose front is the one it is approaching from, and the hill then reads
	# as absent to every raycast while still stopping a body. Verified here,
	# not assumed: without this a ray fired down at the summit reported the
	# flat GroundBody at y = 0.
	trimesh.backface_collision = true
	var shape := CollisionShape3D.new()
	shape.shape = trimesh
	body.add_child(shape)
	add_child(body)


## A point on the dome surface, in world space. Uses the same `height_at`
## every caller does, so the drawn hill and the queried hill cannot drift.
func _surface_point(centre: Vector3, r: float, angle: float) -> Vector3:
	var x := centre.x + cos(angle) * r
	var z := centre.z + sin(angle) * r
	return Vector3(x, height_at(x, z), z)


func _vertex(st: SurfaceTool, v: Vector3) -> void:
	# UVs in world units, so grass tiles at the same scale as the flat disc.
	st.set_uv(Vector2(v.x, v.z))
	st.add_vertex(v)


## --- The horizon -----------------------------------------------------------

## Islands out past everything reachable, as domes with no collider and
## nothing on them.
##
## Deliberately not built through `_mound`: these must never get a body, and
## the surest way to guarantee that is for the code that makes them to have
## no line that could add one. They are also excluded from `height_at`, so
## nothing scattered can ever be placed on one.
func _distant_islands() -> void:
	var root := Node3D.new()
	root.name = "DistantIslands"
	add_child(root)
	for i in Tuning.DISTANT_ISLANDS.size():
		var spec: Array = Tuning.DISTANT_ISLANDS[i]
		var bearing: float = spec[0]
		var distance: float = spec[1]
		var radius: float = spec[2]
		var height: float = spec[3]
		var centre := Vector3(cos(bearing), 0.0, sin(bearing)) * distance

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ring in Tuning.DISTANT_ISLAND_RINGS:
			var r0 := radius * float(ring) / Tuning.DISTANT_ISLAND_RINGS
			var r1 := radius * float(ring + 1) / Tuning.DISTANT_ISLAND_RINGS
			for seg in Tuning.DISTANT_ISLAND_SEGMENTS:
				var a0 := TAU * seg / Tuning.DISTANT_ISLAND_SEGMENTS
				var a1 := TAU * (seg + 1) / Tuning.DISTANT_ISLAND_SEGMENTS
				var quad := [
					_far_point(radius, height, r0, a0),
					_far_point(radius, height, r1, a0),
					_far_point(radius, height, r1, a1),
					_far_point(radius, height, r0, a1),
				]
				for v in [quad[0], quad[2], quad[1]]:
					st.add_vertex(v)
				for v in [quad[0], quad[3], quad[2]]:
					st.add_vertex(v)
		st.generate_normals()

		var node := MeshInstance3D.new()
		node.name = "FarIsland%d" % i
		node.mesh = st.commit()
		# The dome's own base is at zero, so drop the whole thing to the
		# waterline and a little under it: the rim has to be below the sea
		# or the island reads as hovering over it.
		node.position = centre + Vector3.DOWN * (
			-Tuning.WATER_LEVEL + Tuning.DISTANT_ISLAND_SINK
		)
		if far_land:
			node.material_override = far_land
		root.add_child(node)


## A point on a far island's dome, in the island's own space. Same raised
## cosine as a hill, but standalone: these are never sampled by `height_at`,
## because nothing may ever be placed on one.
func _far_point(radius: float, height: float, r: float, angle: float) -> Vector3:
	var h := 0.0
	if r < radius:
		h = height * 0.5 * (1.0 + cos(PI * r / radius))
	return Vector3(cos(angle) * r, h, sin(angle) * r)


## --- The cave --------------------------------------------------------------

## A mouth of boulders in the side of the biggest hill, with a hollow behind
## it. Not a carved interior: the hollow is a box of walls, a floor and a
## roof, which is enough to walk into, stand up in and walk out of, and is
## four primitive colliders instead of a subtracted mesh nobody can debug.
func _cave() -> void:
	var root := Node3D.new()
	root.name = "Cave"
	root.position = mouth_position()
	root.rotation.y = Tuning.CAVE_FACING
	add_child(root)

	_hollow(root)
	_mouth_rocks(root)

	var lamp := OmniLight3D.new()
	lamp.name = "CaveLight"
	lamp.light_energy = Tuning.CAVE_LIGHT_ENERGY
	lamp.light_color = Tuning.CAVE_LIGHT_COLOR
	lamp.omni_range = Tuning.CAVE_LIGHT_RANGE
	lamp.position = Vector3(
		0.0,
		Tuning.CAVE_LIGHT_HEIGHT,
		-Tuning.CAVE_DEPTH * 0.6,
	)
	root.add_child(lamp)


## Where the mouth stands: out along CAVE_FACING from the hill's centre, at
## whatever height the hill surface has reached there.
func mouth_position() -> Vector3:
	var out := Vector3(
		sin(Tuning.CAVE_FACING),
		0.0,
		cos(Tuning.CAVE_FACING),
	) * Tuning.CAVE_MOUTH_DISTANCE
	var at := Tuning.CAVE_POS + out
	at.y = height_at(at.x, at.z) - Tuning.CAVE_FLOOR_DROP
	return at


## Floor, roof, back and two sides. The front is left open, which is the
## whole point, and nothing is put across it: a cave the player can be
## trapped in is worse than no cave.
##
## Local space, with the opening on +Z, so the parent's rotation aims the
## mouth and none of this has to know which way it points.
func _hollow(root: Node3D) -> void:
	var half_w := Tuning.CAVE_WIDTH * 0.5
	var wall := 1.0
	var mid := -Tuning.CAVE_DEPTH * 0.5
	_slab(root, "Floor", Vector3(Tuning.CAVE_WIDTH, wall, Tuning.CAVE_DEPTH),
		Vector3(0.0, -wall * 0.5, mid))
	_slab(root, "Roof", Vector3(Tuning.CAVE_WIDTH + wall * 2.0, wall, Tuning.CAVE_DEPTH),
		Vector3(0.0, Tuning.CAVE_HEIGHT + wall * 0.5, mid))
	_slab(root, "Back", Vector3(Tuning.CAVE_WIDTH + wall * 2.0, Tuning.CAVE_HEIGHT, wall),
		Vector3(0.0, Tuning.CAVE_HEIGHT * 0.5, -Tuning.CAVE_DEPTH - wall * 0.5))
	_slab(root, "SideL", Vector3(wall, Tuning.CAVE_HEIGHT, Tuning.CAVE_DEPTH),
		Vector3(-half_w - wall * 0.5, Tuning.CAVE_HEIGHT * 0.5, mid))
	_slab(root, "SideR", Vector3(wall, Tuning.CAVE_HEIGHT, Tuning.CAVE_DEPTH),
		Vector3(half_w + wall * 0.5, Tuning.CAVE_HEIGHT * 0.5, mid))


func _slab(root: Node3D, slab_name: String, size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = slab_name
	node.mesh = mesh
	node.position = at
	if rock:
		node.material_override = rock
	root.add_child(node)

	var body := StaticBody3D.new()
	body.name = slab_name + "Body"
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = at
	body.add_child(shape)
	root.add_child(body)


## Boulders around the opening, so the mouth reads as rock rather than as a
## box cut into a hillside. Placed either side of the gap and never across
## it: the arc skips the middle of the front face.
func _mouth_rocks(root: Node3D) -> void:
	var rock_scene: PackedScene = load(ROCK_SCENE_PATH)
	var rng := RandomNumberGenerator.new()
	# Its own generator, not the scatter's. The cave is authored, so it must
	# not consume draws from SCATTER_SEED and reshuffle the whole island.
	rng.seed = Tuning.SCATTER_SEED + 1
	var half_w := Tuning.CAVE_WIDTH * 0.5
	for i in Tuning.CAVE_ROCK_COUNT:
		# Half the boulders down each side, marching back from the opening.
		var side := 1.0 if i % 2 == 0 else -1.0
		var along := float(i / 2) / maxf(Tuning.CAVE_ROCK_COUNT / 2.0, 1.0)
		var boulder := rock_scene.instantiate() as Node3D
		boulder.position = Vector3(
			side * (half_w + rng.randf_range(1.0, 2.0)),
			rng.randf_range(-1.2, 0.4),
			1.5 - along * Tuning.CAVE_DEPTH * 0.8,
		)
		boulder.rotation.y = rng.randf() * TAU
		boulder.scale = Vector3.ONE * rng.randf_range(
			Tuning.CAVE_ROCK_SCALE_MIN, Tuning.CAVE_ROCK_SCALE_MAX
		)
		root.add_child(boulder)
