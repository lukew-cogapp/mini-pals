extends GutTest
## Catch-odds assertions, ported from test/catch_chance_test.gd.
##
## A subtractive level penalty once sank the whole curve under
## CUBE_CATCH_MIN, so the level 10 boss read 5% at every health and damage
## did nothing. These pin the properties that made that a bug, not the
## specific percentages, which are free to move.

var _wolf: Node3D


## Freed in after_all rather than by add_child_autofree, which frees at the
## end of the test that called it and would leave the rest reading a dead wolf.
## after_all uses free, not queue_free, because GUT counts children still
## parented when the script ends and queue_free has not run by then.
func before_all() -> void:
	_wolf = load("res://scenes/pal_wolf.tscn").instantiate()
	add_child(_wolf)
	await wait_process_frames(1)
	_wolf.set_physics_process(false)


func after_all() -> void:
	_wolf.free()


## Levels a cube is ever thrown at: ordinary pals cap at PAL_LEVEL_MAX, but
## the boss sits well above it, and that gap is where the old curve broke.
func _levels() -> Array:
	return range(1, maxi(Tuning.PAL_LEVEL_MAX, Tuning.BOSS_LEVEL) + 1)


## Odds for a pal of this level at this fraction of damage taken.
func _odds(level: int, missing: float) -> float:
	_wolf.level = level
	_wolf.max_hp = 100.0
	_wolf.hp = 100.0 * (1.0 - missing)
	return _wolf.catch_chance()


## The whole point of weakening a pal: every level must reward it.
func test_damage_always_helps() -> void:
	for level in _levels():
		var full := _odds(level, 0.0)
		var hurt := _odds(level, 0.9)
		assert_true(
			hurt > full,
			"damage raises the odds at level %d: full=%.3f hurt=%.3f" % [level, full, hurt],
		)


func test_level_always_hurts() -> void:
	var previous := 1.1
	for level in _levels():
		var odds := _odds(level, 0.0)
		assert_true(
			odds < previous,
			(
				"level %d is no easier than level %d: odds=%.3f previous=%.3f"
				% [level, level - 1, odds, previous]
			),
		)
		previous = odds


## The boss fight is meant to be won by wearing it down, so its odds have to
## clear the floor by enough that throwing a cube is worth doing.
func test_boss_is_catchable_when_worn_down() -> void:
	var worn := _odds(Tuning.BOSS_LEVEL, 0.9)
	assert_true(
		worn > Tuning.CUBE_CATCH_MIN * 3.0,
		(
			"a worn-down boss is well clear of the floor: worn=%.3f floor=%.3f"
			% [worn, Tuning.CUBE_CATCH_MIN]
		),
	)


func test_a_fresh_low_level_pal_is_a_coin_flip() -> void:
	var odds := _odds(1, 0.0)
	assert_true(
		odds > 0.4 and odds < 0.7,
		"a fresh level 1 pal is near an even chance: odds=%.3f" % odds,
	)
