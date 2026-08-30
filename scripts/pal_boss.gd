extends Pal
## The Mushroom King, summoned at the altar. Catching it wins the game.
## Its level and BOSS_BONUS_HP make it the hardest catch in the game, but the
## odds still climb as it is worn down, which is the fight.


func _level_hp() -> int:
	return super() + Tuning.BOSS_BONUS_HP


func _swing() -> bool:
	if _anim and _anim.has_animation("Punch"):
		_anim.stop()
		_anim.play("Punch")
	Audio.play("boss_attack", global_position)
	if _player and _player.has_method("damage"):
		return _player.damage(Tuning.BOSS_ATTACK_DAMAGE, global_position)
	return false


func on_caught() -> void:
	super()
	# Deferred so it outlives the cube's own "Caught!" flash.
	Hud.flash.call_deferred("The Mushroom King is caught. You win!")
