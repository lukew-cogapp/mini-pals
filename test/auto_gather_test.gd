extends SceneTree
## Headless auto-gathering assertions. Run:
##   godot --headless --path . -s test/auto_gather_test.gd
##
## The active pal works the scenery beside you, by species. These pin who
## gathers what, that only the pal that is out does it, that defending and
## the leash both outrank the job, and that a worked node still depletes.

var _fails := 0


func _init() -> void:
	await process_frame

	await _test_cactoro_gathers_wood()
	await _test_wolf_gathers_stone()
	await _test_cactoro_ignores_rocks()
	await _test_wolf_ignores_trees()
	await _test_stowed_pal_gathers_nothing()
	await _test_defending_stops_gathering()
	await _test_node_depletes_and_pal_moves_on()
	await _test_leash_bounds_the_job()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _test_cactoro_gathers_wood() -> void:
	var f = await _fixture("res://scenes/pal_cactoro.tscn", "tree", "wood")
	var before: int = f.inv.count("wood")
	_run(f.pal, 40)
	_check(
		"an active Cactoro beside a tree raises the player's wood",
		f.inv.count("wood") > before,
		"wood %d -> %d" % [before, f.inv.count("wood")],
	)
	_free(f)


func _test_wolf_gathers_stone() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn", "rock", "stone")
	var before: int = f.inv.count("stone")
	_run(f.pal, 40)
	_check(
		"an active Wolf beside a rock raises the player's stone",
		f.inv.count("stone") > before,
		"stone %d -> %d" % [before, f.inv.count("stone")],
	)
	_free(f)


func _test_cactoro_ignores_rocks() -> void:
	var f = await _fixture("res://scenes/pal_cactoro.tscn", "rock", "stone")
	var before: int = f.inv.count("stone")
	_run(f.pal, 40)
	_check(
		"a Cactoro does not gather stone",
		f.inv.count("stone") == before and f.pal.state == f.pal.State.FOLLOW,
		"stone %d -> %d state=%s" % [
			before, f.inv.count("stone"), f.pal.State.keys()[f.pal.state]
		],
	)
	_free(f)


func _test_wolf_ignores_trees() -> void:
	var f = await _fixture("res://scenes/pal_wolf.tscn", "tree", "wood")
	var before: int = f.inv.count("wood")
	_run(f.pal, 40)
	_check(
		"a Wolf does not gather wood",
		f.inv.count("wood") == before and f.pal.state == f.pal.State.FOLLOW,
		"wood %d -> %d state=%s" % [
			before, f.inv.count("wood"), f.pal.State.keys()[f.pal.state]
		],
	)
	_free(f)


func _test_stowed_pal_gathers_nothing() -> void:
	var f = await _fixture("res://scenes/pal_cactoro.tscn", "tree", "wood")
	# Out of the party's active slot is exactly what stowing does.
	f.party.active = null
	var before: int = f.inv.count("wood")
	_run(f.pal, 40)
	_check(
		"a pal that is not the active one gathers nothing",
		f.inv.count("wood") == before,
		"wood %d -> %d" % [before, f.inv.count("wood")],
	)
	_free(f)


func _test_defending_stops_gathering() -> void:
	var f = await _fixture("res://scenes/pal_cactoro.tscn", "tree", "wood")
	# One tick to take the job, and no more: three ticks would deplete the
	# tree and end it before the demon ever arrives.
	_run(f.pal, 1)
	var was_gathering: bool = f.pal.state == f.pal.State.GATHER

	var demon = load("res://scenes/pal_demon.tscn").instantiate()
	get_root().add_child(demon)
	await process_frame
	demon.global_position = Vector3(0.0, 0.0, 2.0)
	demon.set_physics_process(false)
	demon._player_cache = f.player

	var before: int = f.inv.count("wood")
	_run(f.pal, 20)
	_check(
		"a gathering pal drops the job to defend against a hostile",
		was_gathering and f.pal.state == f.pal.State.DEFEND
			and f.inv.count("wood") == before,
		"was_gathering=%s state=%s wood %d -> %d" % [
			was_gathering, f.pal.State.keys()[f.pal.state], before, f.inv.count("wood")
		],
	)
	demon.queue_free()
	_free(f)


func _test_node_depletes_and_pal_moves_on() -> void:
	var f = await _fixture("res://scenes/pal_cactoro.tscn", "tree", "wood")
	# A second tree further out, so there is somewhere to move on to.
	var second := _make_node("tree", "wood", Vector3(4.0, 0.0, 0.0))
	await process_frame

	# Long enough to run the first tree out several times over.
	_run(f.pal, 120)
	_check(
		"a worked node depletes after GATHER_HITS",
		not f.node.is_available(),
		"hits=%d available=%s" % [f.node._hits, f.node.is_available()],
	)
	_check(
		"the pal moves on to another node rather than hammering a dead one",
		f.pal._gather_target != f.node,
		"target=%s" % ("null" if f.pal._gather_target == null else str(f.pal._gather_target.name)),
	)
	second.queue_free()
	_free(f)


func _test_leash_bounds_the_job() -> void:
	var f = await _fixture("res://scenes/pal_cactoro.tscn", "tree", "wood")
	_run(f.pal, 1)
	var was_gathering: bool = f.pal.state == f.pal.State.GATHER
	# The player walks off. Nothing else changes.
	f.player.global_position = Vector3(0.0, 0.0, Tuning.PAL_GATHER_LEASH + 5.0)
	f.pal._tick_gather(0.1)
	_check(
		"a pal past its leash from the player stops gathering and follows",
		was_gathering and f.pal.state == f.pal.State.FOLLOW
			and f.pal._gather_target == null,
		"was_gathering=%s state=%s" % [
			was_gathering, f.pal.State.keys()[f.pal.state]
		],
	)
	_check(
		"the search radius can never pick a node outside the leash",
		Tuning.PAL_GATHER_RADIUS < Tuning.PAL_GATHER_LEASH,
		"radius=%.1f leash=%.1f" % [Tuning.PAL_GATHER_RADIUS, Tuning.PAL_GATHER_LEASH],
	)
	_free(f)


## Drive the pal's own state ticks. Physics is off, so nothing walks out of
## the arrangement under test; the pal is placed in bite range to begin with.
func _run(pal, steps: int) -> void:
	for i in steps:
		match pal.state:
			pal.State.FOLLOW:
				pal._tick_follow(0.5)
			pal.State.GATHER:
				pal._tick_gather(0.5)
			pal.State.DEFEND:
				pal._tick_defend(0.5)


## A caught, active pal standing in bite range of one gatherable node.
func _fixture(scene: String, group: String, item: String):
	var inv = get_root().get_node("Inventory")
	var party = get_root().get_node("Party")

	var player := Node3D.new()
	get_root().add_child(player)
	player.global_position = Vector3.ZERO

	var node := _make_node(group, item, Vector3(1.5, 0.0, 0.0))

	var pal = load(scene).instantiate()
	get_root().add_child(pal)
	await process_frame
	pal.global_position = Vector3.ZERO
	pal.velocity = Vector3.ZERO
	pal.set_physics_process(false)
	pal._player_cache = player
	pal.caught = true
	pal.state = pal.State.FOLLOW
	party.active = pal

	return {
		"pal": pal, "player": player, "node": node,
		"inv": inv, "party": party, "item": item,
	}


## A stand-in for a scattered tree or rock: the real resource_node script,
## in the real groups, so depletion and respawn are the shipped ones.
func _make_node(group: String, item: String, at: Vector3) -> StaticBody3D:
	var n := StaticBody3D.new()
	n.set_script(load("res://scripts/resource_node.gd"))
	n.add_to_group("resource_node")
	n.add_to_group(group)
	get_root().add_child(n)
	n.global_position = at
	n.item = item
	return n


func _free(f) -> void:
	f.party.active = null
	f.pal.queue_free()
	f.node.queue_free()
	f.player.queue_free()
