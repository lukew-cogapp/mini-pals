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

var _hill_mat: StandardMaterial3D


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
				_vertex(st, v, hill[3])
			for v in [quad[0], quad[3], quad[2]]:
				_vertex(st, v, hill[3])

	st.generate_normals()
	var mesh := _carve_mesh(st.commit())

	var node := MeshInstance3D.new()
	node.name = "Hill%d" % index
	node.mesh = mesh
	node.material_override = _hill_material()
	add_child(node)

	var body := StaticBody3D.new()
	body.name = "HillBody%d" % index
	var trimesh := _hill_shape(mesh)
	var shape := CollisionShape3D.new()
	shape.shape = trimesh
	body.add_child(shape)
	add_child(body)


## The hill mesh with the cave's doorway and approach cut out of it.
##
## Carving the collider alone is not enough once the hill material is
## two-sided. While it was single-sided the dome simply vanished when seen
## from within, and that hole read as the cave mouth by accident; a two-sided
## dome draws its inner face instead, so the doorway is covered by hillside
## the player can walk through. The mesh has to lose the same triangles the
## shape does.
##
## Dropped triangle by triangle rather than subtracted properly. A real CSG
## cut is not worth it here: the opening is a box, the hill is dense enough
## that a per-triangle cut follows it closely, and the chamber's own slabs
## line everything behind the doorway.
func _carve_mesh(mesh: ArrayMesh) -> ArrayMesh:
	var faces := mesh.get_faces()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kept := 0
	for i in range(0, faces.size(), 3):
		var centre := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		if _inside_cave(centre):
			continue
		kept += 1
		for v in [faces[i], faces[i + 1], faces[i + 2]]:
			st.set_uv(Vector2(v.x, v.z))
			st.set_color(Tuning.HILL_SHADE_LOW.lerp(
				Tuning.HILL_SHADE_HIGH,
				clampf(v.y / Tuning.HILL_SHADE_REFERENCE, 0.0, 1.0)
			))
			st.add_vertex(v)
	if kept == 0:
		return mesh
	st.generate_normals()
	return st.commit()


## The mound's collider, with the cave's footprint left out of it.
##
## A hill is one solid trimesh, so burying the chamber inside it walls the
## chamber off: a capsule at floor height walking in hits HillBody before it
## reaches the back, and the cave is only walkable at all while it stands far
## enough out of the hill to show. That is the same conflict from both ends,
## and this is what resolves it. Triangles whose centre falls inside the
## chamber's plan are dropped from the SHAPE only; the drawn mesh keeps them,
## so the hillside still looks unbroken from outside while the hollow behind
## it is hollow. The cave's own slabs are what the player then walks on.
func _hill_shape(mesh: ArrayMesh) -> ConcavePolygonShape3D:
	var faces := mesh.get_faces()
	var kept := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var centre := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		if _inside_cave(centre):
			continue
		kept.append(faces[i])
		kept.append(faces[i + 1])
		kept.append(faces[i + 2])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(kept)
	# A trimesh is one-sided: a downward ray passes straight through a face
	# whose front is the one it is approaching from, and the hill then reads
	# as absent to every raycast while still stopping a body. Verified here,
	# not assumed: without this a ray fired down at the summit reported the
	# flat GroundBody at y = 0.
	shape.backface_collision = true
	return shape


## Is a world point inside the volume the chamber occupies?
##
## Plan only, plus a generous height band: the hill surface above the cave has
## to be dropped from the collider whatever its height, or the roof slab and
## the hill fight over the same space. Widened by CAVE_CARVE_MARGIN so a
## triangle straddling the wall does not leave a lip in the doorway.
func _inside_cave(world_point: Vector3) -> bool:
	var mouth := mouth_position()
	var inward := -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
	var across := Vector3(inward.z, 0.0, -inward.x)
	var offset := world_point - mouth
	var along := offset.dot(inward)
	var side := absf(offset.dot(across))
	var margin := Tuning.CAVE_CARVE_MARGIN
	# Negative `along` is OUTSIDE the mouth, where the approach cutting runs.
	# It has to be carved too, or the hill collider stands across the trench
	# and the walk-in is sealed by ground the player can see straight through.
	if along < -(Tuning.CAVE_RAMP + margin):
		return false
	if along > Tuning.CAVE_DEPTH + Tuning.CAVE_WALL + margin:
		return false
	# No margin across, deliberately. Widening here drops hill triangles out
	# beside the doorway where the visible grass is intact, and the player
	# then falls through solid-looking ground into the slot beside the
	# chamber wall.
	if side > Tuning.CAVE_WIDTH * 0.5 + Tuning.CAVE_WALL:
		return false
	# Everything from the floor up to the roof's cover, over the whole
	# footprint. Outside the mouth that is what makes the approach a cutting
	# rather than a tunnel under intact ground: the hill there is taller than
	# the chamber, and leaving its upper triangles in place walls off the
	# walk-in a couple of metres before the door.
	return world_point.y < (
		mouth.y + Tuning.CAVE_HEIGHT + Tuning.CAVE_WALL + Tuning.CAVE_COVER + margin
	)


## The grass material, with vertex colours switched on so the height tint
## shows. A duplicate rather than the shared resource itself: `grass` is also
## on the flat island, and turning the flag on there would tint the ground by
## whatever vertex colours the plane happens to carry.
func _hill_material() -> Material:
	if _hill_mat != null:
		return _hill_mat
	var base := grass as StandardMaterial3D
	if base == null:
		return grass
	_hill_mat = base.duplicate()
	_hill_mat.vertex_color_use_as_albedo = true
	# Two-sided, to match `backface_collision` on the shape. The winding is
	# correct (verified: 736 of 768 triangles face up, the rest are degenerate
	# slivers at the apex), so this is not a fix for an inverted dome. It is
	# needed because the cave puts the player INSIDE the hill: the collider is
	# carved there, and a single-sided dome seen from within disappears, so
	# the approach cutting and the mouth read as a hole through to the sky
	# with the dome's far inner face floating beyond it.
	_hill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _hill_mat


## A point on the dome surface, in world space. Uses the same `height_at`
## every caller does, so the drawn hill and the queried hill cannot drift.
func _surface_point(centre: Vector3, r: float, angle: float) -> Vector3:
	var x := centre.x + cos(angle) * r
	var z := centre.z + sin(angle) * r
	return Vector3(x, height_at(x, z), z)


## `top` is the mound's own summit height, so the tint runs the full range on
## a low mound as well as a tall one.
func _vertex(st: SurfaceTool, v: Vector3, top: float) -> void:
	# UVs in world units, so grass tiles at the same scale as the flat disc.
	st.set_uv(Vector2(v.x, v.z))
	st.set_color(Tuning.HILL_SHADE_LOW.lerp(
		Tuning.HILL_SHADE_HIGH, clampf(v.y / maxf(top, 0.001), 0.0, 1.0)
	))
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


## Where the chamber floor sits: out along CAVE_FACING from the hill's
## centre, CAVE_SINK below the hill surface it meets there.
##
## Sunk rather than level with the doorway. The hill does not climb fast
## enough over CAVE_DEPTH to cover a chamber whose floor is at grade, so a
## level floor puts the roof out through the grass; dropping it buries the
## roof and `_ramp` walks the player down. Everything cave-shaped shares this
## one datum, so the floor, the boulders and the cave pals cannot drift apart.
func mouth_position() -> Vector3:
	var out := Vector3(
		sin(Tuning.CAVE_FACING),
		0.0,
		cos(Tuning.CAVE_FACING),
	) * Tuning.CAVE_MOUTH_DISTANCE
	var at := Tuning.CAVE_POS + out
	at.y = height_at(at.x, at.z) - Tuning.CAVE_SINK
	return at


## Ground height at a point in the cave root's local space.
##
## The root is rotated and raised, so anything that wants to sit on the hill
## has to ask in world space and bring the answer back. Every cave-local
## placement goes through here rather than repeating the transform.
func _local_ground(root: Node3D, at: Vector3) -> float:
	var here := root.transform * at
	return height_at(here.x, here.z) - root.position.y


## Floor, roof, back and two sides. The front is left open, which is the
## whole point, and nothing is put across it: a cave the player can be
## trapped in is worse than no cave.
##
## Local space, with the opening on +Z, so the parent's rotation aims the
## mouth and none of this has to know which way it points.
func _hollow(root: Node3D) -> void:
	var half_w := Tuning.CAVE_WIDTH * 0.5
	var wall := Tuning.CAVE_WALL
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
	_ramp(root)


## The walk-in: a level trench outside the mouth, cut down to floor height.
##
## Not a sloped ramp. CAVE_SINK is chosen so the hill surface CAVE_RAMP metres
## out is already level with the chamber floor, so the approach is a cutting
## at floor height that meets the grass at its outer end with no step at
## either end. A tilted slab was tried and is worse: getting the rotation sign
## right is fiddly (it was inverted, and the wedge stood proud of the hill the
## whole way), and it solves a problem the sink already solved.
##
## Collider only. The hill mesh still draws over this footprint, and the
## trench walls are the hill's own surface.
func _ramp(root: Node3D) -> void:
	var length := Tuning.CAVE_RAMP
	var size := Vector3(Tuning.CAVE_WIDTH, Tuning.CAVE_WALL, length)
	# Floor height, running from the door plane out along local +Z.
	var at := Vector3(0.0, -Tuning.CAVE_WALL * 0.5, length * 0.5)
	_slab(root, "Ramp", size, at, Vector3.ZERO, false)


## One slab, as a mesh and a matching box collider.
##
## Normal culling, deliberately. Flipping these to draw only their inside
## face was tried and is worse: with the outer skin gone you see straight
## through the near wall into the lit chamber, and the cave renders as a grey
## window in the hillside from every angle behind it. What keeps the slabs out
## of sight is being buried, which `test/cave_test.gd` measures.
func _slab(
	root: Node3D,
	slab_name: String,
	size: Vector3,
	at: Vector3,
	tilt := Vector3.ZERO,
	visible_mesh := true,
) -> void:
	if not visible_mesh:
		_slab_body(root, slab_name, size, at, tilt)
		return
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = slab_name
	node.mesh = mesh
	node.position = at
	node.rotation = tilt
	if rock:
		node.material_override = rock
	# Buried geometry must not cast a shadow. The slabs sit metres inside the
	# hill, so nothing draws them directly, but their shadow still falls on
	# the hillside ABOVE them and reads as a flat grey rectangle lying on the
	# grass. That shadow is what kept showing from open ground and from
	# overhead while every burial measurement said the cave was covered: a
	# shadow with nothing visible attached to it always reads as broken.
	# The chamber is lit by CaveLight from inside, which needs no shadow
	# caster to work.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	_slab_body(root, slab_name, size, at, tilt)


## The solid half of a slab, on its own so the ramp can have one without a
## mesh.
func _slab_body(
	root: Node3D, slab_name: String, size: Vector3, at: Vector3, tilt: Vector3
) -> void:
	var body := StaticBody3D.new()
	body.name = slab_name + "Body"
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = at
	shape.rotation = tilt
	body.add_child(shape)
	root.add_child(body)


## Push a boulder down until its own underside is under the ground.
##
## Measured from the instanced model's AABB rather than computed from a
## nominal model height times its scale. The rock scene's origin is not at
## its base, so every arithmetic version of this has left rocks hanging with
## sky beneath them; the mesh knows where its own bottom is, so ask it.
## Called after the boulder is in the tree, since the AABB needs its final
## transform.
func _bed_boulder(boulder: Node3D) -> void:
	var lowest := INF
	# Under the node's own origin, which is the point the shared decoration
	# assertion in terrain_test.gd measures. Sampling under the mesh's centre
	# instead leaves the two disagreeing by the slope between them.
	var centre_ground := height_at(
		boulder.global_position.x, boulder.global_position.z
	)
	for node in boulder.find_children("*", "VisualInstance3D", true, false):
		var vis := node as VisualInstance3D
		if vis == null:
			continue
		var aabb := vis.get_aabb()

		# The whole underside, so the lowest visible point is known. The rock
		# scene's origin is not at its base, so a height measured from the
		# origin sits the rock wrong by however far the two differ.
		for sx in [0.0, 0.5, 1.0]:
			for sz in [0.0, 0.5, 1.0]:
				var base := aabb.position + Vector3(
					aabb.size.x * sx, 0.0, aabb.size.z * sz
				)
				lowest = minf(lowest, (vis.global_transform * base).y)
	if lowest == INF:
		return
	# Two bounds meet here and the offset has to satisfy both.
	#
	# The visible underside must end up below the ground under it, or the rock
	# hangs with sky beneath it. And the ORIGIN must end up just below the
	# surface: terrain_test.gd bounds a decoration's origin on both sides and
	# reads the ground under the origin, not under the footprint, so a rock
	# bedded to its lowest corner reads there as swallowed by the hill.
	#
	# The two cannot both be met by moving the rock: on this slope a footprint
	# wide enough to overhang is also wide enough that burying its lowest
	# corner drives the origin metres down. So satisfy the origin rule here
	# and hold the underside rule with CAVE_ROCK_SCALE_MAX instead, keeping
	# the rocks small enough that they do not overhang far enough to matter.
	# cave_test.gd asserts the underside, so shrinking is forced, not assumed.
	var height := boulder.global_position.y - lowest
	var drop := boulder.global_position.y - (
		centre_ground - height * Tuning.CAVE_ROCK_BURY
	)
	boulder.global_position.y -= drop


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
		var scale := rng.randf_range(
			Tuning.CAVE_ROCK_SCALE_MIN, Tuning.CAVE_ROCK_SCALE_MAX
		)
		boulder.scale = Vector3.ONE * scale
		boulder.rotation.y = rng.randf() * TAU
		# Ranged over CAVE_ROCK_SPREAD, which is the doorway, not the whole
		# chamber. They used to march CAVE_DEPTH * 0.8 back INTO the hill,
		# which put five-metre rocks over the roof and up the summit: from
		# open ground that reads as a boulder wall rather than a cave mouth.
		var at := Vector3(
			side * (half_w + rng.randf_range(1.0, 2.0)),
			0.0,
			Tuning.CAVE_ROCK_SPREAD * (0.5 - along),
		)
		at.y = _local_ground(root, at)
		boulder.position = at
		root.add_child(boulder)
		_bed_boulder(boulder)
