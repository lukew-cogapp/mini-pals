extends SceneTree
## Finds the top of a pal's back from its POSED skeleton, so a Seat can be set
## from a measurement rather than by bisecting renders.
##
##   godot --headless --path . -s test/seat_probe.gd
##
## Bones, not meshes. Two earlier attempts measured the wrong thing and both
## looked plausible:
##   - the MeshInstance3D AABB is the BIND pose, and on the Alpaking it is
##     about half a metre taller than the animal stands;
##   - a sweep over every MeshInstance3D under the pal picks up the five
##     health-bar quads, which billboard at the camera, so the "surface" it
##     reports is the HUD rather than the animal.
## A posed bone is neither: it is where that part of the body actually is on
## the frame being drawn.
##
## Prints each bone's position in the pal's own metres and in Model-local
## metres, which is what a Seat transform is written in.

const RIDEABLE := [
	"res://scenes/pal_llama.tscn",
	"res://scenes/pal_mudwader.tscn",
	"res://scenes/pal_wolf.tscn",
]


func _init() -> void:
	await process_frame
	for path in RIDEABLE:
		var pal = load(path).instantiate()
		get_root().add_child(pal)
		await process_frame
		pal.state = pal.State.IDLE
		pal.velocity = Vector3.ZERO
		for i in 10:
			await physics_frame
		_report(path, pal)
		pal.free()
		await process_frame
	quit()


func _report(path: String, pal: Node3D) -> void:
	var model: Node3D = pal.get_node("Model")
	var scale_now: float = model.scale.x
	var skeleton := _skeleton(pal)
	if skeleton == null:
		printerr(path, ": no Skeleton3D")
		return
	var seat: Vector3 = (
		pal.global_transform.affine_inverse() * pal.get_node("Model/Seat").global_position
	)
	var model_local_seat: Vector3 = (pal.get_node("Model/Seat") as Node3D).position
	print(
		"%s  model.scale %.3f\n  seat: written (%.2f, %.2f, %.2f)  in pal metres (%.2f, %.2f, %.2f)"
		% [
			path, scale_now,
			model_local_seat.x, model_local_seat.y, model_local_seat.z,
			seat.x, seat.y, seat.z,
		]
	)
	for i in skeleton.get_bone_count():
		var at: Vector3 = (
			pal.global_transform.affine_inverse()
			* (skeleton.global_transform * skeleton.get_bone_global_pose(i).origin)
		)
		# Model-local, the frame a Seat is written in: the same inverse the
		# Seat's own `position` is expressed through, not a divide by
		# model_scale, which drops every transform between Model and the
		# skeleton.
		var written: Vector3 = (
			model.global_transform.affine_inverse()
			* (skeleton.global_transform * skeleton.get_bone_global_pose(i).origin)
		)
		print(
			"  %-22s pal (%+.2f, %+.2f, %+.2f)  Model-local (%+.2f, %+.2f, %+.2f)"
			% [
				skeleton.get_bone_name(i),
				at.x, at.y, at.z,
				written.x, written.y, written.z,
			]
		)


func _skeleton(root: Node) -> Skeleton3D:
	for child in root.get_children():
		if child is Skeleton3D:
			return child
		var found := _skeleton(child)
		if found:
			return found
	return null
