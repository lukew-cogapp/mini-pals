extends Area3D
class_name Spit
## A wad of llama spit in flight. The only projectile in the game that is a
## weapon; scenes/pal_cube.tscn is the only other thing that flies, and that
## one catches rather than hurts.
##
## Modelled on pal_cube.gd, which already solved the parts that bite: it
## travels under its own gravity rather than the world's, and it sweeps a
## SPHERE along its step each frame instead of raycasting, because a ray let a
## fast cube tunnel clean through a target between two physics frames.
##
## The damage itself is NOT computed here. A wad carries the same `target` the
## melee swing would have hit and calls the same function that swing calls, so
## a follower's spit goes through `Pal.take_follower_hit` and inherits the
## FOLLOWER_MIN_TARGET_HP clamp for free. A ranged attack that reimplemented
## the arithmetic would be a way round the clamp, and the clamp is the whole
## reason a follower cannot cost the player a catch.

## Which of the game's three damage paths this wad settles on arrival. One
## enum rather than three subclasses, and each case is one call.
enum Mode {
	PLAYER,    ## A wild pal shooting the player: Player.damage.
	FOLLOWER,  ## A caught pal defending: Pal.take_follower_hit, clamped.
	RIVAL,     ## Two wild pals brawling: Pal.take_rival_hit, lethal.
	RIDER,     ## The player firing from the saddle: Pal.take_hit, lethal.
}

var mode: Mode = Mode.PLAYER
## Who fired it. Held so a wad can never hit its own shooter, and so a rival
## hit knows which way to shove its target.
var shooter: Pal = null

var _velocity: Vector3
var _life := Tuning.SPIT_LIFETIME
var _spent := false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Launch from `from` towards `target_point`, leading a target moving at
## `target_velocity`.
##
## The lead is deliberately partial (SPIT_LEAD_FACTOR). A wad aimed at where
## the target will be is hitscan with a delay, and one aimed at where it is
## now is free to walk out of; at 0.7 a target holding its line is hit and one
## that turns is missed. Nothing steers the wad after this call.
func launch(
	from: Vector3, target_point: Vector3, target_velocity := Vector3.ZERO
) -> void:
	global_position = from
	var flat := target_point - from
	flat.y = 0.0
	var flight := maxf(flat.length(), 0.01) / Tuning.SPIT_SPEED
	var lead := target_velocity * flight * Tuning.SPIT_LEAD_FACTOR
	lead.y = 0.0
	var to := target_point + lead
	var out := to - from
	out.y = 0.0
	var dist := out.length()
	if dist < 0.01:
		out = -global_transform.basis.z
		dist = 1.0
	flight = dist / Tuning.SPIT_SPEED
	# Solve the vertical so the wad passes through the aim point at `flight`
	# rather than dropping short: the horizontal pace is fixed, so the only
	# free term is the launch rise.
	var rise := (to.y - from.y) / flight + 0.5 * Tuning.SPIT_GRAVITY * flight
	_velocity = out.normalized() * Tuning.SPIT_SPEED + Vector3.UP * rise


func _physics_process(delta: float) -> void:
	if _spent:
		return
	var from := global_position
	_velocity.y -= Tuning.SPIT_GRAVITY * delta
	global_position += _velocity * delta

	var hit := _sweep(from, global_position)
	if hit:
		_land_on(hit)
		return
	if global_position.y <= Tuning.SPIT_GROUND_HEIGHT:
		_miss()
		return
	_life -= delta
	if _life <= 0.0:
		_miss()


func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return
	if _is_target(body):
		_land_on(body)


## The wad's path this frame, swept as a sphere rather than a ray. See the
## class comment: a ray is how a projectile passes through a target it should
## have hit, and this project has already shipped that bug once.
func _sweep(from: Vector3, to: Vector3) -> Node3D:
	var ball := SphereShape3D.new()
	ball.radius = Tuning.SPIT_HIT_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = ball
	params.collision_mask = collision_mask
	params.transform = Transform3D(Basis.IDENTITY, from)
	params.motion = to - from
	var space := get_world_3d().direct_space_state
	# cast_motion reports how far along the motion something was touched, not
	# what was touched, so the hit itself comes from a query at that point.
	var travel := space.cast_motion(params)
	if travel.is_empty() or travel[0] >= 1.0:
		return _within(to)
	params.transform = Transform3D(Basis.IDENTITY, from + (to - from) * travel[0])
	return _first_target(space.intersect_shape(params, 8))


func _within(point: Vector3) -> Node3D:
	var ball := SphereShape3D.new()
	ball.radius = Tuning.SPIT_HIT_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = ball
	params.collision_mask = collision_mask
	params.transform = Transform3D(Basis.IDENTITY, point)
	return _first_target(get_world_3d().direct_space_state.intersect_shape(params, 8))


func _first_target(hits: Array[Dictionary]) -> Node3D:
	for hit in hits:
		var body := hit.collider as Node3D
		if _is_target(body):
			return body
	return null


## Whether this body is what the wad was fired at. The shooter itself is
## excluded, since a spitter standing still would otherwise swallow its own
## wad on the first frame, and a wad never crosses modes: one aimed at the
## player passes straight through a pal that wanders into it, which keeps a
## brawl from paying the player XP it did not earn.
func _is_target(body: Node3D) -> bool:
	if body == null or body == shooter:
		return false
	match mode:
		Mode.PLAYER:
			return body.is_in_group("player")
		Mode.FOLLOWER, Mode.RIVAL, Mode.RIDER:
			var pal := body as Pal
			return pal != null and not pal.caught and not pal.dying
	return false


## Arrival. Each mode calls exactly the function its melee equivalent calls,
## so the follower clamp, the rival knockback and the player's invulnerability
## window all behave the way they do for a bite.
func _land_on(body: Node3D) -> void:
	# Guarded here rather than only at the call sites. `queue_free` is
	# deferred, so between deciding to land and actually leaving the tree the
	# area can still emit body_entered, and the sweep and the signal can both
	# see the same target on the same frame. Unguarded, one wad billed a
	# target three times.
	if _spent:
		return
	_spent = true
	Audio.play(Tuning.SPIT_HIT_SOUND, global_position)
	match mode:
		Mode.PLAYER:
			if body.has_method("damage"):
				body.damage(Tuning.SPIT_PLAYER_DAMAGE, global_position)
		Mode.FOLLOWER:
			var target := body as Pal
			if target:
				target.take_follower_hit()
		Mode.RIVAL:
			var rival := body as Pal
			if rival and shooter and is_instance_valid(shooter):
				rival.take_rival_hit(shooter)
		Mode.RIDER:
			# The player's own attack, so it goes through take_hit exactly as
			# their punch does: the same damage, the same knockback, and the
			# same _credit_player, or a kill from the saddle would pay no drop
			# and no XP.
			var quarry := body as Pal
			if quarry:
				quarry.take_hit(global_position)
	_finish()


## Nothing was there. Silent, deliberately: a spitter firing at a target that
## keeps stepping aside would otherwise tick across the island every two
## seconds like a metronome.
func _miss() -> void:
	if _spent:
		return
	_spent = true
	_finish()


func _finish() -> void:
	set_physics_process(false)
	# Deferred, because Godot refuses to change monitoring from inside the
	# area's own signal callback. It stops any further body_entered arriving
	# in the frames between here and the queued free.
	set_deferred("monitoring", false)
	queue_free()
