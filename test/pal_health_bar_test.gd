extends SceneTree
## Headless assertions for the floating pal health bar. Run:
##   godot --headless --path . -s test/pal_health_bar_test.gd

var _fails := 0


func _init() -> void:
	await process_frame

	await _test_bar_hides_far_and_shows_near()
	await _test_fill_tracks_damage()
	await _test_fill_follows_max_hp_on_level_gain()
	await _test_caught_and_dying_pals_show_nothing()

	print("FAILURES=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS ", name)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _spawn_pal(pos: Vector3, player: Node3D):
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	get_root().add_child(pal)
	await process_frame
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	pal._player_cache = player
	return pal


func _player_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	get_root().add_child(n)
	n.global_position = pos
	return n


## Force the interval sampler to run this frame rather than waiting on it.
func _sample(pal) -> void:
	pal._bar_check = 0.0
	pal._tick_health_bar()


## The fill's drawn width as a fraction of the space inside the border, which
## is what the eye actually reads off the bar.
func _fill_fraction(pal) -> float:
	var full := Tuning.PAL_HEALTH_BAR_WIDTH * (1.0 - Tuning.PAL_HEALTH_BAR_BORDER)
	return pal._bar_fill.scale.x / full


## Where the drawn left edge of the fill sits, in the bar's own local space.
## center_offset shifts the mesh before the node scale applies to it.
func _fill_left_edge(pal) -> float:
	var quad: QuadMesh = pal._bar_fill.mesh
	return (quad.center_offset.x - 0.5) * pal._bar_fill.scale.x


func _test_bar_hides_far_and_shows_near() -> void:
	var player := _player_at(Vector3.ZERO)
	var far := Tuning.PAL_HEALTH_BAR_DISTANCE + 10.0
	var pal = await _spawn_pal(Vector3(0.0, 0.0, far), player)

	_sample(pal)
	_check("bar hidden beyond the show distance", not pal._bar_back.visible)

	pal.global_position = Vector3(0.0, 0.0, Tuning.PAL_HEALTH_BAR_DISTANCE - 2.0)
	_sample(pal)
	_check("bar shown inside the show distance", pal._bar_back.visible)

	pal.queue_free()
	player.queue_free()


func _test_fill_tracks_damage() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 2.0), player)
	pal.max_hp = 4
	pal.hp = 4
	_sample(pal)
	_check(
		"a full-health bar fills the whole inner width",
		is_equal_approx(_fill_fraction(pal), 1.0),
		"fraction=%.3f" % _fill_fraction(pal),
	)

	pal.hp = 1
	pal._refresh_bar()
	_check(
		"the fill shrinks to the hp fraction",
		is_equal_approx(_fill_fraction(pal), 0.25),
		"fraction=%.3f" % _fill_fraction(pal),
	)
	var mat: StandardMaterial3D = pal._bar_fill.material_override
	_check(
		"a nearly dead pal shows a red bar",
		mat.albedo_color.is_equal_approx(Tuning.PAL_HEALTH_BAR_LOW_COLOUR),
		"colour=%s" % mat.albedo_color,
	)

	# The bar grows from its left edge, so the left edge must not move.
	var left := _fill_left_edge(pal)
	pal.hp = 4
	pal._refresh_bar()
	var left_full := _fill_left_edge(pal)
	_check(
		"the fill grows from a fixed left edge",
		is_equal_approx(left, left_full),
		"empty=%.4f full=%.4f" % [left, left_full],
	)

	pal.queue_free()
	player.queue_free()


func _test_fill_follows_max_hp_on_level_gain() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 2.0), player)
	pal.level = 1
	pal.max_hp = 3
	pal.hp = 1
	_sample(pal)
	var before := _fill_fraction(pal)

	pal.gain_level()
	_check(
		"levelling refills the bar to the new max",
		is_equal_approx(_fill_fraction(pal), 1.0) and pal.max_hp > 3,
		"before=%.3f after=%.3f max_hp=%d" % [before, _fill_fraction(pal), pal.max_hp],
	)
	# The label rises with the model, and the bar must stay above it.
	_check(
		"the bar stays above the name label after levelling",
		pal._bar_back.position.y > pal._label.position.y,
		"bar=%.2f label=%.2f" % [pal._bar_back.position.y, pal._label.position.y],
	)

	pal.queue_free()
	player.queue_free()


## A caught pal is yours and its bar would follow you everywhere; a dying one
## is about to vanish. Both hide, as the name label already does.
func _test_caught_and_dying_pals_show_nothing() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 2.0), player)
	_sample(pal)
	_check("a wild pal near the player shows its bar", pal._bar_back.visible)

	pal.caught = true
	pal._update_label()
	_check("a caught pal shows no bar", not pal._bar_back.visible)

	pal.caught = false
	pal.dying = true
	pal._update_label()
	_check("a dying pal shows no bar", not pal._bar_back.visible)

	pal.queue_free()
	player.queue_free()
