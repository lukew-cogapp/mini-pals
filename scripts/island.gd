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
	_ash_ring()
	_disc("Beach", Tuning.ISLAND_RADIUS + Tuning.BEACH_WIDTH, -0.35, sand, 64)
	_disc("Water", Tuning.WATER_RADIUS, Tuning.WATER_LEVEL, water, 48)
	_ground_body()
	_shore_wall()
	_zones()


## Zones for the discs just built, in the same pass and from the same
## numbers, so the island and the regions describing it cannot drift apart.
func _zones() -> void:
	# Walkable ground stops at the shore wall, not at the painted sand.
	_zone("LandZone", Zone.Kind.LAND, Tuning.SHORE_WALL_RADIUS, 0.0)
	_zone(
		"AshZone",
		Zone.Kind.ASH,
		Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MAX,
		Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MIN,
	)
	# Everything from the shore wall out to the far edge of the water disc.
	_zone("DeepZone", Zone.Kind.DEEP, Tuning.WATER_RADIUS, Tuning.SHORE_WALL_RADIUS)


func _zone(name: String, kind: Zone.Kind, radius: float, hole: float) -> void:
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


## The demon annulus, scorched. A ring rather than a disc: _disc draws a
## solid cylinder, which would paint the safe middle of the island brown
## too. Built as a triangle strip lifted just above the grass.
func _ash_ring() -> void:
	var inner := Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MIN * Tuning.ASH_INNER
	var outer := Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MAX * Tuning.ASH_OUTER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var segments := 96
	for i in segments + 1:
		var angle := TAU * i / segments
		var c := cos(angle)
		var s := sin(angle)
		# Flat and face up; generate_normals rejects a triangle strip.
		st.set_normal(Vector3.UP)
		# UVs in world units, so the noise tiles at the same scale as grass.
		st.set_uv(Vector2(c * inner, s * inner))
		st.add_vertex(Vector3(c * inner, 0.0, s * inner))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(c * outer, s * outer))
		st.add_vertex(Vector3(c * outer, 0.0, s * outer))
	var node := MeshInstance3D.new()
	node.name = "Ash"
	node.mesh = st.commit()
	node.position.y = Tuning.ASH_LIFT
	if ash:
		node.material_override = ash
	add_child(node)


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
