extends CharacterBody3D
## Third-person player: WASD moves relative to where the camera looks.
## Numbers live in scripts/tuning.gd.

const SPHERE_SCENE := preload("res://scenes/catch_sphere.tscn")

@onready var pivot: Node3D = $CameraPivot
@onready var body: Node3D = $Body

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
		_throw_sphere()
	elif event.is_action_pressed("ride"):
		_toggle_ride()
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


## --- Catching -------------------------------------------------------------

func _throw_sphere() -> void:
	var sphere := SPHERE_SCENE.instantiate()
	get_parent().add_child(sphere)
	var aim := -pivot.global_transform.basis.z
	sphere.throw(global_position + Vector3.UP * 1.3 + aim * 0.6, aim)
	sphere.resolved.connect(_on_sphere_resolved)


func _on_sphere_resolved(pal: Node, success: bool) -> void:
	if pal and success:
		print("Caught %s!" % pal.display_name)
	elif pal:
		print("%s broke free!" % pal.display_name)


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
