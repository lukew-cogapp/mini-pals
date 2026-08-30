extends Node3D
## Scatters trees and rocks so the ground has landmarks to move past.
## Seeded, so the world is the same every run.

@export var tree_scene: PackedScene
@export var rock_scene: PackedScene
@export var pal_scene: PackedScene
@export var pal_scene_b: PackedScene

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.SCATTER_SEED
	_scatter(tree_scene, Tuning.TREE_COUNT, Tuning.TREE_SCALE_MIN, Tuning.TREE_SCALE_MAX, rng)
	_scatter(rock_scene, Tuning.ROCK_COUNT, Tuning.ROCK_SCALE_MIN, Tuning.ROCK_SCALE_MAX, rng)
	_scatter_pals(rng)


func _scatter_pals(rng: RandomNumberGenerator) -> void:
	if pal_scene == null:
		return
	var half := Tuning.GROUND_SIZE * 0.35
	for i in Tuning.PAL_COUNT:
		# Alternate species so both are findable near spawn.
		var source := pal_scene if (i % 2 == 0 or pal_scene_b == null) else pal_scene_b
		var pal := source.instantiate() as Node3D
		pal.position = Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		pal.rotation.y = rng.randf() * TAU
		add_child(pal)


func _scatter(
	scene: PackedScene, count: int, scale_min: float, scale_max: float, rng: RandomNumberGenerator
) -> void:
	if scene == null:
		return
	var half := Tuning.GROUND_SIZE * 0.5
	for i in count:
		var pos := Vector3.ZERO
		# Keep the player's spawn clear so they don't start inside a tree.
		for _attempt in 12:
			pos = Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
			if pos.length() > Tuning.SCATTER_CLEAR_RADIUS:
				break
		var item := scene.instantiate() as Node3D
		item.position = pos
		item.rotation.y = rng.randf() * TAU
		item.scale = Vector3.ONE * rng.randf_range(scale_min, scale_max)
		add_child(item)
