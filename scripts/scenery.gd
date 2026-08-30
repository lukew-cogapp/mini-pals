extends Node3D
## Scatters trees and rocks so the ground has landmarks to move past.
## Seeded, so the world is the same every run.

@export var tree_scene: PackedScene
@export var rock_scene: PackedScene
@export var pal_scene: PackedScene
@export var pal_scene_b: PackedScene
@export var demon_scene: PackedScene
@export var palm_scene: PackedScene
@export var shell_scene: PackedScene
@export var altar_scene: PackedScene

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.SCATTER_SEED
	_scatter(tree_scene, Tuning.TREE_COUNT, Tuning.TREE_SCALE_MIN, Tuning.TREE_SCALE_MAX, rng)
	_scatter(rock_scene, Tuning.ROCK_COUNT, Tuning.ROCK_SCALE_MIN, Tuning.ROCK_SCALE_MAX, rng)
	_scatter_shore(palm_scene, Tuning.PALM_COUNT, 0.82, 0.97, 0.8, 1.3, rng)
	_scatter_shore(shell_scene, Tuning.SHELL_COUNT, 1.0, 1.07, 0.6, 1.4, rng)
	_scatter_pals(rng)
	_scatter_demons(rng)
	_place_altar()


func _scatter_pals(rng: RandomNumberGenerator) -> void:
	if pal_scene == null:
		return
	for i in Tuning.PAL_COUNT:
		# Alternate species so both are findable near spawn.
		var source := pal_scene if (i % 2 == 0 or pal_scene_b == null) else pal_scene_b
		var pal := source.instantiate() as Pal
		# Same rng as the scatter, so levels are part of the reproducible
		# world. Each species rolls inside its own band from the scene.
		pal.level = rng.randi_range(pal.level_min, pal.level_max)
		pal.position = _on_island(rng, 0.0, Tuning.ISLAND_RADIUS * 0.6)
		pal.rotation.y = rng.randf() * TAU
		add_child(pal)


## Demons live in an annulus at the rim; the middle stays safe for pottering.
func _scatter_demons(rng: RandomNumberGenerator) -> void:
	if demon_scene == null:
		return
	for i in Tuning.DEMON_COUNT:
		var demon := demon_scene.instantiate() as Pal
		demon.level = rng.randi_range(demon.level_min, demon.level_max)
		demon.position = _on_island(
			rng,
			Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MIN,
			Tuning.ISLAND_RADIUS * Tuning.DEMON_RING_MAX,
		)
		demon.rotation.y = rng.randf() * TAU
		add_child(demon)


func _scatter(
	scene: PackedScene, count: int, scale_min: float, scale_max: float, rng: RandomNumberGenerator
) -> void:
	if scene == null:
		return
	for i in count:
		var pos := Vector3.ZERO
		# Keep the player's spawn clear so they don't start inside a tree.
		for _attempt in 12:
			pos = _on_island(rng, 0.0, Tuning.ISLAND_RADIUS - 3.0)
			if (
				pos.length() > Tuning.SCATTER_CLEAR_RADIUS
				and pos.distance_to(Tuning.ALTAR_POS) > Tuning.ALTAR_CLEAR_RADIUS
			):
				break
		var item := scene.instantiate() as Node3D
		item.position = pos
		item.rotation.y = rng.randf() * TAU
		item.scale = Vector3.ONE * rng.randf_range(scale_min, scale_max)
		add_child(item)

## One altar, at a fixed spot out among the demons, so reaching it is
## itself a small journey. Scatter keeps its clearing free of trees.
func _place_altar() -> void:
	if altar_scene == null:
		return
	var altar := altar_scene.instantiate() as Node3D
	altar.position = Tuning.ALTAR_POS
	add_child(altar)


## A point in an annulus on the island. Sqrt keeps the distribution even
## rather than crowding the centre.
func _on_island(rng: RandomNumberGenerator, inner: float, outer: float) -> Vector3:
	var angle := rng.randf() * TAU
	var t := rng.randf()
	var dist := sqrt(lerpf(inner * inner, outer * outer, t))
	return Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


## Dressing for the shoreline. Bands are fractions of the island radius, so
## palms sit on the last of the grass and shells out on the sand.
func _scatter_shore(
	scene: PackedScene,
	count: int,
	inner: float,
	outer: float,
	scale_min: float,
	scale_max: float,
	rng: RandomNumberGenerator,
) -> void:
	if scene == null:
		return
	for i in count:
		var item := scene.instantiate() as Node3D
		item.position = _on_island(
			rng, Tuning.ISLAND_RADIUS * inner, Tuning.ISLAND_RADIUS * outer
		)
		if inner >= 1.0:
			item.position.y = -0.35
		item.rotation.y = rng.randf() * TAU
		item.scale = Vector3.ONE * rng.randf_range(scale_min, scale_max)
		add_child(item)
