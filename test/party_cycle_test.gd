extends SceneTree
## Headless party-cycling assertions. Run:
##   godot --headless --path . -s test/party_cycle_test.gd
##
## Pressing 1 or 3 while riding used to stow the pal out from under the
## player. The rider's own collider is disabled while mounted, so nothing
## was left to stand on and the player fell through the world.

var _fails := 0

func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	var player = world.get_node("Player")
	var party = get_root().get_node("Party")
	for i in 30:
		await physics_frame

	var wolf = load("res://scenes/pal_wolf.tscn").instantiate()
	var other = load("res://scenes/pal_cactoro.tscn").instantiate()
	world.add_child(wolf)
	world.add_child(other)
	await physics_frame
	player.global_position = Vector3(0, 1, 0)
	wolf.global_position = Vector3(1.2, 0, 0)
	other.global_position = Vector3(-1.2, 0, 0)
	for i in 10:
		await physics_frame

	wolf.caught = true
	other.caught = true
	party.members.append(wolf)
	party.members.append(other)
	party.active = wolf
	await physics_frame

	player._toggle_ride()
	await physics_frame
	_check("we are on the pal", player.mount != null, "mount=%s" % player.mount)

	player._cycle_party(1)
	for i in 90:
		await physics_frame

	var y = player.global_position.y
	_check("cycling does not drop the player through the world", y > -2.0,
		"player y=%.2f mount=%s" % [y, player.mount])
	_check("cycling while mounted steps us off first", player.mount == null,
		"mount=%s" % player.mount)

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)
