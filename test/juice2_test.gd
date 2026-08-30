extends GutTest
## Headless assertions for the second juice pass.
##
## Each of these is a bug a screenshot cannot show. A facing gate with the dot
## comparison the wrong way round lights up everything behind the player and
## nothing in front, and a still frame of it looks almost right. An edge
## trigger that has lost its bool fires its message every poll, which reads as
## a stuck HUD rather than as a missing `if`. And sound has no picture at all.


## queue_free has not run by the time GUT counts the script's children, so
## every node spawned here is tracked and freed outright in after_all.
var _spawned: Array[Node] = []


## Party outlives a single suite now that every test shares one process, so
## the level-up case would read another script's XP as its own.
func before_all() -> void:
	Party.xp = 0
	Party.player_level = 1


func after_all() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _spawn_player() -> Node3D:
	var player: Node3D = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	_spawned.append(player)
	await wait_process_frames(1)
	player.set_physics_process(false)
	return player


func _spawn_pal(pos: Vector3, player) -> Node3D:
	var pal: Node3D = load("res://scenes/pal_wolf.tscn").instantiate()
	add_child(pal)
	_spawned.append(pal)
	await wait_process_frames(1)
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	pal._player_cache = player
	return pal


## Force the interval sampler to run this frame rather than waiting on it.
func _sample(pal) -> void:
	pal._bar_check = 0.0
	pal._tick_health_bar()


## --- Item 3: the facing gate ----------------------------------------------


## The pivot's forward, flattened, exactly as _faced_by_player computes it.
func _flat_forward(pivot) -> Vector3:
	var f = -pivot.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


## The whole gate rests on which axis the pivot's forward is. CLAUDE.md is
## emphatic that reasoning about this has been wrong here repeatedly, so it is
## measured: yaw the pivot to a known heading and read where forward points.
func test_camera_forward_is_minus_z() -> void:
	var player := await _spawn_player()
	var pivot = player.get_node("CameraPivot")

	# The pivot starts pitched down by CAMERA_PITCH_START, so -basis.z has a
	# Y component. The gate flattens it before the dot, so flatten here too:
	# asserting the raw vector fails on the pitch and says nothing about the
	# axis, which is what is actually in question.
	pivot.rotation.y = 0.0
	var forward := _flat_forward(pivot)
	assert_true(
		forward.is_equal_approx(Vector3(0.0, 0.0, -1.0)),
		"an unrotated camera pivot looks along -Z: forward=%s" % forward,
	)

	# A quarter turn left about +Y takes -Z round to -X.
	pivot.rotation.y = PI * 0.5
	forward = _flat_forward(pivot)
	assert_true(
		forward.is_equal_approx(Vector3(-1.0, 0.0, 0.0)),
		"a quarter turn left points the pivot along -X: forward=%s" % forward,
	)

	# And a half turn puts it on +Z, which is the heading the facing test
	# below turns to in order to see a pal it started with its back to.
	pivot.rotation.y = PI
	forward = _flat_forward(pivot)
	assert_true(
		forward.is_equal_approx(Vector3(0.0, 0.0, 1.0)),
		"a half turn points the pivot along +Z: forward=%s" % forward,
	)

	player.queue_free()


func test_bar_gates_on_facing() -> void:
	var player := await _spawn_player()
	player.global_position = Vector3.ZERO
	var pivot = player.get_node("CameraPivot")
	# Looking along -Z, so a pal at +Z is directly behind.
	pivot.rotation.y = 0.0
	await wait_process_frames(1)

	var behind := 8.0
	var pal := await _spawn_pal(Vector3(0.0, 0.0, behind), player)
	_sample(pal)
	assert_false(
		pal._bar_back.visible,
		(
			"a pal in range but behind the player shows no bar: hp=%d/%d dist=%.1f"
			% [pal.hp, pal.max_hp, behind]
		),
	)

	# Turn to face it. A half turn puts the pivot's forward on +Z.
	pivot.rotation.y = PI
	await wait_process_frames(1)
	_sample(pal)
	assert_true(
		pal._bar_back.visible,
		"the same pal shows a bar once the player turns to face it",
	)

	# Full health must not suppress it: the gate is where you are looking,
	# not whether you have already hurt something.
	assert_true(
		pal.hp == pal.max_hp and pal._bar_back.visible,
		"a faced pal at full health still shows its bar: hp=%d/%d" % [pal.hp, pal.max_hp],
	)

	# Faced, but too far away.
	pal.global_position = Vector3(0.0, 0.0, Tuning.PAL_HEALTH_BAR_DISTANCE + 10.0)
	_sample(pal)
	assert_false(
		pal._bar_back.visible,
		"a faced pal beyond the show distance shows no bar",
	)

	pal.queue_free()
	player.queue_free()


func test_bar_shows_for_the_reticule_lock() -> void:
	var player := await _spawn_player()
	player.global_position = Vector3.ZERO
	var pivot = player.get_node("CameraPivot")
	pivot.rotation.y = 0.0
	await wait_process_frames(1)

	# Behind the player, so the cone check is certain to reject it.
	var pal := await _spawn_pal(Vector3(0.0, 0.0, 8.0), player)
	_sample(pal)
	assert_false(pal._bar_back.visible, "the lock case starts with no bar")

	player.locked_pal = pal
	_sample(pal)
	assert_true(
		pal._bar_back.visible,
		"the reticule-locked pal shows a bar despite failing the cone",
	)

	player.locked_pal = null
	_sample(pal)
	assert_false(pal._bar_back.visible, "dropping the lock hides it again")

	pal.queue_free()
	player.queue_free()


## --- Item 4: rival knockback ----------------------------------------------


func test_rival_hit_imparts_velocity() -> void:
	var attacker := await _spawn_pal(Vector3.ZERO, null)
	var target := await _spawn_pal(Vector3(0.0, 0.0, 4.0), null)
	target.max_hp = 10
	target.hp = 10
	target.velocity = Vector3.ZERO
	target._hit_stun = 0.0

	target.take_rival_hit(attacker)

	# The attacker is at the origin and the target at +4Z, so the shove is
	# away from the attacker: +Z, with a lift on top.
	var v: Vector3 = target.velocity
	var want: float = Tuning.PAL_HIT_KNOCKBACK * Tuning.RIVAL_HIT_IMPULSE_FACTOR
	assert_true(
		is_equal_approx(v.z, want) and absf(v.x) < 0.001,
		"a rival hit shoves the target away from the attacker: velocity=%s want z=%.3f" % [v, want],
	)
	assert_true(
		is_equal_approx(v.y, Tuning.PAL_HIT_POP * Tuning.RIVAL_HIT_IMPULSE_FACTOR),
		"a rival hit pops the target upwards: y=%.3f" % v.y,
	)
	assert_true(
		is_equal_approx(target._hit_stun, Tuning.PAL_HIT_STUN * Tuning.RIVAL_HIT_IMPULSE_FACTOR),
		"a rival hit stuns the target: stun=%.3f" % target._hit_stun,
	)
	var player_impulse := Vector3(0.0, Tuning.PAL_HIT_POP, Tuning.PAL_HIT_KNOCKBACK).length()
	assert_true(
		v.length() < player_impulse,
		(
			"the shove is softer than a player punch, so brawls stay put: rival=%.2f player=%.2f"
			% [v.length(), player_impulse]
		),
	)

	# take_follower_hit's lack of knockback keeps a softened target inside
	# cube range. Guard it here so item 4 cannot creep into it later.
	target.velocity = Vector3.ZERO
	target.hp = 10
	target.take_follower_hit()
	assert_eq(
		target.velocity,
		Vector3.ZERO,
		"a follower hit still imparts no knockback",
	)

	attacker.queue_free()
	target.queue_free()


## --- Item 5: the ash edge -------------------------------------------------


## A stand-in ash zone, so the test does not have to build the whole island.
func _make_ash_zone() -> void:
	var zone = load("res://scripts/zone.gd").new()
	zone.kind = Zone.Kind.ASH
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 20.0
	cyl.height = Tuning.ZONE_HEIGHT
	shape.shape = cyl
	zone.add_child(shape)
	add_child(zone)
	_spawned.append(zone)
	zone.global_position = Vector3(100.0, 0.0, 0.0)
	zone.edge_radius = 20.0


func test_ash_entry_fires_once() -> void:
	var player := await _spawn_player()
	_make_ash_zone()
	await wait_process_frames(1)

	# Well outside the stand-in zone.
	player.global_position = Vector3.ZERO
	player._was_in_ash = false
	player._ash_poll = 0.0
	player._tick_ash(1.0)
	Audio.played.clear()

	player.global_position = Vector3(100.0, 0.0, 0.0)
	player._ash_poll = 0.0
	player._tick_ash(1.0)
	assert_eq(Audio.played.count("ash_enter"), 1, "entering the ash plays its sting")

	# Standing there is not news. Poll it many more times.
	for _i in 20:
		player._ash_poll = 0.0
		player._tick_ash(1.0)
	assert_eq(
		Audio.played.count("ash_enter"),
		1,
		"standing on the ash does not re-fire it after 20 more polls",
	)

	# Leave and come back: a second entry is a second sting.
	player.global_position = Vector3.ZERO
	player._ash_poll = 0.0
	player._tick_ash(1.0)
	player.global_position = Vector3(100.0, 0.0, 0.0)
	player._ash_poll = 0.0
	player._tick_ash(1.0)
	assert_eq(
		Audio.played.count("ash_enter"),
		2,
		"leaving and re-entering fires it again",
	)

	# The poll interval is real: a tick inside it must do nothing at all.
	player.global_position = Vector3.ZERO
	player._ash_poll = Tuning.PROMPT_POLL_INTERVAL
	player._tick_ash(0.0)
	assert_true(
		player._was_in_ash,
		"a tick inside the poll interval does not sample the zone: was_in_ash=%s"
		% player._was_in_ash,
	)

	player.queue_free()


## --- Item 2: the water edge -----------------------------------------------


func test_splash_fires_on_the_water_edge() -> void:
	var player := await _spawn_player()
	var mount := await _spawn_pal(Vector3.ZERO, player)
	mount.swimmer = true
	player.mount = mount

	# No LAND zone exists in this bare tree, so _mount_is_wading reads true.
	# Start the edge armed as if the mount were ashore.
	player._was_wading = false
	Audio.played.clear()

	player._ride(0.016)
	assert_eq(Audio.played.count("splash"), 1, "riding into the water splashes")
	assert_true(player._shake > 0.0, "the crossing kicks the camera: shake=%.3f" % player._shake)

	for _i in 30:
		player._ride(0.016)
	assert_eq(
		Audio.played.count("splash"),
		1,
		"wading on does not repeat the splash after 30 more frames",
	)

	# The sink is eased, not snapped: one frame in, the model must be part
	# way down rather than already at SWIM_SINK.
	player._was_wading = false
	if player._sink_tween:
		player._sink_tween.kill()
	mount.sink_model(0.0)
	player._ride(0.016)
	await wait_process_frames(1)
	var depth: float = -mount._model_root.position.y
	assert_true(
		depth > 0.0 and depth < Tuning.SWIM_SINK,
		(
			"the sink eases rather than snapping to SWIM_SINK: depth=%.4f of %.2f"
			% [depth, Tuning.SWIM_SINK]
		),
	)

	player.mount = null
	mount.queue_free()
	player.queue_free()


## --- Item 6: the level-up chime -------------------------------------------


func test_level_up_chimes() -> void:
	Audio.played.clear()

	var before: int = Party.player_level
	# Short of a level: XP goes up, no chime.
	Party.grant_xp(1)
	assert_eq(Audio.played.count("level_up"), 0, "gaining XP without a level is silent")

	Party.grant_xp(Tuning.PLAYER_XP_PER_LEVEL)
	assert_true(
		Party.player_level > before and Audio.played.count("level_up") == 1,
		(
			"reaching a player level chimes: level %d -> %d plays=%d"
			% [before, Party.player_level, Audio.played.count("level_up")]
		),
	)


## --- Item 1: the spawn and death poof -------------------------------------


func test_death_and_respawn_poof() -> void:
	var host := Node3D.new()
	add_child(host)
	_spawned.append(host)
	await wait_process_frames(1)

	var p = load("res://scripts/pal.gd").poof(host, Vector3(3.0, 0.0, -2.0))
	assert_true(p.one_shot and p.emitting, "a poof is a one-shot emitter")
	assert_true(
		p.global_position.is_equal_approx(Vector3(3.0, 0.0, -2.0)),
		"the poof stands where it was asked to: at=%s" % p.global_position,
	)
	assert_true(
		is_equal_approx(p.lifetime, Tuning.PAL_POOF_TIME),
		"the poof lives no longer than PAL_POOF_TIME: lifetime=%.2f" % p.lifetime,
	)

	# A respawning pal grows in from near nothing to the scale _ready set,
	# rather than appearing at full size.
	var pal := await _spawn_pal(Vector3.ZERO, null)
	var full: Vector3 = pal._model_root.scale
	pal.grow_in()
	var started: Vector3 = pal._model_root.scale
	assert_true(
		started.x < full.x * 0.5 and started.x > 0.0,
		"a grown-in pal starts small: start=%.3f full=%.3f" % [started.x, full.x],
	)
	await wait_seconds(Tuning.RESPAWN_GROW_TIME + 0.2)
	assert_true(
		pal._model_root.scale.is_equal_approx(full),
		"the grow lands on the scale _ready computed: now=%s want=%s"
		% [pal._model_root.scale, full],
	)

	pal.queue_free()
	host.queue_free()
