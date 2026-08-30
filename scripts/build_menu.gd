extends CanvasLayer
## Workbench crafting menu, one row per Tuning.RECIPES entry. B opens it when
## the player stands near a workbench; while open it intercepts input in
## _input so the player's own ui_cancel and mouse-recapture handlers never
## see those events.

const STYLE_NORMAL := preload("res://ui/button.tres")
const STYLE_HOVER := preload("res://ui/button_hover.tres")
const STYLE_OFF := preload("res://ui/button_off.tres")

@onready var counts_label: Label = $Panel/VBox/Counts
@onready var recipes_box: VBoxContainer = $Panel/VBox/Recipes

var _buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	Inventory.changed.connect(_refresh)
	# Levelling up can unlock a recipe while the menu is open.
	Party.changed.connect(_refresh)
	for i in Tuning.RECIPES.size():
		var button := _make_button()
		button.pressed.connect(_craft.bind(i))
		recipes_box.add_child(button)
		_buttons.append(button)
	_refresh()


## Styled to match the one hand-built button this menu used to have.
func _make_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.6))
	b.add_theme_stylebox_override("normal", STYLE_NORMAL)
	b.add_theme_stylebox_override("hover", STYLE_HOVER)
	b.add_theme_stylebox_override("pressed", STYLE_HOVER)
	b.add_theme_stylebox_override("disabled", STYLE_OFF)
	return b


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
		if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_craft(0)
			get_viewport().set_input_as_handled()
		elif (
			event.physical_keycode >= KEY_1
			and event.physical_keycode < KEY_1 + Tuning.RECIPES.size()
		):
			_craft(event.physical_keycode - KEY_1)
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


func _unlocked(recipe: Dictionary) -> bool:
	return Party.player_level >= recipe.min_level


func _affordable(recipe: Dictionary) -> bool:
	for item in recipe.costs:
		if Inventory.count(item) < recipe.costs[item]:
			return false
	return true


func _cost_text(costs: Dictionary) -> String:
	var parts: Array[String] = []
	for item in costs:
		parts.append("%d %s" % [costs[item], String(item).capitalize().to_lower()])
	return " + ".join(parts)


func _craft(i: int) -> void:
	var recipe: Dictionary = Tuning.RECIPES[i]
	if not _unlocked(recipe):
		print("Cannot craft %s: unlocks at player level %d" % [recipe.label, recipe.min_level])
		return
	if not _affordable(recipe):
		print("Cannot craft %s: need %s" % [recipe.label, _cost_text(recipe.costs)])
		return
	for item in recipe.costs:
		Inventory.remove(item, recipe.costs[item])
	Inventory.add(recipe.item, 1)
	Audio.play("craft")
	if recipe.item == "altar_key":
		Hud.flash("Altar key forged! Seek the stone circle at the world's rim.")
	print("Crafted %s (%d held)" % [recipe.label, Inventory.count(recipe.item)])


func _refresh() -> void:
	var text := "Wood: %d   Stone: %d   Cubes: %d" % [
		Inventory.count("wood"), Inventory.count("stone"), Inventory.count("cube")
	]
	# Key materials join the readout once the recipe is reachable at all.
	if Party.player_level >= Tuning.KEY_UNLOCK_LEVEL:
		var parts: Array[String] = []
		for item in Tuning.KEY_RECIPE:
			parts.append("%s: %d" % [String(item).capitalize(), Inventory.count(item)])
		parts.append("Keys: %d" % Inventory.count("altar_key"))
		text += "\n" + "   ".join(parts)
	counts_label.text = text
	for i in _buttons.size():
		var recipe: Dictionary = Tuning.RECIPES[i]
		if not _unlocked(recipe):
			_buttons[i].text = "%s    unlocks at player level %d" % [recipe.label, recipe.min_level]
			_buttons[i].disabled = true
		else:
			_buttons[i].text = "%s    %s" % [recipe.label, _cost_text(recipe.costs)]
			_buttons[i].disabled = not _affordable(recipe)
