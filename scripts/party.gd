extends Node
## Caught pals. One can be out at a time; the rest wait to be cycled in.

signal changed

var members: Array[Pal] = []
var active: Pal = null


func store(pal: Pal) -> void:
	if pal in members:
		return
	members.append(pal)
	pal.stow()
	# First catch comes straight out, so a catch visibly does something.
	if active == null:
		_activate(pal)
	changed.emit()


## Cycle to the next member, or put the current one away if it is the only one.
func cycle(near: Vector3) -> void:
	if members.is_empty():
		return
	var i := members.find(active) if active else -1
	var next: Pal = members[(i + 1) % members.size()]
	if active:
		active.stow()
	if next == active and members.size() == 1:
		active = null
	else:
		_activate(next, near)
	changed.emit()


func recall() -> void:
	if active:
		active.stow()
		active = null
		changed.emit()


func _activate(pal: Pal, near := Vector3.ZERO) -> void:
	active = pal
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var at := near
	if player:
		at = player.global_position + player.global_transform.basis.z * 2.0
	pal.summon(at)
