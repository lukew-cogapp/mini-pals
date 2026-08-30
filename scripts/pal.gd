extends CharacterBody3D
class_name Pal
## A creature that wanders, flees when approached, and once caught follows the
## player and can be ridden.

enum State { WANDER, IDLE, FLEE, FOLLOW, RIDDEN }

@export var display_name := "Wolf"
@export var rideable := false

var state: State = State.IDLE
var caught := false

var _home: Vector3
var _target: Vector3
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _player: Node3D

@onready var _model_root: Node3D = $Model
@onready var _anim: AnimationPlayer = _find_anim(self)


func _ready() -> void:
	_rng.randomize()
	_home = global_position
	_player = get_tree().get_first_node_in_group("player")
	_enter_idle()


func _find_anim(n: Node) -> AnimationPlayer:
	for c in n.get_children():
		if c is AnimationPlayer:
			return c
		var found := _find_anim(c)
		if found:
			return found
	return null


func _play(anim: String) -> void:
	if _anim and _anim.has_animation(anim) and _anim.current_animation != anim:
		_anim.play(anim)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	match state:
		State.RIDDEN:
			return  # The rider drives us; see rider.gd.
		State.IDLE:
			_tick_idle(delta)
		State.WANDER:
			_tick_wander(delta)
		State.FLEE:
			_tick_flee(delta)
		State.FOLLOW:
			_tick_follow(delta)

	move_and_slide()


func _tick_idle(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_play("Idle")
	_timer -= delta
	if _threat_near():
		_enter_flee()
	elif _timer <= 0.0:
		_enter_wander()


func _tick_wander(delta: float) -> void:
	if _threat_near():
		_enter_flee()
		return
	_move_towards(_target, Tuning.PAL_WALK_SPEED, delta)
	_play("Walk")
	if _flat_distance(_target) < 1.0:
		_enter_idle()


func _tick_flee(delta: float) -> void:
	if not _threat_near():
		_enter_idle()
		return
	var away := global_position - _player.global_position
	away.y = 0.0
	_move_towards(global_position + away.normalized() * 4.0, Tuning.PAL_FLEE_SPEED, delta)
	_play("Walk")


func _tick_follow(delta: float) -> void:
	if _player == null:
		return
	if _flat_distance(_player.global_position) > Tuning.PAL_FOLLOW_DISTANCE:
		_move_towards(_player.global_position, Tuning.PAL_FOLLOW_SPEED, delta)
		_play("Walk")
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_play("Idle")


func _move_towards(point: Vector3, speed: float, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	face(dir, delta, Tuning.PAL_TURN_SPEED)


func face(dir: Vector3, delta: float, speed: float) -> void:
	var target := atan2(-dir.x, -dir.z)
	_model_root.rotation.y = lerp_angle(_model_root.rotation.y, target, speed * delta)


func _flat_distance(point: Vector3) -> float:
	var d := point - global_position
	d.y = 0.0
	return d.length()


func _threat_near() -> bool:
	if caught or _player == null:
		return false
	return _flat_distance(_player.global_position) < Tuning.PAL_FLEE_DISTANCE


func _enter_idle() -> void:
	state = State.IDLE
	_timer = _rng.randf_range(Tuning.PAL_IDLE_MIN, Tuning.PAL_IDLE_MAX)


func _enter_wander() -> void:
	state = State.WANDER
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(2.0, Tuning.PAL_WANDER_RADIUS)
	_target = _home + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _enter_flee() -> void:
	state = State.FLEE


## Called by the sphere on a successful catch.
func on_caught() -> void:
	caught = true
	state = State.FOLLOW
