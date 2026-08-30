extends GutTest
## Every hill's collider must match the surface the player sees.
##
## The CSG hills once rendered perfectly with no collider at all: the brush
## was wound clockwise-out, which Godot's CSG reads as an inside-out solid,
## and the two-sided hill material rendered it anyway. Every visual check
## passed while the player walked through all four hills. So this measures
## the collider itself, a ray grid per hill compared against `height_at`,
## with no ground plane in the scene: a missing collider is a missed ray,
## not a hit on flat ground that happens to be under everything.

const TERRAIN := preload("res://scripts/terrain.gd")

## The drawn hill is a 32-by-12 chorded approximation of the ideal dome, so
## between vertices it sags below `height_at`. Measured slack, not assumed:
## worst chord sag on HILLS[0] is under 0.3, and the apex ray in the probe
## hit 0.037 low.
const SAG := 0.6
const RISE := 0.1

var _terrain: Node3D


func before_all() -> void:
	_terrain = TERRAIN.new()
	add_child(_terrain)
	# CSG builds its collider on the first process frame after entering the
	# tree, and the physics server sees it a frame later.
	await wait_process_frames(3)


func after_all() -> void:
	_terrain.free()


## Points over the cave cut are legitimately below the hill surface; the
## cutting's own floor is measured by cave_fall_test.gd, not here.
func _in_cave_cut(at: Vector3) -> bool:
	var mouth: Vector3 = _terrain.mouth_position()
	var inward := -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
	var flat := Vector3(at.x - mouth.x, 0.0, at.z - mouth.z)
	var along := flat.dot(inward)
	var across := (flat - inward * along).length()
	var half_w: float = (Tuning.CAVE_WIDTH + Tuning.CAVE_WALL * 2.0) * 0.5
	return (
		across <= half_w + 1.0
		and along >= -(Tuning.CAVE_RAMP + Tuning.CAVE_CARVE_MARGIN + 1.0)
		and along <= Tuning.CAVE_DEPTH + 1.0
	)


func test_every_hill_stops_a_ray_at_its_own_surface() -> void:
	var space := _terrain.get_world_3d().direct_space_state
	var bad: Array[String] = []
	var checked := 0
	for hill: Array in Tuning.HILLS:
		var centre := Vector3(hill[0], 0.0, hill[1])
		var radius: float = hill[2]
		var top: float = hill[3]
		for frac: float in [0.0, 0.25, 0.5, 0.75, 0.95]:
			var bearings := 1 if frac == 0.0 else 8
			for b in bearings:
				var a := TAU * b / 8.0
				var at := centre + Vector3(cos(a), 0.0, sin(a)) * (radius * frac)
				if _in_cave_cut(at):
					continue
				var want := TERRAIN.height_at(at.x, at.z)
				var from := at + Vector3.UP * (top + 20.0)
				var query := PhysicsRayQueryParameters3D.create(
					from, from + Vector3.DOWN * (top + 60.0)
				)
				var hit := space.intersect_ray(query)
				checked += 1
				if hit.is_empty():
					bad.append("hill at %s: no collider under (%.1f, %.1f), want %.2f" % [
						centre, at.x, at.z, want
					])
				elif hit["position"].y < want - SAG or hit["position"].y > want + RISE:
					bad.append("hill at %s: ray hit %.2f at (%.1f, %.1f), want %.2f" % [
						centre, hit["position"].y, at.x, at.z, want
					])
	gut.p("checked %d points" % checked)
	for line in bad.slice(0, 10):
		gut.p("  " + line)
	assert_eq(bad.size(), 0, "%d points where the collider disagrees with the surface" % bad.size())
