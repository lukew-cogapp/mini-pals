extends Control
## Top-down map of the island, drawn straight into `_draw` from live node
## positions. No viewport and no second camera: it is a few dozen circles and
## one polygon, so a render pass would cost more than the thing it draws.
##
## NORTH-UP, not rotating with the player. The map exists to steer the player
## towards fixed landmarks (the altar, the scorched blob), and a map that spins
## gives those a different shape every frame, so nobody builds a mental model
## of the island. The wedge at the centre carries the heading instead.
##
## Screen mapping, once, here: world +X is right and world -Z is UP, so a
## world point maps to `Vector2(x, z) * _scale` from the map's centre. Godot
## forward is -Z (see CLAUDE.md), so a player facing forward draws a wedge
## pointing up the screen. `test/minimap_test.gd` asserts this rather than
## trusting it.

## World metres per fog cell edge, and the grid's origin corner.
var _fog: PackedByteArray = PackedByteArray()
## Terrain colour per cell, resolved once when the cell is revealed:
## 0 nothing, 1 ash, 2 land, 3 shallow.
var _terrain: PackedByteArray = PackedByteArray()
var _cells := 0
var _fog_origin := 0.0

var _player: Node3D = null
## Redrawn every frame, so the scale is computed once here rather than per draw.
var _scale := 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(Tuning.MINIMAP_SIZE, Tuning.MINIMAP_SIZE)
	size = custom_minimum_size
	_scale = Tuning.MINIMAP_SIZE / Tuning.MINIMAP_WORLD_SPAN
	_cells = int(ceil(Tuning.MINIMAP_WORLD_SPAN / Tuning.FOG_CELL_SIZE))
	_fog.resize(_cells * _cells)
	_terrain.resize(_cells * _cells)
	_fog_origin = -Tuning.MINIMAP_WORLD_SPAN * 0.5


func _process(_delta: float) -> void:
	if not visible:
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player:
		reveal_around(_player.global_position)
	queue_redraw()


## Mark every fog cell within FOG_REVEAL_RADIUS of `at` as seen. Revealed is
## one-way: nothing here ever clears a cell, so the map only grows.
func reveal_around(at: Vector3) -> void:
	var r := Tuning.FOG_REVEAL_RADIUS
	var lo := _cell_index(at.x - r)
	var hi := _cell_index(at.x + r)
	var lo_z := _cell_index(at.z - r)
	var hi_z := _cell_index(at.z + r)
	for cx in range(lo, hi + 1):
		for cz in range(lo_z, hi_z + 1):
			if cx < 0 or cz < 0 or cx >= _cells or cz >= _cells:
				continue
			# Cell centre against the circle, so the revealed area is a disc
			# rather than the square the loop walks.
			var wx := _fog_origin + (cx + 0.5) * Tuning.FOG_CELL_SIZE
			var wz := _fog_origin + (cz + 0.5) * Tuning.FOG_CELL_SIZE
			if Vector2(wx - at.x, wz - at.z).length() <= r:
				var i := cz * _cells + cx
				if _fog[i] != 1:
					_fog[i] = 1
					_terrain[i] = _terrain_at(Vector3(wx, 0.0, wz))


## True once the player has been near `point`. Terrain, markers and pals all
## ask this, so nothing leaks through the fog by being drawn a different way.
func is_revealed(point: Vector3) -> bool:
	var cx := _cell_index(point.x)
	var cz := _cell_index(point.z)
	if cx < 0 or cz < 0 or cx >= _cells or cz >= _cells:
		return false
	return _fog[cz * _cells + cx] == 1


func _cell_index(world: float) -> int:
	return int(floor((world - _fog_origin) / Tuning.FOG_CELL_SIZE))


## World point to a position inside this control, north-up and centred on the
## map's own origin (the world origin), not on the player: the island does not
## move, so a fixed frame keeps the shapes still.
func _to_map(point: Vector3) -> Vector2:
	var half := Tuning.MINIMAP_SIZE * 0.5
	return Vector2(half + point.x * _scale, half + point.z * _scale)


func _draw() -> void:
	# A square ground filling the panel, not a disc inside it: the panel is
	# already a rounded rectangle, and a circle drawn within it left a ring of
	# dead panel around the map.
	draw_rect(Rect2(Vector2.ZERO, Vector2(Tuning.MINIMAP_SIZE, Tuning.MINIMAP_SIZE)),
		Tuning.MINIMAP_BG_COLOR)

	_draw_terrain()
	_draw_altar()
	_draw_pals()
	_draw_player()


## Terrain as fog cells rather than as discs: a disc clipped to an arbitrary
## revealed shape is not something `_draw` can express, and the grid is the
## revealed shape already. Each seen cell is painted the colour of whichever
## zone contains it, so the island appears in the shape it was walked.
func _draw_terrain() -> void:
	var px := Tuning.FOG_CELL_SIZE * _scale
	for cz in _cells:
		for cx in _cells:
			if _fog[cz * _cells + cx] != 1:
				continue
			var kind := _terrain[cz * _cells + cx]
			if kind == 0:
				continue
			var colour := _terrain_colour(kind)
			var wx := _fog_origin + (cx + 0.5) * Tuning.FOG_CELL_SIZE
			var wz := _fog_origin + (cz + 0.5) * Tuning.FOG_CELL_SIZE
			var at := _to_map(Vector3(wx - Tuning.FOG_CELL_SIZE * 0.5, 0.0,
				wz - Tuning.FOG_CELL_SIZE * 0.5))
			# One pixel of overlap, or the grid shows as a mesh of hairlines.
			draw_rect(Rect2(at, Vector2(px + 1.0, px + 1.0)), colour)


## Asked of the Zone system rather than of a second copy of the island maths,
## so the ash blob's noisy edge is the one the world actually uses.
func _terrain_colour(kind: int) -> Color:
	match kind:
		1: return Tuning.MINIMAP_ASH_COLOR
		2: return Tuning.MINIMAP_LAND_COLOR
		3: return Tuning.MINIMAP_SHALLOW_COLOR
	return Color(0, 0, 0, 0)


func _terrain_at(point: Vector3) -> int:
	if _player == null:
		return 0
	var world := _player.get_world_3d()
	if Zone.is_inside(world, point, Zone.Kind.ASH):
		return 1
	if Zone.is_inside(world, point, Zone.Kind.LAND):
		return 2
	if Zone.is_inside(world, point, Zone.Kind.SHALLOW):
		return 3
	return 0


func _draw_altar() -> void:
	if not is_revealed(Tuning.ALTAR_POS):
		return
	# A diamond, so the one fixed goal never reads as another pal dot.
	var at := _to_map(Tuning.ALTAR_POS)
	var r := Tuning.MINIMAP_ALTAR_SIZE
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, -r), at + Vector2(r, 0),
		at + Vector2(0, r), at + Vector2(-r, 0),
	]), Tuning.MINIMAP_ALTAR_COLOR)


func _draw_pals() -> void:
	for node in get_tree().get_nodes_in_group("pal"):
		var pal := node as Node3D
		if pal == null or not is_revealed(pal.global_position):
			continue
		var colour := Tuning.MINIMAP_PAL_COLOR
		var dot := Tuning.MINIMAP_PAL_DOT
		if pal == Party.active:
			colour = Tuning.MINIMAP_PAL_ACTIVE_COLOR
			dot = Tuning.MINIMAP_PAL_ACTIVE_DOT
		elif pal.get("aggressive"):
			colour = Tuning.MINIMAP_PAL_HOSTILE_COLOR
		draw_circle(_to_map(pal.global_position), dot, colour)


## Always drawn, fog or not: it is the player's own position, which the fog
## cannot be hiding from them.
func _draw_player() -> void:
	if _player == null:
		return
	draw_colored_polygon(player_wedge(), Tuning.MINIMAP_PLAYER_COLOR)


## The three corners of the heading wedge, in control coordinates. Public so
## the test can assert where it points instead of eyeballing a render.
func player_wedge() -> PackedVector2Array:
	var at := _to_map(_player.global_position)
	var f: Vector3 = _player.facing()
	var dir := Vector2(f.x, f.z).normalized()
	var side := Vector2(-dir.y, dir.x)
	var r := Tuning.MINIMAP_PLAYER_SIZE
	return PackedVector2Array([
		at + dir * r,
		at - dir * r * 0.6 + side * r * 0.6,
		at - dir * r * 0.6 - side * r * 0.6,
	])
