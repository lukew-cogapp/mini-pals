# godot-world

Godot 4.7 third-person game, built with Aubrey. Long-term aim is a small
Palworld-style loop: walk a world, find creatures, catch one, it follows you.

Build order, each step playable on its own:

1. ~~Character controller on a ground plane~~ done
2. Creature that wanders (idle -> wander -> flee state machine)
3. Throwable ball, hit detection, capture roll
4. Caught creature follows the player
5. Inventory UI
6. Bigger terrain, several creature types

## Layout

```
project.godot              input map, autoloads, main scene
scripts/tuning.gd          every tunable number, autoloaded as `Tuning`
scripts/*.gd               behaviour only, no literals
materials/*.tres           shared StandardMaterial3D resources
scenes/models/*.tscn       visuals only, swappable for real .glb
scenes/*.tscn              things with logic: player, world
assets/monsters/           Quaternius CC0 pack, 50 rigged monsters
```

Two conventions the owner asked for, worth keeping:

- **Numbers live in `tuning.gd`.** Playtesting means editing one file, and
  GDScript hot-reloads, so values can change while the game runs.
- **Models are their own scenes.** `player.tscn` instances
  `models/player_model.tscn` rather than embedding meshes, so swapping in a
  real `.glb` touches one file.

## Godot facts worth not relearning

**-Z is forward.** Facing a body along its travel direction is
`atan2(-dir.x, -dir.z)`. Using `atan2(x, z)` points it backwards; the tell is
a model that moons you as you walk. Cost us one bug already.

**`.tscn` sub-resources must be declared before the node that uses them.**
A `SubResource("2")` referenced above its own `[sub_resource]` block fails with
`Condition "!int_resources.has(id)" is true` and a parse error on the *using*
line, which points away from the real problem.

**`load_steps` in a scene header must cover every ext + sub resource.**
Too low and the scene fails to load. Bump it when adding resources.

**`--quit` exits before importing.** To generate `.godot/` and check for asset
errors, use `--import`. To check a scene actually runs, `--quit-after N`
(frames). Both exit 0 on success and print nothing useful on failure, so grep
stderr for `error`.

**Verifying without a screen.** `godot --headless --path . -s some_script.gd`
with `extends SceneTree` runs arbitrary checks: instantiate a scene, count
children, read a material. The `RID allocations ... leaked at exit` errors from
such scripts are the script not freeing nodes, not a real fault.

**Hot reload:** `.gd` yes, `.tscn` no. F8 stop, F5 play.

## Assets

`assets/monsters/` is Quaternius Ultimate Monsters, **CC0 1.0** (public domain,
commercial use fine, no attribution needed). Licence kept beside the files.
50 monsters in Big / Blob / Flying, each rigged with ~8 animations
(`Flying_Idle`, `Fast_Flying`, `Headbutt`, `Punch`, `Death`, `HitReact`,
`Yes`, `No` on Armabee). Several have `_Evolved` variants, useful later.

glTF geometry is embedded, so there are no `.bin` sidecars. Godot imports
`.gltf` natively; each gets a generated `.import`.

## Working notes

Trees and rocks are **visual only, no collision** — you walk through them.
Deliberate while prototyping.

Scatter is seeded (`Tuning.SCATTER_SEED`), so the world is identical each run.
Change the seed for a new layout.

The owner can see the game and I cannot. I can verify a scene loads, spawns the
right node count, and runs without errors; I cannot tell whether the jump feels
good or the camera sits too close. Ask, rather than claiming it plays well.
