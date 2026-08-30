extends CharacterBody3D
## Third-person player: WASD moves relative to where the camera looks.
## Numbers live in scripts/tuning.gd.

const CUBE_SCENE := preload("res://scenes/pal_cube.tscn")

@onready var pivot: Node3D = $CameraPivot
@onready var body: Node3D = $Body
@onready var _anim: AnimationPlayer = _find_anim(body)

var mount: Pal = null  ## The pal we are riding, if any.

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
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
	elif event.is_action_pressed("cycle_pal"):
		Party.cycle(global_position)
	elif event.is_action_pressed("punch"):
		_punch()
	elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
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
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Face travel direction rather than snapping instantly.
		# Quaternius models put the face on +Z, so +Z leads, not Godot's -Z.
		var target := atan2(direction.x, direction.z)
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


## --- Catching -------------------------------------------------------------

func _throw_cube() -> void:
	if not Inventory.remove("cube", 1):
		Hud.flash("No pal cubes. Punch trees and rocks, then craft at the workbench.")
		return
	Audio.play("throw", global_position)
	var cube := CUBE_SCENE.instantiate()
	get_parent().add_child(cube)
	var aim := -pivot.global_transform.basis.z
	cube.throw(
		global_position + Vector3.UP * Tuning.CUBE_SPAWN_HEIGHT
		+ aim * Tuning.CUBE_SPAWN_FORWARD,
		aim,
	)
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
	if best:
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
	var landing := mount.global_position + mount.global_transform.basis.x * 1.2
	mount.state = Pal.State.FOLLOW
	mount = null
	_set_collision_enabled(true)
	global_position = landing + Vector3.UP * 0.5
	velocity = Vector3.ZERO


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

	global_position = mount.global_position + Vector3.UP * Tuning.RIDE_SEAT_HEIGHT
	velocity = Vector3.ZERO
