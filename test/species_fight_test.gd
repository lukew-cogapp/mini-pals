extends GutTest
## Wild-versus-wild aggression, ported from test/species_fight_test.gd.
##
## The things that would ruin the world if they were wrong: a demon brawling
## with its own kind, a demon that ignores the player because it is busy, a
## fight that never ends, and who gets paid when a pal dies. Wild fights kill,
## so the payout is decided by whether the player was in the fight recently
## (Tuning.PAL_CREDIT_TIME) rather than by who struck last.

class FarAway:
	extends Node3D

	var hits := 0

	func damage(_amount: float, _from_position: Vector3) -> bool:
		hits += 1
		return true


## Each test frees its fixture with queue_free, which has not run by the time
## GUT counts children still parented. One frame between tests drains it.
func after_each() -> void:
	await wait_process_frames(1)


## One frame of the demon's own state machine, entered where play enters it:
## idle scans for a rival, ATTACK then runs the brawl.
func _tick(pal, delta: float) -> void:
	match pal.state:
		pal.State.ATTACK:
			pal._tick_attack(delta)
		_:
			pal._tick_idle(delta)


func test_demon_engages_a_wolf() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	var before: int = f.other.hp
	for i in 4:
		_tick(f.demon, 0.5)
	assert_true(
		f.demon._rival == f.other and f.other.hp < before,
		(
			"a demon engages a nearby wolf  rival=%s hp %d -> %d"
			% [f.demon._rival != null, before, f.other.hp]
		),
	)
	_free(f)


func test_demon_ignores_another_demon() -> void:
	var f = await _fixture("res://scenes/pal_demon.tscn")
	var before: int = f.other.hp
	for i in 20:
		_tick(f.demon, 0.5)
	assert_true(
		f.demon._rival == null and f.other.hp == before,
		(
			"a demon does not pick a fight with another demon  rival=%s hp %d -> %d"
			% [f.demon._rival, before, f.other.hp]
		),
	)
	_free(f)


## The demon starts mid-brawl with a wolf, then the player walks up. The
## player is the point of the game, so the brawl has to be dropped.
func test_player_outranks_a_rival() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	# Long enough for the staggered rival scan to have come round.
	for i in 6:
		_tick(f.demon, 0.5)
	var brawling: bool = f.demon._rival != null
	f.player.global_position = f.demon.global_position + Vector3(0.0, 0.0, 2.0)
	var wolf_hp: int = f.other.hp
	for i in 10:
		_tick(f.demon, 0.5)
	assert_true(
		brawling and f.demon._rival == null and f.other.hp == wolf_hp,
		(
			"the player takes priority over a pal target  brawling=%s rival=%s wolf hp=%d"
			% [brawling, f.demon._rival, f.other.hp]
		),
	)
	_free(f)


## Wild fights kill. The world is kept populated by respawning instead; see
## test/respawn_test.gd.
func test_a_fight_kills() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	# Long enough to run the wolf's whole health bar down several times over.
	for i in 400:
		_tick(f.demon, 0.25)
	assert_true(
		f.other.hp <= 0 and f.other.dying and not f.other.is_in_group("pal"),
		(
			"a wild fight kills the loser  hp=%d max_hp=%d dying=%s"
			% [f.other.hp, f.other.max_hp, f.other.dying]
		),
	)
	_free(f)


func test_a_fight_terminates() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	for i in 400:
		_tick(f.demon, 0.25)
	assert_true(
		f.demon._rival == null and f.demon.state != f.demon.State.ATTACK,
		(
			"a fight ends rather than looping on a dead loser  rival=%s state=%s"
			% [f.demon._rival, f.demon.State.keys()[f.demon.state]]
		),
	)
	_free(f)


## Two demons cannot brawl, so this is the case that matters: an aggressive
## pal hit by another species answers rather than standing there.
func test_a_rival_hits_back() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	var other_demon = await _spawn(
		"res://scenes/pal_demon.tscn", Vector3(40.0, 0.0, 0.0), f.player
	)
	other_demon.take_rival_hit(f.other)
	assert_true(
		other_demon._rival == f.other and other_demon.state == other_demon.State.ATTACK,
		(
			"an aggressive pal hit by another species fights back  rival=%s state=%s"
			% [
				other_demon._rival != null,
				other_demon.State.keys()[other_demon.state],
			]
		),
	)
	other_demon.queue_free()
	_free(f)


## --- Retaliation -----------------------------------------------------------

## The case the old `aggressive and ...` gate never covered: a demon mauling a
## wolf used to get no answer at all, because demons are the only aggressive
## species and _is_rival excludes their own kind.
func test_a_skittish_pal_fights_the_pal_that_hit_it() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	f.other.take_rival_hit(f.demon)
	assert_true(
		f.other.state == f.other.State.ATTACK and f.other._rival == f.demon,
		(
			"a skittish pal attacked by another pal fights that pal  state=%s rival is the demon=%s"
			% [f.other.State.keys()[f.other.state], f.other._rival == f.demon]
		),
	)
	_free(f)


## Entering ATTACK is not the same as landing anything, so this drives the
## wolf's own ticks and reads the demon's health.
func test_a_retaliating_pal_hurts_its_attacker() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	f.demon.max_hp = 30
	f.demon.hp = 30
	var before: int = f.demon.hp
	f.other.take_rival_hit(f.demon)
	for i in 10:
		_tick(f.other, 0.5)
	assert_true(
		f.demon.hp < before,
		"a retaliating pal damages the pal that hit it  demon hp %d -> %d" % [before, f.demon.hp],
	)
	_free(f)


## Retaliation is against the attacking pal only. Nothing here may make a
## skittish species hostile to the player, who is a separate rule entirely.
##
## The brawl is run and then the rival taken away, because that is where a
## leaked player-aggro would show: while a rival is alive _tick_attack runs
## the brawl branch and never looks at the player at all, so a wolf that had
## been angered at them would look identical until the demon was gone.
func test_retaliation_never_angers_a_pal_at_the_player() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	f.demon.max_hp = 60
	f.demon.hp = 60
	# The player stands right next to the brawl, well inside attack range.
	f.player.global_position = f.other.global_position + Vector3(0.0, 0.0, 1.0)
	f.other.take_rival_hit(f.demon)
	for i in 20:
		_tick(f.other, 0.25)
	var during: int = f.player.hits
	# The demon is gone; a wolf carrying player aggro would now turn on them.
	f.other._rival = null
	f.other._rival_fight = 0.0
	for i in 40:
		_tick(f.other, 0.25)
	assert_true(
		during == 0 and f.player.hits == 0,
		(
			"retaliation never turns a pal on the player  player hits during=%d after=%d, wolf state=%s"
			% [during, f.player.hits, f.other.State.keys()[f.other.state]]
		),
	)
	_free(f)


## A hits B, B answers, A answers back.
##
## RIVAL_FIGHT_TIME does NOT bound this: when it expires each side drops its
## rival, and the next hit that lands re-arms retaliation with a fresh timer,
## so the pair simply renews. What ends it is lethality. Both start on 30 hp
## and RIVAL_DAMAGE is 1 on a RIVAL_ATTACK_COOLDOWN, so the window here is
## sized from those rather than from the fight timer.
func test_a_mutual_fight_terminates() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	f.demon.max_hp = 30
	f.demon.hp = 30
	f.other.take_rival_hit(f.demon)
	var step := 0.25
	var rounds: float = f.demon.max_hp * Tuning.RIVAL_ATTACK_COOLDOWN * 2.0
	var limit := int(rounds / step)
	for i in limit:
		_tick(f.demon, step)
		_tick(f.other, step)
	var settled: bool = (
		f.demon.dying
		or f.other.dying
		or (f.demon._rival == null and f.other._rival == null)
	)
	assert_true(
		settled,
		(
			"a mutual fight settles rather than trading blows for good  demon dying=%s hp=%d, wolf dying=%s hp=%d, over %.0fs"
			% [f.demon.dying, f.demon.hp, f.other.dying, f.other.hp, limit * step]
		),
	)
	_free(f)


## --- Who gets paid for a death ---------------------------------------------

## Every item plus the XP, so a test can diff the lot across a death without
## having to know which drop the species carries.
func _payout() -> Array:
	var items := 0
	for item in Inventory.items():
		items += Inventory.count(item)
	return [items, Party.player_level, Party.xp]


## Age a pal through the real countdown in _physics_process rather than by
## setting _credit directly, so this asserts against the shipped timer. The
## pal is put back where it started afterwards: a physics frame walks it.
func _age(pal, seconds: float) -> void:
	var at: Vector3 = pal.global_position
	var step := 0.5
	var left := seconds
	while left > 0.0:
		pal._physics_process(minf(step, left))
		left -= step
	pal.global_position = at
	pal.velocity = Vector3.ZERO


## Kill a pal outright by another pal's hand, however much health it has.
func _rival_kill(victim, killer) -> void:
	for i in victim.max_hp + 2:
		if victim.dying:
			return
		victim.take_rival_hit(killer)


## The case the whole rule exists for: the player softens a pal, something
## else finishes it seconds later. The player did the work.
func test_a_brawl_the_player_started_pays() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	f.other.take_hit(Vector3(0.0, 0.0, 5.0))
	var before := _payout()
	_rival_kill(f.other, f.demon)
	var after := _payout()
	assert_true(
		after[0] > before[0] and (after[1] > before[1] or after[2] > before[2]),
		(
			"a pal the player bit still pays when something else kills it  drops %d -> %d, level %d -> %d, xp %d -> %d"
			% [before[0], after[0], before[1], after[1], before[2], after[2]]
		),
	)
	_free(f)


## The abuse this blocks: standing back and watching demons brawl to farm
## pelts and XP for nothing.
func test_a_brawl_across_the_island_pays_nothing() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	var before := _payout()
	_rival_kill(f.other, f.demon)
	var after := _payout()
	assert_true(
		f.other.dying and after == before,
		(
			"a wild kill the player had no part in pays nothing  dying=%s payout %s -> %s"
			% [f.other.dying, before, after]
		),
	)
	_free(f)


## Being attacked counts as being in the fight, so a demon that chased the
## player and then lost to a wolf is still the player's.
func test_a_pal_that_hit_the_player_pays() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	var other_demon = await _spawn(
		"res://scenes/pal_demon.tscn", Vector3(60.0, 0.0, 0.0), f.player
	)
	other_demon.max_hp = 30
	other_demon.hp = 30
	# The demon reaches the player and lands one, which is what opens the
	# window; the player never swings back.
	other_demon.global_position = f.player.global_position + Vector3(0.0, 0.0, 1.0)
	other_demon._enter_attack()
	for i in 10:
		other_demon._tick_attack(0.5)
	var landed: bool = f.player.hits > 0
	var before := _payout()
	_rival_kill(other_demon, f.other)
	var after := _payout()
	assert_true(
		landed and other_demon.dying and after[0] > before[0],
		(
			"a pal that hit the player pays when a third party kills it  player hits=%d drops %d -> %d"
			% [f.player.hits, before[0], after[0]]
		),
	)
	other_demon.queue_free()
	_free(f)


## The assertion that proves the window is a timer and not a flag: the same
## bite, left long enough, pays nothing.
func test_the_credit_window_expires() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	f.other.take_hit(Vector3(0.0, 0.0, 5.0))
	var opened: bool = f.other._credit > 0.0
	_age(f.other, Tuning.PAL_CREDIT_TIME + 1.0)
	var before := _payout()
	_rival_kill(f.other, f.demon)
	var after := _payout()
	assert_true(
		opened and f.other.dying and after == before,
		(
			"a bite older than PAL_CREDIT_TIME no longer pays  credit opened=%s window=%.1f payout %s -> %s"
			% [opened, Tuning.PAL_CREDIT_TIME, before, after]
		),
	)
	_free(f)


## Nothing about the rule may change the ordinary case of punching a pal to
## death yourself.
func test_the_players_own_kill_pays() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	var before := _payout()
	for i in f.other.max_hp + 2:
		if f.other.dying:
			break
		f.other.take_hit(Vector3(0.0, 0.0, 5.0))
	var after := _payout()
	assert_true(
		(
			f.other.dying
			and after[0] > before[0]
			and (after[1] > before[1] or after[2] > before[2])
		),
		(
			"the player's own kill still pays the drop and the XP  drops %d -> %d, level %d -> %d, xp %d -> %d"
			% [before[0], after[0], before[1], after[1], before[2], after[2]]
		),
	)
	_free(f)


## --- Temperament -----------------------------------------------------------

func test_a_neutral_pal_does_not_flee() -> void:
	var player := FarAway.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	var pal = await _spawn("res://scenes/pal_mudwader.tscn", Vector3(0.0, 0.0, 1.0), player)
	var start: Vector3 = pal.global_position
	for i in 20:
		pal._tick_idle(0.2)
	assert_true(
		pal.state != pal.State.FLEE and pal.global_position.is_equal_approx(start),
		(
			"a neutral pal does not flee the player standing on top of it  state=%s moved=%.2f flee_distance=%.1f"
			% [
				pal.State.keys()[pal.state],
				pal.global_position.distance_to(start),
				Tuning.PAL_FLEE_DISTANCE,
			]
		),
	)
	pal.queue_free()


## The behaviour the enum replaced, so a species that should still run does.
func test_a_skittish_pal_still_flees() -> void:
	var player := FarAway.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	var pal = await _spawn("res://scenes/pal_wolf.tscn", Vector3(0.0, 0.0, 1.0), player)
	pal._tick_idle(0.2)
	assert_true(
		pal.state == pal.State.FLEE,
		"a skittish pal still flees  state=%s" % pal.State.keys()[pal.state],
	)
	pal.queue_free()


func test_a_neutral_pal_fights_back() -> void:
	var player := FarAway.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	var pal = await _spawn("res://scenes/pal_mudwader.tscn", Vector3(0.0, 0.0, 1.0), player)
	pal.max_hp = 30
	pal.hp = 30
	pal.take_hit(player.global_position)
	var angered: bool = pal.state == pal.State.ATTACK
	for i in 10:
		pal._tick_attack(0.5)
	assert_true(
		angered and player.hits > 0,
		(
			"a neutral pal fights back when bitten  state=%s player hits=%d"
			% [pal.State.keys()[pal.state], player.hits]
		),
	)
	pal.queue_free()


func test_a_neutral_pal_leaves_the_player_alone() -> void:
	var player := FarAway.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	var pal = await _spawn("res://scenes/pal_mudwader.tscn", Vector3(0.0, 0.0, 1.0), player)
	for i in 60:
		_tick(pal, 0.2)
	assert_true(
		player.hits == 0 and pal.state != pal.State.ATTACK,
		(
			"a neutral pal never starts on the player  state=%s player hits=%d"
			% [pal.State.keys()[pal.state], player.hits]
		),
	)
	pal.queue_free()


## A demon and one other pal beside each other, with the player far enough
## off that they are not in PAL_AGGRO_RADIUS and the demon is free to brawl.
func _fixture(other_scene: String):
	var player := FarAway.new()
	add_child(player)
	player.global_position = Vector3(0.0, 0.0, 500.0)

	var demon = await _spawn("res://scenes/pal_demon.tscn", Vector3.ZERO, player)
	# Inside RIVAL_ATTACK_RANGE already: these tests drive ticks directly, so
	# nothing ever moves and a demon parked at chase distance never arrives.
	var other = await _spawn(other_scene, Vector3(0.0, 0.0, 1.5), player)
	# A deep health bar, so a test that wants to watch a fight in progress is
	# not reading a corner case where it was over in two swings.
	other.max_hp = 30
	other.hp = 30

	return {"player": player, "demon": demon, "other": other}


func _free(f) -> void:
	f.demon.queue_free()
	f.other.queue_free()
	f.player.queue_free()


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
