extends GutTest
## The Debug button really does hand over a Mushroom King.
##
## `debug_start_test.gd` covers `Party.debug_start_king()` against a world it
## builds and parents itself. That proves the function, not the button: the
## real path goes through `change_scene_to_file`, which swaps the tree at the
## end of the frame, and the King is granted one `process_frame` later. The
## owner reported starting a debug game with no King in the party, so the gap
## between those two is exactly what needs a test.

const START := "res://scenes/start_screen.tscn"


func before_each() -> void:
	Party.members.clear()
	Party.active = null
	Party.player_level = 1


func after_all() -> void:
	Party.members.clear()
	Party.active = null
	Party.player_level = 1
	if get_tree().current_scene and get_tree().current_scene.name == "World":
		var world := get_tree().current_scene
		get_tree().current_scene = null
		world.free()


## Drive `_on_debug` itself, so the scene swap and the wait are the shipped
## ones rather than a re-creation of them here.
func test_the_debug_button_grants_a_king() -> void:
	# As current_scene, which is what makes this a real test. Parented as an
	# ordinary child the start screen SURVIVES change_scene_to_file, and the
	# shipped bug (a coroutine resuming inside the freed screen, get_tree()
	# null, the grant never running) cannot reproduce.
	var screen: Node = load(START).instantiate()
	get_tree().root.add_child(screen)
	var previous := get_tree().current_scene
	get_tree().current_scene = screen
	await wait_process_frames(1)

	screen._on_debug()
	# Generously more frames than the handler waits, so a King that arrives
	# late still counts as arrived and only a King that never arrives fails.
	await wait_process_frames(14)
	await wait_physics_frames(5)
	if is_instance_valid(previous):
		pass

	assert_eq(
		Party.members.size(), 1,
		"the debug start puts one pal in the party: members=%d" % Party.members.size()
	)
	if Party.members.is_empty():
		return
	var king: Node = Party.members[0]
	assert_true(is_instance_valid(king), "the King is still alive after a few frames")
	if not is_instance_valid(king):
		return
	assert_eq(king.display_name, "Mushroom King", "it is the King: %s" % king.display_name)
	assert_true(king.caught, "the King is marked caught")
	assert_eq(
		Party.active, king,
		"the King is the active pal, so cubes are free from the first frame"
	)
	assert_true(
		Party.infinite_cubes(),
		"the King's job is infinite cubes and it is doing it"
	)
	assert_gte(
		Party.player_level, Tuning.DEBUG_START_PLAYER_LEVEL,
		"the player is levelled enough to open the key recipe: level %d" % Party.player_level
	)
	# Where it actually stands. _activate summons beside the player, but only
	# if the player is already in its group; otherwise the fallback is the
	# world origin, and a King at (0,0,0) is a King the owner never sees.
	var player := get_tree().get_first_node_in_group("player")
	assert_not_null(player, "the player is in its group by the time the King is granted")
	if player == null:
		return
	gut.p("king at %s, player at %s" % [king.global_position, player.global_position])
	assert_lt(
		king.global_position.distance_to(player.global_position), 8.0,
		"the King is summoned beside the player, not at the origin: king %s player %s" % [
			king.global_position, player.global_position
		]
	)
	assert_true(king.visible, "the King is visible, not stowed")
