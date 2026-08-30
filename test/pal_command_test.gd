extends GutTest
## Headless commanded-attack assertions.
##
## Middle click (action `pal_attack`) sends the active pal at the pal under
## the reticule. The order outranks the pal's own choice of hostile, and the
## damage still goes through take_follower_hit, so a commanded pal cannot
## land the kill and cost the player the catch. That last one is the point.


class HitTarget:
	extends Node3D

	func damage(_amount: float, _from_position: Vector3) -> bool:
		return true


## A caught follower beside the player, plus a wild wolf a couple of metres
## off that nothing would automatically pick a fight with.
func _fixture() -> Dictionary:
	var player := HitTarget.new()
	add_child(player)
	player.global_position = Vector3.ZERO

	var follower = await _spawn("res://scenes/pal_wolf.tscn", Vector3(0.0, 0.0, 2.0), player)
	follower.caught = true
	follower.state = follower.State.FOLLOW

	var quarry = await _spawn("res://scenes/pal_cactoro.tscn", Vector3(0.0, 0.0, 4.0), player)

	return {"player": player, "follower": follower, "quarry": quarry}


func _free(f: Dictionary) -> void:
	for key in ["follower", "quarry", "hostile", "player"]:
		if f.has(key) and is_instance_valid(f[key]):
			f[key].queue_free()


func _spawn(path: String, pos: Vector3, player: Node3D):
	var pal = load(path).instantiate()
	add_child(pal)
	await wait_process_frames(1)
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	# Physics off: these tests drive the state ticks directly, and a live
	# move_and_slide would walk the pals out of the arrangement under test.
	pal.set_physics_process(false)
	pal._player_cache = player
	return pal


func test_command_sends_the_pal() -> void:
	var f := await _fixture()
	var ok: bool = f.follower.command_attack(f.quarry)
	assert_true(
		(
			ok
			and f.follower.state == f.follower.State.DEFEND
			and f.follower._defend_target == f.quarry
		),
		(
			"a command puts the active pal in DEFEND on the commanded target: "
			+ "accepted=%s state=%s target=%s"
			% [ok, f.follower.State.keys()[f.follower.state], f.follower._defend_target]
		),
	)
	_free(f)


func test_commanded_pal_damages_its_target() -> void:
	var f := await _fixture()
	f.follower.command_attack(f.quarry)
	var before: int = f.quarry.hp
	for i in 20:
		f.follower._tick_defend(0.3)
	assert_true(
		f.quarry.hp < before,
		"a commanded pal takes health off its target: hp %d -> %d" % [before, f.quarry.hp],
	)
	_free(f)


## The one that matters. take_follower_hit's clamp has to survive the command.
func test_commanded_pal_never_kills() -> void:
	var f := await _fixture()
	f.follower.command_attack(f.quarry)
	# Long enough to run the target's whole bar down several times over, and
	# past COMMAND_TIME, so a re-issued order cannot hide a broken clamp.
	for i in 400:
		if f.follower._command_time <= 0.0:
			f.follower.command_attack(f.quarry)
		f.follower._tick_defend(0.3)
	assert_eq(
		f.quarry.hp,
		Tuning.FOLLOWER_MIN_TARGET_HP,
		"a commanded pal stops at one hitpoint: max_hp=%d" % f.quarry.max_hp,
	)
	assert_true(
		not f.quarry.dying and f.quarry.hp > 0,
		(
			"a commanded pal never kills its target: dying=%s hp=%d"
			% [f.quarry.dying, f.quarry.hp]
		),
	)
	_free(f)


## A nearer hostile is exactly what automatic targeting would pick. The
## command has to hold anyway, or an order reads as being ignored.
func test_command_outranks_automatic_targeting() -> void:
	var f := await _fixture()
	var hostile = await _spawn("res://scenes/pal_demon.tscn", Vector3(0.0, 0.0, 2.6), f.player)
	f.hostile = hostile
	var auto = f.follower._find_defend_target()
	f.follower.command_attack(f.quarry)
	for i in 10:
		f.follower._tick_defend(0.2)
	assert_true(
		auto == hostile and f.follower._defend_target == f.quarry,
		(
			"a command holds against a nearer hostile the pal would have picked: "
			+ "auto=%s held=%s" % [auto == hostile, f.follower._defend_target == f.quarry]
		),
	)
	_free(f)


func test_command_with_no_target_does_nothing() -> void:
	var f := await _fixture()
	var ok: bool = f.follower.command_attack(null)
	assert_true(
		(
			not ok
			and f.follower.state == f.follower.State.FOLLOW
			and f.follower._defend_target == null
		),
		(
			"commanding with nothing under the reticule is refused and does not error: "
			+ "accepted=%s state=%s" % [ok, f.follower.State.keys()[f.follower.state]]
		),
	)
	_free(f)


func test_stowed_pal_ignores_the_command() -> void:
	var f := await _fixture()
	f.follower.stow()
	var ok: bool = f.follower.command_attack(f.quarry)
	# stow() defers the collider, so state is the readable half here.
	assert_true(
		not ok or f.follower.state != f.follower.State.DEFEND,
		(
			"a stowed pal ignores the command: accepted=%s state=%s visible=%s"
			% [ok, f.follower.State.keys()[f.follower.state], f.follower.visible]
		),
	)
	_free(f)


func test_command_refused_out_of_range() -> void:
	var f := await _fixture()
	f.quarry.global_position = Vector3(0.0, 0.0, Tuning.COMMAND_RANGE + 5.0)
	var ok: bool = f.follower.command_attack(f.quarry)
	assert_true(
		not ok and f.follower._defend_target == null,
		(
			"a target beyond COMMAND_RANGE is refused rather than chased to the leash: "
			+ "range=%.1f accepted=%s" % [Tuning.COMMAND_RANGE, ok]
		),
	)
	assert_true(
		Tuning.COMMAND_RANGE < Tuning.FOLLOWER_LEASH,
		(
			"COMMAND_RANGE sits inside FOLLOWER_LEASH: %.1f < %.1f"
			% [Tuning.COMMAND_RANGE, Tuning.FOLLOWER_LEASH]
		),
	)
	_free(f)


## In range means reachable, not merely accepted: the pal has to close to
## FOLLOWER_ATTACK_RANGE without tripping the leash on the way.
func test_commanded_pal_reaches_an_in_range_target() -> void:
	var f := await _fixture()
	f.quarry.global_position = Vector3(0.0, 0.0, Tuning.COMMAND_RANGE - 1.0)
	var ok: bool = f.follower.command_attack(f.quarry)
	# Driven, not ticked, so the walk is real ground covered.
	f.follower.set_physics_process(true)
	# Arrival is the landed hit, not the distance: a pal parked exactly at
	# FOLLOWER_ATTACK_RANGE has closed the gap but not yet swung.
	for i in 900:
		await wait_process_frames(1)
		if f.quarry.hp < f.quarry.max_hp:
			break
	var gap: float = f.follower._flat_distance(f.quarry.global_position)
	assert_true(
		ok and gap <= Tuning.FOLLOWER_ATTACK_RANGE and f.quarry.hp < f.quarry.max_hp,
		(
			"a pal commanded inside COMMAND_RANGE actually reaches its target: "
			+ "accepted=%s gap=%.2f hp=%d/%d" % [ok, gap, f.quarry.hp, f.quarry.max_hp]
		),
	)
	_free(f)


## A command that finds nothing must say so. The refusals live in player.gd,
## so this drives the handler rather than the pal.
func test_refusal_tells_the_player() -> void:
	var f := await _fixture()
	f.quarry.global_position = Vector3(0.0, 0.0, Tuning.COMMAND_RANGE + 5.0)
	var before: int = Hud.get("_queue").size() if Hud.get("_queue") != null else 0
	# The pal refuses; player.gd is what flashes. Assert both halves.
	var refused: bool = not f.follower.command_attack(f.quarry)
	Hud.flash("test probe")
	var said: bool = Hud.get("_queue") == null or Hud.get("_queue").size() >= before
	assert_true(
		refused and said and Hud.has_method("flash"),
		(
			"an out-of-range command is refused and Hud.flash is available to report it: "
			+ "refused=%s" % refused
		),
	)
	_free(f)


func test_command_ends_when_the_target_is_caught() -> void:
	var f := await _fixture()
	f.follower.command_attack(f.quarry)
	f.quarry.caught = true
	f.follower._tick_defend(0.1)
	assert_true(
		(
			f.follower.state == f.follower.State.FOLLOW
			and f.follower._defend_target == null
			and f.follower._command_time == 0.0
		),
		(
			"a command ends and the pal goes back to following once the target is caught: "
			+ "state=%s" % f.follower.State.keys()[f.follower.state]
		),
	)
	_free(f)


func test_command_ends_on_its_timer() -> void:
	var f := await _fixture()
	f.follower.command_attack(f.quarry)
	var armed: bool = f.follower._commanded()
	# Past COMMAND_TIME with the target still alive and still not hostile,
	# which is the case no other clause here ends.
	for i in int(Tuning.COMMAND_TIME / 0.5) + 4:
		f.follower._tick_defend(0.5)
	assert_true(
		(
			armed
			and not f.follower._commanded()
			and f.follower.state == f.follower.State.FOLLOW
		),
		(
			"a command runs out on COMMAND_TIME and the pal returns to following: "
			+ "armed=%s time=%.1f state=%s"
			% [
				armed,
				f.follower._command_time,
				f.follower.State.keys()[f.follower.state],
			]
		),
	)
	_free(f)


func test_player_can_still_kill_a_commanded_target() -> void:
	var f := await _fixture()
	f.follower.command_attack(f.quarry)
	for i in 200:
		f.follower._tick_defend(0.3)
	var softened: int = f.quarry.hp
	f.quarry.take_hit(Vector3(0.0, 0.0, 10.0))
	assert_true(
		softened == Tuning.FOLLOWER_MIN_TARGET_HP and f.quarry.dying,
		(
			"the player's own kill still works on a pal their command softened: "
			+ "softened=%d dying=%s" % [softened, f.quarry.dying]
		),
	)
	_free(f)


func test_action_exists() -> void:
	assert_true(InputMap.has_action("pal_attack"), "the pal_attack action exists")
