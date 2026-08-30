extends GutTest
## The Llama: the first pal in the game that attacks at range.
##
## Every other attack is melee under 2 m, so the things worth pinning here are
## the ones a ranged attack could quietly get wrong. It must stop at
## SPIT_RANGE rather than closing, the wad must actually take hitpoints off a
## target that far away, a wad that hits nothing must clean itself up, and,
## the one that matters most, a FOLLOWER's spit must still be unable to land
## the kill: `take_follower_hit` is what stops a follower costing the player a
## catch, and a projectile that did its own arithmetic would be a way round it.

const LLAMA := "res://scenes/pal_llama.tscn"
const WOLF := "res://scenes/pal_wolf.tscn"


class HitTarget:
	extends CharacterBody3D
	## A player stand-in that records what hit it. A CharacterBody3D rather
	## than a Node3D because the wad finds its target by a physics query, so a
	## target with no collider is one the sweep can never see.

	var hits := 0
	var taken := 0.0

	func _init() -> void:
		add_to_group("player")
		collision_layer = 1
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.5
		capsule.height = 1.8
		shape.shape = capsule
		add_child(shape)

	func damage(amount: float, _from_position: Vector3) -> bool:
		hits += 1
		taken += amount
		return true

	## The live Hud autoload draws its minimap wedge off whatever is in the
	## `player` group, and joining that group is what makes this stub a target
	## the wad can find. Without this the minimap errors every frame and GUT
	## counts those engine errors as a failure of whichever test is running.
	func facing() -> Vector3:
		return -global_transform.basis.z


## A wad outlives the pal that fired it, deliberately: a spitter killed
## mid-volley should not un-fire what is already in the air. In the game they
## land or expire within SPIT_LIFETIME and free themselves; in here the tests
## run back to back inside one scene, so a volley from the previous test is
## still flying when the next one starts and would bill its target. Swept
## before each test rather than after, so a test that fails leaves its wads
## behind to be looked at.
func before_each() -> void:
	_clear_wads()


## Collected in full before anything is freed. Freeing while walking the tree
## leaves the rest of the collected list pointing at instances that are
## already gone, and `is` on one of those is an engine error GUT counts as a
## failure of whichever test is running.
func _clear_wads() -> void:
	var doomed: Array[Node] = []
	for node in _all_nodes(get_tree().root):
		if node is Spit:
			doomed.append(node)
	for node in doomed:
		if is_instance_valid(node):
			node.free()


## --- Reach ------------------------------------------------------------------


func test_llama_is_ranged_and_armed() -> void:
	var llama = await _spawn(LLAMA, Vector3.ZERO)
	assert_true(llama.ranged, "the Llama is a ranged species")
	assert_not_null(llama.spit_scene, "the Llama has a wad wired, or it falls back to melee")


func test_attack_range_is_the_spit_range() -> void:
	var llama = await _spawn(LLAMA, Vector3.ZERO)
	# All three fights a pal can be in ask attack_range() rather than reading
	# their own constant, so one flag makes a species ranged everywhere.
	assert_eq(llama.attack_range(Tuning.PAL_ATTACK_RANGE), Tuning.SPIT_RANGE)
	assert_eq(llama.attack_range(Tuning.FOLLOWER_ATTACK_RANGE), Tuning.SPIT_RANGE)
	assert_eq(llama.attack_range(Tuning.RIVAL_ATTACK_RANGE), Tuning.SPIT_RANGE)
	assert_true(
		Tuning.SPIT_RANGE > Tuning.PAL_ATTACK_RANGE * 3.0,
		"the spit clears melee by a distance the player can read  spit=%.1f melee=%.1f"
		% [Tuning.SPIT_RANGE, Tuning.PAL_ATTACK_RANGE],
	)


func test_a_melee_species_keeps_its_melee_range() -> void:
	var wolf = await _spawn(WOLF, Vector3.ZERO)
	assert_eq(
		wolf.attack_range(Tuning.PAL_ATTACK_RANGE),
		Tuning.PAL_ATTACK_RANGE,
		"attack_range() leaves every other species alone",
	)


## It spits from where it stands instead of walking in. Driven by position
## rather than by asserting a call happened: the bug this guards against is a
## spitter that closes to biting distance anyway, and that shows as movement.
func test_llama_spits_rather_than_closing_to_melee() -> void:
	var player := HitTarget.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	await wait_process_frames(1)

	var start := Vector3(0.0, 0.0, 6.0)
	var llama = await _spawn(LLAMA, start, player)
	llama.temperament = llama.Temperament.AGGRESSIVE
	llama.state = llama.State.ATTACK
	llama._attack_cooldown = 0.0

	for i in 10:
		llama._tick_attack(0.1)
	var moved: float = llama.global_position.distance_to(start)

	assert_lt(
		moved,
		0.5,
		"a llama already inside SPIT_RANGE holds its ground  moved %.2f m from %.1f m out"
		% [moved, start.length()],
	)
	assert_gt(
		_wads(),
		0,
		"a llama in range of the player fires  wads=%d dist=%.1f" % [_wads(), start.length()],
	)


func test_llama_closes_only_to_the_spit_range() -> void:
	var player := HitTarget.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	await wait_process_frames(1)

	# Well outside SPIT_RANGE but inside PAL_CHASE_GIVE_UP, so it walks in.
	var llama = await _spawn(LLAMA, Vector3(0.0, 0.0, 16.0), player)
	llama.temperament = llama.Temperament.AGGRESSIVE
	llama.state = llama.State.ATTACK

	var chased := false
	for i in 30:
		var before: Vector3 = llama.global_position
		llama._tick_attack(0.1)
		# Physics is off, so the tick sets velocity rather than moving; step
		# the position by hand the way move_and_slide would.
		llama.global_position += Vector3(llama.velocity.x, 0.0, llama.velocity.z) * 0.1
		if llama.global_position.distance_to(before) > 0.01:
			chased = true

	var gap: float = llama.global_position.distance_to(player.global_position)
	assert_true(chased, "a llama out of range does walk in")
	assert_almost_eq(
		gap,
		Tuning.SPIT_RANGE,
		1.0,
		"it stops at SPIT_RANGE rather than walking into melee  gap=%.2f" % gap,
	)


## --- The wad in flight ------------------------------------------------------


## The whole point of a projectile: hitpoints come off a target the shooter
## never touched. Asserts the target's hp, not that a function was called.
func test_a_spit_damages_a_player_at_range() -> void:
	var player := HitTarget.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	await wait_process_frames(1)

	var llama = await _spawn(LLAMA, Vector3(0.0, 0.0, 7.0), player)
	llama._fire_spit(player, Spit.Mode.PLAYER)
	await _fly()

	assert_gt(player.hits, 0, "a wad fired from 7 m hits the player  hits=%d" % player.hits)
	assert_almost_eq(
		player.taken,
		Tuning.SPIT_PLAYER_DAMAGE,
		0.001,
		"and takes SPIT_PLAYER_DAMAGE off  taken=%.2f" % player.taken,
	)


func test_a_spit_damages_a_rival_at_range() -> void:
	var shooter = await _spawn(LLAMA, Vector3(0.0, 0.0, 7.0))
	var target = await _spawn(WOLF, Vector3.ZERO)
	target.level = 5
	target.max_hp = 20
	target.hp = 20
	var before: int = target.hp

	shooter._fire_spit(target, Spit.Mode.RIVAL)
	await _fly()

	assert_lt(
		target.hp, before, "a rival wad takes hitpoints off  hp %d -> %d" % [before, target.hp]
	)


## Damage is lower than the melee it replaces, because a spitter never enters
## reach. A ranged attack that hit as hard as a bite would be strictly better.
func test_the_spit_is_weaker_than_the_melee_it_replaces() -> void:
	assert_lt(
		Tuning.SPIT_PLAYER_DAMAGE,
		Tuning.AGGRESSIVE_ATTACK_DAMAGE,
		"a wad hurts less than an aggressive bite",
	)
	assert_gt(
		Tuning.SPIT_COOLDOWN,
		Tuning.PAL_ATTACK_COOLDOWN,
		"and comes slower than one",
	)


## A wad that hits nothing frees itself, on the ground or on the timer. A
## projectile that leaked would accumulate one per shot per llama forever.
func test_a_missed_spit_cleans_itself_up() -> void:
	var llama = await _spawn(LLAMA, Vector3.ZERO)
	# Fired at empty air far from anything.
	var mark := Node3D.new()
	add_child_autofree(mark)
	mark.global_position = Vector3(0.0, 0.0, -7.0)
	await wait_process_frames(1)

	var wad = llama._fire_spit(mark, Spit.Mode.PLAYER)
	assert_not_null(wad, "the wad launched")
	assert_eq(_wads(), 1, "exactly one wad is in the world")

	await _fly()

	assert_eq(_wads(), 0, "a wad that hit nothing is gone  wads=%d" % _wads())
	assert_false(is_instance_valid(wad), "and freed rather than merely hidden")


## --- The follower clamp -----------------------------------------------------


## The constraint that matters most.
##
## `take_follower_hit` clamps at FOLLOWER_MIN_TARGET_HP so a caught pal can
## never land the killing blow and cost the player the catch. A ranged attack
## is a new path to that same damage, so it is a new way to get round the
## clamp. This drives a whole fight, not one call: the follower fires wad
## after wad at a target across the room until it cannot take another point.
func test_a_spitting_follower_can_never_kill() -> void:
	var player := HitTarget.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	await wait_process_frames(1)

	var follower = await _spawn(LLAMA, Vector3(0.0, 0.0, 1.0), player)
	follower.caught = true
	follower.state = follower.State.DEFEND

	var hostile = await _spawn("res://scenes/pal_demon.tscn", Vector3(0.0, 0.0, 7.0), player)
	hostile.state = hostile.State.ATTACK
	follower._defend_target = hostile

	# Long enough to run the target's health bar down many times over, with
	# the wads given time to fly between volleys.
	for volley in 30:
		follower._attack_cooldown = 0.0
		follower._tick_defend(0.1)
		await _fly()
		if not is_instance_valid(hostile):
			break

	assert_true(is_instance_valid(hostile), "the target is still there at all")
	assert_false(hostile.dying, "a spitting follower never kills its target")
	assert_eq(
		hostile.hp,
		Tuning.FOLLOWER_MIN_TARGET_HP,
		"the spit path stops on FOLLOWER_MIN_TARGET_HP exactly, like the bite does  hp=%d"
		% hostile.hp,
	)


## And the softened target is still the player's to finish, which is what the
## clamp was protecting.
func test_the_player_can_still_kill_a_spit_softened_target() -> void:
	var player := HitTarget.new()
	add_child_autofree(player)
	await wait_process_frames(1)

	var follower = await _spawn(LLAMA, Vector3(0.0, 0.0, 1.0), player)
	follower.caught = true
	var hostile = await _spawn(WOLF, Vector3(0.0, 0.0, 7.0), player)

	for volley in 30:
		follower._fire_spit(hostile, Spit.Mode.FOLLOWER)
		await _fly()

	var softened: int = hostile.hp
	hostile.take_hit(Vector3(0.0, 0.0, 20.0))

	assert_eq(softened, Tuning.FOLLOWER_MIN_TARGET_HP, "softened to the clamp")
	assert_true(hostile.dying, "and the player's own punch still finishes it")


## A rival wad is NOT clamped: wild fights kill, and routing the spit through
## take_rival_hit is what keeps that true. The two modes must not have been
## collapsed into one.
func test_a_rival_spit_is_not_clamped() -> void:
	var shooter = await _spawn(LLAMA, Vector3(0.0, 0.0, 7.0))
	var target = await _spawn(WOLF, Vector3.ZERO)

	for volley in 30:
		if not is_instance_valid(target) or target.dying:
			break
		shooter._fire_spit(target, Spit.Mode.RIVAL)
		await _fly()

	assert_true(
		not is_instance_valid(target) or target.dying,
		"a wild spitter can finish a rival, unlike a follower",
	)


## --- Neutral ----------------------------------------------------------------


func test_the_llama_is_neutral() -> void:
	var llama = await _spawn(LLAMA, Vector3.ZERO)
	assert_eq(
		llama.temperament,
		llama.Temperament.NEUTRAL,
		"the Llama neither hunts the player nor flees them",
	)
	assert_false(llama.aggressive, "and so never opens fire on sight")


## A ranged attack on an aggressive species would shell the player from
## outside the distance they can see it at. This is the assertion that the
## llama does not: an unprovoked player stands next to a wild one for several
## seconds of physics and takes nothing.
func test_a_wild_llama_does_not_spit_at_an_unprovoked_player() -> void:
	var player := HitTarget.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	await wait_process_frames(1)

	# Well inside PAL_AGGRO_RADIUS and inside SPIT_RANGE, so nothing but
	# temperament is keeping it quiet.
	var llama = await _spawn(LLAMA, Vector3(0.0, 0.0, 3.0), player)
	# Every state a pal can idle into, ticked by hand rather than by running
	# live physics. The choice of state is the pal's own on each tick, so the
	# gate under test is untouched; driving it avoids putting a second moving
	# body into the scene these suites share, which is enough to unsettle the
	# timing tests running after this one.
	for i in 200:
		match llama.state:
			llama.State.IDLE:
				llama._tick_idle(0.05)
			llama.State.WANDER:
				llama._tick_wander(0.05)
			llama.State.FLEE:
				llama._tick_flee(0.05)
			llama.State.ATTACK:
				llama._tick_attack(0.05)
			_:
				pass

	assert_eq(player.hits, 0, "an unprovoked wild llama never fires  hits=%d" % player.hits)
	assert_eq(_wads(), 0, "and no wad is ever in the air  wads=%d" % _wads())
	assert_ne(
		llama.state,
		llama.State.ATTACK,
		"nor does it enter ATTACK  state=%s" % llama.State.keys()[llama.state],
	)


## Bitten, it does fight back, which is what NEUTRAL means. The other half of
## the pair above: quiet is temperament, not a broken attack.
func test_a_punched_llama_does_spit_back() -> void:
	var player := HitTarget.new()
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	await wait_process_frames(1)

	var llama = await _spawn(LLAMA, Vector3(0.0, 0.0, 4.0), player)
	llama.max_hp = 50
	llama.hp = 50
	llama.take_hit(player.global_position)
	assert_eq(
		llama.state, llama.State.ATTACK, "a punch puts a neutral llama into ATTACK"
	)

	llama._attack_cooldown = 0.0
	llama._tick_attack(0.1)
	assert_gt(_wads(), 0, "and it answers with a wad rather than closing to bite")


## --- Spitting from the saddle -----------------------------------------------


## Riding a llama turns the attack button into a spit, and it must be a spit
## rather than a bite: asserted by a target OUTSIDE melee reach losing
## hitpoints, which a punch could never manage.
func test_riding_a_llama_makes_the_attack_a_spit() -> void:
	var rider = await _rider(LLAMA)
	var quarry = await _spawn(WOLF, Vector3(0.0, 0.0, -9.0))
	quarry.max_hp = 50
	quarry.hp = 50
	var before: int = quarry.hp

	# Aimed down -Z, which is where the quarry is. Godot forward is -Z, so an
	# unrotated pivot already points there.
	rider.player._punch()
	assert_gt(_wads(), 0, "the attack button fires a wad from the saddle")

	await _fly()
	assert_lt(
		quarry.hp,
		before,
		"and it damages a target at %.0f m, far outside the %.1f m a punch reaches  hp %d -> %d"
		% [9.0, Tuning.GATHER_RANGE, before, quarry.hp],
	)


## The regression that matters. A Wolf is rideable too, and a branch that
## caught every mount rather than only a spitter would break biting from every
## other saddle in the game.
func test_riding_a_wolf_still_bites() -> void:
	var rider = await _rider(WOLF)
	var quarry = await _spawn(WOLF, Vector3(0.0, 0.0, -9.0))
	quarry.max_hp = 50
	quarry.hp = 50
	var far_before: int = quarry.hp

	rider.player._punch()
	assert_eq(_wads(), 0, "a Wolf saddle fires no projectile  wads=%d" % _wads())

	await _fly()
	assert_eq(
		quarry.hp, far_before, "and nothing 9 m away is touched  hp=%d" % quarry.hp
	)

	# And the bite itself still lands, so this is a melee attack that works
	# rather than an attack that was disabled.
	var near = await _spawn(WOLF, Vector3(0.0, 0.0, -1.2))
	near.max_hp = 50
	near.hp = 50
	var near_before: int = near.hp
	rider.player._punch()
	assert_lt(
		near.hp, near_before, "a bite from the Wolf saddle still lands  hp %d -> %d"
		% [near_before, near.hp],
	)


## Orientation. CLAUDE.md is emphatic that this has been reasoned about wrongly
## four times here, so the direction is measured from where the wad actually
## goes, for two separate headings, rather than argued from the sign of a
## basis vector.
func test_the_mounted_spit_follows_the_camera() -> void:
	for heading in [0.0, PI * 0.5]:
		var rider = await _rider(LLAMA)
		rider.pivot.rotation.y = heading
		await wait_process_frames(1)

		# Godot forward is -Z, so this is the way the camera points.
		var expected: Vector3 = -rider.pivot.global_transform.basis.z
		expected.y = 0.0
		expected = expected.normalized()

		rider.player._punch()
		var wad := _first_wad()
		assert_not_null(wad, "a wad was fired at heading %.2f" % heading)
		if wad == null:
			continue

		var start: Vector3 = wad.global_position
		await wait_process_frames(10)
		var travelled: Vector3 = wad.global_position - start if is_instance_valid(wad) else Vector3.ZERO
		travelled.y = 0.0

		assert_gt(travelled.length(), 0.5, "and it moved  heading=%.2f" % heading)
		assert_gt(
			travelled.normalized().dot(expected),
			0.95,
			"the wad travels the way the camera points  heading=%.2f dot=%.3f travelled=%s expected=%s"
			% [heading, travelled.normalized().dot(expected), travelled.normalized(), expected],
		)
		# Clear the wad before the next heading, or the first one is still in
		# the air and _first_wad returns it instead.
		rider.player.mount = null
		_clear_wads()


## The balance lever. Without a cooldown a fast mount plus a free ranged
## attack outranges everything on the island.
func test_the_mounted_spit_is_rate_limited() -> void:
	var rider = await _rider(LLAMA)

	rider.player._punch()
	rider.player._punch()
	rider.player._punch()
	assert_eq(_wads(), 1, "three presses in one frame fire one wad  wads=%d" % _wads())

	# And it does come back, rather than firing once ever.
	rider.player._rider_spit_cooldown = 0.0
	rider.player._punch()
	assert_eq(_wads(), 2, "the next shot lands once the cooldown expires  wads=%d" % _wads())
	assert_gt(Tuning.RIDER_SPIT_COOLDOWN, 0.0, "and the cooldown is a real number")


## --- Where it lives ---------------------------------------------------------


## Placement is arithmetic on LLAMA_BAND, so it is asserted as arithmetic
## rather than by scattering a world: the band must sit outside the crowded
## starting ring and inside the shore.
func test_the_llama_band_is_the_outer_grass() -> void:
	assert_gt(
		Tuning.LLAMA_BAND.x,
		Tuning.PAL_BAND,
		"llamas start outside the ring the wolves and cactoros scatter in",
	)
	assert_lt(
		Tuning.LLAMA_BAND.y,
		Tuning.AMPHIBIAN_BAND.x,
		"and stop short of the sand the amphibians hold",
	)
	assert_lt(Tuning.LLAMA_BAND.y, 1.0, "so no llama spawns off the island")


## Every llama the scatter places is inside its own band, on the grass, and
## nowhere else: not in the starting clearing, not on the demons' ash.
func test_scattered_llamas_land_only_in_their_band() -> void:
	var world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await wait_process_frames(2)

	var llamas: Array = []
	for node in get_tree().get_nodes_in_group("pal"):
		if node is Pal and node.display_name == "Llama":
			llamas.append(node)

	var inner := Tuning.ISLAND_RADIUS * Tuning.LLAMA_BAND.x
	var outer := Tuning.ISLAND_RADIUS * Tuning.LLAMA_BAND.y
	var strays := 0
	var in_ash := 0
	var floating := 0
	for llama in llamas:
		var r: float = Vector3(llama.global_position.x, 0.0, llama.global_position.z).length()
		if r < inner - 0.01 or r > outer + 0.01:
			strays += 1
		if Zone.is_inside(world.get_world_3d(), llama.global_position, Zone.Kind.ASH):
			in_ash += 1
		# The band reaches over the skirts of two of the mounds, so a llama
		# placed on the flat plane and never sat would hang in the air above
		# one exactly as the cave boulders did.
		var ground: float = Terrain.height_at(llama.global_position.x, llama.global_position.z)
		if absf(llama.global_position.y - ground) > 0.01:
			floating += 1

	assert_eq(llamas.size(), Tuning.LLAMA_COUNT, "the scatter places LLAMA_COUNT of them")
	assert_eq(strays, 0, "every llama is inside LLAMA_BAND  strays=%d of %d" % [strays, llamas.size()])
	assert_eq(in_ash, 0, "and none on the demons' scorched ground  in_ash=%d" % in_ash)
	assert_eq(floating, 0, "and each sits on the terrain  floating=%d of %d" % [floating, llamas.size()])

	world.free()


## --- Species knobs ----------------------------------------------------------


func test_the_llama_has_a_drop_and_an_icon() -> void:
	var llama = await _spawn(LLAMA, Vector3.ZERO)
	assert_eq(llama.drop_item, "llama_wool")
	assert_true(
		Tuning.ITEM_ICONS.has(llama.drop_item),
		"its drop has an icon, or the HUD row renders blank",
	)
	assert_not_null(
		load(Tuning.ITEM_ICONS[llama.drop_item]), "and the icon file loads"
	)


## Its job. The buff is read live through Party, capped like every other one.
func test_the_llama_buff_fattens_drops_while_it_is_out() -> void:
	var llama = await _spawn(LLAMA, Vector3.ZERO)
	llama.caught = true
	llama.level = Tuning.PAL_LEVEL_MAX
	Party.active = llama

	var buff := Party.buff(&"drop")
	assert_gt(buff, 0.0, "an out Llama buffs drops  buff=%.2f" % buff)
	assert_lte(buff, Tuning.LLAMA_DROP_BUFF_CAP, "and the buff is capped")

	Party.active = null
	assert_eq(Party.buff(&"drop"), 0.0, "stowing it puts the player back on the base rate")


## --- Helpers ----------------------------------------------------------------


## Wads in the world right now. Counted off the tree rather than tracked, so a
## wad that freed itself really is gone rather than merely dropped from a list.
func _wads() -> int:
	var n := 0
	for node in _all_nodes(get_tree().root):
		if node is Spit:
			n += 1
	return n


func _first_wad() -> Spit:
	for node in _all_nodes(get_tree().root):
		if node is Spit:
			return node
	return null


## The real player scene, mounted on `path`.
##
## The real one rather than a stand-in, because what is under test is
## `player.gd _punch` branching on the mount, and a stand-in would be a second
## copy of the branch rather than a test of it. Physics is left off: these
## drive `_punch` directly and a live `_ride` would carry the pair away from
## the target between the shot and the assertion.
func _rider(path: String):
	var player = load("res://scenes/player.tscn").instantiate()
	add_child_autofree(player)
	await wait_process_frames(1)
	player.global_position = Vector3.ZERO
	player.set_physics_process(false)

	var pal = await _spawn(path, Vector3.ZERO)
	pal.caught = true
	player.mount = pal
	pal.state = pal.State.RIDDEN

	return {"player": player, "pal": pal, "pivot": player.get_node("CameraPivot")}


func _all_nodes(from: Node) -> Array[Node]:
	if not is_instance_valid(from):
		return []
	var out: Array[Node] = [from]
	for child in from.get_children():
		out.append_array(_all_nodes(child))
	return out


## Long enough for a wad to cross SPIT_RANGE and either land or expire.
func _fly() -> void:
	await wait_process_frames(int(Tuning.SPIT_LIFETIME * 60.0) + 10)


func _spawn(path: String, pos: Vector3, player: Node3D = null):
	var pal = load(path).instantiate()
	add_child_autofree(pal)
	await wait_process_frames(1)
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	# Physics off: these drive the state ticks directly, and a live
	# move_and_slide would walk the pals out of the arrangement under test.
	pal.set_physics_process(false)
	if player:
		pal._player_cache = player
	return pal
