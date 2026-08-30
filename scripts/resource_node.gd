extends StaticBody3D
## Gatherable scenery. Each punch yields one item; after enough hits the node
## hides, then respawns in place so the seeded scatter layout never changes.

@export var item := "wood"

var _hits := 0
var _base_scale := Vector3.ONE


func _ready() -> void:
	# Scenery applies its random scale before add_child, so this is final.
	_base_scale = scale


func is_available() -> bool:
	return _hits < Tuning.GATHER_HITS


func punch() -> void:
	if not is_available():
		return
	_hits += 1
	var n := Tuning.GATHER_YIELD + int(Party.buff(&"gather"))
	Inventory.add(item, n)
	Audio.play("gather", global_position)
	if is_available():
		_shake()
	else:
		_deplete()


func _shake() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", _base_scale * Tuning.GATHER_PUNCH_SCALE, Tuning.GATHER_PUNCH_TIME)
	tween.tween_property(self, "scale", _base_scale, Tuning.GATHER_PUNCH_TIME)


func _deplete() -> void:
	visible = false
	collision_layer = 0
	await get_tree().create_timer(Tuning.GATHER_RESPAWN_DELAY).timeout
	_hits = 0
	scale = _base_scale
	collision_layer = 1
	visible = true
