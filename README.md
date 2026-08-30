# Mini Pals

A creature-collecting game in Godot 4.7, in the shape of Palworld: walk a
field, gather materials, craft cubes, and catch the pals wandering around.

Built by a parent and child together. Most of the art is the free Quaternius
monster pack; the world, the code and the mistakes are ours.

## Play it in a browser

**https://lukew-cogapp.github.io/mini-pals/**

No download, no install. Works in Chrome, Edge and Firefox; Safari is
rougher, since its WebGL 2 support is patchier. A controller needs a button
pressed before the browser will see it.

## Running it from source

```
godot --path .
```

Or open the folder in the Godot editor and press F5.

Tests are `./test/run.sh` (GUT, one process, all suites). A pre-commit hook
compiles every script and scene, so a rename that misses a use is caught
before it lands rather than the next time someone walks that far into the
world.

## Controls

Press `/` in game for the same list.

| | Keyboard | Gamepad |
|---|---|---|
| Move | WASD or arrows | Left stick |
| Run | Shift | Left stick click |
| Jump | Space | A |
| Look | Mouse | Right stick |
| Bite a tree, rock or pal | F | Y |
| Build menu, at the workbench | B | B |
| Aim and throw a pal cube (hold) | Q | Right trigger |
| Ride a caught pal | E | X |
| Use altar / interact | R | D-pad up |
| Swap active pal | Tab, 1, 3 | LB |
| Controls list | / | Start |
| Free the mouse | Esc | |

## The loop

1. **Gather.** Bite trees for wood and rocks for stone. Three hits empties a
   node; it comes back after a while.
2. **Craft.** Find the workbench near where you start and press `B`. A pal cube
   costs one wood and one stone.
3. **Weaken.** Biting a wild pal makes it easier to catch, and so does a pal
   of your own: a follower fights alongside you but never lands the killing
   blow, so the catch stays yours.
4. **Catch.** Hold `Q` to aim. The reticule names the pal it has locked and
   shows the odds; let go to throw.
5. **Keep.** Caught pals join your party, one out at a time. The Wolf can be
   ridden.
6. **Grow.** Catches and defeats earn XP. Species drops let you craft the
   Altar Key once you reach level 4.
7. **Win.** Take the key to the altar out in the scorched ground, summon the
   Mushroom King, and catch it.

## Species

| | Rideable | Behaviour |
|---|---|---|
| Wolf | Yes | Flees when you get close |
| Cactoro | No | Flees when you get close |
| Demon | No | Attacks on sight, lives on the scorched ground |
| Mudwader | Yes | On the sand. The only way into the shallows |
| Glimmerfin | No | Lives in the shallows and never leaves the water |
| Mushroom King | No | Summoned boss and win condition |

Catching a Mudwader is the gate to the water: the Glimmerfin swim too far out
to reach a cube thrown from the beach, so you have to ride out to them.

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

Made with the [Godot Engine](https://godotengine.org), MIT.

Art is [Quaternius](https://quaternius.com), CC0: Ultimate Monsters, the
Stylized Nature MegaKit, and the Ultimate Platformer Pack. Everything else,
including the sound, is ours: every tone and the boss music are synthesised
at startup in `scripts/audio.gd`, so the repo carries no audio files.
