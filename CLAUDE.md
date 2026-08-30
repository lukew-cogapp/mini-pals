# godot-world

Godot 4.7 third-person game, built with Aubrey. Long-term aim is a small
Palworld-style loop: walk a world, find creatures, catch one, it follows you.

Build order, each step playable on its own:

1. ~~Character controller on a ground plane~~ done
2. ~~Creature that wanders (idle -> wander -> flee)~~ done
3. ~~Throwable pal cube, hit detection, capture roll~~ done
4. ~~Caught creature follows the player~~ done, and can be ridden
5. ~~Gathering, inventory, workbench crafting~~ done
6. ~~Bigger terrain, several creature types~~ done
7. ~~Player health, combat, XP, species drops~~ done
8. ~~Endgame altar, key recipe, boss fight~~ done

Current direction: polish feedback, adopt a real test runner, and make the
game easier to share.

## Layout

```
project.godot              input map, autoloads, main scene
scripts/tuning.gd          every tunable number, autoloaded as `Tuning`
scripts/*.gd               behaviour only, no literals
materials/*.tres           shared StandardMaterial3D resources
scenes/models/*.tscn       visuals only, swappable for real .glb
scenes/*.tscn              things with logic: player, world
assets/monsters/           Quaternius CC0 pack, 50 rigged monsters
assets/nature/             Quaternius CC0 nature kit, trees and rocks
```

Two conventions the owner asked for, worth keeping:

- **Numbers live in `tuning.gd`.** Playtesting means editing one file, and
  GDScript hot-reloads, so values can change while the game runs.
- **Models are their own scenes.** `player.tscn` instances
  `models/player_model.tscn` rather than embedding meshes, so swapping in a
  real `.glb` touches one file.

## Godot facts worth not relearning

**Orientation: one convention, one compensation.** Gameplay code is pure Godot
convention, where forward is **-Z**: `Vector3.FORWARD == (0, 0, -1)`, cameras
look along -Z, `look_at()` points -Z at the target, and a camera's or body's
forward is `-basis.z`. Facing a body along its travel is
`atan2(-dir.x, -dir.z)`. SpringArm3D extends its children along its local
**+Z** (verified: a child camera ends at `(0, 0, spring_length)`), which is
exactly behind a -Z-facing body, so the camera rig has NO rotation on it.

glTF 2.0 defines the front of an asset as **+Z** (spec, "Coordinate System
and Units"; Godot mirrors this as `Vector3.MODEL_FRONT`), and Quaternius
follows the spec: rendering the raw pack showed the face from +Z, the back
from -Z. So every `.gltf` under `assets/monsters/` has been rotated 180
degrees at source (root node quaternion `[0, 1, 0, 0]`) by
`scripts/tools/face_forward.py`, and the art now faces -Z like everything
else. No animation targets the root node, so the flip survives animation.
Nothing in any scene or script compensates for model facing; run the script
on any newly downloaded pack before instancing it, or it will spawn facing
backwards. The player's SpringArm needs `add_excluded_object(get_rid())`
(done in `player.gd _ready`) or its cast hits the player's own capsule and
pulls the camera into the head.

Do not trust reasoning about any of this; it has been wrong here four times.
`godot --headless --path . -s test/orientation_test.gd` asserts camera
placement, turn maths for all four inputs, throw direction, and punch facing.
The screenshot harness renders facing shots for all four walk directions
(14 to 17), the rig camera view (18), a thrown cube in flight (19), and a
walking wolf (20). Run both after touching anything orientation-adjacent,
and LOOK at the images. Never infer facing from vertex counts or bone
positions; both gave the wrong answer here. Render it and look.

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

**Screenshots.** `test/screenshot.gd` renders the player and world to
`test/shots/*.png` from several angles, walking and jumping included:

    godot --path . -s test/screenshot.gd

It must run WINDOWED. Under `--headless` the dummy renderer writes blank
images. Downscale with `sips -Z 700` before reading them. This is the only way
to check anything visual, and it has already caught a backwards model and
wings buried inside a body.

**Verifying without a screen.** `godot --headless --path . -s some_script.gd`
with `extends SceneTree` runs arbitrary checks: instantiate a scene, count
children, read a material. The `RID allocations ... leaked at exit` errors from
such scripts are the script not freeing nodes, not a real fault.

**Hot reload:** `.gd` yes, `.tscn` no. F8 stop, F5 play.

**Autoloads register after a `-s` script's `_init` starts.** A verify script
that touches an autoload (or `load()`s a scene whose scripts reference one)
from `_init` fails with `Identifier not found`. `await process_frame` once
before doing anything.

**Area3D needs its mask to match the target's layer.** Pals sit on layer 4, so
the pal cube needs `collision_mask = 4`; the default mask of 1 silently
detects nothing. No error, the cube just sails through.

**Two CharacterBody3Ds cannot occupy each other.** Riding puts the player
inside the mount, and the mount's `move_and_slide` then jams against the rider:
the tell is `get_slide_collision_count()` pegged at `max_slides` every frame
while `velocity` looks correct and position never changes. Disable the rider's
collider while mounted.

## Assets

`assets/monsters/` is Quaternius Ultimate Monsters, **CC0 1.0** (public domain,
commercial use fine, no attribution needed). Licence kept beside the files.
50 monsters in Big / Blob / Flying, each rigged with ~8 animations
(`Flying_Idle`, `Fast_Flying`, `Headbutt`, `Punch`, `Death`, `HitReact`,
`Yes`, `No` on Armabee). Several have `_Evolved` variants, useful later.

glTF geometry is embedded, so there are no `.bin` sidecars. Godot imports
`.gltf` natively; each gets a generated `.import`.

`assets/nature/` is Quaternius Stylized Nature MegaKit, **CC0 1.0**, 68
unrigged models: trees, rocks, bushes, grass, mushrooms, flowers. Unlike the
monster pack these carry `.bin` sidecars and external `.png` textures, and
the download splits those textures into a `Textures/` folder the `glTF/`
folder does not duplicate: copy both or the import fails on a missing
`Rocks_Diffuse.png`. Single mesh, no rig, no root rotation, and radially
symmetric, so `face_forward.py` does not apply.

Trees and rocks each have several variants wrapped as their own scenes
(`scenes/models/commontree_*.tscn`, `pine_*.tscn`, `rock_medium_*.tscn`);
`scenery.gd` picks one per instance from an exported array. Kit trees stand
~7m and rocks ~2m at scale 1, well above the primitives they replaced, so
`TREE_SCALE_*` and `ROCK_SCALE_*` are correspondingly smaller. Tree collision
is a cylinder on the trunk only, so the canopy is walked under.

## Working notes

Trees and rocks have collision. Rocks under `Tuning.STEP_HEIGHT` are stepped
over, trees block. Step-up is a home-rolled probe in `player.gd`; Godot has no
built-in stair stepping and the proposal for it is still open. The shore wall
is a generated ring of box colliders with each long side tangent to the shore;
`test/water_bounds_test.gd` covers the gap between wall segments for walking
and riding.

Scatter is seeded (`Tuning.SCATTER_SEED`), so the world is identical each run.
Change the seed for a new layout.

Endgame: player level 4 unlocks the Altar Key recipe at the workbench
(3 pelt + 3 cactus fruit + 3 demon horn). One stone altar stands at
`Tuning.ALTAR_POS`, out in the demon ring; R (action `interact`, gamepad
D-pad up) with a key summons the Mushroom King (`scenes/pal_boss.tscn`),
one alive at a time. The fight darkens the world, gives every pal a glow
light, and loops procedural music; `scripts/altar.gd` restores all of it
when the boss is caught or dies. Catching it is the win condition.

Trees and rocks are gatherable (`scripts/resource_node.gd`, groups
`tree`/`rock`/`resource_node`): punch (F) yields wood/stone, deplete after
`Tuning.GATHER_HITS`, respawn in place. The workbench (B nearby) crafts pal
cubes from `Tuning.CUBE_RECIPE`; throwing consumes one from `Inventory`
(autoload, `scripts/inventory.gd`).

Holding the throw key aims: a reticule appears at screen centre showing the
locked pal's name and catch %, and releasing throws. `_current_throw_aim`
projects the ray from the active camera through the screen centre, prefers a
pal within a lock radius that widens with distance
(`CUBE_AIM_ASSIST_RADIUS` + `CUBE_AIM_ASSIST_GROWTH` per metre), and falls
back to a world raycast (mask `0b101`), then to the ground at
`CUBE_AIM_DISTANCE`. That distance is measured from the camera, not the
player, so it must exceed the intended catch range by the camera's arm
length. `_lob_velocity` solves the launch velocity through the aim point
under `CUBE_GRAVITY`, so the shoulder spawn offset cannot cause a miss.
`CUBE_LOB_SPEED` is the feel knob: lower is floatier and higher-arcing.
A fast cube can tunnel past a pal between frames, so `pal_cube.gd` also
raycasts its own step each frame rather than relying on `body_entered`.

Dismounting probes four directions around the mount for a spot clear of
geometry and inside `SHORE_WALL_RADIUS`, and refuses with a message if none
is safe. Death dismounts with `force`, which accepts an unsafe spot rather
than trapping the player on a corpse.

Feedback the player's own body gives: every swing of `punch` plays
`Bite_Front` for `BITE_ANIM_TIME` (the cat rig has no `Punch` clip) and a
swing that reaches nothing still plays a `whiff` tone, so the most pressed
button in the game always moves something. `_animate` yields while
`_bite_left` is running or Walk would stomp the swing on the next frame.
A cube that lands on nothing bursts and plays `cube_miss` before freeing,
rather than blinking out: it cost wood and stone.

Player health: `player.gd` has `hp` and `damage(amount, from_position)`,
regen after a no-hit delay, and death -> respawn at the origin spawn with
inventory and party kept and all pal aggro cleared. HUD shows a bar top-left.

Pals fight back: punching one puts it in `State.ATTACK` (chase + hit on a
cooldown) for `PAL_AGGRO_TIME`. If it cannot land a hit for
`PAL_NO_HIT_GIVE_UP_TIME`, it gives up; a successful `Player.damage()` or
another player hit on the pal resets that timer. Species with `aggressive = true` (the Demon,
`scenes/pal_demon.tscn`, spawned in an annulus at the map rim) attack on sight
inside `PAL_AGGRO_RADIUS`; after giving up they wait for the player to leave
and re-enter that radius before reacquiring. A caught pal never attacks the player.

A following pal does fight for you. In `State.DEFEND` it picks the nearest
hostile (one in `State.ATTACK`, or an aggressive species within
`PAL_AGGRO_RADIUS` of the player) inside `FOLLOWER_DEFEND_RADIUS` and hits it
through `take_follower_hit`, which clamps hp at `FOLLOWER_MIN_TARGET_HP` so a
follower can never land the kill and cost you the catch. It drops back to
FOLLOW when the target dies, is caught, calms down, or the player passes
`FOLLOWER_LEASH` away. `test/pal_combat_test.gd` covers all of it.

Every bug this project has hit was invisible on inspection and only showed up
in a headless test: a cube flying over the target's head, a mount jammed at
max_slides, a model facing backwards, a collision mask that matched nothing.
Write the check, run it, read the numbers. Do not reason about whether it works.

The owner can see the game and I cannot. I can verify a scene loads, spawns the
right node count, and runs without errors; I cannot tell whether the jump feels
good or the camera sits too close. Ask, rather than claiming it plays well.
