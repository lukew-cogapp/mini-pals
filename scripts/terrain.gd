class_name Terrain
extends Node3D
## Hand-placed mounds and one cave, sitting on the island's flat ground plane.
##
## The plane stays. Every mound is a CSG solid of its own with a collider
## derived from the same boolean result it renders, so the shore wall, the
## zones, the swim sink and the seeded scatter all still work against a flat
## y = 0 world and only the things that actually stand on a slope have to
## know about one.
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


## One mound, as a closed CSG solid.
##
## The dome is closed with `_underside` into a manifold, because CSG booleans
## a closed manifold and nothing else, and `use_collision` derives the
## collider from the boolean result, so what the player walks on is exactly
## what they see, cave cut included.
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
			# Two triangles, wound counter-clockwise seen from above, which
			# is the winding CSG treats as facing OUT. It is the reverse of
			# what the renderer alone would want, and getting it backwards
			# turns the solid inside-out: the collider stops nothing arriving
			# from outside, and while the hill material was two-sided that
			# was invisible on screen, every hill rendering perfectly and
			# walked straight through. Measured: the inverted brush's apex
			# normal was (0, -1, 0) and a downward ray passed through the
			# dome to the base floor. hill_collider_test.gd holds this.
			for v in [quad[0], quad[1], quad[2]]:
				_vertex(st, v, hill[3])
			for v in [quad[0], quad[2], quad[3]]:
				_vertex(st, v, hill[3])

	_underside(st, centre, radius, hill[3])

	st.generate_normals()
	var mesh := st.commit()

	# One CSG solid per mound, so the cave can be subtracted out of the hill
	# it is buried in. `use_collision` builds the collider from the SAME
	# boolean result, which is the whole reason for the node: the drawn hole
	# and the walkable hole cannot disagree, because there is only one.
	var solid := CSGCombiner3D.new()
	solid.name = "Hill%d" % index
	solid.use_collision = true
	solid.material_override = _hill_material()
	add_child(solid)

	var shell := CSGMesh3D.new()
	shell.name = "Shell"
	shell.mesh = mesh
	solid.add_child(shell)

	if index == Tuning.CAVE_HILL:
		_carve_cave(solid)


## The dome's floor and rim wall, which is what makes it a solid.
##
## CSG booleans a closed manifold and nothing else. Measured, not assumed: an
## open surface through CSGMesh3D yields a mesh of ZERO faces, and with
## `use_collision` on that means no collider either, so the hill silently
## disappears in both senses at once. The dome alone is an open bowl.
##
## The base sits HILL_BASE_DEPTH below y = 0 rather than level with it. The
## cave floor is CAVE_SINK under the grass, so a base at zero would slice
## through the chamber and leave its lower half outside the solid the cave is
## subtracted from.
func _underside(st: SurfaceTool, centre: Vector3, radius: float, top: float) -> void:
	var base := -Tuning.HILL_BASE_DEPTH
	var mid := Vector3(centre.x, base, centre.z)
	for seg in Tuning.HILL_SEGMENTS:
		var a0 := TAU * seg / Tuning.HILL_SEGMENTS
		var a1 := TAU * (seg + 1) / Tuning.HILL_SEGMENTS
		var r0 := Vector3(
			centre.x + cos(a0) * radius, base, centre.z + sin(a0) * radius
		)
		var r1 := Vector3(
			centre.x + cos(a1) * radius, base, centre.z + sin(a1) * radius
		)
		# Floor fan, facing DOWN under CSG's counter-clockwise-out rule, the
		# opposite hand from the dome above it.
		for v in [mid, r1, r0]:
			_vertex(st, v, top)
		# The rim wall, closing the gap between the dome's edge and the floor
		# below it. Its top must be the dome's OWN edge height, not zero: a
		# neighbouring mound's skirt reaches under this rim and lifts it by a
		# centimetre or so, and a wall built to a flat zero leaves a crack of
		# exactly that size all the way round. The solid is then open, the
		# boolean yields nothing, and the hill disappears from the frame and
		# the physics together. Measured on HILLS[0]: rim at 0.014, not 0.
		var t0 := _surface_point(Vector3(centre.x, 0.0, centre.z), radius, a0)
		var t1 := _surface_point(Vector3(centre.x, 0.0, centre.z), radius, a1)
		for v in [r0, t1, t0]:
			_vertex(st, v, top)
		for v in [r0, r1, t1]:
			_vertex(st, v, top)


## The cave, subtracted out of the hill it sits in.
##
## One box in the hill's own CSG solid, sized to the chamber plus its walls
## and long enough to reach out through the hillside as the approach cutting.
## Godot's boolean does the rest: the doorway in the drawn mesh and the hole
## in the collider are the same surface, so they cannot drift apart.
##
## This replaced a hand-rolled carve that dropped whole hill triangles whose
## centre fell inside the chamber. It could not work at this resolution: the
## cave hill is 32 segments around a ~200 m circumference, so one triangle is
## over 6 m across against a 9 m cave, and dropping it took out most of the
## doorway's width along with a ragged star of hillside beside it. Rebuilding
## the same cavity twice, once to remove and once to replace, is what left
## holes to fall through; there is now one description of it.
## The cavity's width, used by the cut that makes the hole and the slabs that
## floor it. One function so the two cannot be retuned apart, which is the
## bug that has produced every hole beside this doorway so far.
func _cut_width() -> float:
	return Tuning.CAVE_WIDTH + Tuning.CAVE_WALL * 2.0


func _carve_cave(solid: CSGCombiner3D) -> void:
	var cut := CSGBox3D.new()
	cut.name = "CaveCut"
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	# Local to the hill, which sits at the origin, so the mouth's world
	# position is used directly.
	var mouth := mouth_position()
	# The cavity runs from the back wall out past the mouth to the far end of
	# the approach cutting, and the box is centred on the middle of that.
	var length := Tuning.CAVE_DEPTH + Tuning.CAVE_RAMP + Tuning.CAVE_CARVE_MARGIN
	cut.size = Vector3(
		_cut_width(),
		Tuning.CAVE_HEIGHT + Tuning.CAVE_WALL,
		length,
	)
	var inward := -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
	# Centre of the run: half the length in from the cutting's outer end.
	var mid := mouth - inward * (Tuning.CAVE_RAMP + Tuning.CAVE_CARVE_MARGIN) \
		+ inward * (length * 0.5)
	mid.y = mouth.y + cut.size.y * 0.5
	cut.position = mid
	cut.rotation.y = Tuning.CAVE_FACING
	solid.add_child(cut)


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
	# Normal culling. The old carved trimesh needed CULL_DISABLED because the
	# player inside the chamber saw the dome's back faces; the CSG cut gives
	# the cavity real front faces, so from the chamber and the cutting alike
	# every visible surface faces the camera. Verified by rendering the mouth
	# and the chamber with culling on.
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
## it. The hole itself is `_carve_cave`'s boolean; the slabs here line it
## with a rock floor, walls and roof, and floor the approach cutting.
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
	# Wider than the hole it floors, by CAVE_SLAB_OVERLAP on each side. The
	# CSG cut and a slab of exactly its width meet flush along a plane, and a
	# body standing on that seam is over neither of them; the overlap runs
	# under intact hill, where it is buried and does nothing.
	# Longer than the chamber as well as wider, and pushed back by half the
	# excess so the extra lands behind the back wall rather than out in the
	# doorway.
	var floor_len := Tuning.CAVE_DEPTH + Tuning.CAVE_SLAB_OVERLAP
	_slab(root, "Floor", Vector3(_cut_width() + Tuning.CAVE_SLAB_OVERLAP * 2.0,
		wall, floor_len),
		Vector3(0.0, -wall * 0.5, mid - Tuning.CAVE_SLAB_OVERLAP * 0.5))
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
	# Overlapping the cut on every side, for the reason given on Floor: a slab
	# flush with the hole leaves a seam that is over neither surface, and the
	# cutting's whole width and its outer end are both walked over.
	var length := (
		Tuning.CAVE_RAMP + Tuning.CAVE_CARVE_MARGIN + Tuning.CAVE_SLAB_OVERLAP
	)
	var size := Vector3(
		_cut_width() + Tuning.CAVE_SLAB_OVERLAP * 2.0, Tuning.CAVE_WALL, length
	)
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
