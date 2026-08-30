extends CharacterBody3D
## Third-person player: WASD moves relative to where the camera looks.
## Numbers live in scripts/tuning.gd.

@onready var pivot: Node3D = $CameraPivot
@onready var body: Node3D = $Body

func _ready() -> void:
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
	elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
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
		# Negated because -Z is forward in Godot, so atan2(x, z) would face away.
		var target := atan2(-direction.x, -direction.z)
		body.rotation.y = lerp_angle(body.rotation.y, target, Tuning.PLAYER_TURN_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	_try_step_up(direction)


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
