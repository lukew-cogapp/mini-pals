class_name Zone
extends Area3D
## A named region of the world, asked "is this point inside me" through its
## own collision shape.
##
## Replaces radius-from-origin tests, which only ever described one island
## sitting at (0, 0). A zone is wherever its shape is, so a second island can
## carry its own LAND and ASH without any of the maths changing.

enum Kind { LAND, ASH, SHALLOW, DEEP }

## Zones sit alone on their own layer so a point query can ask for zones
## without also hitting terrain, pals, or the shore wall.
const LAYER := 1 << 6

@export var kind: Kind = Kind.LAND

## Radius of a circular hole punched out of this zone's shape, measured from
## the zone's own origin. Zero means solid.
##
## Physics shapes cannot express a ring, and approximating one as a fan of
## boxes is wrong by up to a centimetre at the seams. That is enough to move
## a scattered thing across a boundary and reshuffle the whole seeded layout,
## so a hole is subtracted arithmetically instead of being built as geometry.
@export var hole_radius: float = 0.0

## Noise perturbing this zone's edge radius by angle, or null for a shape
## with the edge its collision shape already has.
##
## A physics shape cannot express a wobbly edge any more than it can a ring,
## so the ash blob's collision shape is a plain cylinder covering the widest
## the edge can reach, and `edge_radius_at` trims it back down here. That
## keeps ONE definition of the boundary: island.gd builds the ash mesh by
## calling the same method, so the drawn edge and the queried edge are the
## same curve rather than two that have to be kept in step.
var edge_noise: FastNoiseLite = null
var edge_radius: float = 0.0
var edge_wobble: float = 0.0


## Radius of this zone's edge along `angle`, in radians around its centre.
##
## Sampling 2D noise around a unit circle rather than by raw angle keeps the
## curve continuous at the 0/TAU seam, where sampling the angle itself would
## leave a visible step.
func edge_radius_at(angle: float) -> float:
	if edge_noise == null:
		return edge_radius
	var n := edge_noise.get_noise_2d(cos(angle), sin(angle))
	return edge_radius * (1.0 + n * edge_wobble)


func _ready() -> void:
	add_to_group("zone")
	collision_layer = LAYER
	# Zones are asked about points, never told about bodies, so they need to
	# detect nothing themselves.
	collision_mask = 0
	monitoring = false


## True when `point` falls within this zone's shape and outside its hole.
##
## Answered from this zone's own numbers rather than through the physics
## server, so it is correct the moment the zone is built. A point query only
## starts seeing a new Area3D after a physics frame has run, and the world is
## generated and scattered inside `_ready`, well before the first one.
func contains(point: Vector3) -> bool:
	var shape := _shape()
	if shape == null:
		return false
	var local := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	var dist := local.length()
	if dist > shape.radius:
		return false
	if hole_radius > 0.0 and dist < hole_radius:
		return false
	if edge_noise != null and dist > edge_radius_at(atan2(local.z, local.x)):
		return false
	return true


func _shape() -> CylinderShape3D:
	for c in get_children():
		if c is CollisionShape3D:
			return (c as CollisionShape3D).shape as CylinderShape3D
	return null


## The zone containing `point`, or null. Height is ignored: zones are tall
## enough to span the ground, and every caller is asking a map question.
static func zone_at(world: World3D, point: Vector3) -> Zone:
	for z in _zones_at(world, point):
		return z
	return null


static func is_inside(world: World3D, point: Vector3, kind: Kind) -> bool:
	for z in _zones_at(world, point):
		if z.kind == kind:
			return true
	return false


## Every zone containing `point`, asked one at a time through `contains`.
##
## Walking the zone group rather than firing a point query keeps one
## definition of the boundary and works during `_ready`, before the physics
## server has seen the zones. There are three zones, so the loop is cheaper
## than the query it replaced.
static func _zones_at(world: World3D, point: Vector3) -> Array[Zone]:
	var found: Array[Zone] = []
	if world == null:
		return found
	for node in Engine.get_main_loop().get_nodes_in_group("zone"):
		var z := node as Zone
		if z == null or z.get_world_3d() != world:
			continue
		if z.contains(point):
			found.append(z)
	return found
