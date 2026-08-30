# Godot World

A creature-collecting game in Godot 4.7, in the shape of Palworld: walk a
field, gather materials, craft cubes, and catch the pals wandering around.

Built by a parent and child together. Most of the art is the free Quaternius
monster pack; the world, the code and the mistakes are ours.

## Playing it

```
godot --path .
```

Or open the folder in the Godot editor and press F5.

## Controls

Press `/` in game for the same list.

| | Keyboard | Gamepad |
|---|---|---|
| Move | WASD or arrows | Left stick |
| Run | Shift | Left stick click |
| Jump | Space | A |
| Look | Mouse | Right stick |
| Punch a tree, rock or pal | F | Y |
| Build menu, at the workbench | B | B |
| Throw a pal cube | Q or left click | Right trigger |
| Ride a caught pal | E | X |
| Swap active pal | Tab, 1, 3 | LB |
| Controls list | / | Start |
| Free the mouse | Esc | |

## The loop

1. **Gather.** Punch trees for wood and rocks for stone. Three hits empties a
   node; it comes back after a while.
2. **Craft.** Find the workbench near where you start and press `B`. A pal cube
   costs one wood and one stone.
3. **Weaken.** Punching a wild pal makes it easier to catch. The chance is
   shown above its head.
4. **Catch.** Throw a cube with `Q`. The cube shakes three times before it
   decides.
5. **Keep.** Caught pals join your party, one out at a time. The Wolf can be
   ridden.

## Species

| | Rideable | Behaviour |
|---|---|---|
| Wolf | Yes | Flees when you get close |
| Cactoro | No | Flees when you get close |
| Demon | No | Attacks on sight, lives at the edge of the map |

## Layout

```
project.godot          input map, autoloads, main scene
scripts/tuning.gd      every tunable number, autoloaded as `Tuning`
scripts/*.gd           behaviour, no literals
materials/*.tres       shared materials
ui/*.tres              shared UI styles
scenes/models/*.tscn   visuals only, swappable
scenes/*.tscn          things with logic
assets/monsters/       Quaternius pack, CC0
test/screenshot.gd     renders the game to test/shots for review
```

Everything you might want to change while playing lives in `scripts/tuning.gd`:
speeds, jump height, catch chance, respawn times, how far a cube flies. GDScript
hot-reloads, so you can edit it while the game runs.

## Credits

Monsters are [Quaternius Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html),
CC0. Everything else is ours.
