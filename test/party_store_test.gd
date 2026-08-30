extends SceneTree
## Headless party assertions. Run:
##   godot --headless --path . -s test/party_store_test.gd
##
## A caught pal that is freed elsewhere does not remove itself from
## Party.members, so store() read display_name off a freed object and threw.
## It surfaced as an intermittent failure in unrelated suites.

var _fails := 0

func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	var party = get_root().get_node("Party")
	for i in 10:
		await physics_frame

	var doomed = load("res://scenes/pal_wolf.tscn").instantiate()
	world.add_child(doomed)
	await physics_frame
	doomed.caught = true
	party.members.append(doomed)

	# Free it behind the party's back, as a death elsewhere would.
	doomed.free()
	await physics_frame

	var fresh = load("res://scenes/pal_cactoro.tscn").instantiate()
	world.add_child(fresh)
	await physics_frame
	fresh.caught = true
	party.store(fresh)
	await physics_frame

	_check("storing a pal survives a freed member", fresh in party.members,
		"members=%d" % party.members.size())
	_check("the freed member is gone from the party",
		party.members.all(func(p): return is_instance_valid(p)),
		"members=%d" % party.members.size())

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)
