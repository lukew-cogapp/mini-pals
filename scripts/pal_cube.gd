extends Area3D
## Thrown pal cube. Hits a pal, plays the capture sequence, then reports.

signal resolved(pal: Node, success: bool)

var _velocity: Vector3
var _life := Tuning.CUBE_LIFETIME
var _spent := false
var _rng := RandomNumberGenerator.new()

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _burst: GPUParticles3D = $Burst


func _ready() -> void:
	# Connected here rather than in the scene: a stray node appended after the
	# [connection] block once silently dropped it, and nothing hit for a while.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func throw(from: Vector3, velocity: Vector3) -> void:
	global_position = from
	_velocity = velocity


func _physics_process(delta: float) -> void:
	if _spent:
		return
	var from := global_position
	_velocity.y -= Tuning.CUBE_GRAVITY * delta
	global_position += _velocity * delta
	var pal := _sweep_pal(from, global_position)
	if pal:
		_hit_pal(pal)
		return
	# Tumble on two axes so the flat faces catch the light; a single-axis
	# spin reads as a wheel, not a thrown cube.
	rotate_x(-delta * 6.0)
	rotate_z(delta * 3.5)

	# Landing on the ground without hitting anything is a miss.
	if global_position.y <= Tuning.CUBE_HALF_SIZE:
		_finish(null, false)
		return
	_life -= delta
	if _life <= 0.0:
		_finish(null, false)


func _on_body_entered(body: Node3D) -> void:
	if _spent or not body is Pal:
		return
	var pal := body as Pal
	_hit_pal(pal)


func _hit_pal(pal: Pal) -> void:
	if pal.caught or pal.dying:
		return
	_spent = true
	_capture(pal)


func _sweep_pal(from: Vector3, to: Vector3) -> Pal:
	var ray := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit:
		return hit.collider as Pal
	return null


## Suck the pal in, wobble while it decides, then burst open either way.
func _capture(pal: Pal) -> void:
	set_physics_process(false)
	var ground := pal.global_position + Vector3.UP * Tuning.CUBE_HALF_SIZE
	global_position = pal.global_position + Vector3.UP * 0.8
	rotation = Vector3.ZERO
	Audio.play("suck", global_position)

	var suck := create_tween().set_parallel()
	suck.tween_property(pal, "scale", Vector3.ONE * 0.05, Tuning.CATCH_SUCK_TIME) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	suck.tween_property(pal, "global_position", global_position, Tuning.CATCH_SUCK_TIME)
	await suck.finished

	pal.visible = false
	pal.scale = Vector3.ONE
	var drop := create_tween()
	drop.tween_property(self, "global_position", ground, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	await drop.finished

	var success := _rng.randf() < pal.catch_chance()
	for i in Tuning.CATCH_SHAKE_COUNT:
		Audio.play("shake", global_position)
		var shake := create_tween()
		var lean := 0.5 if i % 2 == 0 else -0.5
		shake.tween_property(self, "rotation:z", lean, Tuning.CATCH_SHAKE_TIME * 0.5) \
			.set_trans(Tween.TRANS_SINE)
		shake.tween_property(self, "rotation:z", 0.0, Tuning.CATCH_SHAKE_TIME * 0.5) \
			.set_trans(Tween.TRANS_SINE)
		await shake.finished

	if success:
		await _succeed(pal)
	else:
		await _fail(pal)


func _succeed(pal: Pal) -> void:
	Audio.play("caught", global_position)
	_burst.emitting = true
	var settle := create_tween()
	settle.tween_property(_mesh, "scale", Vector3.ONE * 1.3, Tuning.CATCH_SETTLE_TIME * 0.4)
	settle.tween_property(_mesh, "scale", Vector3.ZERO, Tuning.CATCH_SETTLE_TIME * 0.6) \
		.set_ease(Tween.EASE_IN)
	await settle.finished
	pal.on_caught()
	_finish(pal, true)


func _fail(pal: Pal) -> void:
	Audio.play("escape", global_position)
	_burst.emitting = true
	pal.global_position = global_position
	pal.visible = true
	pal.scale = Vector3.ONE * 0.05
	var out := create_tween().set_parallel()
	out.tween_property(pal, "scale", Vector3.ONE, Tuning.CATCH_BURST_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	out.tween_property(_mesh, "scale", Vector3.ZERO, Tuning.CATCH_BURST_TIME * 0.5)
	await out.finished
	_finish(pal, false)


func _finish(pal: Node, success: bool) -> void:
	_spent = true
	resolved.emit(pal, success)
	queue_free()
