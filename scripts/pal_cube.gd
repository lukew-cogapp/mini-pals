extends Area3D
## Thrown pal cube. Hits a pal, rolls for a catch, and reports the outcome.

signal resolved(pal: Node, success: bool)

var _velocity: Vector3
var _life := Tuning.CUBE_LIFETIME
var _spent := false


func throw(from: Vector3, direction: Vector3) -> void:
	global_position = from
	_velocity = direction.normalized() * Tuning.CUBE_THROW_SPEED
	_velocity.y += Tuning.CUBE_THROW_LIFT


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_velocity.y -= Tuning.CUBE_GRAVITY * delta
	global_position += _velocity * delta
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
	if pal.caught:
		return
	var success := randf() < Tuning.CUBE_CATCH_CHANCE
	if success:
		pal.on_caught()
	_finish(pal, success)


func _finish(pal: Node, success: bool) -> void:
	_spent = true
	resolved.emit(pal, success)
	queue_free()
