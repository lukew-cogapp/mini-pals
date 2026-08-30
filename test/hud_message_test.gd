extends SceneTree
## Headless HUD message assertions. Run:
##   godot --headless --path . -s test/hud_message_test.gd
##
## Ten callers share one message label. A catch flashes the catch, the XP and
## sometimes a level in the same frame, and the catch used to be overwritten
## before it could be read.

var _fails := 0

func _init() -> void:
	await process_frame
	var world = load("res://scenes/world.tscn").instantiate()
	get_root().add_child(world)
	await process_frame
	for i in 5:
		await physics_frame
	var hud = get_root().get_node("Hud")

	hud.flash("Caught Wolf!")
	hud.flash("You reached level 2!")
	hud.flash("Wolf defeated! +1 Pelt")
	await process_frame

	_check("the catch message is the one on screen",
		hud._message.text == "Caught Wolf!", "showing=%s" % hud._message.text)
	_check("the others are queued, not lost",
		hud._messages.size() == 2, "queued=%s" % str(hud._messages))

	# Let the first turn expire.
	hud._next_message()
	await process_frame
	_check("the next message takes its turn",
		hud._message.text == "You reached level 2!", "showing=%s" % hud._message.text)

	hud._next_message()
	hud._next_message()
	await process_frame
	_check("the queue empties and clears the label",
		hud._message.text == "" and hud._messages.is_empty(),
		"showing=%s queued=%d" % [hud._message.text, hud._messages.size()])

	# A repeat of what is already showing must not stack up.
	hud.flash("Wood 1")
	hud.flash("Wood 1")
	_check("a repeated message does not queue twice",
		hud._messages.is_empty(), "queued=%s" % str(hud._messages))

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)
