extends CanvasLayer
## Resource counts along the bottom of the screen.

@onready var _label: Label = $Bar/Margin/Counts

func _ready() -> void:
	Inventory.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_label.text = "Wood %d     Stone %d     Cubes %d" % [
		Inventory.count("wood"), Inventory.count("stone"), Inventory.count("cube")
	]
