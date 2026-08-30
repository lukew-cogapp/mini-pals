extends GutTest
## Floating pal health bar assertions, ported from test/pal_health_bar_test.gd.

func _spawn_pal(pos: Vector3, player: Node3D):
	var pal = load("res://scenes/pal_wolf.tscn").instantiate()
	add_child_autofree(pal)
	await wait_process_frames(1)
	pal.global_position = pos
	pal.velocity = Vector3.ZERO
	pal._player_cache = player
	return pal


func _player_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child_autofree(n)
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


func test_bar_hides_far_and_shows_near() -> void:
	var player := _player_at(Vector3.ZERO)
	var far := Tuning.PAL_HEALTH_BAR_DISTANCE + 10.0
	var pal = await _spawn_pal(Vector3(0.0, 0.0, far), player)

	_sample(pal)
	assert_true(not pal._bar_back.visible, "bar hidden beyond the show distance")

	pal.global_position = Vector3(0.0, 0.0, Tuning.PAL_HEALTH_BAR_DISTANCE - 2.0)
	_sample(pal)
	assert_true(pal._bar_back.visible, "bar shown inside the show distance")


func test_fill_tracks_damage() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, -2.0), player)
	pal.max_hp = 4
	pal.hp = 4
	_sample(pal)
	assert_true(
		is_equal_approx(_fill_fraction(pal), 1.0),
		"a full-health bar fills the whole inner width  fraction=%.3f" % _fill_fraction(pal),
	)

	pal.hp = 1
	pal._refresh_bar()
	assert_true(
		is_equal_approx(_fill_fraction(pal), 0.25),
		"the fill shrinks to the hp fraction  fraction=%.3f" % _fill_fraction(pal),
	)
	var mat: StandardMaterial3D = pal._bar_fill.material_override
	assert_true(
		mat.albedo_color.is_equal_approx(Tuning.PAL_HEALTH_BAR_LOW_COLOUR),
		"a nearly dead pal shows a red bar  colour=%s" % mat.albedo_color,
	)

	# The bar grows from its left edge, so the left edge must not move.
	var left := _fill_left_edge(pal)
	pal.hp = 4
	pal._refresh_bar()
	var left_full := _fill_left_edge(pal)
	assert_true(
		is_equal_approx(left, left_full),
		"the fill grows from a fixed left edge  empty=%.4f full=%.4f" % [left, left_full],
	)


func test_fill_follows_max_hp_on_level_gain() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, -2.0), player)
	pal.level = 1
	pal.max_hp = 3
	pal.hp = 1
	_sample(pal)
	var before := _fill_fraction(pal)

	pal.gain_level()
	assert_true(
		is_equal_approx(_fill_fraction(pal), 1.0) and pal.max_hp > 3,
		"levelling refills the bar to the new max  before=%.3f after=%.3f max_hp=%d"
		% [before, _fill_fraction(pal), pal.max_hp],
	)
	# The label rises with the model, and the bar must stay above it.
	assert_true(
		pal._bar_back.position.y > pal._label.position.y,
		"the bar stays above the name label after levelling  bar=%.2f label=%.2f"
		% [pal._bar_back.position.y, pal._label.position.y],
	)


## A caught pal is yours and its bar would follow you everywhere; a dying one
## is about to vanish. Both hide, as the name label already does.
func test_caught_and_dying_pals_show_nothing() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, -2.0), player)
	_sample(pal)
	assert_true(pal._bar_back.visible, "a wild pal near the player shows its bar")

	pal.caught = true
	pal._update_label()
	assert_true(not pal._bar_back.visible, "a caught pal shows no bar")

	pal.caught = false
	pal.dying = true
	pal._update_label()
	assert_true(not pal._bar_back.visible, "a dying pal shows no bar")
