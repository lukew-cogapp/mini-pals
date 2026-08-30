extends GutTest
## Follower-defence assertions, ported from test/pal_combat_test.gd.
##
## A follower that lands a killing blow costs the player the catch, which is
## the whole loop. These pin that it damages hostiles, stops at one hitpoint,
## leaves the kill to the player, and always comes back to following.

class HitTarget:
	extends Node3D

	func damage(_amount: float, _from_position: Vector3) -> bool:
		return true


func test_follower_damages_a_hostile() -> void:
	var f = await _fixture()
	var before: int = f.hostile.hp
	for i in 20:
		f.follower._tick_defend(0.5)
	assert_true(
		f.hostile.hp < before,
		"a follower damages a hostile pal  hp %d -> %d" % [before, f.hostile.hp],
	)


func test_follower_never_kills() -> void:
	var f = await _fixture()
	# Long enough to run the target's whole health bar down several times over.
	for i in 200:
		f.follower._tick_defend(0.5)
	assert_true(
		f.hostile.hp == Tuning.FOLLOWER_MIN_TARGET_HP,
		"repeated follower attacks stop at one hitpoint  hp=%d max_hp=%d"
		% [f.hostile.hp, f.hostile.max_hp],
	)
	assert_true(
		not f.hostile.dying and f.hostile.hp > 0,
		"a follower never kills its target  dying=%s hp=%d" % [f.hostile.dying, f.hostile.hp],
	)


func test_player_can_still_kill_a_softened_target() -> void:
	var f = await _fixture()
	for i in 200:
		f.follower._tick_defend(0.5)
	var softened: int = f.hostile.hp
	f.hostile.take_hit(Vector3(0.0, 0.0, 5.0))
	assert_true(
		f.hostile.dying and softened == Tuning.FOLLOWER_MIN_TARGET_HP,
		"the player can still kill a target the follower softened up  softened=%d dying=%s hp=%d"
		% [softened, f.hostile.dying, f.hostile.hp],
	)


func test_follower_returns_to_follow() -> void:
	var f = await _fixture()
	var acquired: bool = f.follower.state == f.follower.State.DEFEND
	# The way a target most often leaves: the player cubes it.
	f.hostile.caught = true
	f.follower._tick_defend(0.1)
	assert_true(
		acquired and f.follower.state == f.follower.State.FOLLOW,
		"a follower acquires a hostile then returns to following once it is gone  acquired=%s state=%s"
		% [acquired, f.follower.State.keys()[f.follower.state]],
	)


func test_follower_ignores_caught_pals() -> void:
	var f = await _fixture()
	f.hostile.caught = true
	f.follower._defend_target = null
	f.follower.state = f.follower.State.FOLLOW
	f.follower._tick_follow(0.1)
	assert_true(
		f.follower.state == f.follower.State.FOLLOW and f.follower._defend_target == null,
		"a follower does not pick a fight with another caught pal  state=%s"
		% f.follower.State.keys()[f.follower.state],
	)


## A caught follower beside the player, and an aggressive demon in range of
## both, which is the situation the whole feature exists for.
func _fixture():
	var player := HitTarget.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO

	var follower = await _spawn("res://scenes/pal_wolf.tscn", Vector3(0.0, 0.0, 2.0), player)
	follower.caught = true
	follower.state = follower.State.FOLLOW

	var hostile = await _spawn("res://scenes/pal_demon.tscn", Vector3(0.0, 0.0, 3.0), player)
	# One follow tick is how the follower picks its target in play.
	follower._tick_follow(0.1)

	return {"player": player, "follower": follower, "hostile": hostile}


func _spawn(path: String, pos: Vector3, player: Node3D):
	var pal = load(path).instantiate()
	add_child_autofree(pal)
	await wait_process_frames(1)
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	# Physics off: these tests drive the state ticks directly, and a live
	# move_and_slide would walk the pals out of the arrangement under test.
	pal.set_physics_process(false)
	pal._player_cache = player
	return pal
