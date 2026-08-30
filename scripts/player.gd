extends CharacterBody3D
## Third-person player: WASD moves relative to where the camera looks.
## Numbers live in scripts/tuning.gd.

const CUBE_SCENE := preload("res://scenes/pal_cube.tscn")

@onready var pivot: Node3D = $CameraPivot
@onready var body: Node3D = $Body
@onready var _anim: AnimationPlayer = _find_anim(body)

var mount: Pal = null  ## The pal we are riding, if any.

var hp := 0.0  ## Set from Tuning in _ready; autoloads are not up at parse time.
var _spawn := Vector3.ZERO
var _since_hit := 1000.0  ## Long ago, so regen is armed from the start.
var _invuln := 0.0
var _dead := false

func _ready() -> void:
	add_to_group("player")
	_spawn = global_position
	hp = Tuning.PLAYER_MAX_HP
	Hud.set_health(hp, Tuning.PLAYER_MAX_HP)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The arm's shape cast would otherwise hit our own capsule and pull the
	# camera into the player's head.
	$CameraPivot/SpringArm3D.add_excluded_object(get_rid())


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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("throw"):
		_throw_cube()
	elif event.is_action_pressed("ride"):
		_toggle_ride()
	elif event.is_action_pressed("cycle_pal") or event.is_action_pressed("pal_next"):
		Party.cycle(global_position, 1)
	elif event.is_action_pressed("pal_prev"):
		Party.cycle(global_position, -1)
	elif event.is_action_pressed("punch"):
		_punch()
	elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_tick_health(delta)
	if mount:
		_ride(delta)
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = Tuning.PLAYER_JUMP_STRENGTH

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Flatten the camera basis so looking up or down never slows movement.
	var basis := pivot.global_transform.basis
	var direction := (basis.x * input.x + basis.z * input.y)
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
func damage(amount: float, from_position: Vector3) -> void:
	if _dead or _invuln > 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_since_hit = 0.0
	Hud.set_health(hp, Tuning.PLAYER_MAX_HP)
	Audio.play("player_hurt", global_position)
	var away := global_position - from_position
	away.y = 0.0
	if away.length() > 0.01:
		velocity += away.normalized() * Tuning.PLAYER_HIT_KNOCKBACK
	if hp <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	if mount:
		_dismount()
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

func _throw_cube() -> void:
	if not Inventory.remove("cube", 1):
		Hud.flash("No pal cubes. Punch trees and rocks, then craft at the workbench.")
		return
	Audio.play("throw", global_position)
	var cube := CUBE_SCENE.instantiate()
	get_parent().add_child(cube)
	# Cameras look along -Z, so this is where the crosshair points.
	var aim := -pivot.global_transform.basis.z
	# Thrown from the shoulder so the cat's body does not hide it, but aimed
	# from the eyeline, or the side offset makes it fly a parallel line.
	var from := (
		global_position
		+ Vector3.UP * Tuning.CUBE_SPAWN_HEIGHT
		+ aim * Tuning.CUBE_SPAWN_FORWARD
		+ pivot.global_transform.basis.x * Tuning.CUBE_SPAWN_SIDE
	)
	var eye := global_position + Vector3.UP * Tuning.CUBE_SPAWN_HEIGHT
	var target := eye + aim * Tuning.CUBE_AIM_DISTANCE
	cube.throw(from, (target - from).normalized())
	cube.resolved.connect(_on_cube_resolved)


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
	if best is Pal:
		(best as Pal).take_hit(global_position)
	elif best:
		best.punch()


## --- Riding ---------------------------------------------------------------

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
		# Riding puts us inside the pal's collider, which would jam its
		# move_and_slide against ours every frame.
		_set_collision_enabled(false)


func _dismount() -> void:
	# +X is the mount's right side under the -Z-forward convention.
	var landing := (
		mount.global_position
		+ mount.global_transform.basis.x * Tuning.RIDE_DISMOUNT_SIDE
	)
	mount.state = Pal.State.FOLLOW
	mount = null
	_set_collision_enabled(true)
	global_position = landing + Vector3.UP * Tuning.RIDE_DISMOUNT_UP
	velocity = Vector3.ZERO


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
	if _anim == null:
		return
	var want := "Walk" if direction else "Idle"
	if not is_on_floor() and _anim.has_animation("Jump"):
		want = "Jump"
	if _anim.has_animation(want) and _anim.current_animation != want:
		_anim.play(want)


func _set_collision_enabled(on: bool) -> void:
	$CollisionShape3D.disabled = not on


## While mounted the pal does the moving and we sit on its seat.
func _ride(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := pivot.global_transform.basis
	var direction := (basis.x * input.x + basis.z * input.y)
	direction.y = 0.0
	direction = direction.normalized()

	if not mount.is_on_floor():
		mount.velocity += get_gravity() * delta
	if direction:
		mount.velocity.x = direction.x * Tuning.RIDE_SPEED
		mount.velocity.z = direction.z * Tuning.RIDE_SPEED
		mount.face(direction, delta, Tuning.RIDE_TURN_SPEED)
		mount._play("Walk")
	else:
		mount.velocity.x = 0.0
		mount.velocity.z = 0.0
		mount._play("Idle")
	mount.move_and_slide()

	global_position = mount.seat_position()
	velocity = Vector3.ZERO
