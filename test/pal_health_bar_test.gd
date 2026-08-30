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
	await _test_every_layer_shows_and_hides_together()
	await _test_the_colour_ramp_slides_rather_than_snapping()
	await _test_the_sheen_tracks_the_fill()
	await _test_the_shadow_sits_behind_and_below_the_backing()

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


## The real player scene, not a bare Node3D: the bar gates on the CameraPivot's
## heading as well as on distance, and a stand-in with no pivot is waved
## through the cone and so tests a path the game never takes.
func _player_at(pos: Vector3) -> Node3D:
	var n: Node3D = load("res://scenes/player.tscn").instantiate()
	get_root().add_child(n)
	n.set_physics_process(false)
	n.global_position = pos
	return n


## Point the camera at `pos`, so the pal there is inside the facing cone.
func _look_at_from(player: Node3D, pos: Vector3) -> void:
	var to := pos - player.global_position
	player.get_node("CameraPivot").rotation.y = atan2(-to.x, -to.z)


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
	_look_at_from(player, pal.global_position)
	_sample(pal)
	_check("bar shown inside the show distance when looked at", pal._bar_back.visible)

	# Distance is still the outer gate, so the far case must stay hidden even
	# with the camera pointed straight at it.
	pal.global_position = Vector3(0.0, 0.0, far)
	_look_at_from(player, pal.global_position)
	_sample(pal)
	_check("bar still hidden beyond the show distance when looked at",
		not pal._bar_back.visible)

	pal.queue_free()
	player.queue_free()


func _test_fill_tracks_damage() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 2.0), player)
	_look_at_from(player, pal.global_position)
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
	_look_at_from(player, pal.global_position)
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
	_look_at_from(player, pal.global_position)
	_sample(pal)
	_check("a wild pal the player is looking at shows its bar", pal._bar_back.visible)

	pal.caught = true
	pal._update_label()
	_check("a caught pal shows no bar", not pal._bar_back.visible)

	pal.caught = false
	pal.dying = true
	pal._update_label()
	_check("a dying pal shows no bar", not pal._bar_back.visible)

	pal.queue_free()
	player.queue_free()


## Five quads now, not two. One left visible when the rest hide is a bar that
## half-follows the player around the map.
func _test_every_layer_shows_and_hides_together() -> void:
	var player := _player_at(Vector3.ZERO)
	# In front of the player: Godot forward is -Z, and the bar is now gated on
	# the camera's facing cone as well as distance.
	var pal = await _spawn_pal(Vector3(0.0, 0.0, -2.0), player)
	var layers := [
		pal._bar_shadow, pal._bar_back, pal._bar_track, pal._bar_fill, pal._bar_sheen
	]
	_check(
		"the bar is built from a shadow, a backing, a track, a fill and a sheen",
		layers.all(func(q): return q != null),
	)
	_sample(pal)
	_check("every layer shows together", layers.all(func(q): return q.visible))
	pal.global_position = Vector3(0.0, 0.0, Tuning.PAL_HEALTH_BAR_DISTANCE + 10.0)
	_sample(pal)
	_check("every layer hides together", layers.all(func(q): return not q.visible))

	# The shadow is the only translucent layer, and the whole point of it is
	# that a dark bar over dark ash still has an edge.
	var shadow_mat: StandardMaterial3D = pal._bar_shadow.material_override
	_check(
		"the shadow is translucent and darker than the backing",
		shadow_mat.albedo_color.a < 1.0
		and shadow_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
		"colour=%s" % shadow_mat.albedo_color,
	)
	# Every layer keeps the billboard scale fix. Without it each renders as a
	# 1 m black square, which is invisible to every non-visual check there is.
	for quad in layers:
		var mat: StandardMaterial3D = quad.material_override
		_check(
			"%s keeps billboard_keep_scale" % quad.name,
			mat.billboard_keep_scale
			and mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED,
		)

	pal.queue_free()
	player.queue_free()


## The old ramp had one step: green until 0.35, red below it, so two hits took
## a pal from healthy to critical with no warning in between. It slides now.
func _test_the_colour_ramp_slides_rather_than_snapping() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 2.0), player)

	_check(
		"a full bar is the healthy colour",
		pal.bar_colour(1.0).is_equal_approx(Tuning.PAL_HEALTH_BAR_FILL_COLOUR),
		"colour=%s" % pal.bar_colour(1.0),
	)
	_check(
		"an empty bar is the low colour",
		pal.bar_colour(0.0).is_equal_approx(Tuning.PAL_HEALTH_BAR_LOW_COLOUR),
		"colour=%s" % pal.bar_colour(0.0),
	)
	_check(
		"the mid stop is the mid colour",
		pal.bar_colour(Tuning.PAL_HEALTH_BAR_MID_FRACTION).is_equal_approx(
			Tuning.PAL_HEALTH_BAR_MID_COLOUR
		),
		"colour=%s" % pal.bar_colour(Tuning.PAL_HEALTH_BAR_MID_FRACTION),
	)
	# The slide itself: green must fall steadily as health does, never climbing
	# back, and every step above the low stop must actually move. Below the
	# low stop the fill is fully the low colour by design, so those samples
	# repeat and are excluded.
	var monotonic := true
	var moved_every_step := true
	var prev: Color = pal.bar_colour(1.0)
	for i in range(1, 21):
		var frac := 1.0 - i / 20.0
		var here: Color = pal.bar_colour(frac)
		if here.g > prev.g + 0.0001:
			monotonic = false
		if frac >= Tuning.PAL_HEALTH_BAR_LOW_FRACTION and is_equal_approx(here.g, prev.g):
			moved_every_step = false
		prev = here
	_check("green falls without ever climbing back", monotonic)
	_check("every step above the low stop moves the colour", moved_every_step)
	# A single step somewhere in the ramp is what this replaces, so assert the
	# largest jump is small compared with the whole range.
	var biggest := 0.0
	prev = pal.bar_colour(1.0)
	for i in range(1, 21):
		var here: Color = pal.bar_colour(1.0 - i / 20.0)
		biggest = maxf(biggest, absf(here.g - prev.g))
		prev = here
	_check(
		"the ramp has no single snap in it",
		biggest < 0.25,
		"biggest step=%.3f" % biggest,
	)

	pal.queue_free()
	player.queue_free()


## The sheen is a lighter strip pinned to the top of the fill. It shares the
## fill's left edge and width, so it must shrink with it and never overhang.
func _test_the_sheen_tracks_the_fill() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 2.0), player)
	pal.max_hp = 4
	pal.hp = 4
	_sample(pal)

	for hp in [4, 3, 1]:
		pal.hp = hp
		pal._refresh_bar()
		_check(
			"at hp %d the sheen is exactly as wide as the fill" % hp,
			is_equal_approx(pal._bar_sheen.scale.x, pal._bar_fill.scale.x),
			"sheen=%.4f fill=%.4f" % [pal._bar_sheen.scale.x, pal._bar_fill.scale.x],
		)
		var sheen_quad: QuadMesh = pal._bar_sheen.mesh
		var fill_quad: QuadMesh = pal._bar_fill.mesh
		_check(
			"at hp %d the sheen shares the fill's left edge" % hp,
			is_equal_approx(sheen_quad.center_offset.x, fill_quad.center_offset.x),
			"sheen=%.4f fill=%.4f" % [
				sheen_quad.center_offset.x, fill_quad.center_offset.x
			],
		)
		_check(
			"at hp %d the sheen is shorter than the fill" % hp,
			pal._bar_sheen.scale.y < pal._bar_fill.scale.y,
			"sheen=%.4f fill=%.4f" % [pal._bar_sheen.scale.y, pal._bar_fill.scale.y],
		)
		# Its top edge and the fill's, both in the bar's own local space.
		var sheen_top: float = (
			sheen_quad.center_offset.y + 0.5
		) * pal._bar_sheen.scale.y
		var fill_top: float = (fill_quad.center_offset.y + 0.5) * pal._bar_fill.scale.y
		_check(
			"at hp %d the sheen sits on the fill's top edge" % hp,
			absf(sheen_top - fill_top) < 0.001,
			"sheen_top=%.4f fill_top=%.4f" % [sheen_top, fill_top],
		)
		var sheen_mat: StandardMaterial3D = pal._bar_sheen.material_override
		var fill_mat: StandardMaterial3D = pal._bar_fill.material_override
		_check(
			"at hp %d the sheen is lighter than the fill under it" % hp,
			sheen_mat.albedo_color.get_luminance()
			> fill_mat.albedo_color.get_luminance(),
			"sheen=%s fill=%s" % [sheen_mat.albedo_color, fill_mat.albedo_color],
		)

	pal.queue_free()
	player.queue_free()


## The shadow lifts the bar off the ground behind it, which needs it bigger
## than the backing, offset down and right, and drawn under everything else.
func _test_the_shadow_sits_behind_and_below_the_backing() -> void:
	var player := _player_at(Vector3.ZERO)
	var pal = await _spawn_pal(Vector3(0.0, 0.0, 2.0), player)

	_check(
		"the shadow is larger than the backing on both axes",
		pal._bar_shadow.scale.x > pal._bar_back.scale.x
		and pal._bar_shadow.scale.y > pal._bar_back.scale.y,
		"shadow=%s back=%s" % [pal._bar_shadow.scale, pal._bar_back.scale],
	)
	# Offset lives in the mesh, not the node: a billboard ignores the node
	# basis, so a node-space nudge would swing round the bar with the camera.
	var quad: QuadMesh = pal._bar_shadow.mesh
	_check(
		"the shadow is offset down and right inside its own mesh",
		quad.center_offset.x > 0.0 and quad.center_offset.y < 0.0,
		"center_offset=%s" % quad.center_offset,
	)
	_check(
		"the shadow's node position matches the backing's",
		pal._bar_shadow.position.is_equal_approx(pal._bar_back.position),
	)
	var order := [
		pal._bar_shadow, pal._bar_back, pal._bar_track, pal._bar_fill, pal._bar_sheen
	]
	var ascending := true
	for i in range(1, order.size()):
		var here: StandardMaterial3D = order[i].material_override
		var below: StandardMaterial3D = order[i - 1].material_override
		if here.render_priority <= below.render_priority:
			ascending = false
	_check(
		"the layers draw shadow, backing, track, fill, sheen, in that order", ascending
	)
	# The track is the empty part of the bar, so it never moves or resizes: it
	# is the full inner width whatever the fill in front of it is doing.
	pal.hp = 1
	pal.max_hp = 8
	pal._refresh_bar()
	_check(
		"the track stays the full inner width whatever the fill does",
		is_equal_approx(
			pal._bar_track.scale.x,
			Tuning.PAL_HEALTH_BAR_WIDTH * (1.0 - Tuning.PAL_HEALTH_BAR_BORDER),
		)
		and pal._bar_track.scale.x > pal._bar_fill.scale.x,
		"track=%.4f fill=%.4f" % [pal._bar_track.scale.x, pal._bar_fill.scale.x],
	)
	# And it is lighter than the border around it, or it is not a track.
	var track_mat: StandardMaterial3D = pal._bar_track.material_override
	var back_mat: StandardMaterial3D = pal._bar_back.material_override
	_check(
		"the track is lighter than the border framing it",
		track_mat.albedo_color.get_luminance() > back_mat.albedo_color.get_luminance(),
		"track=%s back=%s" % [track_mat.albedo_color, back_mat.albedo_color],
	)

	pal.queue_free()
	player.queue_free()
