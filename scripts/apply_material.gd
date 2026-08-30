extends Node3D
## Overrides the material on every mesh below this node.
## Quaternius monsters share one atlas material, so a recoloured copy is the
## cheapest way to reskin a single creature.

@export var material: Material
## Nodes to leave alone, e.g. wings with their own material.
@export var skip: Array[NodePath] = []

func _ready() -> void:
	if material:
		var skipped: Array[Node] = []
		for path in skip:
			var n := get_node_or_null(path)
			if n:
				skipped.append(n)
		_apply(self, skipped)


func _apply(n: Node, skipped: Array[Node]) -> void:
	if n in skipped:
		return
	if n is MeshInstance3D:
		for i in n.get_surface_override_material_count():
			n.set_surface_override_material(i, material)
	for c in n.get_children():
		_apply(c, skipped)
