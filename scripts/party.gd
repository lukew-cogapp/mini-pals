extends Node
## Caught pals. One can be out at a time; the rest wait to be cycled in.

signal changed

var members: Array[Pal] = []
var active: Pal = null

## Player progression. XP comes from catches and kills, scaled by pal level;
## it lives here with the rest of what catching earns.
var player_level := 1
var xp := 0
var _key_hint_shown := false


func grant_xp(amount: int) -> void:
	xp += amount
	var levelled := false
	while xp >= Tuning.PLAYER_XP_PER_LEVEL:
		xp -= Tuning.PLAYER_XP_PER_LEVEL
		player_level += 1
		levelled = true
	if levelled:
		# Deferred so it outlives the catch or defeat flash of the same frame.
		Hud.flash.call_deferred("You reached level %d!" % player_level)
		if player_level >= Tuning.KEY_UNLOCK_LEVEL and not _key_hint_shown:
			_key_hint_shown = true
			Hud.flash.call_deferred("The workbench can now craft an Altar Key.")
	changed.emit()


func store(pal: Pal) -> void:
	if pal in members:
		return
	# A second catch of a species feeds the kept pal a level instead of
	# adding a duplicate nobody would use. Species is keyed by display_name.
	for kept in members:
		if kept.display_name == pal.display_name:
			if kept.level < Tuning.PAL_LEVEL_MAX:
				kept.gain_level()
				# Deferred so it outlives the cube's own "Caught!" flash.
				Hud.flash.call_deferred(
					"%s reached level %d!" % [kept.display_name, kept.level]
				)
			pal.queue_free()
			changed.emit()
			return
	members.append(pal)
	pal.stow()
	# First catch comes straight out, so a catch visibly does something.
	if active == null:
		_activate(pal)
	changed.emit()


## Step through the party. A single member toggles out and away instead.
func cycle(near := Vector3.ZERO, step := 1) -> void:
	if members.is_empty():
		return
	if members.size() == 1:
		if active:
			recall()
		else:
			_activate(members[0], near)
			changed.emit()
		return
	var i := members.find(active)
	var next: Pal = members[posmod(i + step, members.size())]
	if active:
		active.stow()
	_activate(next, near)
	changed.emit()


## The active pal's passive buff of the given kind, or 0 when none applies.
## Read live wherever the buff matters, so stowing or swapping removes it
## with no bookkeeping to get wrong.
func buff(kind: StringName) -> float:
	if active == null or active.buff_kind != kind:
		return 0.0
	var v: float = active.buff_per_level * active.level
	return minf(v, Tuning.PAL_BUFF_CAPS.get(kind, v))


## The King's job: throws stop costing a cube while he is out. Read live like
## buff(), so stowing him puts the player back on their crafted stock.
func infinite_cubes() -> bool:
	return active != null and active.display_name == Tuning.INFINITE_CUBE_SPECIES


func recall() -> void:
	if active:
		active.stow()
		active = null
		changed.emit()


func _activate(pal: Pal, near := Vector3.ZERO) -> void:
	active = pal
	var player = get_tree().get_first_node_in_group("player")
	var at := near
	if player:
		# Behind and to one side. Summoning ahead means walking straight into
		# your own pal, which shoves it along instead of letting it follow.
		at = (
			player.global_position
			- player.facing() * Tuning.SUMMON_DISTANCE
			+ player.global_transform.basis.x * Tuning.SUMMON_SIDE
		)
	pal.summon(at)
