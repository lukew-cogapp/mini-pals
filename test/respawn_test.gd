extends SceneTree
## Headless assertions for the pal respawn trickle. Run:
##   godot --headless --path . -s test/respawn_test.gd
##
## Wild fights kill now, so the island has to refill itself. The four ways
## that could go wrong: refilling a world that is already full, never
## refilling a gutted one, refilling it so fast a cull means nothing, and
## putting the refill somewhere no pal belongs.
##
## Time is driven by calling Scenery._process with big deltas rather than by
## waiting: real seconds would put this suite past the runner's limit, and
## the pacing under test is in seconds of game time either way.

var _fails := 0
var _world: Node
var _scenery: Node


func _init() -> void:
	await process_frame
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	_scenery = _world.get_node("Scenery")

	_test_a_full_world_does_not_respawn()
	_test_a_culled_world_recovers()
	_test_recovery_is_gradual()
	_test_a_demon_respawns_in_the_ash()
	_test_a_fish_respawns_in_the_shallows()
	_test_nothing_respawns_on_the_player()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


## Seconds of game time, in slices big enough that every respawn roll fires
## but small enough that none is skipped over.
func _advance(seconds: float) -> void:
	var step := Tuning.RESPAWN_INTERVAL_MIN * 0.5
	var left := seconds
	while left > 0.0:
		_scenery._process(minf(step, left))
		left -= step


func _population() -> int:
	return _scenery._live_pal_count()


## Kill `n` pals outright, the way a rival kill leaves them: out of the group
## and flagged dying, with no payout.
func _cull(n: int) -> void:
	var killed := 0
	for node in get_nodes_in_group("pal"):
		if killed >= n:
			return
		var pal = node
		if pal.caught or pal.dying:
			continue
		pal.dying = true
		pal.remove_from_group("pal")
		killed += 1


func _test_a_full_world_does_not_respawn() -> void:
	var before := _population()
	_advance(Tuning.RESPAWN_INTERVAL_MAX * 20.0)
	_check(
		"a world at full population respawns nothing over a long stretch",
		_population() == before,
		"population %d -> %d over %.0fs" % [
			before, _population(), Tuning.RESPAWN_INTERVAL_MAX * 20.0,
		],
	)


func _test_a_culled_world_recovers() -> void:
	_cull(Tuning.PAL_POPULATION / 2)
	var culled := _population()
	_advance(Tuning.RESPAWN_INTERVAL_MAX * 60.0)
	_check(
		"a culled world recovers",
		_population() > culled,
		"population %d -> %d" % [culled, _population()],
	)


## Two readings, so a refill that snapped back in one tick would fail here
## even though the previous test would still pass.
func _test_recovery_is_gradual() -> void:
	_cull(Tuning.PAL_POPULATION / 2)
	var culled := _population()
	_advance(Tuning.RESPAWN_INTERVAL_MAX * 2.0)
	var early := _population()
	_advance(Tuning.RESPAWN_INTERVAL_MAX * 40.0)
	var late := _population()
	_check(
		"recovery is gradual, not instant",
		early < Tuning.PAL_POPULATION and late > early,
		"culled=%d early=%d late=%d target=%d" % [culled, early, late, Tuning.PAL_POPULATION],
	)


## Placement is _pal_position's job, shared with the initial scatter, so this
## is really asserting that the respawn path goes through it.
func _test_a_demon_respawns_in_the_ash() -> void:
	var scene: PackedScene = _scenery.demon_scene
	var inside := 0
	for i in 20:
		var pos: Vector3 = _scenery._pal_position(scene, _scenery._respawn_rng)
		# _in_demon_ring is the scenery's own ash test, so this asks the same
		# question the placement did. A -s script cannot name Zone directly.
		if _scenery._in_demon_ring(pos):
			inside += 1
	_check(
		"a respawned demon lands on the ash",
		inside == 20,
		"%d/20 inside the ash zone" % inside,
	)


func _test_a_fish_respawns_in_the_shallows() -> void:
	var scene: PackedScene = _scenery.fish_scene
	var inside := 0
	for i in 20:
		var pos: Vector3 = _scenery._pal_position(scene, _scenery._respawn_rng)
		var d := pos.length()
		if d >= Tuning.FISH_RING_MIN and d <= Tuning.FISH_RING_MAX:
			inside += 1
	_check(
		"a respawned Glimmerfin lands in the shallow ring",
		inside == 20,
		"%d/20 inside %.0f..%.0f" % [inside, Tuning.FISH_RING_MIN, Tuning.FISH_RING_MAX],
	)


## The one placement rule that is the respawn's own rather than the scatter's:
## nothing may fade in beside the player.
func _test_nothing_respawns_on_the_player() -> void:
	var player: Node3D = get_first_node_in_group("player")
	var at_player: bool = _scenery._is_clear(player.global_position)
	var one_step_out: bool = _scenery._is_clear(
		player.global_position + Vector3(Tuning.RESPAWN_CLEAR_RADIUS - 1.0, 0.0, 0.0)
	)
	# Only the pals that arrive from here on: the initial scatter puts plenty
	# near the origin the player spawns at, and those are not this rule's.
	var existing := {}
	for node in get_nodes_in_group("pal"):
		existing[node.get_instance_id()] = true
	_cull(Tuning.PAL_POPULATION / 2)
	_advance(Tuning.RESPAWN_INTERVAL_MAX * 60.0)
	var near := 0
	var arrived := 0
	for node in get_nodes_in_group("pal"):
		if existing.has(node.get_instance_id()):
			continue
		arrived += 1
		if node.global_position.distance_to(player.global_position) < Tuning.RESPAWN_CLEAR_RADIUS:
			near += 1
	_check(
		"nothing respawns inside the player's clear radius",
		not at_player and not one_step_out and arrived > 0 and near == 0,
		"clear at player=%s at r-1=%s, %d arrived, %d within %.0fm" % [
			at_player, one_step_out, arrived, near, Tuning.RESPAWN_CLEAR_RADIUS,
		],
	)
