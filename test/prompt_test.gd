extends GutTest
## Headless assertions for the contextual key prompt, ported from
## test/prompt_test.gd.
##
## Three failures this guards against, none of them visible on inspection:
## a prompt naming a key that is no longer bound to the action it describes,
## two prompts stacking when the player stands between two things, and a
## panel that overlaps one of the five HUD panels already on screen.

var _hud
var _inv
var _party
var _world
var _player
var _spawned: Array = []


func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(5)
	_hud = Hud
	_inv = Inventory
	_party = Party
	_player = get_tree().get_first_node_in_group("player")
	# The autoloads outlive a single suite now that every test shares one
	# process. The altar prompt reads the key count to decide which of its two
	# states to show, so a key an earlier script crafted would skip the
	# keyless prompt this test is here to check.
	_inv._counts.clear()
	_inv._counts["cube"] = Tuning.STARTING_CUBES


func after_all() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_world.free()


func test_prompt_flow() -> void:
	assert_not_null(_player, "the world has a player")
	if _player == null:
		return

	# The world is a live one, so clear what it spawned near the origin and
	# park the player somewhere nothing else stands.
	_party.members.clear()
	_party.active = null
	_clear_world_props()
	await wait_physics_frames(1)

	assert_eq(_text(), "", "nothing nearby shows no prompt")

	# --- The workbench, in range and out of it -----------------------------

	var bench := _spawn(
		"res://scenes/workbench.tscn",
		_player.global_position + Vector3(Tuning.WORKBENCH_RANGE * 0.5, 0.0, 0.0),
	)
	await wait_physics_frames(1)
	var in_range := _text()
	assert_true(in_range != "", "the workbench prompt appears in range: text=%s" % in_range)
	assert_true(
		in_range.contains("workbench"),
		"the workbench prompt names the crafting it offers: text=%s" % in_range,
	)

	# Walking away must take it with them.
	bench.global_position = (
		_player.global_position + Vector3(Tuning.WORKBENCH_RANGE * 4.0, 0.0, 0.0)
	)
	await wait_physics_frames(1)
	assert_eq(_text(), "", "the workbench prompt goes when out of range")
	bench.global_position = (
		_player.global_position + Vector3(Tuning.WORKBENCH_RANGE * 0.5, 0.0, 0.0)
	)
	await wait_physics_frames(1)

	# --- The key it names is the key that is actually bound ----------------

	var bound := _first_key_name("build")
	assert_true(
		_text().begins_with(bound),
		"the prompt names the real bound key for build: bound=%s text=%s" % [bound, _text()],
	)

	# Rebinding the action must move the prompt with it. This is the whole
	# reason the text is read from InputMap rather than written down.
	var saved := InputMap.action_get_events("build")
	var rebound := InputEventKey.new()
	rebound.physical_keycode = KEY_J
	InputMap.action_erase_events("build")
	InputMap.action_add_event("build", rebound)
	await wait_physics_frames(1)
	assert_true(
		_text().begins_with("J") and not _text().begins_with(bound),
		"rebinding the action changes the prompt: text=%s" % _text(),
	)
	InputMap.action_erase_events("build")
	for event in saved:
		InputMap.action_add_event("build", event)
	await wait_physics_frames(1)
	assert_true(
		_text().begins_with(bound),
		"restoring the binding restores the prompt: text=%s" % _text(),
	)

	# --- One prompt at a time ----------------------------------------------

	var altar := _spawn(
		"res://scenes/altar.tscn",
		_player.global_position + Vector3(0.0, 0.0, Tuning.ALTAR_RANGE * 0.5),
	)
	await wait_physics_frames(1)
	var both := _text()
	assert_true(
		not both.contains("\n"), "standing between two things still shows one line: text=%s" % both
	)
	assert_true(
		both.contains("altar") or both.contains("Mushroom King"),
		"the altar outranks the workbench: text=%s" % both,
	)

	# The altar's own prompt has to tell the player which of the two states
	# they are in, or a keyless player is sent to a stone that does nothing.
	assert_true(both.contains("key"), "with no key the altar prompt says so: text=%s" % both)
	_inv.add("altar_key", 1)
	await wait_physics_frames(1)
	assert_true(
		_text().contains("Mushroom King"),
		"with a key the altar prompt offers the summon: text=%s" % _text(),
	)
	_inv.remove("altar_key", 1)
	altar.queue_free()
	await wait_physics_frames(1)

	# --- Geometry: nothing overlaps anything else --------------------------

	_hud._prompt_panel.visible = true
	_hud._prompt_label.text = "B   Craft at the workbench"
	await wait_process_frames(2)
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
		assert_true(
			not clash,
			(
				"the prompt does not overlap %s: prompt=%s %s=%s"
				% [panel_name, prompt.get_global_rect(), panel_name, other.get_global_rect()]
			),
		)

	assert_true(
		get_tree().root.get_visible_rect().encloses(prompt.get_global_rect()),
		(
			"the prompt is on screen at all: prompt=%s screen=%s"
			% [prompt.get_global_rect(), get_tree().root.get_visible_rect()]
		),
	)


## The prompt as the player would read it, or "" while it is hidden. The panel
## fades out rather than vanishing, so a hidden panel and one mid-fade both
## have to read as no prompt: _prompt_text is the source of truth.
func _text() -> String:
	return _hud._prompt_text()


func _spawn(path: String, at: Vector3) -> Node3D:
	var node: Node3D = load(path).instantiate()
	_world.add_child(node)
	node.global_position = at
	_spawned.append(node)
	return node


## The world scatters hundreds of trees and rocks and spawns every pal, and
## any of them near the origin would answer the prompt check first. Move them
## all far enough away that only what this test places is in range.
func _clear_world_props() -> void:
	var groups := ["resource_node", "pal", "workbench", "altar"]
	for group in groups:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D:
				node.global_position += Vector3(0.0, 0.0, 10000.0)


## The keyboard key the InputMap currently has for the action, named the same
## way the prompt names it, so the assertion is against the map rather than
## against a copy of the prompt's own formatting.
func _first_key_name(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code: int = (
				event.physical_keycode if event.physical_keycode != 0 else event.keycode
			)
			return OS.get_keycode_string(code)
	return ""
