extends Area3D
## Thrown sphere. Hits a pal, rolls for a catch, and reports the outcome.

signal resolved(pal: Node, success: bool)

var _velocity: Vector3
var _life := Tuning.SPHERE_LIFETIME
var _spent := false


func throw(from: Vector3, direction: Vector3) -> void:
	global_position = from
	_velocity = direction.normalized() * Tuning.SPHERE_THROW_SPEED
	_velocity.y += Tuning.SPHERE_THROW_LIFT


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_velocity.y -= Tuning.SPHERE_GRAVITY * delta
	global_position += _velocity * delta
	rotate_x(-delta * 6.0)

	# Landing on the ground without hitting anything is a miss.
	if global_position.y <= Tuning.SPHERE_RADIUS:
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
	var success := randf() < Tuning.SPHERE_CATCH_CHANCE
	if success:
		pal.on_caught()
	_finish(pal, success)


func _finish(pal: Node, success: bool) -> void:
	_spent = true
	resolved.emit(pal, success)
	queue_free()
