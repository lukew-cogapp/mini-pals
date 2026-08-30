extends Node3D
## Scatters trees and rocks so the ground has landmarks to move past.
## Seeded, so the world is the same every run.

@export var tree_scenes: Array[PackedScene] = []
@export var rock_scenes: Array[PackedScene] = []
@export var dead_tree_scenes: Array[PackedScene] = []
@export var pal_scene: PackedScene
@export var pal_scene_b: PackedScene
@export var demon_scene: PackedScene
@export var amphibian_scene: PackedScene
@export var fish_scene: PackedScene
@export var palm_scene: PackedScene
@export var shell_scene: PackedScene
@export var altar_scene: PackedScene

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.SCATTER_SEED
	_scatter(tree_scenes, Tuning.TREE_COUNT, Tuning.TREE_SCALE_MIN, Tuning.TREE_SCALE_MAX, rng)
	_scatter(rock_scenes, Tuning.ROCK_COUNT, Tuning.ROCK_SCALE_MIN, Tuning.ROCK_SCALE_MAX, rng)
	_scatter_biome(
		dead_tree_scenes,
		Tuning.DEAD_TREE_COUNT,
		Tuning.DEAD_TREE_SCALE_MIN,
		Tuning.DEAD_TREE_SCALE_MAX,
		rng,
	)
	_scatter_shore(palm_scene, Tuning.PALM_COUNT, Tuning.PALM_BAND, 0.8, 1.3, rng)
	_scatter_shore(shell_scene, Tuning.SHELL_COUNT, Tuning.SHELL_BAND, 0.6, 1.4, rng)
	_scatter_pals(rng)
	_scatter_demons(rng)
	_scatter_amphibians(rng)
	_scatter_fish(rng)
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


## Demons live on the scorched blob; the rest of the island stays safe for
## pottering.
func _scatter_demons(rng: RandomNumberGenerator) -> void:
	if demon_scene == null:
		return
	for i in Tuning.DEMON_COUNT:
		var demon := demon_scene.instantiate() as Pal
		demon.level = rng.randi_range(demon.level_min, demon.level_max)
		demon.position = _in_ash(rng, 0.0)
		demon.rotation.y = rng.randf() * TAU
		add_child(demon)


## Amphibians wade ashore onto the sand, where a player on foot can reach
## them. Catching one is the only way into the water, so they must be
## catchable without one.
func _scatter_amphibians(rng: RandomNumberGenerator) -> void:
	if amphibian_scene == null:
		return
	for i in Tuning.AMPHIBIAN_COUNT:
		var pal := amphibian_scene.instantiate() as Pal
		pal.level = rng.randi_range(pal.level_min, pal.level_max)
		pal.position = _on_island(
			rng,
			Tuning.ISLAND_RADIUS * Tuning.AMPHIBIAN_BAND.x,
			Tuning.ISLAND_RADIUS * Tuning.AMPHIBIAN_BAND.y,
		)
		pal.rotation.y = rng.randf() * TAU
		add_child(pal)


## Fish, out in the shallows past a cube's reach from the shore. The inner
## radius is the gate the whole feature turns on; test/water_test.gd asserts
## it against CUBE_AIM_DISTANCE.
func _scatter_fish(rng: RandomNumberGenerator) -> void:
	if fish_scene == null:
		return
	for i in Tuning.FISH_COUNT:
		var pal := fish_scene.instantiate() as Pal
		pal.level = rng.randi_range(pal.level_min, pal.level_max)
		pal.position = _on_island(rng, Tuning.FISH_RING_MIN, Tuning.FISH_RING_MAX)
		pal.rotation.y = rng.randf() * TAU
		add_child(pal)


func _scatter(
	scenes: Array[PackedScene],
	count: int,
	scale_min: float,
	scale_max: float,
	rng: RandomNumberGenerator,
) -> void:
	if scenes.is_empty():
		return
	for i in count:
		var pos := Vector3.ZERO
		# Keep the player's spawn clear so they don't start inside a tree.
		for _attempt in 12:
			pos = _on_island(rng, 0.0, Tuning.ISLAND_RADIUS - 3.0)
			if (
				pos.length() > Tuning.SCATTER_CLEAR_RADIUS
				and pos.distance_to(Tuning.ALTAR_POS) > Tuning.ALTAR_CLEAR_RADIUS
				and not _in_demon_ring(pos)
			):
				break
		var item := scenes[rng.randi() % scenes.size()].instantiate() as Node3D
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


## True on the scorched blob. Living scenery stays off it, so the burnt
## ground reads as its own place rather than the same island recoloured.
func _in_demon_ring(pos: Vector3) -> bool:
	return Zone.is_inside(get_world_3d(), pos, Zone.Kind.ASH)


## A point on the scorched blob, inset from its edge by `inset` metres.
##
## The blob's edge is a noise curve, not a radius, so there is no closed form
## to sample from. Rejection sampling in its bounding circle asks the zone
## itself whether each candidate is inside, which keeps scatter and the drawn
## mesh agreeing by construction. Falls back to the altar, which is the one
## point guaranteed inside, so a spawn always gets a position.
func _in_ash(rng: RandomNumberGenerator, inset: float) -> Vector3:
	var centre := Vector3(Tuning.ALTAR_POS.x, 0.0, Tuning.ALTAR_POS.z)
	for _attempt in 64:
		var pos := centre + _on_island(rng, 0.0, Tuning.ASH_MAX_RADIUS)
		if not _in_demon_ring(pos):
			continue
		if inset > 0.0 and pos.distance_to(Tuning.ALTAR_POS) <= inset:
			continue
		return pos
	return centre


## Dead trees, on the scorched blob only, keeping the altar's clearing free.
func _scatter_biome(
	scenes: Array[PackedScene],
	count: int,
	scale_min: float,
	scale_max: float,
	rng: RandomNumberGenerator,
) -> void:
	if scenes.is_empty():
		return
	for i in count:
		var item := scenes[rng.randi() % scenes.size()].instantiate() as Node3D
		item.position = _in_ash(rng, Tuning.ALTAR_CLEAR_RADIUS)
		item.rotation.y = rng.randf() * TAU
		item.scale = Vector3.ONE * rng.randf_range(scale_min, scale_max)
		add_child(item)


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
	band: Vector2,
	scale_min: float,
	scale_max: float,
	rng: RandomNumberGenerator,
) -> void:
	if scene == null:
		return
	for i in count:
		var item := scene.instantiate() as Node3D
		item.position = _on_island(
			rng, Tuning.ISLAND_RADIUS * band.x, Tuning.ISLAND_RADIUS * band.y
		)
		# Out past the grass, so sit on the lower beach instead.
		if band.x >= 1.0:
			item.position.y = -0.35
		item.rotation.y = rng.randf() * TAU
		item.scale = Vector3.ONE * rng.randf_range(scale_min, scale_max)
		add_child(item)
