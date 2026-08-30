extends SceneTree
## Temporary headless check for gathering, inventory, crafting, throw gate.

var fails := 0


func check(name: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		fails += 1


func _init() -> void:
	# Compress the 30s respawn wait; scene tree timers scale with this.
	Engine.time_scale = 50.0

	var w = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(w)
	await physics_frame
	await physics_frame

	var player = w.get_node("Player")
	var menu = w.get_node("BuildMenu")
	var tree = get_nodes_in_group("tree")[0]
	var rock = get_nodes_in_group("rock")[0]

	check("inventory starts empty", Inventory.count("wood") == 0
		and Inventory.count("stone") == 0 and Inventory.count("sphere") == 0)

	# --- Gathering: tree in reach, in front (player faces -Z) ---
	tree.set_deferred("global_position", player.global_position + Vector3(0, 0, -1.5))
	rock.set_deferred("global_position", Vector3(0, 0, 30))
	await physics_frame
	player._punch()
	check("punching tree yields 1 wood", Inventory.count("wood") == 1)

	player._punch()
	player._punch()
	check("3 hits deplete tree (hidden, unavailable)",
		Inventory.count("wood") == 3 and not tree.visible and not tree.is_available())

	player._punch()
	check("punching a depleted node yields nothing", Inventory.count("wood") == 3)

	# --- Gathering: rock ---
	rock.set_deferred("global_position", player.global_position + Vector3(0, 0, -1.6))
	await physics_frame
	player._punch()
	check("punching rock yields 1 stone", Inventory.count("stone") == 1)

	# --- Out-of-reach punch gathers nothing ---
	rock.set_deferred("global_position", Vector3(0, 0, 30))
	await physics_frame
	player._punch()
	check("punch with nothing in reach yields nothing",
		Inventory.count("wood") == 3 and Inventory.count("stone") == 1)

	# --- Workbench proximity ---
	check("menu will not open far from workbench", not menu._near_workbench())
	player.global_position = Vector3(0, 1, -6)
	check("menu opens within range of workbench", menu._near_workbench())

	# --- Crafting ---
	menu._craft()
	check("craft with 3 wood 1 stone gives 1 sphere, costs 1+1",
		Inventory.count("sphere") == 1 and Inventory.count("wood") == 2
		and Inventory.count("stone") == 0)

	menu._craft()
	check("craft refused with 0 stone", Inventory.count("sphere") == 1
		and Inventory.count("wood") == 2)
	menu._refresh()
	check("craft button greyed out when unaffordable", menu.craft_button.disabled)

	# --- Throw gate ---
	var spheres_before := _sphere_count(w)
	player._throw_sphere()
	check("throw with 1 sphere spawns it and decrements",
		_sphere_count(w) == spheres_before + 1 and Inventory.count("sphere") == 0)
	player._throw_sphere()
	check("throw with 0 spheres refused", _sphere_count(w) == spheres_before + 1)

	# --- Respawn (30s scaled by time_scale) ---
	print("waiting for respawn...")
	await create_timer(Tuning.GATHER_RESPAWN_DELAY + 1.0).timeout
	check("tree respawned, gatherable again", tree.visible and tree.is_available()
		and tree.collision_layer == 1)

	print("RESULT: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)


func _sphere_count(w: Node) -> int:
	var n := 0
	for c in w.get_children():
		if c is Area3D:
			n += 1
	return n
