extends Node3D
## Scatters trees and rocks so the ground has landmarks to move past.
## Seeded, so the world is the same every run.
##
## Also trickles pals back in as they are killed off, on an unseeded rng, so
## a culled world refills without the initial layout ever changing.

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
@export var workbench_scene: PackedScene
@export var cave_pal_scene: PackedScene

var _respawn_rng := RandomNumberGenerator.new()
var _respawn_wait := 0.0


## Ground height under a point, from the authored mounds.
##
## Arithmetic rather than a raycast on purpose: scatter runs inside _ready,
## before the physics server has seen a single collider, so a ray would
## report empty space and bury every prop on every hill.
func _ground_y(pos: Vector3) -> float:
	return Terrain.height_at(pos.x, pos.z)


## Sit a node on the ground, keeping whatever vertical offset it already had.
## The shore dressing drops itself onto the lower beach that way, and a hill
## must add to that rather than replace it.
func _sit(item: Node3D) -> void:
	item.position.y += _ground_y(item.position)


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
	_scatter_cave_pals(rng)
	_place_altar()
	_place_workbenches()
	# Unseeded, deliberately: the initial layout must be identical every run,
	# but a refill that arrived in the same order every run would be a script.
	_respawn_rng.randomize()
	_respawn_wait = _next_respawn_wait()


func _scatter_pals(rng: RandomNumberGenerator) -> void:
	if pal_scene == null:
		return
	for i in Tuning.PAL_COUNT:
		# Alternate species so both are findable near spawn.
		_spawn_pal(pal_scene if (i % 2 == 0 or pal_scene_b == null) else pal_scene_b, rng)


func _scatter_demons(rng: RandomNumberGenerator) -> void:
	for i in Tuning.DEMON_COUNT:
		_spawn_pal(demon_scene, rng)


func _scatter_amphibians(rng: RandomNumberGenerator) -> void:
	for i in Tuning.AMPHIBIAN_COUNT:
		_spawn_pal(amphibian_scene, rng)


func _scatter_fish(rng: RandomNumberGenerator) -> void:
	for i in Tuning.FISH_COUNT:
		_spawn_pal(fish_scene, rng)


## The cave species, in the hollow and nowhere else on the island. That is
## the whole point of it: the cave has to be worth the walk, and a Grottolo
## found on the open grass would make it a detour instead of a destination.
##
## Placed around the mouth rather than through `_pal_position`, so they are
## back in the dark where the player has to go in to reach them.
func _scatter_cave_pals(rng: RandomNumberGenerator) -> void:
	if cave_pal_scene == null:
		return
	var terrain := get_parent().get_node_or_null("Terrain")
	var mouth: Vector3 = terrain.mouth_position() if terrain else Tuning.CAVE_POS
	for i in Tuning.GROTTOLO_COUNT:
		# Spread back along the hollow from just inside the mouth, on the
		# axis the cave was built along.
		var back := -Vector3(sin(Tuning.CAVE_FACING), 0.0, cos(Tuning.CAVE_FACING))
		var along := rng.randf_range(1.0, Tuning.CAVE_DEPTH - 1.0)
		var across := (
			Vector3(back.z, 0.0, -back.x)
			* rng.randf_range(-Tuning.CAVE_WIDTH * 0.3, Tuning.CAVE_WIDTH * 0.3)
		)
		_spawn_pal(cave_pal_scene, rng, mouth + back * along + across)


## One pal of `scene`, levelled and placed where its species belongs.
##
## Both the initial scatter and the respawn trickle come through here, so a
## respawned demon lands on the ash and a respawned fish out in the ring for
## the same reason the original ones did, with no second copy of the rules.
## `at` overrides the species position, for a caller that has already picked
## and vetted one.
## `arrive` plays the spawn poof and the grow-in. Off for the initial scatter,
## which happens before the player can see anything and would otherwise fire
## fifty emitters on the first frame; on for the respawn trickle, where a pal
## appearing in a world already being looked at is the whole problem.
func _spawn_pal(
	scene: PackedScene, rng: RandomNumberGenerator, at := Vector3.INF, arrive := false
) -> Pal:
	if scene == null:
		return null
	var pal := scene.instantiate() as Pal
	# Levels roll from the same rng as the position, so a seeded scatter is
	# reproducible in both. Each species rolls inside its own band.
	pal.level = rng.randi_range(pal.level_min, pal.level_max)
	pal.position = _pal_position(scene, rng) if at == Vector3.INF else at
	# Species positions are picked on the flat plane, so a pal on a hillside
	# needs lifting onto it. The cave species is the exception: its position
	# is already a point on the hollow's floor, inside the hill rather than
	# on top of it, and sitting it would put it through the roof.
	if scene != cave_pal_scene:
		_sit(pal)
	pal.rotation.y = rng.randf() * TAU
	add_child(pal)
	if arrive:
		Pal.poof(self, pal.global_position)
		pal.grow_in()
	return pal


## Where a species lives.
##
##   demons     the scorched blob only, so the rest of the island stays safe
##              for pottering
##   amphibians the sand, reachable on foot: catching one is the only way
##              into the water, so it must be catchable without one
##   fish       the shallow ring past a cube's reach from the shore, the gate
##              the whole water feature turns on (see test/water_test.gd)
##   the rest   the green, inside the middle of the island
func _pal_position(scene: PackedScene, rng: RandomNumberGenerator) -> Vector3:
	if scene == demon_scene:
		return _in_ash(rng, 0.0)
	if scene == amphibian_scene:
		return _on_island(
			rng,
			Tuning.ISLAND_RADIUS * Tuning.AMPHIBIAN_BAND.x,
			Tuning.ISLAND_RADIUS * Tuning.AMPHIBIAN_BAND.y,
		)
	if scene == fish_scene:
		return _on_island(rng, Tuning.FISH_RING_MIN, Tuning.FISH_RING_MAX)
	return _on_island(rng, 0.0, Tuning.ISLAND_RADIUS * Tuning.PAL_BAND)


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
		_sit(item)
		item.rotation.y = rng.randf() * TAU
		item.scale = Vector3.ONE * rng.randf_range(scale_min, scale_max)
		add_child(item)

## One altar, at a fixed spot out among the demons, so reaching it is
## itself a small journey. Scatter keeps its clearing free of trees.
## Benches are authored rather than scattered: a random one could land in the
## ash, in the water, or inside a tree, and the player needs to be able to
## learn where they are.
func _place_workbenches() -> void:
	if workbench_scene == null:
		return
	for at in Tuning.WORKBENCH_POSITIONS:
		var bench := workbench_scene.instantiate() as Node3D
		bench.position = at
		_sit(bench)
		add_child(bench)


func _place_altar() -> void:
	if altar_scene == null:
		return
	var altar := altar_scene.instantiate() as Node3D
	altar.position = Tuning.ALTAR_POS
	_sit(altar)
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
		_sit(item)
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
		_sit(item)
		item.rotation.y = rng.randf() * TAU
		item.scale = Vector3.ONE * rng.randf_range(scale_min, scale_max)
		add_child(item)


## --- Respawning ------------------------------------------------------------

## Wild fights kill and so does the player, so the island refills itself.
##
## Driven by the total live population rather than a per-species quota or a
## fixed clock: near the intended headcount respawns all but stop, and a
## culled world refills faster the emptier it is. Deliberately slow. The
## point of a lethal world is that a cull is felt, and one that repopulated
## while the player walked home would undo that.
func _process(delta: float) -> void:
	_respawn_wait -= delta
	if _respawn_wait > 0.0:
		return
	_respawn_wait = _next_respawn_wait()
	var deficit := Tuning.PAL_POPULATION - _live_pal_count()
	if deficit <= 0:
		return
	# The emptier the island, the likelier a roll spawns: a single missing pal
	# is usually skipped, a gutted map almost never is. randf() can return
	# exactly 0, so the full-world case is the guard above rather than odds of
	# zero, which would let one through now and then.
	var odds := float(deficit) / float(Tuning.PAL_POPULATION)
	if _respawn_rng.randf() > odds * Tuning.RESPAWN_URGENCY:
		return
	_respawn_one()


func _next_respawn_wait() -> float:
	return _respawn_rng.randf_range(Tuning.RESPAWN_INTERVAL_MIN, Tuning.RESPAWN_INTERVAL_MAX)


## Wild pals only. A caught pal is the player's, and counting it would let a
## full party starve the island of respawns; a dying one is already gone as
## far as the population is concerned.
func _live_pal_count() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("pal"):
		var pal := node as Pal
		if pal != null and not pal.caught and not pal.dying:
			n += 1
	return n


## One pal of a randomly chosen species, somewhere clear.
##
## Species is rolled rather than balanced back towards the starting mix: the
## roll is the variety, and chasing exact per-species quotas would need a
## census the feature does not otherwise want.
func _respawn_one() -> void:
	var pool := _species_pool()
	if pool.is_empty():
		return
	var scene := pool[_respawn_rng.randi() % pool.size()]
	# Retry like _scatter does, for the same reason: nothing may appear inside
	# a tree, a rock, or on top of the player. The position is settled before
	# anything joins the tree, so a run of blocked tries costs no node.
	for _attempt in Tuning.RESPAWN_PLACE_TRIES:
		var pos := _pal_position(scene, _respawn_rng)
		if _is_clear(pos):
			_spawn_pal(scene, _respawn_rng, pos, true)
			return


func _species_pool() -> Array[PackedScene]:
	var pool: Array[PackedScene] = []
	for scene in [pal_scene, pal_scene_b, demon_scene, amphibian_scene, fish_scene]:
		if scene != null:
			pool.append(scene)
	return pool


## Far enough from the player to not appear in front of them, and clear of
## the scenery already standing there.
func _is_clear(pos: Vector3) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and pos.distance_to(player.global_position) < Tuning.RESPAWN_CLEAR_RADIUS:
		return false
	# One group covers both trees and rocks, which is every gatherable thing
	# a pal could otherwise appear inside.
	for node in get_tree().get_nodes_in_group("resource_node"):
		var item := node as Node3D
		if item != null and pos.distance_to(item.global_position) < Tuning.SCATTER_CLEAR_RADIUS:
			return false
	return true
