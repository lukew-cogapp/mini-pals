extends Node3D
## Builds the island: grass disc, sand rim, water, and a wall at the shore.
##
## Generated rather than authored so the radius stays a single number in
## Tuning and the scatter code can share it.

@export var grass: Material
@export var sand: Material
@export var water: Material
@export var ash: Material


func _ready() -> void:
	_disc("Grass", Tuning.ISLAND_RADIUS, 0.0, grass, 64)
	_zones()
	_ash_blob()
	_disc("Beach", Tuning.ISLAND_RADIUS + Tuning.BEACH_WIDTH, -0.35, sand, 64)
	_disc("Water", Tuning.WATER_RADIUS, Tuning.WATER_LEVEL, water, 48)
	_ground_body()
	_shore_wall()


## Zones for the discs just built, in the same pass and from the same
## numbers, so the island and the regions describing it cannot drift apart.
##
## Runs before _ash_blob because the blob's mesh is built from the ash
## zone's own edge curve rather than from a second copy of the maths.
func _zones() -> void:
	# Walkable ground stops at the shore wall, not at the painted sand.
	_zone("LandZone", Zone.Kind.LAND, Tuning.SHORE_WALL_RADIUS, 0.0)
	_ash_zone()
	# Everything from the shore wall out to the far edge of the water disc.
	_zone("DeepZone", Zone.Kind.DEEP, Tuning.WATER_RADIUS, Tuning.SHORE_WALL_RADIUS)


## The scorched blob, as a zone. Its cylinder is the bounding circle of the
## widest the noisy edge can reach; the zone trims queries back to the real
## edge itself.
func _ash_zone() -> void:
	var zone := _zone("AshZone", Zone.Kind.ASH, Tuning.ASH_MAX_RADIUS, 0.0)
	zone.position = Tuning.ALTAR_POS
	var noise := FastNoiseLite.new()
	noise.seed = Tuning.ASH_EDGE_SEED
	noise.frequency = Tuning.ASH_EDGE_FREQUENCY
	noise.fractal_octaves = Tuning.ASH_EDGE_OCTAVES
	zone.edge_noise = noise
	zone.edge_radius = Tuning.ASH_RADIUS
	zone.edge_wobble = Tuning.ASH_EDGE_WOBBLE


func _zone(name: String, kind: Zone.Kind, radius: float, hole: float) -> Zone:
	var zone := Zone.new()
	zone.name = name
	zone.kind = kind
	zone.hole_radius = hole
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	# Tall enough that a point query at any sane height still lands inside.
	cyl.height = Tuning.ZONE_HEIGHT
	var shape := CollisionShape3D.new()
	shape.shape = cyl
	zone.add_child(shape)
	add_child(zone)
	return zone


## The ash zone built by _zones, for the scatter code and the mesh builder.
func ash_zone() -> Zone:
	return get_node_or_null("AshZone") as Zone


func _disc(name: String, radius: float, y: float, mat: Material, segments: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.5
	mesh.radial_segments = segments
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.position.y = y - 0.25
	if mat:
		node.material_override = mat
	add_child(node)


## The scorched ground, as one blob centred on the altar. A triangle fan
## from that centre out to the zone's noisy edge, so the drawn shape and the
## shape the zone answers point queries with are the same curve.
func _ash_blob() -> void:
	var zone := ash_zone()
	if zone == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 192
	var centre := Vector3(Tuning.ALTAR_POS.x, 0.0, Tuning.ALTAR_POS.z)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := centre + _edge_point(zone, a0)
		var p1 := centre + _edge_point(zone, a1)
		# Godot culls back faces, and +Z runs "down" the screen when looking
		# from above, so this order is the one that leaves the fan facing up.
		# The other winding renders nothing at all from a camera overhead.
		for v in [centre, p0, p1]:
			st.set_normal(Vector3.UP)
			# UVs in world units, so the ash tiles at the same scale as grass.
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)
	var node := MeshInstance3D.new()
	node.name = "Ash"
	node.mesh = st.commit()
	node.position.y = Tuning.ASH_LIFT
	if ash:
		node.material_override = ash
	add_child(node)


func _edge_point(zone: Zone, angle: float) -> Vector3:
	var r := zone.edge_radius_at(angle)
	return Vector3(cos(angle) * r, 0.0, sin(angle) * r)


## One flat collider under the island. The beach sits lower than the grass but
## is only ever walked on at its inner edge, so a single plane is enough.
func _ground_body() -> void:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	add_child(body)


## A ring of walls just past the sand, invisible, so the island reads as open
## while the player cannot wander into the water.
func _shore_wall() -> void:
	var body := StaticBody3D.new()
	body.name = "ShoreWall"
	add_child(body)
	var segments := 24
	var seg_width := TAU * Tuning.SHORE_WALL_RADIUS / segments * 1.05
	for i in segments:
		var angle := TAU * i / segments
		var box := BoxShape3D.new()
		box.size = Vector3(seg_width, Tuning.SHORE_WALL_HEIGHT, 1.0)
		var shape := CollisionShape3D.new()
		shape.shape = box
		var at := Vector3(cos(angle), 0.0, sin(angle)) * Tuning.SHORE_WALL_RADIUS
		shape.position = at + Vector3.UP * (Tuning.SHORE_WALL_HEIGHT * 0.5 - 1.0)
		# Long side tangent to the shore, short side radial.
		shape.rotation.y = PI * 0.5 - angle
		body.add_child(shape)
