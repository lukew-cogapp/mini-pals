extends SceneTree
## Headless assertions for per-species pace. Run:
##   godot --headless --path . -s test/species_speed_test.gd
##
## Every distance here is ground actually covered over a fixed number of
## physics frames, never the constant that was asked for. A factor applied to
## the wrong call site, or a clamp swallowing it, reads as correct in the
## export and wrong on the ground, which is the only place it matters.

const FRAMES := 40

var _fails := 0


func _init() -> void:
	await process_frame

	await _test_factors_are_distinct()
	await _test_wander_distance_follows_the_factor()
	await _test_a_slow_species_is_outwalked_and_a_fast_one_is_not()
	await _test_a_slow_follower_still_keeps_up_with_a_sprinting_player()
	await _test_a_chaser_never_outruns_a_sprint()
	await _test_riding_ignores_the_species_factor()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


const SCENES := {
	"Wolf": "res://scenes/pal_wolf.tscn",
	"Cactoro": "res://scenes/pal_cactoro.tscn",
	"Demon": "res://scenes/pal_demon.tscn",
	"Mudwader": "res://scenes/pal_mudwader.tscn",
	"Glimmerfin": "res://scenes/pal_glimmerfin.tscn",
	"Mushroom King": "res://scenes/pal_boss.tscn",
}


func _spawn(species: String, pos: Vector3, player: Node3D):
	var pal = load(SCENES[species]).instantiate()
	get_root().add_child(pal)
	await process_frame
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	pal._player_cache = player
	# No ground under a bare SceneTree, so gravity would drag every pal down
	# and the flat distance covered would still be right but the fall noisy.
	pal.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	return pal


func _player_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	get_root().add_child(n)
	n.global_position = pos
	return n


## Flat ground covered while the pal is driven straight at a distant point.
## Physics frames, not process frames: move_and_slide only applies velocity
## there.
##
## The pal's own _physics_process runs on the same frames and calls
## move_and_slide itself, so it is parked in IDLE first: idle zeroes the
## velocity and slides nowhere, leaving exactly one real step per frame. Leave
## it in a moving state and every distance here doubles.
func _distance_walking_at(pal, base_speed: float) -> float:
	pal.state = pal.State.IDLE
	var start: Vector3 = pal.global_position
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	for i in FRAMES:
		pal._move_towards(pal.global_position + Vector3.FORWARD * 50.0, pal.speed(base_speed), step)
		pal.move_and_slide()
		await physics_frame
	return _flat(pal.global_position - start)


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## What the player itself covers over the same frames, which is the reference
## every species is judged against.
func _player_distance(speed: float) -> float:
	return speed * FRAMES / float(Engine.physics_ticks_per_second)


func _test_factors_are_distinct() -> void:
	var player := _player_at(Vector3.ZERO)
	var seen := {}
	for species in SCENES:
		var pal = await _spawn(species, Vector3.ZERO, player)
		var f: float = pal.speed_factor
		_check(
			"%s carries a speed factor inside the clamp" % species,
			f >= Tuning.PAL_SPEED_FACTOR_MIN and f <= Tuning.PAL_SPEED_FACTOR_MAX,
			"factor=%.2f" % f,
		)
		seen[species] = f
		pal.queue_free()
	# The whole point of the change: not every species moves at one pace.
	var values := seen.values()
	_check(
		"the six species do not all share one pace",
		values.min() < values.max(),
		"factors=%s" % [seen],
	)
	# The two ends named in the brief, so a retune that flattens them fails.
	_check(
		"the Wolf is quicker than the Cactoro",
		seen["Wolf"] > seen["Cactoro"],
		"wolf=%.2f cactoro=%.2f" % [seen["Wolf"], seen["Cactoro"]],
	)
	_check(
		"the Mushroom King ambles slower than the Demon hunts",
		seen["Mushroom King"] < seen["Demon"],
		"king=%.2f demon=%.2f" % [seen["Mushroom King"], seen["Demon"]],
	)
	player.queue_free()


## Distance covered, not the number asked for. Ordered by factor, so a factor
## dropped on the floor between the export and move_and_slide shows up here.
func _test_wander_distance_follows_the_factor() -> void:
	var player := _player_at(Vector3(0.0, 0.0, 500.0))
	var covered := {}
	for species in SCENES:
		var pal = await _spawn(species, Vector3.ZERO, player)
		covered[species] = await _distance_walking_at(pal, Tuning.PAL_WALK_SPEED)
		pal.queue_free()
		await process_frame

	for species in SCENES:
		var pal_scene = load(SCENES[species]).instantiate()
		var want: float = (
			Tuning.PAL_WALK_SPEED
			* pal_scene.speed_factor
			* FRAMES
			/ float(Engine.physics_ticks_per_second)
		)
		pal_scene.free()
		_check(
			"%s covers the ground its factor asks for" % species,
			absf(covered[species] - want) < want * 0.05,
			"covered=%.3f wanted=%.3f" % [covered[species], want],
		)

	_check(
		"the Wolf covers more ground than the Cactoro",
		covered["Wolf"] > covered["Cactoro"] * 1.5,
		"wolf=%.3f cactoro=%.3f" % [covered["Wolf"], covered["Cactoro"]],
	)
	_check(
		"the Demon covers more ground than the Mudwader",
		covered["Demon"] > covered["Mudwader"],
		"demon=%.3f mudwader=%.3f" % [covered["Demon"], covered["Mudwader"]],
	)
	player.queue_free()


## The flee side of the intent, stated in both directions on purpose. A
## Cactoro is meant to be caught by a walking player; a Wolf is not.
func _test_a_slow_species_is_outwalked_and_a_fast_one_is_not() -> void:
	var player := _player_at(Vector3(0.0, 0.0, 500.0))
	var walk := _player_distance(Tuning.PLAYER_SPEED)
	var sprint := _player_distance(Tuning.PLAYER_RUN_SPEED)

	var cactoro = await _spawn("Cactoro", Vector3.ZERO, player)
	var slow := await _distance_walking_at(cactoro, Tuning.PAL_FLEE_SPEED)
	cactoro.queue_free()
	await process_frame

	var wolf = await _spawn("Wolf", Vector3.ZERO, player)
	var fast := await _distance_walking_at(wolf, Tuning.PAL_FLEE_SPEED)
	wolf.queue_free()

	_check(
		"a fleeing Cactoro is run down by a walking player",
		slow < walk,
		"cactoro=%.3f player_walk=%.3f" % [slow, walk],
	)
	_check(
		"a fleeing Wolf outpaces a walking player",
		fast > walk,
		"wolf=%.3f player_walk=%.3f" % [fast, walk],
	)
	_check(
		"a fleeing Wolf is still run down by a sprinting player",
		fast < sprint,
		"wolf=%.3f player_sprint=%.3f" % [fast, sprint],
	)
	player.queue_free()


## The regression that matters. A follower slower than a sprinting player
## drifts back to FOLLOWER_LEASH and the party reads as broken, so the
## catch-up end of the follow ramp keeps FOLLOW_CATCHUP_FLOOR whatever the
## species factor is. Checked on the slowest species in the game.
func _test_a_slow_follower_still_keeps_up_with_a_sprinting_player() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn("Cactoro", Vector3.ZERO, player)
	pal.caught = true
	pal.state = pal.State.FOLLOW
	pal.global_position = Vector3.ZERO

	# The player actually runs away, frame by frame, which is the only way the
	# ramp reaches its catch-up end and stays there. Measuring distance over a
	# window against a stationary player does not: the pal arrives, the slow
	# radius takes over, and a broken floor still looks fine.
	#
	# The pal drives ITSELF here: _physics_process already ticks the state and
	# calls move_and_slide, so a hand-driven tick on top of it steps the pal
	# twice a frame and every speed reads double.
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	# Long enough that a follower losing ground reaches the leash, not just
	# drifts towards it: 8 seconds of sprint is 72 m of running away.
	var worst := 0.0
	for i in 480:
		player.global_position -= Vector3(0.0, 0.0, Tuning.PLAYER_RUN_SPEED * step)
		await physics_frame
		# Ignore the opening frames, which are pure acceleration from a stop.
		if i > 60:
			worst = maxf(worst, _flat(pal.global_position - player.global_position))

	_check(
		"the slowest species never falls to its leash behind a sprinting player",
		worst < Tuning.FOLLOWER_LEASH,
		"worst_gap=%.3f leash=%.2f" % [worst, Tuning.FOLLOWER_LEASH],
	)
	_check(
		"and settles within the follow distance rather than trailing away",
		_flat(pal.global_position - player.global_position)
		< Tuning.FOLLOW_CATCHUP_RADIUS,
		"final_gap=%.3f catchup_radius=%.2f" % [
			_flat(pal.global_position - player.global_position),
			Tuning.FOLLOW_CATCHUP_RADIUS,
		],
	)
	_check(
		"the catch-up floor clears the player's sprint outright",
		Tuning.FOLLOW_CATCHUP_FLOOR > Tuning.PLAYER_RUN_SPEED,
		"floor=%.2f sprint=%.2f" % [Tuning.FOLLOW_CATCHUP_FLOOR, Tuning.PLAYER_RUN_SPEED],
	)
	pal.queue_free()
	player.queue_free()


## Nothing hostile may outrun a sprint, or a fight has no exit. The Demon is
## the fastest chaser in the game, so it is the one worth asserting.
func _test_a_chaser_never_outruns_a_sprint() -> void:
	var player := _player_at(Vector3(0.0, 0.0, 500.0))
	var sprint := _player_distance(Tuning.PLAYER_RUN_SPEED)
	for species in ["Demon", "Mushroom King"]:
		var pal = await _spawn(species, Vector3.ZERO, player)
		var covered := await _distance_walking_at(pal, Tuning.PAL_CHASE_SPEED)
		pal.queue_free()
		await process_frame
		_check(
			"a chasing %s cannot outrun a sprinting player" % species,
			covered < sprint,
			"chase=%.3f sprint=%.3f" % [covered, sprint],
		)
	# The King is summoned to fight, and gives up after
	# PAL_NO_HIT_GIVE_UP_TIME with no hit landed. A chase below the player's
	# walk means it never lands one and quits the fight on its own.
	var king = await _spawn("Mushroom King", Vector3.ZERO, player)
	var king_chase := await _distance_walking_at(king, Tuning.PAL_CHASE_SPEED)
	king.queue_free()
	_check(
		"the King's chase outpaces the player's walk",
		king_chase > _player_distance(Tuning.PLAYER_SPEED),
		"king=%.3f player_walk=%.3f" % [king_chase, _player_distance(Tuning.PLAYER_SPEED)],
	)
	player.queue_free()


## Riding is the player's own knob, RIDE_SPEED, applied straight to the
## mount's velocity. A slow mount would be a regression and its whole job is
## water traversal, so the factor must not reach it.
func _test_riding_ignores_the_species_factor() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/player.gd")
	_check(
		"riding drives the mount at RIDE_SPEED, not through speed()",
		src.contains("Tuning.RIDE_SPEED") and not src.contains("mount.speed("),
		"player.gd no longer sets the mount velocity from RIDE_SPEED alone",
	)
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn("Mudwader", Vector3.ZERO, player)
	var ride := Tuning.RIDE_SPEED * Tuning.SWIM_SPEED_FACTOR
	_check(
		"a ridden Mudwader in the shallows still outswims every fish",
		ride > Tuning.PAL_WALK_SPEED * pal.speed(1.0) * Tuning.PAL_SPEED_FACTOR_MAX,
		"ride=%.2f" % ride,
	)
	_check(
		"the Mudwader's own pace is slow on land",
		pal.speed_factor < 1.0,
		"factor=%.2f" % pal.speed_factor,
	)
	pal.queue_free()
	player.queue_free()
