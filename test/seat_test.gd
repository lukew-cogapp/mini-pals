extends GutTest
## Where a rider sits on a mount.
##
## A Seat is a Marker3D with no visual, so every number in a scene file reads
## as correct whether the rider lands on the back, on the skull or a metre up
## in the air. Both of the long-bodied mounts here had it wrong: the Llama sat
## the player on its head, and the Mudwader's seat, set from the mesh AABB, was
## most of a metre above the animal.
##
## Measured against the posed SKELETON, which is the only thing in the scene
## that says where the animal is. The mesh AABB is the bind pose and reads
## about half a metre taller than the idle, and a MeshInstance sweep picks up
## the billboarded health-bar quads instead of the body. Both looked plausible
## and both were wrong; see test/seat_probe.gd.
##
## These bound the seat rather than pinning it: art may be swapped and a mount
## retuned, and a test that pinned an exact height would fail on every such
## change while catching none of the mistakes this one is for. The render is
## what settles a seat (test/seat_shot.gd shots 50 to 61); this stops the two
## errors that have actually happened from coming back unseen.

## Clearance above the torso a seat may have before the rider is floating,
## in the model's own local metres. Generous: mounts differ in build.
const SEAT_CLEARANCE_MAX := 0.8


func test_a_riders_seat_is_behind_the_head() -> void:
	for path in ["res://scenes/pal_llama.tscn", "res://scenes/pal_mudwader.tscn"]:
		var pal = await _posed(path)
		var bones := _bones(pal)
		assert_true(bones.has("Head"), "%s has a Head bone to place a seat against" % path)
		if not bones.has("Head"):
			pal.free()
			continue
		var seat := _seat(pal)
		# Forward is -Z, so "behind the head" is a LARGER z.
		assert_gt(
			seat.z,
			bones["Head"].z,
			"%s seats the rider behind the head  seat.z=%.2f head.z=%.2f" % [
				path, seat.z, bones["Head"].z
			],
		)
		pal.free()


func test_a_riders_seat_rests_on_the_torso() -> void:
	for path in ["res://scenes/pal_llama.tscn", "res://scenes/pal_mudwader.tscn"]:
		var pal = await _posed(path)
		var bones := _bones(pal)
		assert_true(bones.has("Torso"), "%s has a Torso bone to sit on" % path)
		if not bones.has("Torso"):
			pal.free()
			continue
		var seat := _seat(pal)
		var torso: Vector3 = bones["Torso"]
		assert_gt(
			seat.y, torso.y, "%s seats the rider above the torso, not inside it" % path
		)
		assert_lt(
			seat.y - torso.y,
			SEAT_CLEARANCE_MAX,
			"%s does not leave the rider floating  seat.y=%.2f torso.y=%.2f" % [
				path, seat.y, torso.y
			],
		)
		pal.free()


## The seat in the SAME frame the bones are reported in: Model-local metres,
## which is what the Seat's own transform is written in. Reading the marker's
## position directly would work today and break the moment a mount's
## model_scale changed, which is exactly when this test is wanted.
func _seat(pal: Node3D) -> Vector3:
	return (pal.get_node("Model/Seat") as Node3D).position


## Every posed bone, in Model-local metres.
func _bones(pal: Node3D) -> Dictionary:
	var model: Node3D = pal.get_node("Model")
	var skeleton := _skeleton(pal)
	var out := {}
	if skeleton == null:
		return out
	for i in skeleton.get_bone_count():
		var at: Vector3 = (
			model.global_transform.affine_inverse()
			* (skeleton.global_transform * skeleton.get_bone_global_pose(i).origin)
		)
		out[skeleton.get_bone_name(i)] = at
	return out


func _posed(path: String) -> Node3D:
	var pal = load(path).instantiate()
	add_child(pal)
	await wait_process_frames(1)
	pal.state = pal.State.IDLE
	pal.velocity = Vector3.ZERO
	await wait_physics_frames(6)
	return pal


func _skeleton(root: Node) -> Skeleton3D:
	for child in root.get_children():
		if child is Skeleton3D:
			return child
		var found := _skeleton(child)
		if found:
			return found
	return null
