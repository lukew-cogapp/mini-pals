extends Node
## Player inventory, autoloaded as `Inventory`. Plain item -> count dictionary.

signal changed

var _counts := {"wood": 0, "stone": 0, "cube": 0}


func add(item: String, n: int = 1) -> void:
	_counts[item] = count(item) + n
	changed.emit()


func remove(item: String, n: int = 1) -> bool:
	if count(item) < n:
		return false
	_counts[item] -= n
	changed.emit()
	return true


func count(item: String) -> int:
	return _counts.get(item, 0)


func items() -> Array:
	return _counts.keys()
