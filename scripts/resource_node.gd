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
	var bonus := int(Party.buff(&"gather"))
	var n := Tuning.GATHER_YIELD + bonus
	# The cave species pays out on rock only, so its job is a reason to go
	# mining rather than a second, better Glimmerfin.
	if is_in_group("rock"):
		n += int(Party.buff(&"stone"))
	Inventory.add(item, n)
	# The extra items otherwise land silently in the corner counter, so a
	# buffed punch gets a brighter chime than a bare one.
	Audio.play(Tuning.GATHER_BUFF_SOUND if bonus > 0 else "gather", global_position)
	if is_available():
		_shake()
	else:
		_deplete()


func _shake() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", _base_scale * Tuning.GATHER_PUNCH_SCALE, Tuning.GATHER_PUNCH_TIME)
	tween.tween_property(self, "scale", _base_scale, Tuning.GATHER_PUNCH_TIME)


func _deplete() -> void:
	# A poof, because the last punch used to make a whole tree vanish between
	# one frame and the next and it read as the tree being deleted by a bug.
	# Parented to this node's own parent, not to current_scene, which is null
	# whenever a world is instantiated rather than made the running scene.
	var host := get_parent()
	if host:
		Pal.poof(host, global_position + Vector3.UP)
	visible = false
	collision_layer = 0
	await get_tree().create_timer(Tuning.GATHER_RESPAWN_DELAY).timeout
	_hits = 0
	collision_layer = 1
	visible = true
	# Grows back rather than popping in whole, the same shape of beat the
	# respawning pals get.
	scale = _base_scale * 0.01
	var tween := create_tween()
	tween.tween_property(self, "scale", _base_scale, Tuning.GATHER_REGROW_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
