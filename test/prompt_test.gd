extends SceneTree
## Headless assertions for the contextual key prompt. Run:
##   godot --headless --path . -s test/prompt_test.gd
##
## Three failures this guards against, none of them visible on inspection:
## a prompt naming a key that is no longer bound to the action it describes,
## two prompts stacking when the player stands between two things, and a
## panel that overlaps one of the five HUD panels already on screen.

var _fails := 0
var _hud
var _inv
var _party
var _world
var _player


func _init() -> void:
	await process_frame
	_world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(_world)
	await process_frame
	for i in 5:
		await physics_frame
	_hud = get_root().get_node("Hud")
	_inv = get_root().get_node("Inventory")
	_party = get_root().get_node("Party")
	_player = get_first_node_in_group("player")
	if _player == null:
		print("FAILURES=1")
		print("FAIL the world has no player")
		quit(1)
		return

	# The world is a live one, so clear what it spawned near the origin and
	# park the player somewhere nothing else stands.
	_party.members.clear()
	_party.active = null
	_clear_world_props()
	await physics_frame

	_check("nothing nearby shows no prompt", _text() == "", "text=%s" % _text())

	# --- The workbench, in range and out of it -----------------------------

	var bench := _spawn("res://scenes/workbench.tscn", _player.global_position
		+ Vector3(Tuning.WORKBENCH_RANGE * 0.5, 0.0, 0.0))
	await physics_frame
	var in_range := _text()
	_check("the workbench prompt appears in range", in_range != "",
		"text=%s" % in_range)
	_check("the workbench prompt names the crafting it offers",
		in_range.contains("workbench"), "text=%s" % in_range)

	# Walking away must take it with them.
	bench.global_position = _player.global_position \
		+ Vector3(Tuning.WORKBENCH_RANGE * 4.0, 0.0, 0.0)
	await physics_frame
	_check("the workbench prompt goes when out of range", _text() == "",
		"text=%s" % _text())
	bench.global_position = _player.global_position \
		+ Vector3(Tuning.WORKBENCH_RANGE * 0.5, 0.0, 0.0)
	await physics_frame

	# --- The key it names is the key that is actually bound ----------------

	var bound := _first_key_name("build")
	_check("the prompt names the real bound key for build",
		_text().begins_with(bound), "bound=%s text=%s" % [bound, _text()])

	# Rebinding the action must move the prompt with it. This is the whole
	# reason the text is read from InputMap rather than written down.
	var saved := InputMap.action_get_events("build")
	var rebound := InputEventKey.new()
	rebound.physical_keycode = KEY_J
	InputMap.action_erase_events("build")
	InputMap.action_add_event("build", rebound)
	await physics_frame
	_check("rebinding the action changes the prompt",
		_text().begins_with("J") and not _text().begins_with(bound),
		"text=%s" % _text())
	InputMap.action_erase_events("build")
	for event in saved:
		InputMap.action_add_event("build", event)
	await physics_frame
	_check("restoring the binding restores the prompt",
		_text().begins_with(bound), "text=%s" % _text())

	# --- One prompt at a time ----------------------------------------------

	var altar := _spawn("res://scenes/altar.tscn",
		_player.global_position + Vector3(0.0, 0.0, Tuning.ALTAR_RANGE * 0.5))
	await physics_frame
	var both := _text()
	_check("standing between two things still shows one line",
		not both.contains("\n"), "text=%s" % both)
	_check("the altar outranks the workbench",
		both.contains("altar") or both.contains("Mushroom King"), "text=%s" % both)

	# The altar's own prompt has to tell the player which of the two states
	# they are in, or a keyless player is sent to a stone that does nothing.
	_check("with no key the altar prompt says so", both.contains("key"),
		"text=%s" % both)
	_inv.add("altar_key", 1)
	await physics_frame
	_check("with a key the altar prompt offers the summon",
		_text().contains("Mushroom King"), "text=%s" % _text())
	_inv.remove("altar_key", 1)
	altar.queue_free()
	await physics_frame

	# --- Geometry: nothing overlaps anything else --------------------------

	_hud._prompt_panel.visible = true
	_hud._prompt_label.text = "B   Craft at the workbench"
	await process_frame
	await process_frame
	var prompt: Control = _hud._prompt_panel
	var others := {
		"Bar": _hud.get_node("Bar"),
		"Message": _hud.get_node("Message"),
		"Health": _hud.get_node("Health"),
		"ItemPanel": _hud.get_node("ItemPanel"),
		"MinimapPanel": _hud.get_node("MinimapPanel"),
		"ObjectivePanel": _hud.get_node("ObjectivePanel"),
		"Reticule": _hud.get_node("Reticule"),
	}
	for panel_name in others:
		var other: Control = others[panel_name]
		var clash := prompt.get_global_rect().intersects(other.get_global_rect())
		_check("the prompt does not overlap %s" % panel_name, not clash,
			"prompt=%s %s=%s" % [prompt.get_global_rect(), panel_name,
				other.get_global_rect()])

	_check("the prompt is on screen at all",
		get_root().get_visible_rect().encloses(prompt.get_global_rect()),
		"prompt=%s screen=%s" % [prompt.get_global_rect(),
			get_root().get_visible_rect()])

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


## The prompt as the player would read it, or "" while it is hidden. The panel
## fades out rather than vanishing, so a hidden panel and one mid-fade both
## have to read as no prompt: _prompt_text is the source of truth.
func _text() -> String:
	return _hud._prompt_text()


func _spawn(path: String, at: Vector3) -> Node3D:
	var node: Node3D = load(path).instantiate()
	_world.add_child(node)
	node.global_position = at
	return node


## The world scatters hundreds of trees and rocks and spawns every pal, and
## any of them near the origin would answer the prompt check first. Move them
## all far enough away that only what this test places is in range.
func _clear_world_props() -> void:
	var groups := ["resource_node", "pal", "workbench", "altar"]
	for group in groups:
		for node in get_nodes_in_group(group):
			if node is Node3D:
				node.global_position += Vector3(0.0, 0.0, 10000.0)


## The keyboard key the InputMap currently has for the action, named the same
## way the prompt names it, so the assertion is against the map rather than
## against a copy of the prompt's own formatting.
func _first_key_name(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code: int = event.physical_keycode if event.physical_keycode != 0 \
				else event.keycode
			return OS.get_keycode_string(code)
	return ""


func _check(check_name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", check_name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", check_name, "  ", detail)
