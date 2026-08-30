extends StaticBody3D
## Summoning altar. Consumes an altar key to summon the boss, then owns the
## fight ambience (music, darkened world, glowing pals) until the boss is
## caught or defeated, whichever way it leaves the fight.

const BOSS_SCENE := preload("res://scenes/pal_boss.tscn")
const GLOW_NODE := "FightGlow"

var _boss: Pal = null
var _fight := false
## Environment numbers as they were at summon time, not the scene defaults:
## another system may have changed them, so restore must be exact.
var _saved := {}
var _tween: Tween

@onready var _glow: OmniLight3D = $Glow
@onready var _idle_particles: GPUParticles3D = $IdleParticles
@onready var _burst: GPUParticles3D = $SummonBurst


func _process(_delta: float) -> void:
	var ready_to_summon := not _boss_alive() \
		and Inventory.count("altar_key") > 0 and _player_in_range()
	_glow.visible = ready_to_summon
	_idle_particles.emitting = ready_to_summon
	# Poll rather than signal: it catches every way the boss can leave the
	# fight (caught, killed, freed) with one piece of code.
	if _fight and not _boss_alive():
		_end_fight()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _player_in_range():
		return
	get_viewport().set_input_as_handled()
	if _boss_alive():
		Hud.flash("The Mushroom King already stalks the world!")
		return
	if Inventory.count("altar_key") < 1:
		Hud.flash("The altar is silent. It hungers for a key.")
		return
	Inventory.remove("altar_key", 1)
	_summon()


func _summon() -> void:
	var boss := BOSS_SCENE.instantiate() as Pal
	boss.level = Tuning.BOSS_LEVEL
	# Positioned before add_child: pal._ready takes its wander home from it.
	boss.position = position + Tuning.BOSS_SPAWN_OFFSET
	get_parent().add_child(boss)
	_boss = boss
	_fight = true
	_burst.restart()
	Audio.play("summon", global_position)
	Audio.play_music("boss_music")
	Hud.flash("The Mushroom King answers the call!")
	_darken(true)
	_set_pal_glow(true)


func _end_fight() -> void:
	_fight = false
	# The dying boss is already out of the "pal" group; clean its light here.
	if is_instance_valid(_boss):
		_remove_glow(_boss)
	_boss = null
	Audio.stop_music()
	_darken(false)
	_set_pal_glow(false)


func _boss_alive() -> bool:
	return is_instance_valid(_boss) and not _boss.caught and not _boss.dying


func _player_in_range() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	return player.global_position.distance_to(global_position) <= Tuning.ALTAR_RANGE


## --- Fight ambience --------------------------------------------------------

func _darken(on: bool) -> void:
	var env_node := _find_node(get_tree().root, "WorldEnvironment") as WorldEnvironment
	var sun := _find_node(get_tree().root, "Sun") as DirectionalLight3D
	if env_node == null or sun == null:
		return
	var env := env_node.environment
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel()
	if on:
		_saved = {
			"sun_energy": sun.light_energy,
			"sun_color": sun.light_color,
			"ambient": env.ambient_light_energy,
			"fog_density": env.fog_density,
			"fog_color": env.fog_light_color,
		}
		_tween_env(sun, env, Tuning.BOSS_DARK_SUN_ENERGY, Tuning.BOSS_DARK_SUN_COLOR,
			Tuning.BOSS_DARK_AMBIENT_ENERGY, Tuning.BOSS_DARK_FOG_DENSITY,
			Tuning.BOSS_DARK_FOG_COLOR)
	elif not _saved.is_empty():
		_tween_env(sun, env, _saved.sun_energy, _saved.sun_color,
			_saved.ambient, _saved.fog_density, _saved.fog_color)


func _tween_env(sun: DirectionalLight3D, env: Environment, sun_energy: float,
		sun_color: Color, ambient: float, fog_density: float, fog_color: Color) -> void:
	var t := Tuning.BOSS_DARK_TWEEN_TIME
	_tween.tween_property(sun, "light_energy", sun_energy, t)
	_tween.tween_property(sun, "light_color", sun_color, t)
	_tween.tween_property(env, "ambient_light_energy", ambient, t)
	_tween.tween_property(env, "fog_density", fog_density, t)
	_tween.tween_property(env, "fog_light_color", fog_color, t)


## Every pal (and the player's cat) carries a small shadowless omni light
## during the fight, so the darkened world is dotted with glowing creatures.
func _set_pal_glow(on: bool) -> void:
	var targets: Array = get_tree().get_nodes_in_group("pal")
	targets += get_tree().get_nodes_in_group("player")
	for node in targets:
		if on:
			_add_glow(node)
		else:
			_remove_glow(node)


func _add_glow(node: Node) -> void:
	if node.has_node(GLOW_NODE):
		return
	var light := OmniLight3D.new()
	light.name = GLOW_NODE
	light.light_color = Tuning.FIGHT_GLOW_COLOR
	light.light_energy = Tuning.FIGHT_GLOW_ENERGY
	light.omni_range = Tuning.FIGHT_GLOW_RANGE
	light.shadow_enabled = false
	light.position = Vector3.UP * Tuning.FIGHT_GLOW_HEIGHT
	node.add_child(light)


func _remove_glow(node: Node) -> void:
	var light := node.get_node_or_null(GLOW_NODE)
	if light:
		light.queue_free()


func _find_node(from: Node, node_name: String) -> Node:
	if from.name == node_name:
		return from
	for child in from.get_children():
		var found := _find_node(child, node_name)
		if found:
			return found
	return null
