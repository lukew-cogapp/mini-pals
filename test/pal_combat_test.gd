extends SceneTree
## Headless follower-defence assertions. Run:
##   godot --headless --path . -s test/pal_combat_test.gd
##
## A follower that lands a killing blow costs the player the catch, which is
## the whole loop. These pin that it damages hostiles, stops at one hitpoint,
## leaves the kill to the player, and always comes back to following.

class HitTarget:
	extends Node3D

	func damage(_amount: float, _from_position: Vector3) -> bool:
		return true


var _fails := 0


func _init() -> void:
	await process_frame

	await _test_follower_damages_a_hostile()
	await _test_follower_never_kills()
	await _test_player_can_still_kill_a_softened_target()
	await _test_follower_returns_to_follow()
	await _test_follower_ignores_caught_pals()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _test_follower_damages_a_hostile() -> void:
	var f = await _fixture()
	var before: int = f.hostile.hp
	for i in 20:
		f.follower._tick_defend(0.5)
	_check(
		"a follower damages a hostile pal",
		f.hostile.hp < before,
		"hp %d -> %d" % [before, f.hostile.hp],
	)
	_free(f)


func _test_follower_never_kills() -> void:
	var f = await _fixture()
	# Long enough to run the target's whole health bar down several times over.
	for i in 200:
		f.follower._tick_defend(0.5)
	_check(
		"repeated follower attacks stop at one hitpoint",
		f.hostile.hp == Tuning.FOLLOWER_MIN_TARGET_HP,
		"hp=%d max_hp=%d" % [f.hostile.hp, f.hostile.max_hp],
	)
	_check(
		"a follower never kills its target",
		not f.hostile.dying and f.hostile.hp > 0,
		"dying=%s hp=%d" % [f.hostile.dying, f.hostile.hp],
	)
	_free(f)


func _test_player_can_still_kill_a_softened_target() -> void:
	var f = await _fixture()
	for i in 200:
		f.follower._tick_defend(0.5)
	var softened: int = f.hostile.hp
	f.hostile.take_hit(Vector3(0.0, 0.0, 5.0))
	_check(
		"the player can still kill a target the follower softened up",
		f.hostile.dying and softened == Tuning.FOLLOWER_MIN_TARGET_HP,
		"softened=%d dying=%s hp=%d" % [softened, f.hostile.dying, f.hostile.hp],
	)
	_free(f)


func _test_follower_returns_to_follow() -> void:
	var f = await _fixture()
	var acquired: bool = f.follower.state == f.follower.State.DEFEND
	# The way a target most often leaves: the player cubes it.
	f.hostile.caught = true
	f.follower._tick_defend(0.1)
	_check(
		"a follower acquires a hostile then returns to following once it is gone",
		acquired and f.follower.state == f.follower.State.FOLLOW,
		"acquired=%s state=%s" % [acquired, f.follower.State.keys()[f.follower.state]],
	)
	_free(f)


func _test_follower_ignores_caught_pals() -> void:
	var f = await _fixture()
	f.hostile.caught = true
	f.follower._defend_target = null
	f.follower.state = f.follower.State.FOLLOW
	f.follower._tick_follow(0.1)
	_check(
		"a follower does not pick a fight with another caught pal",
		f.follower.state == f.follower.State.FOLLOW and f.follower._defend_target == null,
		"state=%s" % f.follower.State.keys()[f.follower.state],
	)
	_free(f)


## A caught follower beside the player, and an aggressive demon in range of
## both, which is the situation the whole feature exists for.
func _fixture():
	var player := HitTarget.new()
	get_root().add_child(player)
	player.global_position = Vector3.ZERO

	var follower = await _spawn("res://scenes/pal_wolf.tscn", Vector3(0.0, 0.0, 2.0), player)
	follower.caught = true
	follower.state = follower.State.FOLLOW

	var hostile = await _spawn("res://scenes/pal_demon.tscn", Vector3(0.0, 0.0, 3.0), player)
	# One follow tick is how the follower picks its target in play.
	follower._tick_follow(0.1)

	return {"player": player, "follower": follower, "hostile": hostile}


func _free(f) -> void:
	f.follower.queue_free()
	f.hostile.queue_free()
	f.player.queue_free()


func _spawn(path: String, pos: Vector3, player: Node3D):
	var pal = load(path).instantiate()
	get_root().add_child(pal)
	await process_frame
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	# Physics off: these tests drive the state ticks directly, and a live
	# move_and_slide would walk the pals out of the arrangement under test.
	pal.set_physics_process(false)
	pal._player_cache = player
	return pal
