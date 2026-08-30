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
## a scattered tree across the demon-ring boundary and reshuffle the whole
## seeded layout, so the ash annulus keeps an exact inner edge instead.
@export var hole_radius: float = 0.0


func _ready() -> void:
	add_to_group("zone")
	collision_layer = LAYER
	# Zones are asked about points, never told about bodies, so they need to
	# detect nothing themselves.
	collision_mask = 0
	monitoring = false


## True when `point` falls within this zone's shape and outside its hole.
func contains(point: Vector3) -> bool:
	for z in _zones_at(get_world_3d(), point):
		if z == self:
			return true
	return false


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


static func _zones_at(world: World3D, point: Vector3) -> Array[Zone]:
	var found: Array[Zone] = []
	if world == null:
		return found
	var flat := Vector3(point.x, 0.0, point.z)
	var params := PhysicsPointQueryParameters3D.new()
	params.position = flat
	params.collision_mask = LAYER
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in world.direct_space_state.intersect_point(params, 8):
		var z := hit.collider as Zone
		if z == null:
			continue
		if z.hole_radius > 0.0:
			var local := flat - Vector3(z.global_position.x, 0.0, z.global_position.z)
			if local.length() < z.hole_radius:
				continue
		found.append(z)
	return found
