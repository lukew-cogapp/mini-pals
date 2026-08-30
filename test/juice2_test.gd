extends SceneTree
## Headless assertions for the second juice pass. Run:
##   godot --headless --path . -s test/juice2_test.gd
##
## Each of these is a bug a screenshot cannot show. A facing gate with the dot
## comparison the wrong way round lights up everything behind the player and
## nothing in front, and a still frame of it looks almost right. An edge
## trigger that has lost its bool fires its message every poll, which reads as
## a stuck HUD rather than as a missing `if`. And sound has no picture at all.
##
## Untyped on purpose, like juice_test: a `-s` script that names a class_name
## or an autoload fails to compile before any of it runs.

var _fails := 0


func _init() -> void:
	await process_frame

	await _test_camera_forward_is_minus_z()
	await _test_bar_gates_on_facing()
	await _test_bar_shows_for_the_reticule_lock()
	await _test_rival_hit_imparts_velocity()
	await _test_ash_entry_fires_once()
	await _test_splash_fires_on_the_water_edge()
	await _test_level_up_chimes()
	await _test_death_and_respawn_poof()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name, ok, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _audio():
	return get_root().get_node("Audio")


func _party():
	return get_root().get_node("Party")


func _spawn_player():
	var player = load("res://scenes/player.tscn").instantiate()
	get_root().add_child(player)
	await process_frame
	player.set_physics_process(false)
	return player


func _spawn_pal(pos: Vector3, player):
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	get_root().add_child(pal)
	await process_frame
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
func _test_camera_forward_is_minus_z() -> void:
	var player = await _spawn_player()
	var pivot = player.get_node("CameraPivot")

	# The pivot starts pitched down by CAMERA_PITCH_START, so -basis.z has a
	# Y component. The gate flattens it before the dot, so flatten here too:
	# asserting the raw vector fails on the pitch and says nothing about the
	# axis, which is what is actually in question.
	pivot.rotation.y = 0.0
	var forward = _flat_forward(pivot)
	_check(
		"an unrotated camera pivot looks along -Z",
		forward.is_equal_approx(Vector3(0.0, 0.0, -1.0)),
		"forward=%s" % forward,
	)

	# A quarter turn left about +Y takes -Z round to -X.
	pivot.rotation.y = PI * 0.5
	forward = _flat_forward(pivot)
	_check(
		"a quarter turn left points the pivot along -X",
		forward.is_equal_approx(Vector3(-1.0, 0.0, 0.0)),
		"forward=%s" % forward,
	)

	# And a half turn puts it on +Z, which is the heading the facing test
	# below turns to in order to see a pal it started with its back to.
	pivot.rotation.y = PI
	forward = _flat_forward(pivot)
	_check(
		"a half turn points the pivot along +Z",
		forward.is_equal_approx(Vector3(0.0, 0.0, 1.0)),
		"forward=%s" % forward,
	)

	player.queue_free()


func _test_bar_gates_on_facing() -> void:
	var player = await _spawn_player()
	player.global_position = Vector3.ZERO
	var pivot = player.get_node("CameraPivot")
	# Looking along -Z, so a pal at +Z is directly behind.
	pivot.rotation.y = 0.0
	await process_frame

	var behind = 8.0
	var pal = await _spawn_pal(Vector3(0.0, 0.0, behind), player)
	_sample(pal)
	_check(
		"a pal in range but behind the player shows no bar",
		not pal._bar_back.visible,
		"hp=%d/%d dist=%.1f" % [pal.hp, pal.max_hp, behind],
	)

	# Turn to face it. A half turn puts the pivot's forward on +Z.
	pivot.rotation.y = PI
	await process_frame
	_sample(pal)
	_check(
		"the same pal shows a bar once the player turns to face it",
		pal._bar_back.visible,
	)

	# Full health must not suppress it: the gate is where you are looking,
	# not whether you have already hurt something.
	_check(
		"a faced pal at full health still shows its bar",
		pal.hp == pal.max_hp and pal._bar_back.visible,
		"hp=%d/%d" % [pal.hp, pal.max_hp],
	)

	# Faced, but too far away.
	pal.global_position = Vector3(0.0, 0.0, Tuning.PAL_HEALTH_BAR_DISTANCE + 10.0)
	_sample(pal)
	_check(
		"a faced pal beyond the show distance shows no bar",
		not pal._bar_back.visible,
	)

	pal.queue_free()
	player.queue_free()


func _test_bar_shows_for_the_reticule_lock() -> void:
	var player = await _spawn_player()
	player.global_position = Vector3.ZERO
	var pivot = player.get_node("CameraPivot")
	pivot.rotation.y = 0.0
	await process_frame

	# Behind the player, so the cone check is certain to reject it.
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 8.0), player)
	_sample(pal)
	_check("the lock case starts with no bar", not pal._bar_back.visible)

	player.locked_pal = pal
	_sample(pal)
	_check(
		"the reticule-locked pal shows a bar despite failing the cone",
		pal._bar_back.visible,
	)

	player.locked_pal = null
	_sample(pal)
	_check("dropping the lock hides it again", not pal._bar_back.visible)

	pal.queue_free()
	player.queue_free()


## --- Item 4: rival knockback ----------------------------------------------

func _test_rival_hit_imparts_velocity() -> void:
	var attacker = await _spawn_pal(Vector3.ZERO, null)
	var target = await _spawn_pal(Vector3(0.0, 0.0, 4.0), null)
	target.max_hp = 10
	target.hp = 10
	target.velocity = Vector3.ZERO
	target._hit_stun = 0.0

	target.take_rival_hit(attacker)

	# The attacker is at the origin and the target at +4Z, so the shove is
	# away from the attacker: +Z, with a lift on top.
	var v = target.velocity
	var want = Tuning.PAL_HIT_KNOCKBACK * Tuning.RIVAL_HIT_IMPULSE_FACTOR
	_check(
		"a rival hit shoves the target away from the attacker",
		is_equal_approx(v.z, want) and absf(v.x) < 0.001,
		"velocity=%s want z=%.3f" % [v, want],
	)
	_check(
		"a rival hit pops the target upwards",
		is_equal_approx(v.y, Tuning.PAL_HIT_POP * Tuning.RIVAL_HIT_IMPULSE_FACTOR),
		"y=%.3f" % v.y,
	)
	_check(
		"a rival hit stuns the target",
		is_equal_approx(target._hit_stun, Tuning.PAL_HIT_STUN * Tuning.RIVAL_HIT_IMPULSE_FACTOR),
		"stun=%.3f" % target._hit_stun,
	)
	_check(
		"the shove is softer than a player punch, so brawls stay put",
		v.length() < (
			Vector3(0.0, Tuning.PAL_HIT_POP, Tuning.PAL_HIT_KNOCKBACK).length()
		),
		"rival=%.2f player=%.2f" % [
			v.length(),
			Vector3(0.0, Tuning.PAL_HIT_POP, Tuning.PAL_HIT_KNOCKBACK).length(),
		],
	)

	# take_follower_hit's lack of knockback is load-bearing: it keeps a
	# softened target inside cube range. Guard it here so item 4 cannot
	# creep into it later.
	target.velocity = Vector3.ZERO
	target.hp = 10
	target.take_follower_hit()
	_check(
		"a follower hit still imparts no knockback",
		target.velocity == Vector3.ZERO,
		"velocity=%s" % target.velocity,
	)

	attacker.queue_free()
	target.queue_free()


## --- Item 5: the ash edge -------------------------------------------------

## A stand-in ash zone, so the test does not have to build the whole island.
func _make_ash_zone(world_parent) -> void:
	var zone = load("res://scripts/zone.gd").new()
	zone.kind = 1  # Zone.Kind.ASH; naming Zone here would pull the class in.
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 20.0
	cyl.height = Tuning.ZONE_HEIGHT
	shape.shape = cyl
	zone.add_child(shape)
	world_parent.add_child(zone)
	zone.global_position = Vector3(100.0, 0.0, 0.0)
	zone.edge_radius = 20.0


func _test_ash_entry_fires_once() -> void:
	var player = await _spawn_player()
	_make_ash_zone(get_root())
	await process_frame

	var audio = _audio()
	# Well outside the stand-in zone.
	player.global_position = Vector3.ZERO
	player._was_in_ash = false
	player._ash_poll = 0.0
	player._tick_ash(1.0)
	audio.played.clear()

	player.global_position = Vector3(100.0, 0.0, 0.0)
	player._ash_poll = 0.0
	player._tick_ash(1.0)
	var first = audio.played.count("ash_enter")
	_check("entering the ash plays its sting", first == 1, "plays=%d" % first)

	# Standing there is not news. Poll it many more times.
	for _i in 20:
		player._ash_poll = 0.0
		player._tick_ash(1.0)
	var after = audio.played.count("ash_enter")
	_check(
		"standing on the ash does not re-fire it",
		after == 1,
		"plays after 20 more polls=%d" % after,
	)

	# Leave and come back: a second entry is a second sting.
	player.global_position = Vector3.ZERO
	player._ash_poll = 0.0
	player._tick_ash(1.0)
	player.global_position = Vector3(100.0, 0.0, 0.0)
	player._ash_poll = 0.0
	player._tick_ash(1.0)
	_check(
		"leaving and re-entering fires it again",
		audio.played.count("ash_enter") == 2,
		"plays=%d" % audio.played.count("ash_enter"),
	)

	# The poll interval is real: a tick inside it must do nothing at all.
	player.global_position = Vector3.ZERO
	player._ash_poll = Tuning.PROMPT_POLL_INTERVAL
	player._tick_ash(0.0)
	_check(
		"a tick inside the poll interval does not sample the zone",
		player._was_in_ash,
		"was_in_ash=%s" % player._was_in_ash,
	)

	player.queue_free()


## --- Item 2: the water edge -----------------------------------------------

func _test_splash_fires_on_the_water_edge() -> void:
	var player = await _spawn_player()
	var mount = await _spawn_pal(Vector3.ZERO, player)
	mount.swimmer = true
	player.mount = mount
	var audio = _audio()

	# No LAND zone exists in this bare tree, so _mount_is_wading reads true.
	# Start the edge armed as if the mount were ashore.
	player._was_wading = false
	audio.played.clear()

	player._ride(0.016)
	var first = audio.played.count("splash")
	_check("riding into the water splashes", first == 1, "plays=%d" % first)
	_check("the crossing kicks the camera", player._shake > 0.0, "shake=%.3f" % player._shake)

	for _i in 30:
		player._ride(0.016)
	_check(
		"wading on does not repeat the splash",
		audio.played.count("splash") == 1,
		"plays after 30 more frames=%d" % audio.played.count("splash"),
	)

	# The sink is eased, not snapped: one frame in, the model must be part
	# way down rather than already at SWIM_SINK.
	player._was_wading = false
	if player._sink_tween:
		player._sink_tween.kill()
	mount.sink_model(0.0)
	player._ride(0.016)
	await process_frame
	var depth = -mount._model_root.position.y
	_check(
		"the sink eases rather than snapping to SWIM_SINK",
		depth > 0.0 and depth < Tuning.SWIM_SINK,
		"depth=%.4f of %.2f" % [depth, Tuning.SWIM_SINK],
	)

	player.mount = null
	mount.queue_free()
	player.queue_free()


## --- Item 6: the level-up chime -------------------------------------------

func _test_level_up_chimes() -> void:
	var party = _party()
	var audio = _audio()
	audio.played.clear()

	var before = party.player_level
	# Short of a level: XP goes up, no chime.
	party.grant_xp(1)
	_check(
		"gaining XP without a level is silent",
		audio.played.count("level_up") == 0,
		"plays=%d" % audio.played.count("level_up"),
	)

	party.grant_xp(Tuning.PLAYER_XP_PER_LEVEL)
	_check(
		"reaching a player level chimes",
		party.player_level > before and audio.played.count("level_up") == 1,
		"level %d -> %d plays=%d" % [
			before, party.player_level, audio.played.count("level_up"),
		],
	)


## --- Item 1: the spawn and death poof -------------------------------------

func _test_death_and_respawn_poof() -> void:
	var host := Node3D.new()
	get_root().add_child(host)
	await process_frame

	var p = load("res://scripts/pal.gd").poof(host, Vector3(3.0, 0.0, -2.0))
	_check("a poof is a one-shot emitter", p.one_shot and p.emitting)
	_check(
		"the poof stands where it was asked to",
		p.global_position.is_equal_approx(Vector3(3.0, 0.0, -2.0)),
		"at=%s" % p.global_position,
	)
	_check(
		"the poof lives no longer than PAL_POOF_TIME",
		is_equal_approx(p.lifetime, Tuning.PAL_POOF_TIME),
		"lifetime=%.2f" % p.lifetime,
	)

	# A respawning pal grows in from near nothing to the scale _ready set,
	# rather than appearing at full size.
	var pal = await _spawn_pal(Vector3.ZERO, null)
	var full = pal._model_root.scale
	pal.grow_in()
	var started = pal._model_root.scale
	_check(
		"a grown-in pal starts small",
		started.x < full.x * 0.5 and started.x > 0.0,
		"start=%.3f full=%.3f" % [started.x, full.x],
	)
	await create_timer(Tuning.RESPAWN_GROW_TIME + 0.2).timeout
	_check(
		"the grow lands on the scale _ready computed",
		pal._model_root.scale.is_equal_approx(full),
		"now=%s want=%s" % [pal._model_root.scale, full],
	)

	pal.queue_free()
	host.queue_free()
