extends CharacterBody3D
class_name Pal
## A creature that wanders, flees when approached, and once caught follows the
## player and can be ridden. Punched (or aggressive by species) it hunts the
## player instead. A caught pal never attacks the player, but does step in
## against whatever is hostile to them, always stopping short of the kill.
## An aggressive wild pal also brawls with other species, and those fights
## kill.

enum State { WANDER, IDLE, FLEE, FOLLOW, RIDDEN, ATTACK, DEFEND, GATHER }

@export var display_name := "Wolf"
@export var rideable := false
## Art scale for this species, multiplied by level growth. The kit models are
## not authored to one size: the fish stands twice as tall as the dog.
@export var model_scale := 1.0
## Pace for this species, multiplying every shared speed constant rather than
## replacing any of them, so a wolf and a Mushroom King no longer move
## identically and the walk/flee/chase/follow relationship still lives in
## tuning.gd. Read through `speed()`, which clamps it. Riding is deliberately
## unscaled: a mount's pace is RIDE_SPEED, the player's own knob.
@export var speed_factor := 1.0
## Carries a rider past the shore wall. The wall's collision drops while a
## swimmer is ridden, so this flag is what opens the shallows.
@export var swimmer := false
## Confined to the shallow zone for spawning and wandering alike. Fish exist
## to be caught from a mount, so one that could walk ashore would break the
## gate the mount is there to open.
@export var water_only := false
## Confined to the cave, spawning and wandering alike. The cave species is
## the reward for finding the cave, so one that wandered out onto the open
## grass would be met before the place it lives in.
@export var cave_only := false
## How this species reacts to the player. One enum rather than a pair of
## flags, because "aggressive and skittish" is not a thing a pal can be and
## two booleans would let a scene say it.
##   SKITTISH   flees when the player closes in. Small creatures.
##   NEUTRAL    neither flees nor starts anything, but hits back when bitten.
##   AGGRESSIVE hunts the player on sight, and brawls with other species.
enum Temperament { SKITTISH, NEUTRAL, AGGRESSIVE }
@export var temperament: Temperament = Temperament.SKITTISH
## Wild spawn level band, so species map to a difficulty gradient.
@export var level_min := 1
@export var level_max := 5
@export var drop_item := "pelt"
@export var drop_item_name := "Pelt"
## Passive buff granted to the player while this pal is the active one.
## Effect is buff_per_level * level; kinds and caps live in Party and Tuning.
@export var buff_kind: StringName = &""
@export var buff_per_level := 0.0
## Attacks at SPIT_RANGE with a projectile instead of closing to melee. One
## flag rather than a per-species range, because every consequence of fighting
## at 8 m is the same in all three fights a pal can be in, and `attack_range()`
## is the single place any of them reads it.
@export var ranged := false
## The wad a ranged species fires. Left null for everything else, so a species
## that forgot to wire it falls back to melee rather than standing there
## harmlessly out of reach.
@export var spit_scene: PackedScene

## Reads across the file are all about hunting, so they keep the old name.
var aggressive: bool:
	get:
		return temperament == Temperament.AGGRESSIVE

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
var _alert_time := 0.0
## Per-instance idle pacing, rolled once. Some pals dawdle, some fidget.
var _idle_pace := 1.0
var _sight_aggro_suppressed := false
## Seconds left in which a death here still pays the player, reset by a hit
## in either direction. See _die and _credit_player.
var _credit := 0.0
var _defend_target: Pal = null
## Seconds left on a player-issued attack order. While it runs _defend_target
## is the commanded one and _find_defend_target is not consulted.
var _command_time := 0.0
var _rival: Pal = null
var _rival_scan := 0.0
var _rival_fight := 0.0
var _gather_target: Node3D = null
var _gather_cooldown := 0.0
var _gather_rest := 0.0
var _stuck_time := 0.0
var _escape_time := 0.0
var _escape_dir := Vector3.FORWARD
var _last_flat_position := Vector3.ZERO
var _last_move_frame := -1
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
var _bar_shadow: MeshInstance3D
var _bar_back: MeshInstance3D
var _bar_track: MeshInstance3D
var _bar_fill: MeshInstance3D
var _bar_sheen: MeshInstance3D
var _bar_check := 0.0

@onready var _model_root: Node3D = $Model
@onready var _anim: AnimationPlayer = _find_anim(self)


func _ready() -> void:
	_rng.randomize()
	_idle_pace = _rng.randf_range(
		Tuning.PAL_IDLE_PACE_MIN, Tuning.PAL_IDLE_PACE_MAX
	)
	_home = global_position
	max_hp = _level_hp()
	hp = max_hp
	# Grow the model only; the collider stays put so cubes still land.
	var grow := model_scale * (1.0 + (level - 1) * Tuning.PAL_LEVEL_SCALE_STEP)
	_model_root.scale = Vector3.ONE * grow
	# Fish stand on the same flat ground plane as everything else, which sits
	# above the shallow surface, so unsunk they float clear of the water they
	# are supposed to be swimming in.
	if water_only:
		sink_model(Tuning.FISH_SINK)
	_make_label(grow)
	_make_health_bar(grow)
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
		_set_bar_visible(false)
		return
	_label.text = "Lv%d %s" % [level, display_name]
	_tick_health_bar()


## --- Health bar ------------------------------------------------------------

## Five billboarded quads stacked at one origin: a translucent drop shadow, a
## dark backing that doubles as the border, a flat track for the empty part,
## the coloured fill, and a lighter sheen strip along the top of the fill. Built once in _ready and rescaled
## thereafter, never rebuilt: there can be thirty pals in the world and a
## rebuild per frame per pal would be thirty allocations a frame.
##
## The layering is what makes the bar read against both the pale grass and
## the scorched ash. The shadow gives a dark bar an edge over dark ground,
## the backing gives a bright fill one over bright ground, and the sheen
## stops the fill looking like a flat sticker.
func _make_health_bar(grow: float) -> void:
	var top := Tuning.PAL_LABEL_HEIGHT * grow + Tuning.PAL_HEALTH_BAR_RISE * grow
	var w := Tuning.PAL_HEALTH_BAR_WIDTH
	var h := Tuning.PAL_HEALTH_BAR_HEIGHT

	# Priority orders the four against each other; they sit at one origin and
	# no_depth_test means nothing else can separate them.
	_bar_shadow = _bar_quad(Tuning.PAL_HEALTH_BAR_SHADOW_COLOUR, 1)
	_bar_shadow.name = "BarShadow"
	_bar_shadow.position = Vector3.UP * top
	var grown := h * Tuning.PAL_HEALTH_BAR_SHADOW_GROW
	_bar_shadow.scale = Vector3(w + grown, h + grown, 1.0)
	# Offset inside the mesh, not by the node: a billboard ignores the node
	# basis, so a node-space nudge would swing round the bar with the camera.
	var shadow_quad: QuadMesh = _bar_shadow.mesh
	var drop := Tuning.PAL_HEALTH_BAR_SHADOW_DROP * h / (h + grown)
	shadow_quad.center_offset = Vector3(drop, -drop, 0.0)
	add_child(_bar_shadow)

	_bar_back = _bar_quad(Tuning.PAL_HEALTH_BAR_BACK_COLOUR, 2)
	_bar_back.name = "BarBacking"
	_bar_back.position = Vector3.UP * top
	_bar_back.scale = Vector3(w, h, 1.0)
	add_child(_bar_back)

	# Siblings, not children. A billboard is vertex work in the material and
	# does not touch the node basis, so a child offset stays in world space
	# and swings out of the bar as the camera moves round. Every quad sits at
	# the same origin instead, and is shifted inside its own mesh.
	# The empty part of the bar, full width and inside the border, so missing
	# health reads as an unfilled track rather than as a hole in the backing.
	# Fixed size, so it is never touched again after this.
	_bar_track = _bar_quad(Tuning.PAL_HEALTH_BAR_TRACK_COLOUR, 3)
	_bar_track.name = "BarTrack"
	_bar_track.position = _bar_back.position
	_bar_track.scale = Vector3(
		w * (1.0 - Tuning.PAL_HEALTH_BAR_BORDER),
		h * (1.0 - Tuning.PAL_HEALTH_BAR_BORDER * 2.0),
		1.0,
	)
	add_child(_bar_track)

	_bar_fill = _bar_quad(Tuning.PAL_HEALTH_BAR_FILL_COLOUR, 4)
	_bar_fill.name = "BarFill"
	_bar_fill.position = _bar_back.position
	add_child(_bar_fill)

	_bar_sheen = _bar_quad(Tuning.PAL_HEALTH_BAR_FILL_COLOUR, 5)
	_bar_sheen.name = "BarSheen"
	_bar_sheen.position = _bar_back.position
	add_child(_bar_sheen)

	_refresh_bar()
	_set_bar_visible(false)


func _bar_quad(colour: Color, priority: int) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# The billboard shader rebuilds the model matrix from scratch and throws
	# the node's scale away with it, so without this every bar renders as the
	# QuadMesh's default 1m square regardless of what it was scaled to.
	mat.billboard_keep_scale = true
	# The shadow is the only translucent layer, and an opaque quad drawn with
	# alpha still costs a sort, so only it asks for blending.
	if colour.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Drawn on top of the pal, so a bar behind a shoulder is still readable.
	mat.no_depth_test = true
	mat.render_priority = priority
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad


## Distance is sampled on an interval rather than every frame: it changes at
## walking pace and thirty pals asking every frame is work for nothing.
func _tick_health_bar() -> void:
	if _bar_back == null:
		return
	_bar_check -= get_physics_process_delta_time()
	if _bar_check > 0.0:
		return
	_bar_check = Tuning.PAL_HEALTH_BAR_CHECK_INTERVAL
	var show := _bar_wanted()
	_set_bar_visible(show)
	if show:
		_refresh_bar()


## Near enough, and either being looked at or locked by the aim reticule.
##
## Distance alone put a bar over every pal in an 18 m circle, which with
## twenty of them on screen is a field of floating UI rather than a readout.
## The lock overrides the cone because it is by definition what the player is
## aiming at, and the throw's own assist can hold it a little off centre.
func _bar_wanted() -> bool:
	if _player == null:
		return false
	if _flat_distance(_player.global_position) >= Tuning.PAL_HEALTH_BAR_DISTANCE:
		return false
	if _player.get("locked_pal") == self:
		return true
	return _faced_by_player()


## Whether the player's camera is pointed at us.
##
## Measured flat, against the CameraPivot's forward, which is -basis.z like
## everything else in this project. Orientation has been wrong here four
## times, so test/juice2_test.gd asserts the sign rather than trusting it.
## A player with no pivot (a bare stand-in in a test) is treated as facing
## everything, so the distance gate is still what those tests measure.
func _faced_by_player() -> bool:
	if not _player.has_node("CameraPivot"):
		return true
	var pivot: Node3D = _player.get_node("CameraPivot")
	var forward := -pivot.global_transform.basis.z
	forward.y = 0.0
	var to_us := global_position - _player.global_position
	to_us.y = 0.0
	if to_us.length() < 0.01 or forward.length() < 0.01:
		return true
	return to_us.normalized().dot(forward.normalized()) >= Tuning.PAL_HEALTH_BAR_FACING_DOT


func _set_bar_visible(on: bool) -> void:
	for quad in [_bar_shadow, _bar_back, _bar_track, _bar_fill, _bar_sheen]:
		if quad:
			quad.visible = on


## The fill colour at a given health fraction: green down to the mid stop,
## then a slide through amber to red. The old single step at 0.35 snapped
## between two hits and gave no warning the next one mattered.
func bar_colour(frac: float) -> Color:
	var mid := Tuning.PAL_HEALTH_BAR_MID_FRACTION
	var low := Tuning.PAL_HEALTH_BAR_LOW_FRACTION
	if frac >= mid:
		return Tuning.PAL_HEALTH_BAR_FILL_COLOUR.lerp(
			Tuning.PAL_HEALTH_BAR_MID_COLOUR,
			inverse_lerp(1.0, mid, minf(frac, 1.0)),
		)
	return Tuning.PAL_HEALTH_BAR_MID_COLOUR.lerp(
		Tuning.PAL_HEALTH_BAR_LOW_COLOUR,
		clampf(inverse_lerp(mid, low, frac), 0.0, 1.0),
	)


## Fill width is the hp fraction, inset by a border on all sides so the dark
## backing shows as an outline. The sheen tracks the fill exactly, sitting on
## its top edge and shrinking with it.
func _refresh_bar() -> void:
	var frac := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	var border := Tuning.PAL_HEALTH_BAR_BORDER
	var inner := 1.0 - border
	var w := Tuning.PAL_HEALTH_BAR_WIDTH
	var h := Tuning.PAL_HEALTH_BAR_HEIGHT
	var fill_w := w * inner * frac
	var fill_h := h * (1.0 - border * 2.0)
	_bar_fill.scale = Vector3(fill_w, fill_h, 1.0)
	# Shifted in the mesh rather than by the node, which the billboard would
	# ignore. center_offset is in the quad's own units, so it is divided by
	# the scale the node then applies.
	var quad: QuadMesh = _bar_fill.mesh
	var left_shift := -0.5 * (1.0 - frac) / maxf(frac, 0.001)
	quad.center_offset.x = left_shift

	var colour := bar_colour(frac)
	var fill_mat: StandardMaterial3D = _bar_fill.material_override
	fill_mat.albedo_color = colour

	# Same left edge and same width as the fill, a fraction of its height,
	# pinned to its top. Both offsets are in the sheen's own units, so each is
	# divided by the sheen scale that follows.
	var sheen_h := fill_h * Tuning.PAL_HEALTH_BAR_SHEEN_HEIGHT
	_bar_sheen.scale = Vector3(fill_w, sheen_h, 1.0)
	var sheen_quad: QuadMesh = _bar_sheen.mesh
	sheen_quad.center_offset = Vector3(
		left_shift, (fill_h - sheen_h) * 0.5 / maxf(sheen_h, 0.001), 0.0
	)
	var sheen_mat: StandardMaterial3D = _bar_sheen.material_override
	sheen_mat.albedo_color = colour.lerp(
		Color.WHITE, Tuning.PAL_HEALTH_BAR_SHEEN_LIGHTEN
	)


func _find_anim(n: Node) -> AnimationPlayer:
	for c in n.get_children():
		if c is AnimationPlayer:
			return c
		var found := _find_anim(c)
		if found:
			return found
	return null


## Animation names by intent, not by clip. The Glub rig is a flyer and has no
## Walk or Idle at all, so a fish asked to walk would stand frozen; its
## Fast_Flying and Flying_Idle cycles read as swimming instead.
const SWIM_CLIPS := {"Walk": "Fast_Flying", "Run": "Fast_Flying", "Idle": "Flying_Idle"}


## Run if the rig has one, Walk otherwise. Several rigs have no Run clip at
## all, and asking for a missing animation leaves the pal frozen.
func _play_moving() -> void:
	_play("Run" if _anim and _anim.has_animation("Run") else "Walk")


func _play(anim: String) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(anim) and SWIM_CLIPS.has(anim):
		anim = SWIM_CLIPS[anim]
	if _anim.has_animation(anim) and _anim.current_animation != anim:
		_anim.play(anim)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	_update_label()
	_credit = maxf(_credit - delta, 0.0)

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
		State.GATHER:
			_tick_gather(delta)

	move_and_slide()


func _tick_idle(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_play("Idle")
	_timer -= delta
	_watch_player(delta)
	if _wants_attack():
		_enter_attack(true)
	elif _pick_rival(delta):
		_enter_attack()
	elif _threat_near():
		_enter_flee()
	elif _timer <= 0.0:
		_enter_wander()


func _tick_wander(delta: float) -> void:
	if _wants_attack():
		_enter_attack(true)
		return
	if _pick_rival(delta):
		_enter_attack()
		return
	if _threat_near():
		_enter_flee()
		return
	_move_towards(_target, speed(Tuning.PAL_WALK_SPEED), delta)
	_play("Walk")
	if _flat_distance(_target) < 1.0:
		_enter_idle()


func _tick_flee(delta: float) -> void:
	if not _threat_near():
		_enter_idle()
		return
	var away := global_position - _player.global_position
	away.y = 0.0
	_move_towards(global_position + away.normalized() * 4.0, speed(Tuning.PAL_FLEE_SPEED), delta)
	_play_moving()


func _tick_follow(delta: float) -> void:
	if _player == null:
		return

	_defend_target = _find_defend_target()
	if _defend_target:
		state = State.DEFEND
		_attack_cooldown = 0.0
		return

	_gather_rest = maxf(_gather_rest - delta, 0.0)
	if _gather_rest <= 0.0:
		_gather_target = _find_gather_target()
		if _gather_target:
			state = State.GATHER
			_gather_cooldown = 0.0
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
		# The catch-up end keeps FOLLOW_CATCHUP_FLOOR whatever the species
		# factor does to it. A slow pal ambles at its own pace while the
		# player walks, and still hauls itself back into place when they
		# sprint, instead of trailing out to FOLLOWER_LEASH and unspawning
		# the party from view.
		var catchup := maxf(
			speed(Tuning.FOLLOW_CATCHUP_SPEED), Tuning.FOLLOW_CATCHUP_FLOOR
		)
		var pace: float = lerpf(
			speed(Tuning.PAL_FOLLOW_SPEED),
			catchup,
			clampf(gap / Tuning.FOLLOW_CATCHUP_RADIUS, 0.0, 1.0),
		)
		if gap < Tuning.FOLLOW_SLOW_RADIUS:
			pace *= maxf(gap / Tuning.FOLLOW_SLOW_RADIUS, 0.35)
		wanted = to_target.normalized() * pace

	# Following steers itself rather than calling _move_towards, so it opts
	# into the unstick by hand. Only while genuinely trying to close a gap:
	# a pal jostling against the player it has already reached is not stuck.
	if _escape_time > 0.0:
		_escape_time -= delta
		wanted = _escape_dir * Tuning.PAL_STUCK_ESCAPE_SPEED
	elif gap > Tuning.FOLLOW_SLOW_RADIUS:
		_track_progress(to_target.normalized(), wanted.length(), delta)
	else:
		_stuck_time = 0.0

	velocity.x = move_toward(velocity.x, wanted.x, Tuning.FOLLOW_ACCEL * delta * 10.0)
	velocity.z = move_toward(velocity.z, wanted.z, Tuning.FOLLOW_ACCEL * delta * 10.0)

	var moving := Vector2(velocity.x, velocity.z).length()
	if moving > 0.4:
		face(Vector3(velocity.x, 0.0, velocity.z).normalized(), delta, Tuning.PAL_TURN_SPEED)
		# Catching up runs; ambling alongside walks. Feet sliding over the
		# ground at three times the cycle's authored pace is the loudest
		# cheap-game tell a follower has, and it follows you everywhere.
		_play("Run" if moving > speed(Tuning.PAL_FOLLOW_SPEED) else "Walk")
	else:
		_play("Idle")


## --- Auto-gathering --------------------------------------------------------

## The resource_node group this species works, or "" for one that does not.
## Only the pal that is out does it, so a stowed party earns nothing.
func _gather_group() -> String:
	if not caught or Party.active != self:
		return ""
	return Tuning.PAL_GATHER_GROUPS.get(display_name, "")


## The nearest available node of our group within PAL_GATHER_RADIUS of the
## PLAYER, not of us, so the search area moves with them and a job is never
## picked that the leash would immediately cancel.
func _find_gather_target() -> Node3D:
	var group := _gather_group()
	if group == "" or _player == null:
		return null
	var best: Node3D = null
	var best_dist := Tuning.PAL_GATHER_RADIUS
	for node in get_tree().get_nodes_in_group(group):
		var n := node as Node3D
		if n == null or not n.has_method("is_available") or not n.is_available():
			continue
		var d := n.global_position - _player.global_position
		d.y = 0.0
		if d.length() < best_dist:
			best = n
			best_dist = d.length()
	return best


## Defending and following both outrank the job: a hostile nearby, or the
## player walking off, ends it immediately.
func _gather_target_valid() -> bool:
	return (
		_gather_target != null
		and is_instance_valid(_gather_target)
		and _gather_target.is_available()
		and _player != null
		and _find_defend_target() == null
		and _flat_distance(_player.global_position) < Tuning.PAL_GATHER_LEASH
	)


func _tick_gather(delta: float) -> void:
	_gather_cooldown = maxf(_gather_cooldown - delta, 0.0)
	if not _gather_target_valid():
		_stop_gathering()
		return

	var dist := _flat_distance(_gather_target.global_position)
	if dist > Tuning.PAL_GATHER_RANGE:
		_move_towards(_gather_target.global_position, speed(Tuning.PAL_GATHER_SPEED), delta)
		_play("Walk")
		return

	velocity.x = 0.0
	velocity.z = 0.0
	var dir := _gather_target.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		face(dir.normalized(), delta, Tuning.PAL_TURN_SPEED)
	if _gather_cooldown <= 0.0:
		_gather_cooldown = Tuning.PAL_GATHER_COOLDOWN
		_bite_node()


## One bite. resource_node.punch does the yield, the shake, the depletion and
## the respawn, so a pal working a tree wears it down exactly as the player
## does and the world still runs out and comes back on the same timer.
func _bite_node() -> void:
	if _anim:
		for anim_name in ["Bite_Front", "Punch", "Headbutt"]:
			if _anim.has_animation(anim_name):
				_anim.stop()
				_anim.play(anim_name)
				break
	_gather_target.punch()
	if not _gather_target.is_available():
		# Only on depletion: one message per item would bury the HUD queue,
		# and the item panel already counts the trickle live.
		Hud.flash("%s cleared a %s." % [display_name, _gather_target_label()])
		_stop_gathering()


func _gather_target_label() -> String:
	return "tree" if _gather_target.is_in_group("tree") else "rock"


func _stop_gathering() -> void:
	_gather_target = null
	_gather_cooldown = 0.0
	_gather_rest = Tuning.PAL_GATHER_REST
	state = State.FOLLOW


## --- Wild rivalry ----------------------------------------------------------

## An aggressive wild pal picks fights with other SPECIES, so the map looks
## inhabited rather than staged. Same species never fight, and the player
## always outranks a rival: _tick_attack drops the rival the moment they come
## into range, because they are the point of the game.

## True once a rival is acquired. Scanning is on RIVAL_SCAN_INTERVAL and
## staggered by instance id, so thirty pals never scan on the same frame.
func _pick_rival(delta: float) -> bool:
	if not aggressive or caught or dying:
		return false
	_rival_scan -= delta
	if _rival_scan > 0.0:
		return false
	_rival_scan = Tuning.RIVAL_SCAN_INTERVAL * (1.0 + 0.5 * fmod(get_instance_id(), 7) / 7.0)
	_rival = _find_rival()
	if _rival == null:
		return false
	_rival_fight = Tuning.RIVAL_FIGHT_TIME
	return true


func _find_rival() -> Pal:
	var best: Pal = null
	var best_dist := Tuning.RIVAL_RADIUS
	for node in get_tree().get_nodes_in_group("pal"):
		var other := node as Pal
		if other == null or not _is_rival(other):
			continue
		var dist := _flat_distance(other.global_position)
		if dist < best_dist:
			best = other
			best_dist = dist
	return best


## A pal worth fighting: wild, alive, out, and of another species. Caught pals
## are excluded so the party is never mobbed while it follows; a caught pal
## that wants in on the fight has State.DEFEND for that.
func _is_rival(other: Pal) -> bool:
	return (
		other != self
		and not other.caught
		and not other.dying
		and other.visible
		and other.display_name != display_name
		# The King is a summoned event, not part of the ecology. Without this
		# his own demon guard softens or kills him offscreen while the player
		# walks over, spending the key on a fight that never happens.
		and other.display_name != Tuning.INFINITE_CUBE_SPECIES
		and display_name != Tuning.INFINITE_CUBE_SPECIES
	)


## The fight ends when the loser dies, is caught, walks out of RIVAL_GIVE_UP,
## or on RIVAL_FIGHT_TIME. The timer is the backstop for a fight that cannot
## finish because it cannot start: a chase that never closes to attack range,
## which no other clause here bounds.
func _rival_valid() -> bool:
	return (
		_rival != null
		and is_instance_valid(_rival)
		and _is_rival(_rival)
		and _rival_fight > 0.0
		and _flat_distance(_rival.global_position) < Tuning.RIVAL_GIVE_UP
	)


func _tick_rival(delta: float) -> void:
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_rival_fight -= delta
	if not _rival_valid():
		_drop_rival()
		return

	var dist := _flat_distance(_rival.global_position)
	if dist > attack_range(Tuning.RIVAL_ATTACK_RANGE):
		_move_towards(_rival.global_position, speed(Tuning.PAL_CHASE_SPEED), delta)
		_play("Run" if _anim and _anim.has_animation("Run") else "Walk")
		return

	velocity.x = 0.0
	velocity.z = 0.0
	var dir := _rival.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		face(dir.normalized(), delta, Tuning.PAL_TURN_SPEED)
	if _attack_cooldown <= 0.0:
		_attack_cooldown = (
			Tuning.SPIT_COOLDOWN if _can_spit() else Tuning.RIVAL_ATTACK_COOLDOWN
		)
		_swing_at_rival(_rival)


## Damage from one wild pal to another. Unlike take_follower_hit this kills:
## a wild fight has a loser. The world is kept populated by respawning in
## scenery.gd rather than by making its pals unkillable.
func take_rival_hit(from: Pal) -> void:
	if caught or dying:
		return
	hp -= Tuning.RIVAL_DAMAGE
	# Shoved and briefly stunned, the way a player punch does it. Without
	# this a brawl at any distance reads as two pals standing still.
	var away := global_position - from.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var f := Tuning.RIVAL_HIT_IMPULSE_FACTOR
	velocity = away * Tuning.PAL_HIT_KNOCKBACK * f + Vector3.UP * Tuning.PAL_HIT_POP * f
	_hit_stun = Tuning.PAL_HIT_STUN * f
	if hp <= 0:
		_die()
		return
	if _bar_back:
		_refresh_bar()
	Audio.play("hit", global_position)
	# The Blob rigs misspell the hit animation; other sets use HitReact.
	if _anim and _anim.has_animation("HitRecieve"):
		_anim.play("HitRecieve")
	elif _anim and _anim.has_animation("HitReact"):
		_anim.play("HitReact")
	# Anything cornered fights, temperament regardless, and it outranks the
	# flee a skittish pal would otherwise answer with. The gate read
	# `aggressive and ...` and so never fired: demons are the only aggressive
	# species and _is_rival excludes their own kind. Setting neither _aggro nor
	# anything the flee gate reads is what keeps this off the player.
	if _rival == null and _is_rival(from):
		_rival = from
		_rival_fight = Tuning.RIVAL_FIGHT_TIME
		_enter_attack()


func _swing_at_rival(target: Pal) -> void:
	if _can_spit():
		_fire_spit(target, Spit.Mode.RIVAL)
		return
	if _anim:
		for anim_name in ["Punch", "Bite_Front"]:
			if _anim.has_animation(anim_name):
				_anim.stop()
				_anim.play(anim_name)
				break
	target.take_rival_hit(self)


## Back to wandering, with the scan on cooldown so a pal that just gave up on
## a chase does not reacquire the same rival on the very next frame.
func _drop_rival() -> void:
	_rival = null
	_rival_fight = 0.0
	_attack_cooldown = 0.0
	_rival_scan = Tuning.RIVAL_SCAN_INTERVAL
	_enter_idle()


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
##
## A commanded target skips the hostility test: the player picked it, and a
## peaceable wolf would otherwise fail it on the first tick. Everything else
## still applies, the leash included, so an order cannot strand the pal.
## The order also runs out on its own timer, which is the backstop for a
## target that neither dies nor is caught.
func _defend_target_valid() -> bool:
	if _defend_target == null or not is_instance_valid(_defend_target) or _player == null:
		return false
	if _flat_distance(_player.global_position) >= Tuning.FOLLOWER_LEASH:
		return false
	if _commanded():
		return not _defend_target.caught and not _defend_target.dying
	return _is_hostile(_defend_target)


## Whether a player order is still running.
func _commanded() -> bool:
	return _command_time > 0.0


## Send this pal at `target` on the player's order. Refused by anything that
## is not an out, living, caught pal; the caller reports the refusal.
func command_attack(target: Pal) -> bool:
	# `visible` is what stow() sets; the collider it disables is deferred and
	# so still reads as enabled on the frame the order arrives.
	if not caught or dying or not visible or target == null or not is_instance_valid(target):
		return false
	if target == self or target.caught or target.dying:
		return false
	if _player == null or _player.global_position.distance_to(target.global_position) \
			> Tuning.COMMAND_RANGE:
		return false
	_defend_target = target
	_command_time = Tuning.COMMAND_TIME
	_attack_cooldown = 0.0
	_gather_target = null
	state = State.DEFEND
	return true


func _tick_defend(delta: float) -> void:
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_command_time = maxf(_command_time - delta, 0.0)
	if not _defend_target_valid():
		_defend_target = null
		_command_time = 0.0
		state = State.FOLLOW
		return

	var dist := _flat_distance(_defend_target.global_position)
	if dist > attack_range(Tuning.FOLLOWER_ATTACK_RANGE):
		_move_towards(_defend_target.global_position, speed(Tuning.FOLLOWER_CHASE_SPEED), delta)
		_play("Run" if _anim and _anim.has_animation("Run") else "Walk")
		return

	velocity.x = 0.0
	velocity.z = 0.0
	var dir := _defend_target.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		face(dir.normalized(), delta, Tuning.PAL_TURN_SPEED)
	if _attack_cooldown <= 0.0:
		_attack_cooldown = (
			Tuning.SPIT_COOLDOWN if _can_spit() else Tuning.FOLLOWER_ATTACK_COOLDOWN
		)
		_swing_at(_defend_target)


## One landed hit from a caught pal. Spat or bitten, the damage goes through
## take_follower_hit and so through the FOLLOWER_MIN_TARGET_HP clamp: a
## follower must never land the kill and cost the player the catch, and a
## ranged attack that did its own arithmetic would be a way round that.
func _swing_at(target: Pal) -> void:
	if _can_spit():
		_fire_spit(target, Spit.Mode.FOLLOWER)
		return
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
	if _bar_back:
		_refresh_bar()
	Audio.play("hit", global_position)
	# The Blob rigs misspell the hit animation; other sets use HitReact.
	if _anim and _anim.has_animation("HitRecieve"):
		_anim.play("HitRecieve")
	elif _anim and _anim.has_animation("HitReact"):
		_anim.play("HitReact")


## --- Ranged attack ---------------------------------------------------------

## How close this pal has to get before it will attack, given the melee reach
## the fight would otherwise use. A spitter stops at SPIT_RANGE in every fight
## it can be in, so all three combat ticks ask this instead of reading their
## own constant, and a species becomes ranged by setting one export.
##
## A spitter with no wad wired falls back to the melee reach: standing off at
## 8 m firing nothing is worse than biting.
func attack_range(melee: float) -> float:
	if _can_spit():
		return Tuning.SPIT_RANGE
	return melee


func _can_spit() -> bool:
	return ranged and spit_scene != null


## Fire one wad at `target`, settled by `mode` on arrival.
##
## The mode is what keeps a follower's spit inside the catch clamp: the wad
## calls `take_follower_hit` exactly as `_swing_at` does, rather than carrying
## a damage number of its own. See scripts/spit.gd.
##
## Parented to the world rather than to the shooter, so a wad outlives a pal
## that dies mid-flight, and so it does not inherit the pal's scale.
func _fire_spit(target: Node3D, mode: Spit.Mode) -> Spit:
	if not _can_spit() or target == null:
		return null
	var wad := spit_scene.instantiate() as Spit
	if wad == null:
		return null
	wad.mode = mode
	wad.shooter = self
	get_parent().add_child(wad)
	var muzzle := global_position + Vector3.UP * Tuning.SPIT_MUZZLE_HEIGHT
	var aim := target.global_position + Vector3.UP * Tuning.SPIT_MUZZLE_HEIGHT * 0.5
	var moving: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
	wad.launch(muzzle, aim, moving)
	Audio.play(Tuning.SPIT_SOUND, global_position)
	if _anim:
		for anim_name in ["Headbutt", "Punch", "Bite_Front"]:
			if _anim.has_animation(anim_name):
				_anim.stop()
				_anim.play(anim_name)
				break
	return wad


## Whether this pal can be fired from the saddle. Public, because player.gd
## gates its mounted attack on the MOUNT's ability rather than on a species
## name: a Wolf or a Mudwader is rideable too and must keep biting.
func can_spit() -> bool:
	return _can_spit()


## Fire one wad along `direction`, `range_m` ahead, on the player's behalf.
##
## A direction rather than a target, because the rider aims with the camera
## and there may be nothing under the crosshair at all. The wad still leaves
## the mount's head, so it reads as the animal spitting rather than the rider.
func spit_along(direction: Vector3, range_m: float, mode: Spit.Mode) -> Spit:
	if not _can_spit():
		return null
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01:
		return null
	var muzzle := global_position + Vector3.UP * Tuning.SPIT_MUZZLE_HEIGHT
	var aim := muzzle + flat.normalized() * range_m
	var wad := spit_scene.instantiate() as Spit
	if wad == null:
		return null
	wad.mode = mode
	wad.shooter = self
	get_parent().add_child(wad)
	# No lead: the rider is aiming this one, so guessing ahead of them would
	# fight the crosshair rather than help it.
	wad.launch(muzzle, aim)
	Audio.play(Tuning.SPIT_SOUND, global_position)
	return wad


## Every shared speed constant is read through here, so one export gives a
## species its pace and nothing has to remember to multiply. Clamped, because
## a scene is free to type any number and the two ends both break the game: a
## chaser at 0 never arrives, and one at the player's sprint is inescapable.
func speed(base: float) -> float:
	return base * clampf(
		speed_factor, Tuning.PAL_SPEED_FACTOR_MIN, Tuning.PAL_SPEED_FACTOR_MAX
	)


## Every moving state steers through here, so the unstick lives here too and
## none of them has to know about it. The signal is intent against progress:
## a pal that asked for `speed` and covered almost none of it since the last
## move is pushing on something. `get_slide_collision_count()` was the other
## candidate and is wrong for this: a pal walking cleanly along a tree trunk
## collides every frame while making perfectly good progress.
func _move_towards(point: Vector3, speed: float, delta: float) -> void:
	if _escape_time > 0.0:
		_escape_time -= delta
		velocity.x = _escape_dir.x * Tuning.PAL_STUCK_ESCAPE_SPEED
		velocity.z = _escape_dir.z * Tuning.PAL_STUCK_ESCAPE_SPEED
		face(_escape_dir, delta, Tuning.PAL_TURN_SPEED)
		return

	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		_stuck_time = 0.0
		return
	dir = dir.normalized()
	dir = _steer_around(dir)
	_track_progress(dir, speed, delta)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	face(dir, delta, Tuning.PAL_TURN_SPEED)


## Bend a heading away from whatever is about to be walked into.
##
## Two rays either side of the heading. The nearer hit wins and the heading
## turns away from it, by an amount scaled to how close it is, so a distant
## trunk is a drift and a near one is a swerve. Mask 1 is world geometry:
## pals are on layer 4 and zones on layer 7, so neither steers anything.
##
## This does not replace the unstick, which still catches what a forward ray
## cannot see. It does mean the common case, a trunk on an otherwise clear
## line, no longer costs PAL_STUCK_TIME of grinding first.
func _steer_around(dir: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * Tuning.PAL_WHISKER_HEIGHT
	var nearest := INF
	var turn_sign := 0.0
	for side in [-1.0, 1.0]:
		var probe := dir.rotated(Vector3.UP, Tuning.PAL_WHISKER_ANGLE * side)
		var query := PhysicsRayQueryParameters3D.create(
			from, from + probe * Tuning.PAL_WHISKER_LENGTH
		)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var gap: float = from.distance_to(hit["position"])
		if gap < nearest:
			nearest = gap
			# Away from the whisker that hit. Both hitting takes the nearer,
			# which is the side with less room.
			turn_sign = -side
	if turn_sign == 0.0:
		return dir
	var closeness := 1.0 - clampf(nearest / Tuning.PAL_WHISKER_LENGTH, 0.0, 1.0)
	return dir.rotated(
		Vector3.UP, Tuning.PAL_WHISKER_TURN * closeness * turn_sign
	).normalized()


## Compare ground covered since the previous call against what was asked for.
## Measured only while a move is wanted, so a pal that arrived and stopped, or
## one idling, can never accumulate stuck time.
func _track_progress(dir: Vector3, speed: float, delta: float) -> void:
	var here := global_position
	here.y = 0.0
	if _last_move_frame == Engine.get_physics_frames() - 1:
		var moved := here.distance_to(_last_flat_position)
		if moved < speed * delta * Tuning.PAL_STUCK_SPEED_FRACTION:
			_stuck_time += delta
			if _stuck_time >= Tuning.PAL_STUCK_TIME:
				_begin_escape(dir)
		else:
			_stuck_time = 0.0
	else:
		# First move after a pause: no previous sample to compare against.
		_stuck_time = 0.0
	_last_flat_position = here
	_last_move_frame = Engine.get_physics_frames()


## Turn sharply off the blocked heading for a moment. The state is untouched,
## so a fleeing pal is still fleeing and a follower still catches up; it only
## loses control of the steering until the escape runs out.
func _begin_escape(blocked_dir: Vector3) -> void:
	_stuck_time = 0.0
	_escape_time = Tuning.PAL_STUCK_ESCAPE_TIME
	var turn := _rng.randf_range(Tuning.PAL_STUCK_TURN_MIN, Tuning.PAL_STUCK_TURN_MAX)
	if _rng.randf() < 0.5:
		turn = -turn
	_escape_dir = blocked_dir.rotated(Vector3.UP, turn).normalized()
	# A wandering pal would walk straight back into the same trunk, since its
	# target is fixed; give it somewhere else to be.
	if state == State.WANDER:
		_enter_wander()


func face(dir: Vector3, delta: float, speed: float) -> void:
	# Godot forward is -Z; the model is turned to match inside the pal scene.
	# Rotate the whole body, so basis.x stays the pal's right for dismounts.
	var target := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target, speed * delta)


## Drop the visuals by `depth` without moving the collider, so a wading
## swimmer looks submerged while still standing on the one flat ground plane.
func sink_model(depth: float) -> void:
	_model_root.position.y = -depth


## Where a rider sits: the Seat marker, which turns and scales with the pal.
func seat_position() -> Vector3:
	return $Model/Seat.global_position


func _flat_distance(point: Vector3) -> float:
	var d := point - global_position
	d.y = 0.0
	return d.length()


func _threat_near() -> bool:
	# Only a skittish species flees. An aggressive one gets _wants_attack
	# instead, and a neutral one carries on with whatever it was doing.
	if caught or temperament != Temperament.SKITTISH or _player == null:
		return false
	return _flat_distance(_player.global_position) < Tuning.PAL_FLEE_DISTANCE


## An idling pal turns to watch a player who comes near.
##
## Cheap, and it does two things at once: a pal that ignores someone standing
## a metre away reads as furniture, and a skittish species turning to watch
## you approach foreshadows the flee, so bolting looks like a decision rather
## than a distance trigger firing.
func _watch_player(delta: float) -> void:
	if _player == null or caught:
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var gap := to_player.length()
	if gap > Tuning.PAL_WATCH_DISTANCE or gap < 0.01:
		return
	face(to_player.normalized(), delta, Tuning.PAL_WATCH_TURN_SPEED)


func _enter_idle() -> void:
	state = State.IDLE
	# Jittered per pal, so twenty of them do not idle on one metronome. Only
	# the timing: speed_factor is tuned per species against the player's walk
	# and sprint and is measured by ground covered, so varying that would
	# reopen tuning the project treats as load-bearing.
	_timer = _rng.randf_range(
		Tuning.PAL_IDLE_MIN, Tuning.PAL_IDLE_MAX
	) * _idle_pace


func _enter_wander() -> void:
	state = State.WANDER
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(2.0, Tuning.PAL_WANDER_RADIUS)
	_target = _home + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	if water_only:
		_target = _clamp_to_fish_ring(_target)
	elif cave_only:
		_target = _clamp_to_cave(_target)


## Pull a point back inside the hollow. Measured from where the pal spawned
## rather than from a world constant, so the species stays with its cave
## wherever the cave is put.
func _clamp_to_cave(point: Vector3) -> Vector3:
	var flat := Vector3(point.x - _home.x, 0.0, point.z - _home.z)
	var dist := flat.length()
	if dist <= Tuning.GROTTOLO_WANDER_RADIUS:
		return point
	flat = flat / dist * Tuning.GROTTOLO_WANDER_RADIUS
	return Vector3(_home.x + flat.x, point.y, _home.z + flat.z)


## Pull a point back into the band fish are allowed to occupy. The inner edge
## is the gate: FISH_RING_MIN is set beyond a cube's reach from the shore
## wall, so a fish that wandered inside it would be catchable on foot.
func _clamp_to_fish_ring(point: Vector3) -> Vector3:
	var flat := Vector3(point.x, 0.0, point.z)
	var dist := flat.length()
	if dist < 0.01:
		return Vector3(Tuning.FISH_RING_MIN, point.y, 0.0)
	var clamped := clampf(dist, Tuning.FISH_RING_MIN, Tuning.FISH_RING_MAX)
	flat = flat / dist * clamped
	return Vector3(flat.x, point.y, flat.z)


func _enter_flee() -> void:
	state = State.FLEE


## `alert` gives the pal a beat to visibly notice the player before it
## charges. Only sight-aggro passes it: being punched is its own telegraph
## and a demon that pauses politely after taking a hit reads as broken, not
## as thoughtful.
func _enter_attack(alert := false) -> void:
	if caught:
		return
	if state != State.ATTACK:
		_attack_without_hit = 0.0
		if alert:
			_alert_time = Tuning.PAL_ALERT_TIME
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
	# The player outranks any rival: a demon mid-brawl breaks off the moment
	# they walk into range.
	if _rival and not _wants_attack():
		_tick_rival(delta)
		return
	_rival = null
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_attack_without_hit += delta
	if caught or _player == null:
		_enter_idle()
		return
	# The notice. Stand, turn to face, then charge. Without it a pal goes
	# from mooching to full chase speed in one frame the moment the player
	# crosses PAL_AGGRO_RADIUS, which reads as a tripwire rather than as an
	# animal seeing you, and leaves no beat to react in.
	if _alert_time > 0.0:
		_alert_time -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			face(to_player.normalized(), delta, Tuning.PAL_TURN_SPEED)
		_play("Idle")
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
	if dist > attack_range(Tuning.PAL_ATTACK_RANGE):
		_move_towards(_player.global_position, speed(Tuning.PAL_CHASE_SPEED), delta)
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
		if _can_spit():
			_attack_cooldown = Tuning.SPIT_COOLDOWN
			# A wad in the air is progress, whether or not it lands. Without
			# this the give-up timer runs out mid-volley and a spitter that
			# has the player pinned at range simply stops.
			_attack_without_hit = 0.0
			_credit_player()
			_fire_spit(_player, Spit.Mode.PLAYER)
			return
		_attack_cooldown = Tuning.PAL_ATTACK_COOLDOWN
		if _swing():
			_attack_without_hit = 0.0
			# Trading blows with the player makes it their fight too.
			_credit_player()


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
	_command_time = 0.0
	_attack_cooldown = 0.0
	_attack_without_hit = 0.0
	_sight_aggro_suppressed = false
	_defend_target = null
	_rival = null
	_gather_target = null
	if state == State.ATTACK:
		_enter_idle()


func _level_hp() -> int:
	var v: int = Tuning.PAL_BASE_HP + level * Tuning.PAL_HP_PER_LEVEL
	if aggressive:
		v += Tuning.AGGRESSIVE_BONUS_HP
	return v


## What one player punch takes off. Player levels sharpen it, so grinding XP
## speeds up farming too, and a demon out sharpens it again. Both are summed
## before the truncation, or two half-points would round away to nothing.
static func player_punch_damage() -> int:
	var bonus := (Party.player_level - 1) * Tuning.PUNCH_DAMAGE_PER_PLAYER_LEVEL
	return Tuning.PUNCH_DAMAGE + int(bonus + Party.buff(&"damage"))


## Reopen the window in which this pal's death pays the player. Called from
## both directions of a fight, because either one means the player was in it.
func _credit_player() -> void:
	_credit = Tuning.PAL_CREDIT_TIME


## Punched by the player: damage, knockback, and a spell of forced flight.
func take_hit(from: Vector3) -> void:
	if caught or dying:
		return
	hp -= player_punch_damage()
	if _bar_back:
		_refresh_bar()
	_credit_player()
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


## One death path, paid for only when the player was part of the fight.
##
## Wild fights kill, so the last blow is a poor test of who earned the kill:
## a demon softened by the player and finished by a wolf seconds later is the
## player's, and two pals brawling across the island while the player gathers
## wood are nobody's. `_credit` is the window that answers it.
func _die() -> void:
	if dying:
		return
	dying = true
	if _label:
		_label.visible = false
	_set_bar_visible(false)
	velocity = Vector3.ZERO
	set_physics_process(false)
	$Collision.set_deferred("disabled", true)
	# Out of the group so punches and cubes stop finding the corpse.
	remove_from_group("pal")
	Audio.play("defeat", global_position)
	if _credit > 0.0:
		var n := _grant_drop()
		# A kill is worth half a catch: progress for the cubeless, never parity.
		Party.grant_xp(int(xp_worth() * Tuning.XP_KILL_FACTOR))
		Hud.flash("%s defeated! +%d %s" % [display_name, n, drop_item_name])
	var wait := Tuning.PAL_DEATH_TIME
	if _anim and _anim.has_animation("Death"):
		_anim.play("Death")
		wait = _anim.get_animation("Death").length
	await get_tree().create_timer(wait).timeout
	# The poof outlives the corpse, so it is parented to the world rather than
	# to the pal that is about to free.
	poof(get_parent(), global_position)
	queue_free()


## The Llama's job: every catch and kill pays more. Summed before the
## truncation, the way player_punch_damage does it, or a half-point buff would
## round away to nothing.
func _grant_drop() -> int:
	var n := Tuning.PAL_DROP_BASE + int(level / 2.0 + Party.buff(&"drop"))
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
	var grow := model_scale * (1.0 + (level - 1) * Tuning.PAL_LEVEL_SCALE_STEP)
	_model_root.scale = Vector3.ONE * grow
	if _label:
		_label.text = "Lv%d %s" % [level, display_name]
		_label.position = Vector3.UP * Tuning.PAL_LABEL_HEIGHT * grow
	if _bar_back:
		var top := Vector3.UP * (
			Tuning.PAL_LABEL_HEIGHT * grow + Tuning.PAL_HEALTH_BAR_RISE * grow
		)
		for quad in [_bar_shadow, _bar_back, _bar_track, _bar_fill, _bar_sheen]:
			quad.position = top
		_refresh_bar()


## Called by the pal cube on a successful catch. Every catch pays the drop;
## Party.store decides whether the pal joins or merges into a kept one.
func on_caught() -> void:
	caught = true
	clear_aggro()
	if _label:
		_label.visible = false
	_set_bar_visible(false)
	_grant_drop()
	Party.grant_xp(xp_worth())
	Party.store(self)


## Stored pals stay in the tree but out of sight, so their home position and
## wander state survive being put away.
func stow() -> void:
	state = State.IDLE
	_command_time = 0.0
	_defend_target = null
	_rival = null
	_gather_target = null
	velocity = Vector3.ZERO
	visible = false
	set_physics_process(false)
	$Collision.set_deferred("disabled", true)


func summon(at: Vector3) -> void:
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	global_position = at
	visible = true
	set_physics_process(true)
	_command_time = 0.0
	$Collision.set_deferred("disabled", false)
	_defend_target = null
	_rival = null
	_gather_target = null
	state = State.FOLLOW


## --- Spawn and death poof --------------------------------------------------

## A one-shot burst of particles at `at`, parented to `world` and freeing
## itself once the last particle has died.
##
## Static and self-freeing on purpose: a corpse cannot own its own poof, since
## it frees in the same breath, and a per-pal emitter kept alive for the one
## moment it is needed would be thirty idle particle systems in a full world.
static func poof(world: Node, at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = Tuning.PAL_POOF_COUNT
	p.lifetime = Tuning.PAL_POOF_TIME
	p.one_shot = true
	p.explosiveness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.5
	mat.gravity = Vector3(0.0, -4.0, 0.0)
	mat.scale_min = 0.4
	mat.scale_max = 1.1
	mat.color = Tuning.PAL_POOF_COLOUR
	p.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.radial_segments = 6
	mesh.rings = 3
	p.draw_pass_1 = mesh
	var draw := StandardMaterial3D.new()
	draw.emission_enabled = true
	draw.emission = Tuning.PAL_POOF_COLOUR
	draw.emission_energy_multiplier = 3.0
	draw.albedo_color = Tuning.PAL_POOF_COLOUR
	p.material_override = draw
	world.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Grow in from nothing, for a pal joining a world the player is already
## standing in. The scale it lands on is whatever _ready computed, so a level
## 5 demon still arrives at its own size.
func grow_in() -> void:
	var grow: Vector3 = _model_root.scale
	_model_root.scale = grow * Tuning.RESPAWN_GROW_FROM
	var t := create_tween()
	t.tween_property(_model_root, "scale", grow, Tuning.RESPAWN_GROW_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
