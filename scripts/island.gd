extends Node3D
## Builds the island: grass disc, sand rim, water, and a wall at the shore.
##
## Generated rather than authored so the radius stays a single number in
## Tuning and the scatter code can share it.

@export var grass: Material
@export var sand: Material
@export var water: Material


func _ready() -> void:
	_disc("Grass", Tuning.ISLAND_RADIUS, 0.0, grass, 64)
	_disc("Beach", Tuning.ISLAND_RADIUS + Tuning.BEACH_WIDTH, -0.35, sand, 64)
	_disc("Water", Tuning.WATER_RADIUS, Tuning.WATER_LEVEL, water, 48)
	_ground_body()
	_shore_wall()


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
		shape.rotation.y = -angle
		body.add_child(shape)
