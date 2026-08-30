extends CanvasLayer
## Workbench crafting menu. B opens it when the player stands near a
## workbench; while open it intercepts input in _input so the player's
## own ui_cancel and mouse-recapture handlers never see those events.

@onready var counts_label: Label = $Panel/VBox/Counts
@onready var craft_button: Button = $Panel/VBox/CraftButton


func _ready() -> void:
	visible = false
	Inventory.changed.connect(_refresh)
	craft_button.pressed.connect(_craft)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible:
		return
	if event.is_action_pressed("build") and _near_workbench():
		_open()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("build") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_1]:
			_craft()
			get_viewport().set_input_as_handled()


func _near_workbench() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	for bench in get_tree().get_nodes_in_group("workbench"):
		if player.global_position.distance_to(bench.global_position) <= Tuning.WORKBENCH_RANGE:
			return true
	return false


func _open() -> void:
	visible = true
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _affordable() -> bool:
	for item in Tuning.SPHERE_RECIPE:
		if Inventory.count(item) < Tuning.SPHERE_RECIPE[item]:
			return false
	return true


func _craft() -> void:
	if not _affordable():
		print("Cannot craft Catch Sphere: need 1 wood + 1 stone")
		return
	for item in Tuning.SPHERE_RECIPE:
		Inventory.remove(item, Tuning.SPHERE_RECIPE[item])
	Inventory.add("sphere", 1)
	print("Crafted Catch Sphere (%d held)" % Inventory.count("sphere"))


func _refresh() -> void:
	counts_label.text = "Wood: %d   Stone: %d   Spheres: %d" % [
		Inventory.count("wood"), Inventory.count("stone"), Inventory.count("sphere")
	]
	craft_button.disabled = not _affordable()
