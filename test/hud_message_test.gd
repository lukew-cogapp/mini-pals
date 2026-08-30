extends GutTest
## HUD message assertions, ported from test/hud_message_test.gd.
##
## Ten callers share one message label. A catch flashes the catch, the XP and
## sometimes a level in the same frame, and the catch used to be overwritten
## before it could be read.
##
## Note the bare `Hud` and `Inventory` below: a GUT test script loads at
## runtime, after autoloads register, so it can name them. The `-s` script
## this was ported from could not, and had to go through get_node.

var _world: Node


## Freed in after_all, not by add_child_autofree, which frees at the end of
## the test that called it rather than at the end of the script. free, not
## queue_free: GUT counts children still parented when the script ends.
func before_all() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await wait_process_frames(1)
	await wait_physics_frames(5)


func after_all() -> void:
	_world.free()


func test_the_queue_shows_one_and_holds_the_rest() -> void:
	Hud.flash("Caught Wolf!")
	Hud.flash("You reached level 2!")
	Hud.flash("Wolf defeated! +1 Pelt")
	await wait_process_frames(1)

	assert_eq(Hud._message.text, "Caught Wolf!", "the catch message is the one on screen")
	assert_eq(Hud._messages.size(), 2, "the others are queued, not lost")

	# Let the first turn expire.
	Hud._next_message()
	await wait_process_frames(1)
	assert_eq(Hud._message.text, "You reached level 2!", "the next message takes its turn")

	Hud._next_message()
	Hud._next_message()
	await wait_process_frames(1)
	assert_eq(Hud._message.text, "", "the queue empties and clears the label")
	assert_true(Hud._messages.is_empty(), "queued=%d" % Hud._messages.size())


## A repeat of what is already showing must not stack up.
func test_a_repeated_message_does_not_queue_twice() -> void:
	# Drain whatever an earlier test left, so this does not read the tail of it.
	while not Hud._messages.is_empty() or Hud._message.text != "":
		Hud._next_message()
	await wait_process_frames(1)

	Hud.flash("Wood 1")
	Hud.flash("Wood 1")
	assert_true(Hud._messages.is_empty(), "queued=%s" % str(Hud._messages))


## Not in the original suite. It is here to show a GUT test naming a second
## autoload directly, which is the whole reason this file was ported.
func test_the_inventory_autoload_answers_by_name() -> void:
	assert_true(Inventory.count("wood") >= 0, "Inventory resolves without get_node")
