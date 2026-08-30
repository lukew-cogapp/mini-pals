extends CharacterBody3D
class_name Pal
## A creature that wanders, flees when approached, and once caught follows the
## player and can be ridden. Punched (or aggressive by species) it hunts the
## player instead. A caught pal never attacks the player, but does step in
## against whatever is hostile to them, always stopping short of the kill.

enum State { WANDER, IDLE, FLEE, FOLLOW, RIDDEN, ATTACK, DEFEND }

@export var display_name := "Wolf"
@export var rideable := false
## Hunts the player on sight instead of fleeing. Never flees.
@export var aggressive := false
## Wild spawn level band, so species map to a difficulty gradient.
@export var level_min := 1
@export var level_max := 5
@export var drop_item := "pelt"
@export var drop_item_name := "Pelt"
## Passive buff granted to the player while this pal is the active one.
## Effect is buff_per_level * level; kinds and caps live in Party and Tuning.
@export var buff_kind: StringName = &""
@export var buff_per_level := 0.0

var state: State = State.IDLE
var caught := false
var level := 1  ## Set by scenery before add_child; _ready derives hp from it.
var hp := 1
var max_hp := 1
var dying := false

var _home: Vector3
var _target: Vector3
var _timer := 0.0
var _hit_stun := 0.0
var _aggro := 0.0
var _attack_cooldown := 0.0
var _attack_without_hit := 0.0
var _sight_aggro_suppressed := false
var _defend_target: Pal = null
var _rng := RandomNumberGenerator.new()
var _side := 1.0
var _player: Node3D:
	get:
		# Resolved on demand: pals are spawned before the player joins its
		# group, so a lookup in _ready comes back null.
		if _player_cache == null or not is_instance_valid(_player_cache):
			_player_cache = get_tree().get_first_node_in_group("player")
		return _player_cache

var _player_cache: Node3D
var _label: Label3D

@onready var _model_root: Node3D = $Model
@onready var _anim: AnimationPlayer = _find_anim(self)


func _ready() -> void:
	_rng.randomize()
	_home = global_position
	max_hp = _level_hp()
	hp = max_hp
	# Grow the model only; the collider stays put so cubes still land.
	var grow := 1.0 + (level - 1) * Tuning.PAL_LEVEL_SCALE_STEP
	_model_root.scale = Vector3.ONE * grow
	_make_label(grow)
	_enter_idle()


func _make_label(grow: float) -> void:
	_label = Label3D.new()
	_label.text = "Lv%d %s" % [level, display_name]
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = Tuning.PAL_LABEL_FONT_SIZE
	_label.outline_size = Tuning.PAL_LABEL_OUTLINE
	_label.position = Vector3.UP * Tuning.PAL_LABEL_HEIGHT * grow
	add_child(_label)


func _update_label() -> void:
	if _label == null:
		return
	if caught or dying:
		_label.visible = false
		return
	_label.text = "Lv%d %s" % [level, display_name]


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

	_update_label()

	# Knockback plays out before the state ticks retake the velocity.
	if _hit_stun > 0.0:
		_hit_stun -= delta
		move_and_slide()
		return

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
		State.ATTACK:
			_tick_attack(delta)
		State.DEFEND:
			_tick_defend(delta)

	move_and_slide()


func _tick_idle(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_play("Idle")
	_timer -= delta
	if _wants_attack():
		_enter_attack()
	elif _threat_near():
		_enter_flee()
	elif _timer <= 0.0:
		_enter_wander()


func _tick_wander(delta: float) -> void:
	if _wants_attack():
		_enter_attack()
		return
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

	_defend_target = _find_defend_target()
	if _defend_target:
		state = State.DEFEND
		_attack_cooldown = 0.0
		return

	# Walk the player's old footsteps rather than their current position, so
	# the pal trails behind instead of homing in and snapping about.
	var target: Vector3 = (
		_player.trail_point_at(Tuning.PAL_FOLLOW_DISTANCE)
		if _player.has_method("trail_point_at")
		else _player.global_position
	)
	# Sit off to one side so the player does not walk through their own pal.
	target += _player.global_transform.basis.x * _side * Tuning.FOLLOW_SIDE_OFFSET

	var to_target := target - global_position
	to_target.y = 0.0
	var gap := to_target.length()

	# Ease off as it arrives instead of stopping dead, which reads as a glitch.
	var wanted := Vector3.ZERO
	if gap > 0.15:
		# Faster the further behind it is, so it closes without ever sprinting
		# from a standstill.
		var speed: float = lerpf(
			Tuning.PAL_FOLLOW_SPEED,
			Tuning.FOLLOW_CATCHUP_SPEED,
			clampf(gap / Tuning.FOLLOW_CATCHUP_RADIUS, 0.0, 1.0),
		)
		if gap < Tuning.FOLLOW_SLOW_RADIUS:
			speed *= maxf(gap / Tuning.FOLLOW_SLOW_RADIUS, 0.35)
		wanted = to_target.normalized() * speed

	velocity.x = move_toward(velocity.x, wanted.x, Tuning.FOLLOW_ACCEL * delta * 10.0)
	velocity.z = move_toward(velocity.z, wanted.z, Tuning.FOLLOW_ACCEL * delta * 10.0)

	var moving := Vector2(velocity.x, velocity.z).length()
	if moving > 0.4:
		face(Vector3(velocity.x, 0.0, velocity.z).normalized(), delta, Tuning.PAL_TURN_SPEED)
		_play("Walk")
	else:
		_play("Idle")


## --- Follower defence ------------------------------------------------------

## A hostile worth stepping in against: one already fighting the player, or an
## aggressive species close enough to be about to. Kept pals are never targets,
## so a follower cannot pick a fight with the rest of the party.
func _is_hostile(other: Pal) -> bool:
	if other == self or other.caught or other.dying or not other.visible:
		return false
	if other.state == State.ATTACK:
		return true
	return (
		other.aggressive
		and other._flat_distance(_player.global_position) < Tuning.PAL_AGGRO_RADIUS
	)


func _find_defend_target() -> Pal:
	if not caught or _player == null:
		return null
	var best: Pal = null
	var best_dist := Tuning.FOLLOWER_DEFEND_RADIUS
	for node in get_tree().get_nodes_in_group("pal"):
		var other := node as Pal
		if other == null or not _is_hostile(other):
			continue
		var dist := _flat_distance(other.global_position)
		if dist < best_dist:
			best = other
			best_dist = dist
	return best


## The target stops being worth fighting once it is dead, caught, calmed, or
## the player has walked far enough that following matters more.
func _defend_target_valid() -> bool:
	return (
		_defend_target != null
		and is_instance_valid(_defend_target)
		and _player != null
		and _is_hostile(_defend_target)
		and _flat_distance(_player.global_position) < Tuning.FOLLOWER_LEASH
	)


func _tick_defend(delta: float) -> void:
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if not _defend_target_valid():
		_defend_target = null
		state = State.FOLLOW
		return

	var dist := _flat_distance(_defend_target.global_position)
	if dist > Tuning.FOLLOWER_ATTACK_RANGE:
		_move_towards(_defend_target.global_position, Tuning.FOLLOWER_CHASE_SPEED, delta)
		_play("Run" if _anim and _anim.has_animation("Run") else "Walk")
		return

	velocity.x = 0.0
	velocity.z = 0.0
	var dir := _defend_target.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		face(dir.normalized(), delta, Tuning.PAL_TURN_SPEED)
	if _attack_cooldown <= 0.0:
		_attack_cooldown = Tuning.FOLLOWER_ATTACK_COOLDOWN
		_swing_at(_defend_target)


func _swing_at(target: Pal) -> void:
	if _anim:
		for anim_name in ["Punch", "Bite_Front"]:
			if _anim.has_animation(anim_name):
				_anim.stop()
				_anim.play(anim_name)
				break
	target.take_follower_hit()


## Damage from a caught pal. Clamped to leave the target alive on its last
## hitpoint: a follower that finished a kill would cost the player the catch,
## which is the whole loop. No knockback and no aggro either, so softening a
## target up cannot shove it out of cube range or point it at the player.
func take_follower_hit() -> void:
	if caught or dying or hp <= Tuning.FOLLOWER_MIN_TARGET_HP:
		return
	hp = maxi(hp - Tuning.FOLLOWER_DEFEND_DAMAGE, Tuning.FOLLOWER_MIN_TARGET_HP)
	Audio.play("hit", global_position)
	# The Blob rigs misspell the hit animation; other sets use HitReact.
	if _anim and _anim.has_animation("HitRecieve"):
		_anim.play("HitRecieve")
	elif _anim and _anim.has_animation("HitReact"):
		_anim.play("HitReact")


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
	# Godot forward is -Z; the model is turned to match inside the pal scene.
	# Rotate the whole body, so basis.x stays the pal's right for dismounts.
	var target := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target, speed * delta)


## Where a rider sits: the Seat marker, which turns and scales with the pal.
func seat_position() -> Vector3:
	return $Model/Seat.global_position


func _flat_distance(point: Vector3) -> float:
	var d := point - global_position
	d.y = 0.0
	return d.length()


func _threat_near() -> bool:
	# Aggressive species never flee; they get _wants_attack instead.
	if caught or aggressive or _player == null:
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


func _enter_attack() -> void:
	if caught:
		return
	if state != State.ATTACK:
		_attack_without_hit = 0.0
	state = State.ATTACK


## Aggressive species open hostilities on sight; others only when punched.
func _wants_attack() -> bool:
	if caught or _player == null:
		return false
	if not aggressive:
		return false
	var dist := _flat_distance(_player.global_position)
	if _sight_aggro_suppressed:
		if dist > Tuning.PAL_AGGRO_RADIUS:
			_sight_aggro_suppressed = false
		else:
			return false
	return dist < Tuning.PAL_AGGRO_RADIUS


func _tick_attack(delta: float) -> void:
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_attack_without_hit += delta
	if caught or _player == null:
		_enter_idle()
		return
	if not aggressive:
		_aggro -= delta
		if _aggro <= 0.0:
			_enter_idle()
			return
	var dist := _flat_distance(_player.global_position)
	if dist > Tuning.PAL_CHASE_GIVE_UP:
		_enter_idle()
		return
	if _attack_without_hit >= Tuning.PAL_NO_HIT_GIVE_UP_TIME:
		_give_up_attack()
		return
	if dist > Tuning.PAL_ATTACK_RANGE:
		_move_towards(_player.global_position, Tuning.PAL_CHASE_SPEED, delta)
		# The Big rigs have a Run cycle; the Blobs only Walk.
		_play("Run" if _anim and _anim.has_animation("Run") else "Walk")
		return
	velocity.x = 0.0
	velocity.z = 0.0
	var dir := _player.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		face(dir.normalized(), delta, Tuning.PAL_TURN_SPEED)
	if _attack_cooldown <= 0.0:
		_attack_cooldown = Tuning.PAL_ATTACK_COOLDOWN
		if _swing():
			_attack_without_hit = 0.0


func _give_up_attack() -> void:
	_aggro = 0.0
	_attack_cooldown = 0.0
	_attack_without_hit = 0.0
	if aggressive:
		_sight_aggro_suppressed = true
	_enter_idle()


func _swing() -> bool:
	# Restart rather than _play, so back-to-back swings all animate.
	if _anim:
		for anim_name in ["Punch", "Bite_Front"]:
			if _anim.has_animation(anim_name):
				_anim.stop()
				_anim.play(anim_name)
				break
	if aggressive:
		Audio.play("demon_attack", global_position)
	var dmg := Tuning.AGGRESSIVE_ATTACK_DAMAGE if aggressive else Tuning.PAL_ATTACK_DAMAGE
	if _player.has_method("damage"):
		return _player.damage(dmg, global_position)
	return false


## The player respawned (or caught us): forget the fight.
func clear_aggro() -> void:
	_aggro = 0.0
	_attack_cooldown = 0.0
	_attack_without_hit = 0.0
	_sight_aggro_suppressed = false
	_defend_target = null
	if state == State.ATTACK:
		_enter_idle()


func _level_hp() -> int:
	var v: int = Tuning.PAL_BASE_HP + level * Tuning.PAL_HP_PER_LEVEL
	if aggressive:
		v += Tuning.AGGRESSIVE_BONUS_HP
	return v


## Punched by the player: damage, knockback, and a spell of forced flight.
func take_hit(from: Vector3) -> void:
	if caught or dying:
		return
	# Player levels sharpen the punch, so grinding XP speeds up farming too.
	hp -= Tuning.PUNCH_DAMAGE + int((Party.player_level - 1) * Tuning.PUNCH_DAMAGE_PER_PLAYER_LEVEL)
	Audio.play("hit", global_position)
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	velocity = away * Tuning.PAL_HIT_KNOCKBACK + Vector3.UP * Tuning.PAL_HIT_POP
	_hit_stun = Tuning.PAL_HIT_STUN
	if hp <= 0:
		_die()
		return
	# The Blob rigs misspell the hit animation; other sets use HitReact.
	if _anim and _anim.has_animation("HitRecieve"):
		_anim.play("HitRecieve")
	elif _anim and _anim.has_animation("HitReact"):
		_anim.play("HitReact")
	# Fighting back: a punch makes any pal hostile for a while.
	_aggro = Tuning.PAL_AGGRO_TIME
	_sight_aggro_suppressed = false
	_attack_without_hit = 0.0
	_enter_attack()


func _die() -> void:
	dying = true
	if _label:
		_label.visible = false
	velocity = Vector3.ZERO
	set_physics_process(false)
	$Collision.set_deferred("disabled", true)
	# Out of the group so punches and cubes stop finding the corpse.
	remove_from_group("pal")
	Audio.play("defeat", global_position)
	var n := _grant_drop()
	# A kill is worth half a catch: progress for the cubeless, never parity.
	Party.grant_xp(int(xp_worth() * Tuning.XP_KILL_FACTOR))
	Hud.flash("%s defeated! +%d %s" % [display_name, n, drop_item_name])
	var wait := Tuning.PAL_DEATH_TIME
	if _anim and _anim.has_animation("Death"):
		_anim.play("Death")
		wait = _anim.get_animation("Death").length
	await get_tree().create_timer(wait).timeout
	queue_free()


func _grant_drop() -> int:
	var n := Tuning.PAL_DROP_BASE + int(level / 2.0)
	Inventory.add(drop_item, n)
	return n


## Player XP for catching this pal; a kill pays XP_KILL_FACTOR of it.
func xp_worth() -> int:
	return level * Tuning.XP_PER_PAL_LEVEL


## Low level and missing health both make the ball more likely to hold.
func catch_chance() -> float:
	var missing := 1.0 - float(hp) / float(max_hp)
	var chance := (Tuning.CUBE_CATCH_CHANCE + missing * Tuning.CUBE_CATCH_HEALTH_BONUS) \
		* pow(Tuning.CUBE_CATCH_LEVEL_FALLOFF, level - 1)
	return clampf(chance, Tuning.CUBE_CATCH_MIN, Tuning.CUBE_CATCH_MAX)


## A duplicate catch feeds the kept pal a level instead of joining the party.
func gain_level() -> void:
	level = mini(level + 1, Tuning.PAL_LEVEL_MAX)
	max_hp = _level_hp()
	hp = max_hp
	var grow := 1.0 + (level - 1) * Tuning.PAL_LEVEL_SCALE_STEP
	_model_root.scale = Vector3.ONE * grow
	if _label:
		_label.text = "Lv%d %s" % [level, display_name]
		_label.position = Vector3.UP * Tuning.PAL_LABEL_HEIGHT * grow


## Called by the pal cube on a successful catch. Every catch pays the drop;
## Party.store decides whether the pal joins or merges into a kept one.
func on_caught() -> void:
	caught = true
	clear_aggro()
	if _label:
		_label.visible = false
	_grant_drop()
	Party.grant_xp(xp_worth())
	Party.store(self)


## Stored pals stay in the tree but out of sight, so their home position and
## wander state survive being put away.
func stow() -> void:
	state = State.IDLE
	_defend_target = null
	velocity = Vector3.ZERO
	visible = false
	set_physics_process(false)
	$Collision.set_deferred("disabled", true)


func summon(at: Vector3) -> void:
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	global_position = at
	visible = true
	set_physics_process(true)
	$Collision.set_deferred("disabled", false)
	_defend_target = null
	state = State.FOLLOW
