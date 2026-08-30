extends CharacterBody3D
## Third-person player: WASD moves relative to where the camera looks.
## Numbers live in scripts/tuning.gd.

const CUBE_SCENE := preload("res://scenes/pal_cube.tscn")

@onready var pivot: Node3D = $CameraPivot
@onready var body: Node3D = $Body
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _arm: SpringArm3D = $CameraPivot/SpringArm3D
## Rest position of the arm, so shake offsets are always measured from the
## scene's value rather than from wherever the last frame left it.
@onready var _arm_rest: Vector3 = _arm.position
@onready var _anim: AnimationPlayer = _find_anim(body)

var mount: Pal = null  ## The pal we are riding, if any.

var hp := 0.0  ## Set from Tuning in _ready; autoloads are not up at parse time.
var _spawn := Vector3.ZERO
var _since_hit := 1000.0  ## Long ago, so regen is armed from the start.
var _invuln := 0.0
var _dead := false
var _bite_left := 0.0  ## Seconds the bite clip still owns the rig.
## Seconds until the saddle can spit again. On the player rather than on the
## mount, so swapping between two llamas cannot double the rate of fire.
var _rider_spit_cooldown := 0.0
var _aiming_throw := false
## Why we are aiming, which is what decides whether letting go of the throw
## key spends a cube. Holding right mouse aims for free and Q fires; holding
## Q alone still aims and throws on release, the flow that shipped first.
## Without this the right-click release path would throw a cube the player
## meant to cancel, which is the whole point of the feature.
var _aim_held := false
## Whether Escape has freed the mouse. Tracked rather than read back from
## `Input.mouse_mode`, which is not settable at all under the headless
## renderer and reads MOUSE_MODE_VISIBLE forever there, so every click would
## take the recapture branch and no gameplay button would ever be seen.
var _mouse_free := false
var _throw_target := Vector3.ZERO
var _throw_aim := Vector3.FORWARD
var _shake := 0.0  ## Decaying camera shake strength; 0 means the arm sits at rest.

## The pal the aim reticule is locked onto, or null. Published rather than
## recomputed: a pal deciding whether to show its health bar needs the answer
## and the raycast that produces it already runs once a frame while aiming.
var locked_pal: Pal = null

## One bool each, so the edge fires once and wading or standing on the ash
## does not re-fire it every frame.
var _was_wading := false
var _was_in_ash := false
var _ash_poll := 0.0
## Runs the sink to SWIM_SINK and back, killed on each crossing so a quick
## in-and-out does not leave two tweens fighting over the model.
var _sink_tween: Tween = null

## Breadcrumbs of where we have walked, so a following pal has a path to
## take rather than homing on us every frame.
var trail: Array[Vector3] = []


## The point on our trail roughly `distance` behind us, measured along the
## path rather than by index, so it does not depend on how fast we were going
## when the crumbs were dropped.
func trail_point_at(distance: float) -> Vector3:
	if trail.is_empty():
		return global_position
	var walked := global_position.distance_to(trail[-1])
	for i in range(trail.size() - 1, 0, -1):
		if walked >= distance:
			return trail[i]
		walked += trail[i].distance_to(trail[i - 1])
	return trail[0]


func _record_trail() -> void:
	if trail.is_empty() or trail[-1].distance_to(global_position) > Tuning.FOLLOW_TRAIL_SPACING:
		trail.append(global_position)
		if trail.size() > Tuning.FOLLOW_TRAIL_LENGTH:
			trail.pop_front()


func _ready() -> void:
	add_to_group("player")
	_spawn = global_position
	hp = Tuning.PLAYER_MAX_HP
	Hud.set_health(hp, Tuning.PLAYER_MAX_HP)
	_capture_mouse()
	# The arm's shape cast would otherwise hit our own capsule and pull the
	# camera into the player's head.
	_arm.add_excluded_object(get_rid())
	pivot.rotation.x = Tuning.CAMERA_PITCH_START


## Shake moves the arm, not the pivot, so the arm's own collision cast still
## starts at the pivot and the player exclusion above keeps working.
func _process(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake = maxf(_shake - Tuning.SHAKE_DECAY * delta, 0.0)
	if _shake <= 0.0:
		_arm.position = _arm_rest
		return
	var amount := _shake * Tuning.SHAKE_MAX
	_arm.position = _arm_rest + Vector3(
		randf_range(-amount, amount),
		randf_range(-amount, amount),
		0.0,
	)


## Strength is clamped so stacked hits cannot leave the camera flailing.
func kick(strength: float) -> void:
	_shake = minf(maxf(_shake, strength), 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pivot.rotate_y(-event.relative.x * Tuning.MOUSE_SENSITIVITY)
		pivot.rotation.x = clampf(
			pivot.rotation.x - event.relative.y * Tuning.MOUSE_SENSITIVITY,
			Tuning.CAMERA_PITCH_MIN,
			Tuning.CAMERA_PITCH_MAX,
		)
	elif event.is_action_pressed("ui_cancel"):
		_cancel_throw_aim()
		_free_mouse()
	elif event is InputEventMouseButton and _mouse_free:
		# Clicking back into the window after Escape recaptures the mouse and
		# does nothing else. It sits ABOVE the action branches on purpose:
		# left click bites and middle click commands, and a recapture click
		# that also swung is the bug that was removed from throwing.
		_capture_mouse()
	elif event.is_action_pressed("aim"):
		_begin_aim()
	elif event.is_action_released("aim"):
		_end_aim()
	elif event.is_action_pressed("throw"):
		_press_throw()
	elif event.is_action_released("throw"):
		_release_throw_aim()
	elif event.is_action_pressed("ride"):
		_toggle_ride()
	elif event.is_action_pressed("cycle_pal") or event.is_action_pressed("pal_next"):
		_cycle_party(1)
	elif event.is_action_pressed("pal_prev"):
		_cycle_party(-1)
	elif event.is_action_pressed("punch"):
		_punch()
	elif event.is_action_pressed("pal_attack"):
		_command_pal_attack()


func _physics_process(delta: float) -> void:
	_tick_health(delta)
	_tick_ash(delta)
	_bite_left = maxf(_bite_left - delta, 0.0)
	# Ticked before the mounted early return below, or the saddle spit would
	# never come off cooldown while actually riding.
	_rider_spit_cooldown = maxf(_rider_spit_cooldown - delta, 0.0)
	if _aiming_throw:
		_update_throw_aim()
	if mount:
		_ride(delta)
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = Tuning.PLAYER_JUMP_STRENGTH

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Flatten the camera basis so looking up or down never slows movement.
	var pivot_basis := pivot.global_transform.basis
	var direction := (pivot_basis.x * input.x + pivot_basis.z * input.y)
	direction.y = 0.0
	direction = direction.normalized()

	var speed := Tuning.PLAYER_RUN_SPEED if Input.is_action_pressed("run") else Tuning.PLAYER_SPEED
	# The active pal's passive; reads 0.0 with no pal out, so base stays base.
	speed *= 1.0 + Party.buff(&"speed")
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Face travel direction rather than snapping instantly. Godot forward
		# is -Z; the model is turned to match inside player_model.tscn.
		var target := atan2(-direction.x, -direction.z)
		body.rotation.y = lerp_angle(body.rotation.y, target, Tuning.PLAYER_TURN_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	_record_trail()
	_try_step_up(direction)
	_animate(direction)


## CharacterBody3D stops dead at any lip, however small. When we collide with
## something low enough to be a step, lift over it instead of being stopped.
func _try_step_up(direction: Vector3) -> void:
	if direction == Vector3.ZERO or not is_on_floor():
		return
	# Only interested in walls we ran into, not the floor underfoot.
	var blocked := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if absf(c.get_normal().y) < 0.5:
			blocked = true
			break
	if not blocked:
		return

	var probe := direction * Tuning.STEP_FORWARD_PROBE
	var up := Vector3.UP * Tuning.STEP_HEIGHT
	var params := PhysicsTestMotionParameters3D.new()
	params.recovery_as_collision = true
	var result := PhysicsTestMotionResult3D.new()

	# Is the space above the obstacle clear to move into?
	params.from = global_transform.translated(up)
	params.motion = probe
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return

	# Is there ground under that space to stand on?
	params.from = global_transform.translated(up + probe)
	params.motion = Vector3.DOWN * Tuning.STEP_HEIGHT
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return

	global_position += up + probe + Vector3.DOWN * result.get_travel().length()


## --- Health ----------------------------------------------------------------

func _tick_health(delta: float) -> void:
	_invuln = maxf(_invuln - delta, 0.0)
	_since_hit += delta
	if _dead or hp >= Tuning.PLAYER_MAX_HP or _since_hit < Tuning.PLAYER_REGEN_DELAY:
		return
	hp = minf(hp + Tuning.PLAYER_REGEN_RATE * delta, Tuning.PLAYER_MAX_HP)
	Hud.set_health(hp, Tuning.PLAYER_MAX_HP)


## Hostile pals call this; from_position aims the knockback.
func damage(amount: float, from_position: Vector3) -> bool:
	if _dead or _invuln > 0.0:
		return false
	hp = maxf(hp - amount, 0.0)
	_since_hit = 0.0
	Hud.set_health(hp, Tuning.PLAYER_MAX_HP)
	Audio.play("player_hurt", global_position)
	kick(Tuning.SHAKE_HURT * clampf(amount / Tuning.PLAYER_MAX_HP, 0.0, 1.0))
	Hud.hurt_flash()
	var away := global_position - from_position
	away.y = 0.0
	if away.length() > 0.01:
		velocity += away.normalized() * Tuning.PLAYER_HIT_KNOCKBACK
	if hp <= 0.0:
		_die()
	return true


func _die() -> void:
	_dead = true
	_cancel_throw_aim()
	if mount:
		_dismount(true)
	velocity = Vector3.ZERO
	set_physics_process(false)
	Audio.play("player_death", global_position)
	Hud.flash("You fainted!")
	Hud.fade_to(1.0, Tuning.PLAYER_DEATH_TIME)
	await get_tree().create_timer(Tuning.PLAYER_DEATH_TIME).timeout
	_respawn()


## Back at the origin camp with everything kept; only the fight is forgotten.
func _respawn() -> void:
	global_position = _spawn
	velocity = Vector3.ZERO
	hp = Tuning.PLAYER_MAX_HP
	_invuln = Tuning.PLAYER_RESPAWN_INVULN
	_dead = false
	set_physics_process(true)
	for node in get_tree().get_nodes_in_group("pal"):
		var pal := node as Pal
		if pal:
			pal.clear_aggro()
	Hud.set_health(hp, Tuning.PLAYER_MAX_HP)
	Hud.fade_to(0.0, Tuning.PLAYER_RESPAWN_FADE)


## --- Catching -------------------------------------------------------------

## Holding right mouse: the reticule comes up and nothing is spent. Looking
## is free, so this does NOT refuse with an empty pouch: reading a pal's
## catch odds is worth doing before you have a cube to act on it, and the
## message on the throw itself is enough to say why nothing flew.
func _capture_mouse() -> void:
	_mouse_free = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _free_mouse() -> void:
	_mouse_free = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _begin_aim() -> void:
	_capture_mouse()
	_aim_held = true
	_aiming_throw = true
	_update_throw_aim()


## Letting go of right mouse cancels. Never a throw: that is the point.
func _end_aim() -> void:
	_aim_held = false
	_cancel_throw_aim()


## Q. While right mouse is held it fires straight away and stays aimed, so a
## miss can be followed up without re-aiming. On its own it starts the old
## hold-to-aim, throw-on-release flow.
func _press_throw() -> void:
	if _aim_held:
		_update_throw_aim()
		_throw_cube(_throw_target, _throw_aim)
		return
	_begin_throw_aim()


func _begin_throw_aim() -> void:
	if not Party.infinite_cubes() and Inventory.count("cube") <= 0:
		Hud.flash("No pal cubes. Punch trees and rocks, then craft at the workbench.")
		return
	_capture_mouse()
	_aiming_throw = true
	_update_throw_aim()


## Releasing Q throws only when Q is what started the aim. Under right mouse
## the throw already happened on the press, and the aim outlives the key.
func _release_throw_aim() -> void:
	if _aim_held or not _aiming_throw:
		return
	_update_throw_aim()
	var target: Vector3 = _throw_target
	var aim: Vector3 = _throw_aim
	_cancel_throw_aim()
	_throw_cube(target, aim)


func _cancel_throw_aim() -> void:
	if not _aiming_throw:
		return
	_aiming_throw = false
	_aim_held = false
	locked_pal = null
	Hud.set_reticule(false)


func _update_throw_aim() -> void:
	var info: Dictionary = _current_throw_aim()
	_throw_target = info.target
	_throw_aim = info.aim
	var pal := info.pal as Pal
	locked_pal = pal
	var text := ""
	if pal:
		text = "%s %d%%" % [pal.display_name, roundi(pal.catch_chance() * 100.0)]
	Hud.set_reticule(true, text, pal != null)


func _throw_cube(target: Variant = null, aim: Variant = null) -> bool:
	if not Party.infinite_cubes() and not Inventory.remove("cube", 1):
		Hud.flash("No pal cubes. Punch trees and rocks, then craft at the workbench.")
		return false
	Audio.play("throw", global_position)
	var cube := CUBE_SCENE.instantiate()
	get_parent().add_child(cube)
	if target == null or aim == null:
		var info: Dictionary = _current_throw_aim()
		target = info.target
		aim = info.aim
	var aim_dir := (aim as Vector3).normalized()
	# Thrown from the shoulder so the cat's body does not hide it; the lob
	# converges on the aim point, so the offset cannot cause a miss.
	var from := (
		global_position
		+ Vector3.UP * Tuning.CUBE_SPAWN_HEIGHT
		+ aim_dir * Tuning.CUBE_SPAWN_FORWARD
		+ pivot.global_transform.basis.x * Tuning.CUBE_SPAWN_SIDE
	)
	cube.throw(from, _lob_velocity(from, target as Vector3))
	cube.resolved.connect(_on_cube_resolved)
	return true


## Where the screen-centre reticule lands: the first pal or obstacle the
## active camera sees. With nothing in the way, aim at the ground at max range.
func _current_throw_aim() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = _camera
	var centre := get_viewport().get_visible_rect().size * 0.5
	var origin := cam.project_ray_origin(centre)
	var aim := cam.project_ray_normal(centre).normalized()
	var exclude := [get_rid()]
	if mount:
		exclude.append(mount.get_rid())
	var pal := _pal_under_reticule(origin, aim)
	if pal:
		return {
			"origin": origin,
			"aim": aim,
			"target": pal.get_node("Collision").global_position,
			"pal": pal,
		}
	var ray := PhysicsRayQueryParameters3D.create(
		origin, origin + aim * Tuning.CUBE_AIM_DISTANCE, 0b101, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit:
		pal = hit.collider as Pal
		var struck: Vector3 = hit.position
		if pal and pal.has_node("Collision"):
			struck = pal.get_node("Collision").global_position
		return {"origin": origin, "aim": aim, "target": struck, "pal": pal}
	var target := origin + aim * Tuning.CUBE_AIM_DISTANCE
	target.y = minf(target.y, Tuning.CUBE_HALF_SIZE)
	return {"origin": origin, "aim": aim, "target": target, "pal": null}


## --- Commanding the active pal --------------------------------------------

## Middle click: send the pal that is out at whatever the reticule is over.
##
## The reticule aim is recomputed here rather than read from `locked_pal`,
## which only exists while the throw key is held down. `_current_throw_aim`
## is the same raycast the throw uses, so the pal the command picks is the
## one the crosshair would have cubed.
##
## Every refusal says why. A command that quietly found nothing is worse
## than no command at all.
func _command_pal_attack() -> void:
	var pal := Party.active
	if pal == null or not is_instance_valid(pal) or not pal.visible:
		Hud.flash("No pal out. Cycle to one first.")
		return
	if pal == mount:
		Hud.flash("%s cannot fight while you are riding it." % pal.display_name)
		return
	var target: Pal = _current_throw_aim().pal
	if target == null:
		Hud.flash("Nothing to attack. Aim at a wild pal.")
		return
	if not pal.command_attack(target):
		Hud.flash("%s is too far away." % target.display_name)
		return
	Audio.play("bite", pal.global_position)
	Hud.flash("%s attacks the %s!" % [pal.display_name, target.display_name])


func _pal_under_reticule(origin: Vector3, aim: Vector3) -> Pal:
	var best: Pal = null
	var best_along := Tuning.CUBE_AIM_DISTANCE
	for node in get_tree().get_nodes_in_group("pal"):
		var pal := node as Pal
		if pal == null or pal == mount or pal.caught or pal.dying or not pal.visible:
			continue
		var centre: Vector3 = pal.get_node("Collision").global_position \
			if pal.has_node("Collision") else pal.global_position
		var to_pal := centre - origin
		var along := to_pal.dot(aim)
		if along < 0.0 or along > Tuning.CUBE_AIM_DISTANCE:
			continue
		var off_ray := (to_pal - aim * along).length()
		var lock_radius: float = Tuning.CUBE_AIM_ASSIST_RADIUS \
			+ along * Tuning.CUBE_AIM_ASSIST_GROWTH
		if off_ray <= lock_radius and along < best_along:
			best = pal
			best_along = along
	return best


## Ballistic launch velocity through `target` under the cube's gravity.
## Horizontal pace is the design knob; the arc height follows from it.
func _lob_velocity(from: Vector3, target: Vector3) -> Vector3:
	var flat := target - from
	var rise := flat.y
	flat.y = 0.0
	var t := clampf(
		flat.length() / Tuning.CUBE_LOB_SPEED,
		Tuning.CUBE_LOB_TIME_MIN,
		Tuning.CUBE_LOB_TIME_MAX,
	)
	var vel := flat / t
	vel.y = rise / t + 0.5 * Tuning.CUBE_GRAVITY * t
	return vel


func _on_cube_resolved(pal: Node, success: bool) -> void:
	if pal and success:
		Hud.flash("Caught %s!" % pal.display_name)
	elif pal:
		Hud.flash("%s broke free!" % pal.display_name)


## --- Gathering ------------------------------------------------------------

func _punch() -> void:
	var forward := -pivot.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	# Riding a spitter turns the attack button into a spit. Gated on the
	# MOUNT's own ability, not on a species name: the Wolf and the Mudwader
	# are rideable too and have to keep biting from the saddle.
	if mount and mount.can_spit():
		_rider_spit(forward)
		return
	var best: Node3D = null
	var best_dist := Tuning.GATHER_RANGE
	for node in get_tree().get_nodes_in_group("resource_node"):
		if not node.is_available():
			continue
		var to_node: Vector3 = node.global_position - global_position
		to_node.y = 0.0
		var dist := to_node.length()
		if dist < best_dist and to_node.normalized().dot(forward) > Tuning.GATHER_FACING_DOT:
			best = node
			best_dist = dist
	for node in get_tree().get_nodes_in_group("pal"):
		var pal := node as Pal
		if pal == null or pal.caught or pal.dying or not pal.visible:
			continue
		var to_pal: Vector3 = pal.global_position - global_position
		to_pal.y = 0.0
		var dist := to_pal.length()
		if dist < best_dist and to_pal.normalized().dot(forward) > Tuning.GATHER_FACING_DOT:
			best = pal
			best_dist = dist
	_bite()
	if best is Pal:
		# Scaled by the damage the swing actually deals, so the demon's buff
		# is felt on every punch rather than only in how fast things die.
		kick(minf(
			Pal.player_punch_damage() * Tuning.SHAKE_PUNCH_PER_DAMAGE,
			Tuning.SHAKE_PUNCH_MAX,
		))
		(best as Pal).take_hit(global_position)
	elif best:
		best.punch()
	else:
		Audio.play("whiff", global_position)


## Spit from the saddle, along `forward`, which is the CAMERA's flattened
## heading and not the mount's. The player aims with the camera in every other
## part of this game, and a shot that left along the animal's nose while the
## crosshair pointed elsewhere would read as a bug.
##
## Godot forward is -Z, so `forward` here is already `-pivot.basis.z` flattened
## and normalised, exactly as the melee facing test uses it. Orientation has
## been wrong in this project four times, so test/llama_test.gd asserts the wad
## travels the way the pivot points for two separate headings rather than
## trusting the sign.
##
## The cooldown is the whole balance lever: a fast mount plus an unlimited
## ranged attack outranges everything alive.
func _rider_spit(forward: Vector3) -> void:
	if _rider_spit_cooldown > 0.0:
		return
	_rider_spit_cooldown = Tuning.RIDER_SPIT_COOLDOWN
	# Lethal and credited, exactly like the punch it replaces: it is the
	# player's attack, so a kill from the saddle pays the drop and the XP.
	mount.spit_along(forward, Tuning.RIDER_SPIT_RANGE, Spit.Mode.RIDER)
	kick(minf(
		Pal.player_punch_damage() * Tuning.SHAKE_PUNCH_PER_DAMAGE,
		Tuning.SHAKE_PUNCH_MAX,
	))


## The swing itself, played whether or not it lands. Without this the most
## pressed button in the game moves nothing on screen.
func _bite() -> void:
	if _anim == null or not _anim.has_animation("Bite_Front"):
		return
	# Restart rather than play, so back-to-back bites all animate.
	_anim.stop()
	_anim.play("Bite_Front")
	_bite_left = Tuning.BITE_ANIM_TIME


## --- Riding ---------------------------------------------------------------

## Swapping the active pal stows it, collider and all. Riding one while that
## happens drops the player through the world, since the rider's own collider
## is off, so step off first.
func _cycle_party(step: int) -> void:
	if mount and not _dismount():
		return
	Party.cycle(global_position, step)


func _toggle_ride() -> void:
	if mount:
		_dismount()
		return
	var best: Pal = null
	var best_dist := Tuning.RIDE_MOUNT_DISTANCE
	for node in get_tree().get_nodes_in_group("pal"):
		var pal := node as Pal
		if pal == null or not pal.rideable or not pal.caught:
			continue
		var d := global_position.distance_to(pal.global_position)
		if d < best_dist:
			best = pal
			best_dist = d
	if best:
		mount = best
		mount.state = Pal.State.RIDDEN
		# Armed from where the mount is standing, so mounting one already in
		# the water does not fire a splash the player never crossed into.
		_was_wading = _mount_is_wading()
		# Riding puts us inside the pal's collider, which would jam its
		# move_and_slide against ours every frame.
		_set_collision_enabled(false)
		# A swimmer is the only way into the shallows, so the shore wall
		# stands down for as long as one is being ridden.
		_set_shore_wall_enabled(not mount.swimmer)


func _dismount(force := false) -> bool:
	var landing: Variant = _safe_dismount_position(mount)
	if landing == null:
		if not force:
			Hud.flash("No safe place to dismount.")
			return false
		landing = mount.global_position + Vector3.UP * Tuning.RIDE_DISMOUNT_UP
	var old_mount := mount
	old_mount.state = Pal.State.FOLLOW
	# _ride used to reset the sink every frame; with it tweened, a dismount
	# has to put the model back or the pal follows you ashore half-buried.
	if _sink_tween:
		_sink_tween.kill()
		_sink_tween = null
	old_mount.sink_model(Tuning.FISH_SINK if old_mount.water_only else 0.0)
	_was_wading = false
	mount = null
	_set_collision_enabled(true)
	_set_shore_wall_enabled(true)
	global_position = landing
	velocity = Vector3.ZERO
	_record_trail()
	return true


func _safe_dismount_position(from_mount: Pal) -> Variant:
	var mount_basis := from_mount.global_transform.basis
	var candidates: Array[Vector3] = [
		mount_basis.x, -mount_basis.x, -mount_basis.z, mount_basis.z,
	]
	# Out in the shallows none of the four sides is land, so try straight back
	# towards the island first. Without this a swimmer in the water could only
	# ever refuse, and the rider would be stuck aboard.
	var inland := -Vector3(
		from_mount.global_position.x, 0.0, from_mount.global_position.z
	)
	if not Zone.is_inside(get_world_3d(), from_mount.global_position, Zone.Kind.LAND):
		var beached: Variant = _beach_dismount_position(from_mount, inland)
		if beached != null:
			return beached
	for dir in candidates:
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		var landing: Vector3 = (
			from_mount.global_position
			+ dir.normalized() * Tuning.RIDE_DISMOUNT_SIDE
			+ Vector3.UP * Tuning.RIDE_DISMOUNT_UP
		)
		if _dismount_spot_is_safe(landing, from_mount):
			return landing
	return null


## Walk inland from a mount in the water until a spot on land is clear. Steps
## by the same clearance the four-way probe insets by, so the first hit is
## just inside the shore wall rather than flush against it.
func _beach_dismount_position(from_mount: Pal, inland: Vector3) -> Variant:
	if inland.length() < 0.01:
		return null
	var dir := inland.normalized()
	var start := Vector3(from_mount.global_position.x, 0.0, from_mount.global_position.z)
	var out := start.length()
	var step := Tuning.RIDE_DISMOUNT_CLEARANCE
	var tries := int((out - Tuning.SHORE_WALL_RADIUS) / step) + Tuning.DISMOUNT_BEACH_STEPS
	for i in maxi(tries, 1):
		var landing := (
			start
			+ dir * (step * (i + 1))
			+ Vector3.UP * Tuning.RIDE_DISMOUNT_UP
		)
		if _dismount_spot_is_safe(landing, from_mount):
			return landing
	return null


func _dismount_spot_is_safe(landing: Vector3, from_mount: Pal) -> bool:
	# Step in from the landing spot before asking: the zone edge is the shore
	# wall itself, and dismounting flush against it leaves no room to stand.
	var outward := Vector3(landing.x, 0.0, landing.z).normalized()
	var inset := outward * Tuning.RIDE_DISMOUNT_CLEARANCE
	if not Zone.is_inside(get_world_3d(), landing + inset, Zone.Kind.LAND):
		return false

	var shape_node: CollisionShape3D = $CollisionShape3D
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape_node.shape
	params.transform = Transform3D(Basis.IDENTITY, landing + shape_node.position)
	params.collision_mask = collision_mask
	params.exclude = [get_rid(), from_mount.get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(params, 8)
	for hit in hits:
		var collider := hit.collider as Node
		if collider and collider.name == "GroundBody":
			continue
		return false
	return true


## The sink is a tween rather than a set: dropping SWIM_SINK in one frame
## reads as the model teleporting. Entering the water also splashes and kicks
## the camera; leaving it just rises, since climbing out is not the payoff.
func _enter_water(wading: bool) -> void:
	if _sink_tween:
		_sink_tween.kill()
	var to := Tuning.SWIM_SINK if wading else 0.0
	var from: float = -mount._model_root.position.y
	_sink_tween = create_tween()
	_sink_tween.tween_method(
		mount.sink_model, from, to, Tuning.SWIM_SINK_TIME
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	if wading:
		Audio.play("splash", mount.global_position)
		kick(Tuning.SHAKE_SPLASH)


## Crossing onto the scorched ground. Polled on the prompt cadence rather than
## every frame, and fired on the edge only: standing on the ash is not news.
func _tick_ash(delta: float) -> void:
	_ash_poll -= delta
	if _ash_poll > 0.0:
		return
	_ash_poll = Tuning.PROMPT_POLL_INTERVAL
	var inside := Zone.is_inside(get_world_3d(), global_position, Zone.Kind.ASH)
	if inside == _was_in_ash:
		return
	_was_in_ash = inside
	if inside:
		Audio.play("ash_enter", global_position)
		Hud.flash(Tuning.ASH_ENTER_MESSAGE)


## A swimmer off the land is in the water; anything else never is.
func _mount_is_wading() -> bool:
	if mount == null or not mount.swimmer:
		return false
	return not Zone.is_inside(get_world_3d(), mount.global_position, Zone.Kind.LAND)


## Horizontal direction the body faces. Godot forward: -Z.
func facing() -> Vector3:
	var f := -body.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _find_anim(n: Node) -> AnimationPlayer:
	for c in n.get_children():
		if c is AnimationPlayer:
			return c
		var found := _find_anim(c)
		if found:
			return found
	return null


func _animate(direction: Vector3) -> void:
	if _anim == null or _bite_left > 0.0:
		return
	var want := "Walk" if direction else "Idle"
	if not is_on_floor() and _anim.has_animation("Jump"):
		want = "Jump"
	if _anim.has_animation(want) and _anim.current_animation != want:
		_anim.play(want)


func _set_collision_enabled(on: bool) -> void:
	$CollisionShape3D.disabled = not on


## The shore wall's segments, toggled as one. Disabling the shapes rather
## than the body keeps the node in the tree, so the ride can put it back
## without rebuilding the ring.
func _set_shore_wall_enabled(on: bool) -> void:
	var wall := get_tree().get_root().find_child("ShoreWall", true, false)
	if wall == null:
		return
	for child in wall.get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", not on)


## While mounted the pal does the moving and we sit on its seat.
func _ride(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var pivot_basis := pivot.global_transform.basis
	var direction := (pivot_basis.x * input.x + pivot_basis.z * input.y)
	direction.y = 0.0
	direction = direction.normalized()

	# The ground is one flat plane at y = 0, so the shallows are walked on at
	# grass height. Wading is faked by dropping the model and slowing down.
	var wading := _mount_is_wading()
	var speed: float = (
		Tuning.RIDE_SPEED * Tuning.SWIM_SPEED_FACTOR if wading else Tuning.RIDE_SPEED
	)
	if wading != _was_wading:
		_was_wading = wading
		_enter_water(wading)

	if not mount.is_on_floor():
		mount.velocity += get_gravity() * delta
	if direction:
		mount.velocity.x = direction.x * speed
		mount.velocity.z = direction.z * speed
		mount.face(direction, delta, Tuning.RIDE_TURN_SPEED)
		mount._play("Walk")
	else:
		mount.velocity.x = 0.0
		mount.velocity.z = 0.0
		mount._play("Idle")
	mount.move_and_slide()

	global_position = mount.seat_position()
	velocity = Vector3.ZERO
