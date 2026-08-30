extends SceneTree
## Headless assertions for wild-versus-wild aggression. Run:
##   godot --headless --path . -s test/species_fight_test.gd
##
## The three things that would ruin the world if they were wrong: a demon
## brawling with its own kind, a demon that ignores the player because it is
## busy, and a fight that never ends, either because it kills the map's pals
## off or because two immortal pals swing at each other for good.

class FarAway:
	extends Node3D

	var hits := 0

	func damage(_amount: float, _from_position: Vector3) -> bool:
		hits += 1
		return true


var _fails := 0


func _init() -> void:
	await process_frame

	await _test_demon_engages_a_wolf()
	await _test_demon_ignores_another_demon()
	await _test_player_outranks_a_rival()
	await _test_a_fight_never_kills()
	await _test_a_fight_terminates()
	await _test_a_rival_hits_back()
	await _test_a_neutral_pal_does_not_flee()
	await _test_a_skittish_pal_still_flees()
	await _test_a_neutral_pal_fights_back()
	await _test_a_neutral_pal_leaves_the_player_alone()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


## One frame of the demon's own state machine, entered where play enters it:
## idle scans for a rival, ATTACK then runs the brawl.
func _tick(pal, delta: float) -> void:
	match pal.state:
		pal.State.ATTACK:
			pal._tick_attack(delta)
		_:
			pal._tick_idle(delta)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _test_demon_engages_a_wolf() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	var before: int = f.other.hp
	for i in 4:
		_tick(f.demon, 0.5)
	_check(
		"a demon engages a nearby wolf",
		f.demon._rival == f.other and f.other.hp < before,
		"rival=%s hp %d -> %d" % [f.demon._rival != null, before, f.other.hp],
	)
	_free(f)


func _test_demon_ignores_another_demon() -> void:
	var f = await _fixture("res://scenes/pal_demon.tscn")
	var before: int = f.other.hp
	for i in 20:
		_tick(f.demon, 0.5)
	_check(
		"a demon does not pick a fight with another demon",
		f.demon._rival == null and f.other.hp == before,
		"rival=%s hp %d -> %d" % [f.demon._rival, before, f.other.hp],
	)
	_free(f)


## The demon starts mid-brawl with a wolf, then the player walks up. The
## player is the point of the game, so the brawl has to be dropped.
func _test_player_outranks_a_rival() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	# Long enough for the staggered rival scan to have come round.
	for i in 6:
		_tick(f.demon, 0.5)
	var brawling: bool = f.demon._rival != null
	f.player.global_position = f.demon.global_position + Vector3(0.0, 0.0, 2.0)
	var wolf_hp: int = f.other.hp
	for i in 10:
		_tick(f.demon, 0.5)
	_check(
		"the player takes priority over a pal target",
		brawling and f.demon._rival == null and f.other.hp == wolf_hp,
		"brawling=%s rival=%s wolf hp=%d" % [brawling, f.demon._rival, f.other.hp],
	)
	_free(f)


## A world that culled its own pals would be empty by the time the player
## walked out to it, so the loser is maimed and left for a cube instead.
func _test_a_fight_never_kills() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	# Long enough to run the wolf's whole health bar down several times over.
	for i in 400:
		_tick(f.demon, 0.25)
	_check(
		"a wild fight maims but never kills",
		f.other.hp == Tuning.RIVAL_MIN_TARGET_HP and not f.other.dying,
		"hp=%d max_hp=%d dying=%s" % [f.other.hp, f.other.max_hp, f.other.dying],
	)
	_free(f)


func _test_a_fight_terminates() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	for i in 400:
		_tick(f.demon, 0.25)
	_check(
		"a fight ends rather than looping on a maimed loser",
		f.demon._rival == null and f.demon.state != f.demon.State.ATTACK,
		"rival=%s state=%s" % [f.demon._rival, f.demon.State.keys()[f.demon.state]],
	)
	_free(f)


## Two demons cannot brawl, so this is the case that matters: an aggressive
## pal hit by another species answers rather than standing there.
func _test_a_rival_hits_back() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn")
	var other_demon = await _spawn("res://scenes/pal_demon.tscn", Vector3(40.0, 0.0, 0.0), f.player)
	other_demon.take_rival_hit(f.other)
	_check(
		"an aggressive pal hit by another species fights back",
		other_demon._rival == f.other and other_demon.state == other_demon.State.ATTACK,
		"rival=%s state=%s" % [
			other_demon._rival != null,
			other_demon.State.keys()[other_demon.state],
		],
	)
	other_demon.queue_free()
	_free(f)


## --- Temperament -----------------------------------------------------------

func _test_a_neutral_pal_does_not_flee() -> void:
	var player := FarAway.new()
	get_root().add_child(player)
	player.global_position = Vector3.ZERO
	var pal = await _spawn("res://scenes/pal_mudwader.tscn", Vector3(0.0, 0.0, 1.0), player)
	var start: Vector3 = pal.global_position
	for i in 20:
		pal._tick_idle(0.2)
	_check(
		"a neutral pal does not flee the player standing on top of it",
		pal.state != pal.State.FLEE and pal.global_position.is_equal_approx(start),
		"state=%s moved=%.2f flee_distance=%.1f" % [
			pal.State.keys()[pal.state],
			pal.global_position.distance_to(start),
			Tuning.PAL_FLEE_DISTANCE,
		],
	)
	pal.queue_free()
	player.queue_free()


## The behaviour the enum replaced, so a species that should still run does.
func _test_a_skittish_pal_still_flees() -> void:
	var player := FarAway.new()
	get_root().add_child(player)
	player.global_position = Vector3.ZERO
	var pal = await _spawn("res://scenes/pal_wolf.tscn", Vector3(0.0, 0.0, 1.0), player)
	pal._tick_idle(0.2)
	_check(
		"a skittish pal still flees",
		pal.state == pal.State.FLEE,
		"state=%s" % pal.State.keys()[pal.state],
	)
	pal.queue_free()
	player.queue_free()


func _test_a_neutral_pal_fights_back() -> void:
	var player := FarAway.new()
	get_root().add_child(player)
	player.global_position = Vector3.ZERO
	var pal = await _spawn("res://scenes/pal_mudwader.tscn", Vector3(0.0, 0.0, 1.0), player)
	pal.max_hp = 30
	pal.hp = 30
	pal.take_hit(player.global_position)
	var angered: bool = pal.state == pal.State.ATTACK
	for i in 10:
		pal._tick_attack(0.5)
	_check(
		"a neutral pal fights back when bitten",
		angered and player.hits > 0,
		"state=%s player hits=%d" % [pal.State.keys()[pal.state], player.hits],
	)
	pal.queue_free()
	player.queue_free()


func _test_a_neutral_pal_leaves_the_player_alone() -> void:
	var player := FarAway.new()
	get_root().add_child(player)
	player.global_position = Vector3.ZERO
	var pal = await _spawn("res://scenes/pal_mudwader.tscn", Vector3(0.0, 0.0, 1.0), player)
	for i in 60:
		_tick(pal, 0.2)
	_check(
		"a neutral pal never starts on the player",
		player.hits == 0 and pal.state != pal.State.ATTACK,
		"state=%s player hits=%d" % [pal.State.keys()[pal.state], player.hits],
	)
	pal.queue_free()
	player.queue_free()


## A demon and one other pal beside each other, with the player far enough
## off that they are not in PAL_AGGRO_RADIUS and the demon is free to brawl.
func _fixture(other_scene: String):
	var player := FarAway.new()
	get_root().add_child(player)
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
	get_root().add_child(pal)
	await process_frame
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	# Physics off: these tests drive the state ticks directly, and a live
	# move_and_slide would walk the pals out of the arrangement under test.
	pal.set_physics_process(false)
	pal._player_cache = player
	return pal
