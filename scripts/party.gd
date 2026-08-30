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


## Step through the party. A single member toggles out and away instead.
func cycle(near := Vector3.ZERO, step := 1) -> void:
	if members.is_empty():
		return
	if members.size() == 1:
		if active:
			recall()
		else:
			_activate(members[0], near)
			changed.emit()
		return
	var i := members.find(active)
	var next: Pal = members[posmod(i + step, members.size())]
	if active:
		active.stow()
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
