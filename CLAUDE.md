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

**SurfaceTool winding: build a ground fan as `centre, p0, p1`.** Godot culls
back faces, and looking down from above +Z runs *down* the screen, so the
other winding renders NOTHING and the mesh is invisible while `get_faces()`,
the AABB, the normals and the material all still read as correct. Every
non-visual check passed while the ash blob was completely absent from the
frame. If a generated mesh does not appear, flip the winding before doubting
anything else.

**Emission drowns albedo on a big flat surface.** `emission_energy_multiplier`
at 0.35 rendered the ash pure white in daylight; the albedo texture is only
visible below about 0.1. The ash sits at 0.05. Raise it and the biome turns
into a snowfield, which happened three times here.

**Ground `uv1_scale` is world-units-per-tile, and both extremes read as flat.**
UVs are set in world units, so 60 tiled sixty times per metre (sub-pixel, and
the original bug) and 0.018 tiled once per 55 m (one smear). Grass is 0.25,
sand 0.33, ash 0.5. Judge it from `08_world` and `22_biome_ground`, not from
the number.

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

**One Godot at a time per project.** Several `--headless -s` runs against the
same checkout fight over `.godot/`, and the symptom is a script that hangs
with no output at all, not even a `print()` on the first line of `_init`. The
project still boots fine under `--quit-after`, which makes it look like a test
bug rather than a cache one. `godot --headless --path . --import` rebuilds the
cache and clears it. Give a parallel agent its own git worktree instead.

**`timeout` is not installed here.** `timeout 90 godot ...` fails with `env:
timeout: No such file or directory`, and in a pipeline that reads as the
command producing no output, which is easy to misread as a hang.

**Hot reload:** `.gd` yes, `.tscn` no. F8 stop, F5 play.

**A `-s` script cannot name an autoload at all.** Naming `Inventory`, `Party`
or `Hud` fails at compile time with `Identifier not found`, before any code
runs, so awaiting a frame first does NOT help: the script never compiles.
Resolve them at runtime instead, with `get_root().get_node("Inventory")`.
`Tuning.SOME_CONST` looks like an exception but is not: that resolves as a
script-class constant, and bare `Tuning` fails like the rest. Scripts loaded
at runtime (a scene's own `.gd`) reference autoloads by name quite happily;
the limit is only on the `-s` script itself.

**Wrap every test run in a wall-clock timeout.** A test awaiting something
that never fires hangs forever, and no GDScript harness bounds it. This
already burned 15 minutes on a test whose first assertion had failed. There
is no `timeout` binary here, so use Perl, and redirect rather than piping,
since a pipe hides the failing line:

    perl -e 'alarm 120; exec @ARGV' \
      godot --headless --path . -s test/foo.gd < /dev/null > out.txt

Check `FAILURES=` is PRESENT, not just zero: an absent line means the run
died, and that is not the same as passing.

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

Regions are `Zone` nodes (`scripts/zone.gd`, `class_name Zone extends Area3D`,
group `zone`), not radii from the origin. `island.gd` builds LAND, ASH, SHALLOW
and DEEP in the same pass as the discs they describe, so the two cannot drift apart, and
callers ask `Zone.is_inside(world, point, kind)` or `Zone.zone_at(world, point)`.
Membership is `Zone.contains`, answered from the zone's own numbers, so a
second island just adds its own zones and no maths changes. Zones sit alone on
layer 7 (`Zone.LAYER`), which is what a point query would use, but the query
is deliberately NOT a point query: an Area3D is invisible to
`intersect_point` until a physics frame has run, and the world is generated
and scattered inside `_ready`, before the first one. The old point-query
version silently reported "not in ash" for everything during scatter, so the
living-scenery rejection never actually ran. Keep membership arithmetic.

Physics shapes cannot express a ring or a wobbly edge, and a fan of boxes
approximating one is wrong by ~1cm at the seams, which is enough to move a
scattered tree across a boundary and reshuffle the whole seeded layout. So a
zone's shape is always a plain cylinder and anything subtler is arithmetic on
top: `hole_radius` for a ring, and `edge_noise` / `edge_radius_at` for the ash
blob's irregular edge. `island.gd` builds the ash mesh by calling
`edge_radius_at` itself, so the drawn edge and the queried edge are one curve
rather than two that have to be kept in step. Scatter places demons and dead
trees by rejection sampling in the bounding circle and asking the zone, which
keeps placement agreeing with both for free.

`_scatter`'s `SCATTER_CLEAR_RADIUS` and `ALTAR_CLEAR_RADIUS` checks stay radius
maths on purpose: they are clearings around a point, not regions of the map.

Endgame: player level 4 unlocks the Altar Key recipe at the workbench
(3 pelt + 3 cactus fruit + 3 demon horn). One stone altar stands at
`Tuning.ALTAR_POS`, at the centre of the scorched blob; R (action `interact`, gamepad
D-pad up) with a key summons the Mushroom King (`scenes/pal_boss.tscn`),
one alive at a time. The fight darkens the world, gives every pal a glow
light, and loops procedural music; `scripts/altar.gd` restores all of it
when the boss is caught or dies. Catching it is the win condition.

HUD layout: level and XP bar bottom-left, active pal bottom-right, carried
items as an icon list in the top-left under the health bar
(`scripts/hud.gd` `_refresh_items`, icons in `ui/icons/*.svg` mapped by
`Tuning.ITEM_ICONS`). Everything used to be one concatenated label on the
bottom bar, which grew sideways with each new drop. Rows are built once and
reused because `Inventory.changed` fires on every punch.

Trees and rocks are gatherable (`scripts/resource_node.gd`, groups
`tree`/`rock`/`resource_node`): punch (F) yields wood/stone, deplete after
`Tuning.GATHER_HITS`, respawn in place.

The active pal works them too. `State.GATHER` is entered from `_tick_follow`
just after the defend check, so a hostile or a walk-off always wins; species
are mapped to a group by `Tuning.PAL_GATHER_GROUPS` (Cactoro to `tree`,
Wolf to `rock`, nobody else). The pal picks the nearest available node within
`PAL_GATHER_RADIUS` of the PLAYER, not of itself, which is what keeps the
search area moving with them, and `PAL_GATHER_LEASH` (= `FOLLOWER_LEASH`)
breaks the job off. Each bite is `resource_node.punch()`, so depletion,
respawn and yield are the shipped ones. Only depletion flashes a message:
the HUD item panel already counts the trickle, and `Hud.flash` queues, so
one message per item would bury it. Cactoro lost its passive `gather` buff
in the swap, leaving Glimmerfin the only species that has one.
`test/auto_gather_test.gd` covers all of it.

The workbench (B nearby) crafts pal
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
is safe. Out in the shallows none of those four is land, so a mount off the
land tries straight back towards the island first (`_beach_dismount_position`)
and the rider always ends up ashore. Death dismounts with `force`, which
accepts an unsafe spot rather than trapping the player on a corpse.

## Screens, HUD and species art

`scenes/start_screen.tscn` is the main scene; Play swaps in `world.tscn`. Its
backdrop is a small 3D set of its own, not the real world, which loads in
roughly 216 ms against world.tscn's 276 ms. The title reads
`application/config/name` at runtime, so renaming the game is one edit in
`project.godot`. The `Hud` autoload exists before any world does and draws
over the title, so the start screen hides it and restores it in `_exit_tree`.

`Hud.flash` queues rather than overwrites. Ten callers share one label, and
catching a pal fires the catch, the XP and sometimes a level in the same
frame, so the catch used to be gone before it could be read. Queued messages
get `MESSAGE_QUEUED_TIME` rather than the full `MESSAGE_TIME`.

Cubes read in the bottom bar, not the carried-items panel: they are
ammunition rather than a material. `CORE_ITEMS` in `hud.gd` is the list that
always shows; anything else appears once you hold one. Icons come from
`Tuning.ITEM_ICONS`, and a missing entry renders nothing rather than erroring,
so add the path when you add a drop.

`Pal.model_scale` exists because the kit models are not authored to one size:
the fish stands twice as tall as the dog. Level growth multiplies it rather
than replacing it, which is what `pal.gd` used to do, wiping any scale set in
the scene and leaving a rideable fish the player sat inside.

## The shallows

A gated two-step loop: catch a Mudwader on the beach, ride it into the water,
cube a Glimmerfin out there. Both species set `swimmer = true` on `Pal`; the
fish also sets `water_only`.

The gate is arithmetic, not a rule. A cube is aimed `CUBE_AIM_DISTANCE` (30)
from the camera and a walker stops at `SHORE_WALL_RADIUS` (114), so the
furthest a throw from shore reaches is 144. `FISH_RING_MIN` is 148, and
`_clamp_to_fish_ring` holds wandering fish inside 148..179 as well, so no fish
is ever reachable on foot. `test/water_test.gd` asserts
`FISH_RING_MIN - SHORE_WALL_RADIUS > CUBE_AIM_DISTANCE`, because retuning any
one of the three would otherwise reopen the gate silently.

Two walls, both segmented rings from `_wall_ring`. The shore wall's shapes are
disabled while a `swimmer` is ridden (`player.gd _set_shore_wall_enabled`) and
restored on dismount; the shallow wall at `SHALLOW_WALL_RADIUS` (184) is always
on and stops everyone. A segmented ring leaks between segments, so
`water_bounds_test.gd` drives at the gap on both.

The ground stays one `WorldBoundaryShape3D` at y=0, so the shallows are walked
on at grass height and only look submerged. Depth is faked by dropping the
model and not the collider: `Pal.sink_model`, called with `SWIM_SINK` while
riding off the land and with `FISH_SINK` once in `_ready` for a fish. Without
the fish sink they float clear of the water, which the screenshots caught and
inspection did not.

The Glub rig is a flyer with no `Walk` or `Idle` at all, so a fish asked to
walk stands frozen. `Pal.SWIM_CLIPS` maps Walk/Run/Idle onto
`Fast_Flying`/`Flying_Idle`, which read as swimming.

Feedback the player's own body gives: every swing of `punch` plays
`Bite_Front` for `BITE_ANIM_TIME` (the cat rig has no `Punch` clip) and a
swing that reaches nothing still plays a `whiff` tone, so the most pressed
button in the game always moves something. `_animate` yields while
`_bite_left` is running or Walk would stomp the swing on the next frame.
A cube that lands on nothing bursts and plays `cube_miss` before freeing,
rather than blinking out: it cost wood and stone.

A cube catches on a near miss, not just a direct hit. Two places, because
a lob rarely arrives dead on: the flight sweep is a sphere of
`CUBE_HIT_RADIUS` rather than a ray, and a cube reaching the ground grabs
the nearest pal within `CUBE_LANDING_GRAB` before counting as a miss. The
sweep uses `cast_motion` for the fraction of travel, then a shape query at
that point for what was touched, since `cast_motion` reports only when.

Player health: `player.gd` has `hp` and `damage(amount, from_position)`,
regen after a no-hit delay, and death -> respawn at the origin spawn with
inventory and party kept and all pal aggro cleared. HUD shows a bar top-left.

Pals fight back: punching one puts it in `State.ATTACK` (chase + hit on a
cooldown) for `PAL_AGGRO_TIME`. If it cannot land a hit for
`PAL_NO_HIT_GIVE_UP_TIME`, it gives up; a successful `Player.damage()` or
another player hit on the pal resets that timer. A caught pal never attacks
the player.

Temperament is one exported enum on `Pal`, not a pair of flags, so
"aggressive and skittish" cannot be written down. `SKITTISH` (Wolf, Cactoro)
flees inside `PAL_FLEE_DISTANCE`; `NEUTRAL` (Mudwader, Glimmerfin) neither
flees nor starts anything but hits back when bitten; `AGGRESSIVE` (Demon,
boss) attacks on sight inside `PAL_AGGRO_RADIUS` and, after giving up, waits
for the player to leave and re-enter that radius before reacquiring. Reads
across `pal.gd` go through the `aggressive` property, which is the enum by
another name. `_threat_near` is the single gate on fleeing.

An aggressive wild pal also brawls with other species. `_pick_rival` scans
on `RIVAL_SCAN_INTERVAL`, staggered per pal by instance id so thirty of them
never scan on one frame, and a rival is anything wild, alive, out, and of a
different `display_name`. The player always outranks a rival:
`_tick_attack` drops the brawl the frame `_wants_attack` turns true. Wild
fights maim and never kill, clamped at `RIVAL_MIN_TARGET_HP` for the same
reason `take_follower_hit` clamps: a world that culled its own pals would be
empty by the time the player walked out to it, and a softened loser is a
gift. A maimed pal stops being a valid rival, which is what stops a winner
and a spent loser locking each other up; `RIVAL_FIGHT_TIME` is the backstop.
`test/species_fight_test.gd` covers all of it, temperament included.

Species jobs, one each, so choosing which pal is out matters: Cactoro chops
trees, Wolf fetches stone and adds speed, Mudwader is the only way into
water, Glimmerfin adds gather, Demon adds punch damage
(`buff_kind = &"damage"`, capped at `DEMON_DAMAGE_BUFF_CAP` so no catch
becomes a one-hit kill), and the Mushroom King makes throws free
(`Party.infinite_cubes()`, checked in `_begin_throw_aim` and `_throw_cube`;
the HUD shows `INFINITE_CUBE_TEXT` rather than a stock count that would read
as a broken zero). `test/pal_skills_test.gd` covers the last two.

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
