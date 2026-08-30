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

Current direction: the loop is complete and the game ships to
https://lukew-cogapp.github.io/mini-pals/ on a `v*` tag. What is left is
feel, which only playing settles, and nobody has opened the live build.

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
assets/platformer/         Quaternius CC0 pack, the cube and pickups
addons/gut/                vendored test framework, do not restyle
test/*_test.gd             GUT suites; run them with test/run.sh
```

Two conventions the owner asked for, worth keeping:

- **Numbers live in `tuning.gd`.** Playtesting means editing one file, and
  GDScript hot-reloads, so values can change while the game runs.
- **Models are their own scenes.** `player.tscn` instances
  `models/player_model.tscn` rather than embedding meshes, so swapping in a
  real `.glb` touches one file.

The player-facing wiki is the sibling repo `../godot-world-wiki`, an Astro
Starlight site. Its numbers are copied out of `tuning.gd`, so retuning a
species, a recipe or a binding here leaves it lying until someone edits both.
Species pages live in `src/content/docs/pals/` and a new one has to be added
to the sidebar in `astro.config.mjs` as well, or nothing links to it.

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
`test/run.sh orientation_test.gd` asserts camera placement, turn maths for
all four inputs, throw direction, and punch facing.
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

**Additive emission drowns albedo on a big flat surface.** `emission_operator`
defaults to ADD, which lays the emission colour over the albedo rather than
masking it, and the ash rendered as a snowfield. It now uses MULTIPLY with a
crack-shaped emission texture, so the glow is confined to the cracks. See the
comments in `ash.tres` before touching the energy.

**`ground.tres` is triplanar, and that is what keeps the hills and the flat
ground tiling alike.** A hill is SurfaceTool with world-unit UVs, so a 30 m
mound spans UV 0..30; the island disc is a CylinderMesh, whose UVs are
normalised 0..1 across the whole primitive, so 220 m of island spanned a
quarter of a tile and read as flat colour beside a visibly mottled hill. `uv1_triplanar` projects by world position and fixes the
disc, the beach and the shallows together. Anything else built from a
primitive and given this material inherits the fix; anything given a new
material needs the same flag.

**Ground `uv1_scale` is world-units-per-tile, and both extremes read as flat.**
UVs are set in world units, so 60 tiled sixty times per metre (sub-pixel, and
the original bug) and 0.018 tiled once per 55 m (one smear). Judge it from
`08_world` and `22_biome_ground`, not from the number: the values live in the
`.tres` files and drift.

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

**GUT needs an import before it will run.** A fresh checkout fails with
`Some GUT class_names have not been imported`, naming `GutTest` and friends,
because the addon's `class_name` registrations live in `.godot/`, which is
gitignored. `godot --headless --path . --import` once fixes it. CI does this
already; a person cloning the repo has to.

**Hot reload:** `.gd` yes, `.tscn` no. F8 stop, F5 play.

**A `-s` script cannot name an autoload at all.** Naming `Inventory`, `Party`
or `Hud` fails at compile time with `Identifier not found`, before any code
runs, so awaiting a frame first does NOT help: the script never compiles.
Resolve them at runtime instead, with `get_root().get_node("Inventory")`.
`Tuning.SOME_CONST` looks like an exception but is not: that resolves as a
script-class constant, and bare `Tuning` fails like the rest. Scripts loaded
at runtime (a scene's own `.gd`) reference autoloads by name quite happily;
the limit is only on the `-s` script itself.

This no longer constrains the tests, which are all GUT now and load at
runtime, so they name `Inventory`, `Party`, `Hud` and `Tuning` directly. It
still constrains `screenshot.gd` and the other `-s` tools.

**GUT is the harness**, 9.7.1 vendored at `addons/gut`, no editor plugin
needed. **Run tests only through `test/run.sh`**, and read its header before
changing it: the flags that must not move, the wall-clock timeout, the
summary-line check and the guard against a suite that is not `extends
GutTest` all live there, enforced rather than merely written down. A suite
that lacks that line is skipped and the run still exits 0, which is why the
guard exists; watch the script count in the summary for the same reason.

Two things `run.sh` cannot enforce for you:

`add_child_autofree` frees at the end of the *test* that called it, not the
script, so a `before_all` fixture needs an explicit `after_all` calling
`free`. Not `queue_free`, which has not run when GUT counts unfreed children.

Its log path is not worktree-scoped, so two agents running it at once clobber
each other's results, and one has already read another's as its own. Set an
isolated `TMPDIR` when anything else might be running.

`screenshot.gd`, `start_shot.gd`, `prompt_shot.gd`, `cave_shots.gd` and
`compile_check.gd` stay `extends SceneTree`. They are renderers and tools, not
tests, and the `_test.gd` suffix filter leaves them alone.

**A pal drives itself; do not tick it by hand as well.** `_physics_process`
runs the state machine and calls `move_and_slide()` every physics frame, so a
test that also calls `_tick_follow` and `move_and_slide` steps the pal twice
and every measured speed reads double. `test/species_speed_test.gd` parks a
pal in `State.IDLE` when it wants to drive it (idle zeroes the velocity and
slides nowhere) and otherwise lets the pal drive itself.

**Area3D needs its mask to match the target's layer.** Pals sit on layer 4, so
the pal cube needs `collision_mask = 4`; the default mask of 1 silently
detects nothing. No error, the cube just sails through. Spit is aimed at
either a pal or the player, so it masks 5.

**An Area3D can land its hit more than once.** `queue_free` is deferred, so a
projectile that decides it has arrived is still in the tree, still monitoring,
for the frames until it actually leaves; `body_entered` and a per-frame sweep
can also both see the same target on one frame. One wad billed its target
three times this way, and the test read as a damage-tuning failure rather than
a lifecycle one. Guard the arrival function itself, not only its callers, and
`set_deferred("monitoring", false)` on the way out.

**A Quaternius model samples a handful of atlas texels, not a region.** The
Alpaking's 1339 vertices all land on five texels of ONE row: `(0..4, 22)` of
`Alpaking_Atlas_Monsters.png`. Every other row belongs to other monsters and
recolouring it does nothing visible, which is how the cat's body got greyed
once. `scripts/tools/inspect_atlas.py GLTF` decodes the embedded image and the
UVs and prints exactly which texels are read, with vertex counts;
`scripts/tools/paint_atlas.py IN OUT x,y=rrggbb` then paints only those.
Run the first before the second, always.

Five texels is also why a rainbow does not work on these models. They are not
five bands down the body: they are the body, the ears, the muzzle and the
eyes, so five hues render as a red animal with mint ears. Tried, rendered,
looked at, dropped. Pink is one hue family across the four non-eye texels and
reads correctly.

**Two CharacterBody3Ds cannot occupy each other.** Riding puts the player
inside the mount, and the mount's `move_and_slide` then jams against the rider:
the tell is `get_slide_collision_count()` pegged at `max_slides` every frame
while `velocity` looks correct and position never changes. Disable the rider's
collider while mounted.

**A Seat goes on the posed skeleton, not on any mesh measurement.** A Seat is a
Marker3D with no visual, so a wrong one looks correct in the scene file and in
every number the engine reports. Two measurements were tried here and both gave
confident wrong answers: a `MeshInstance3D` AABB is the BIND pose and reads
about half a metre taller than the Alpaking stands, and a sweep over every
`MeshInstance3D` under a pal picks up the five billboarded health-bar quads and
reports the HUD as the animal's surface. `get_bone_global_pose` is neither.
`test/seat_probe.gd` prints every bone in the frame a Seat is written in
(Model-local, which `model_scale` shrinks), and `test/seat_test.gd` asserts a
seat sits above the Torso bone and behind the Head. The Llama sat the player on
its skull and the Mudwader's rider floated 2.3 m up before this.

The Alpaking is worth one warning of its own: it is a winged blob, 13 bones,
no legs and no tail, and its mesh AABB is WIDER on X (4.3) than long on Z
(2.2). Nothing about that says which way it faces. Its Head bone is at
Model-local z -0.08 and its Torso at +0.59, so it faces -Z like everything
else, and a rider belongs at a larger z than the head. `test/seat_shot.gd`
renders all three mounts from the side, above and in front, empty and ridden
(shots 50 to 61), with a green post one metre forward and a white one metre
back so no shot has to be reasoned about.

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
`Tuning.ITEM_ICONS`). The top right is one column: minimap in the corner,
objectives list below it. Everything used to be one concatenated label on the
bottom bar, which grew sideways with each new drop. Rows are built once and
reused because `Inventory.changed` fires on every punch.

Objectives (`_refresh_objectives`) are derived from live state, never stored:
catch pals, reach `KEY_UNLOCK_LEVEL`, gather each `KEY_RECIPE` drop, craft the
key, summon at the altar, catch the King. Only the current objective and
`OBJECTIVE_DONE_ROWS` finished ones above it are drawn, and the window ENDS at
the current one so nothing further down the chain is spoiled. The chain is
forced monotonic after evaluation: crafting spends the key materials, which
would otherwise un-tick those rows and walk the panel backwards. The text is
content and lives in `hud.gd` beside the condition it describes, not in
`tuning.gd`.

The minimap (`scripts/minimap.gd`) is plain `_draw` on a Control: no viewport,
no second camera. It is NORTH-UP so the island keeps one shape, with a wedge
carrying the heading. Terrain colours come from `Zone.is_inside`, so the ash
blob's noisy edge is the world's own curve rather than a second copy. Fog of
war is a boolean grid (`FOG_CELL_SIZE` metres per cell) revealed within
`FOG_REVEAL_RADIUS` of the player and never re-hidden; terrain, the altar
marker and pals all gate on the same `is_revealed`, so nothing leaks through
by being drawn a different way. Fresh fog each run, deliberately: there is no
save system. M (action `minimap`, gamepad Back) toggles the map only;
the objectives stay. `test/minimap_test.gd` asserts the heading against
`facing()` and the sign of a world offset on screen, because a mirrored map
looks perfectly correct in a screenshot.

Note `Party.members` and the `pal` group can both hold a freed pal when
`changed` fires: `Party.store` calls `queue_free` on a duplicate species and
emits in the same breath. Anything walking either list on that signal needs
`is_instance_valid`.

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

Aiming and firing are separate. Holding right mouse (action `aim`, left
trigger) raises the reticule for free and releasing it cancels, so catch odds
can be read without spending a cube; Q throws while it is held and the aim
survives the throw, for a follow-up after a miss. Holding Q alone still aims
and throws on release, the flow that shipped first, and `_aim_held` is what
tells the release handler which of the two it is in. Aiming with an empty
pouch is allowed: looking is free, and the throw itself says why nothing
flew. `test/aim_test.gd` covers all of it.

The reticule shows the locked pal's name and catch %. `_current_throw_aim`
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
roughly measurably faster than world.tscn. The title reads
`application/config/name` at runtime, so renaming the game is one edit in
`project.godot`. The `Hud` autoload exists before any world does and draws
over the title, so the start screen hides it and restores it in `_exit_tree`.

Contextual key prompts (`hud.gd` `_prompt_text`, panel `PromptPanel`) name the
key for whatever the player is standing next to, one line, centre-bottom above
the message label. Exactly one shows: the checks run in priority order and the
first hit wins, altar > workbench > rideable caught pal > gatherable node. The
altar and the bench are places you deliberately walked to and there is one of
each; a caught pal follows everywhere and would otherwise mask both; trees and
rocks are underfoot everywhere. A wild pal in cube range gets no prompt, since
the reticule already shows its name and catch odds. Ranges are the constants
the actions themselves check, so a prompt can never appear out of reach, and
the key text comes from `InputMap`, never a literal: bindings have moved once
already and a prompt naming a dead key is worse than no prompt.
`test/prompt_test.gd` rebinds `build` mid-test to prove that.

`scenes/start_screen.tscn` also carries a Debug button, styled small and dull
under Play, which starts the world and then calls `Party.debug_start_king()`.
That instances `pal_boss.tscn`, sets `caught` and puts it through the normal
`store()`, so the King follows, fights and gives infinite cubes exactly like a
real catch; it also raises the player to `DEBUG_START_PLAYER_LEVEL`, since the
bench's key recipe is gated on that level and the endgame cannot be tested
without it. `test/debug_start_test.gd` asserts a normal Play still starts with
an empty party, which is the regression that matters.

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
`_tick_attack` drops the brawl the frame `_wants_attack` turns true.

**Anything wild fights back when a pal hits it**, temperament regardless.
Retaliation sets `_rival` and enters ATTACK but touches neither `_aggro` nor
the flee gate, and `_wants_attack` is false for anything not aggressive, so a
retaliating wolf takes the `_tick_rival` branch and never turns on the player.
Once its rival is gone it flees them as before.

**Wild fights kill**, and respawning holds the population up.
`RIVAL_FIGHT_TIME` bounds only the case lethality does not reach: a chase that
never closes to `RIVAL_ATTACK_RANGE`. It does NOT bound a mutual brawl,
because each landed hit re-arms retaliation with a fresh timer. What ends a
brawl is one of them dying, roughly `max_hp * RIVAL_ATTACK_COOLDOWN` seconds.

Who a death pays is **participation, not the final blow**. Each pal carries a
`_credit` countdown, reset to `PAL_CREDIT_TIME` by `take_hit` (the player hit
it) and by a landed `_swing` (it hit the player), ticked down in
`_physics_process`. `_die` is one path with the drop, the XP and the HUD
message conditional on that window still being open, so a demon the player
softened and a wolf finished pays out, and two pals brawling across the
island while the player gathers wood pay nothing. `take_follower_hit` still
clamps at `FOLLOWER_MIN_TARGET_HP` so a follower cannot cost you the catch,
but a pal it left on 1 hp is killable by a rival like any other. Every path
that changes hp calls `_refresh_bar()` behind an `if _bar_back:`, and `_die`
hides the bar before either payout branch, so a corpse never floats one.
`test/species_fight_test.gd` covers all of it, temperament included.

The island refills itself (`scripts/scenery.gd`, `_process`). A roll every
`RESPAWN_INTERVAL_MIN..MAX` seconds spawns at most one pal, with odds equal
to the shortfall against `PAL_POPULATION` times `RESPAWN_URGENCY`, so a full
world respawns nothing and a gutted one nearly always does. Caught and dying
pals do not count. Species is rolled from whatever scenes are wired on the
Scenery node, and placement goes through `_pal_position`, the same function
the initial scatter uses, so a respawned demon lands on the ash and a
respawned fish in the shallow ring by construction rather than by a second
copy of the rules. Nothing lands inside `RESPAWN_CLEAR_RADIUS` of the player
or `SCATTER_CLEAR_RADIUS` of a tree or rock; the position is vetted before
anything joins the tree. `_respawn_rng` is randomized, NOT seeded from
`SCATTER_SEED`, so the refill differs run to run while the initial layout
stays identical. `test/respawn_test.gd` covers pacing and placement.

Species jobs, so choosing which pal is out matters: Cactoro chops trees, Wolf
fetches stone and adds speed, Mudwader adds speed and is the only way into
water, Glimmerfin adds gather, Grottolo adds stone and is `cave_only` so the
cave is worth finding, Llama fattens every drop, Demon adds punch damage
(`buff_kind = &"damage"`, capped at `DEMON_DAMAGE_BUFF_CAP` so no catch
becomes a one-hit kill), and the Mushroom King makes throws free
(`Party.infinite_cubes()`, checked in `_begin_throw_aim` and `_throw_cube`;
the HUD shows `INFINITE_CUBE_TEXT` rather than a stock count that would read
as a broken zero). `test/pal_skills_test.gd` covers the last two.

Middle click or T (action `pal_attack`, pad button 5) sends the active pal at
whatever the reticule is over. The target comes from `_current_throw_aim`,
the same raycast the throw uses, since `locked_pal` only exists while the
throw key is held. `Pal.command_attack` reuses `State.DEFEND` rather than
adding a state, so the chase, the swing and the `take_follower_hit` clamp are
all the shipped ones and a commanded pal still cannot land the kill.
`_command_time` is what makes it an order: while it runs `_defend_target` is
the commanded one and `_find_defend_target` is not consulted, so a nearer
hostile cannot steal the pal off its job. It ends on the target dying or
being caught, the player passing `FOLLOWER_LEASH`, or `COMMAND_TIME`.
`COMMAND_RANGE` (14) is measured from the player and sits inside
`FOLLOWER_LEASH` (16), so a command the pal would abandon at the leash is
refused with a message instead; the reticule reaches 30 m, which is the trap
that constraint exists for. Every refusal flashes why. `test/pal_command_test.gd`
covers it and asserts the range against the leash arithmetically.

Left click also bites, alongside F and pad Y. Left click was removed from
`throw` because `player.gd` recaptures the mouse on any click, so clicking
back in after Escape spent a cube; with three mouse buttons now in gameplay
actions that branch sits ABOVE them all in `_unhandled_input`. It gates on
`player._mouse_free` rather than reading `Input.mouse_mode` back, which is
not settable under the headless renderer and reads VISIBLE forever there.
`test/input_map_test.gd` asserts the branch order and every action's event
count, since a bad hand-edit to `[input]` has taken the whole map out before.

## The Llama, and ranged attacks

The Llama (`scenes/pal_llama.tscn`, a pink-recoloured Alpaking) is the first
species that attacks at range, and `scripts/spit.gd` is the game's first
projectile weapon. It scatters in `LLAMA_BAND` (0.62 to 0.9 of the island
radius), on the grass between the starting ring and the sand, with the ash
rejected by `scenery.gd` `_on_grass`. Its job is `buff_kind = &"drop"`: every
catch and kill pays more while it is out, read in `Pal._grant_drop`.

One export makes a species ranged. `Pal.ranged` plus a `spit_scene`, and
`Pal.attack_range(melee)` returns `SPIT_RANGE` instead of whatever the caller
passed. All three combat ticks ask it rather than reading their own constant,
so wild-on-player, follower-on-hostile and rival-on-rival all become ranged
together and none of them can be forgotten. A `ranged` species with no
`spit_scene` falls back to melee rather than standing uselessly out of reach.

**A wad carries no damage number.** It carries a `Spit.Mode` and calls exactly
the function the melee swing at that target would have called:
`Player.damage`, `Pal.take_follower_hit`, `Pal.take_rival_hit`. This is
what keeps the catch loop intact: `take_follower_hit` clamps at
`FOLLOWER_MIN_TARGET_HP` so a follower can never land the kill and cost the
player a catch, and a ranged attack that did its own arithmetic would be a way
straight round that clamp. `test/llama_test.gd` drives thirty volleys from a
spitting follower and asserts the target lands on exactly
`FOLLOWER_MIN_TARGET_HP`, and separately that a RIVAL wad still kills, so the
two modes cannot be collapsed into one.

The wad leads a moving target by `SPIT_LEAD_FACTOR` (0.7) of a perfect
solution and then steers no further. Full lead is hitscan with a delay and no
lead is free to walk out of; at 0.7 a target holding its line is hit and one
that turns is missed. Damage is below the melee it replaces and the cooldown
above it, because a spitter never enters reach.

**Riding a llama turns the player's attack into a spit.** `player.gd _punch`
branches on `mount.can_spit()`, the MOUNT's own ability, never on a species
name: the Wolf and the Mudwader are rideable too and must keep biting from the
saddle, and a branch reading `if mount:` breaks both while still firing no
projectile, so it fails silently rather than loudly. `test/llama_test.gd`
guards it from the wolf side, which is the direction the mistake goes.

The mounted wad aims along the CAMERA's flattened heading, not the mount's
nose, since the player aims with the camera everywhere else in this game. It
carries `Spit.Mode.RIDER` and lands on `Pal.take_hit`, so a kill from the
saddle pays the drop, the XP and the knockback exactly as a punch does.
`RIDER_SPIT_COOLDOWN` (0.7 s, on the player, not the mount) is the balance
lever: a fast mount plus an unlimited ranged attack outranges everything
alive.

The Llama stays NEUTRAL, so nothing about the spit gives it a reason to open
fire. It cannot: `_wants_attack` is false for anything not aggressive, and
only `take_hit` sets `_aggro`. Both halves are asserted, because "it never
spits" and "it never spits unprovoked" look identical from a passing test that
only checks the first.

`test/llama_shot.gd` renders shots 40 to 44 (windowed, like every other
renderer here).

A following pal does fight for you. In `State.DEFEND` it picks the nearest
hostile (one in `State.ATTACK`, or an aggressive species within
`PAL_AGGRO_RADIUS` of the player) inside `FOLLOWER_DEFEND_RADIUS` and hits it
through `take_follower_hit`, which clamps hp at `FOLLOWER_MIN_TARGET_HP` so a
follower can never land the kill and cost you the catch. It drops back to
FOLLOW when the target dies, is caught, calms down, or the player passes
`FOLLOWER_LEASH` away. `test/pal_combat_test.gd` covers all of it.

Each species has its own pace. `Pal.speed_factor` multiplies every shared
speed constant through `Pal.speed()`, the way `model_scale` multiplies size,
so wander, flee, chase, gather and follow all scale together and the
relationship between them still lives in `tuning.gd`. Clamped to
`PAL_SPEED_FACTOR_MIN`..`MAX`.

The player is the reference: `PLAYER_SPEED` 5.0 and `PLAYER_RUN_SPEED` 9.0.
Cactoro 0.6 and Mudwader 0.7 are caught by a walking player; Glimmerfin 1.15,
Boss 1.3, Wolf 1.35 and Demon 1.55 are not, and none of them outruns a sprint,
deliberately: a fight with no exit is not a fight. Two interactions matter
here, and both have tests. A chasing pal below the player's WALK lands
no hit for `PAL_NO_HIT_GIVE_UP_TIME` and quits, which is why the boss is 1.3
and not lower. And a follower must never lose ground to a sprint, so the
catch-up end of the follow ramp keeps `FOLLOW_CATCHUP_FLOOR` whatever the
factor does to it; without that a Cactoro drifts past `FOLLOWER_LEASH`.
Riding never goes through `speed()`: `player.gd` drives the mount at
`RIDE_SPEED` directly, so a slow Mudwader is still a fast boat.
`test/species_speed_test.gd` asserts ground actually covered, not the
constants.

Pals unstick themselves. `_move_towards` in `pal.gd` compares ground covered
against the speed the state asked for; below `PAL_STUCK_SPEED_FRACTION` of it
for `PAL_STUCK_TIME` the pal turns sharply off the blocked heading and runs
for `PAL_STUCK_ESCAPE_TIME` before resuming. The state itself is untouched, so
a fleeing pal is still fleeing when it comes out. `_tick_follow` steers itself
rather than calling `_move_towards`, so it opts in by hand, and only while the
gap exceeds `FOLLOW_SLOW_RADIUS`: a follower jostling against the player it
has already reached moves nowhere every frame and is not stuck.
`get_slide_collision_count()` was the other candidate and is wrong for this,
since a pal walking cleanly along a trunk collides every frame while making
fine progress. `test/pal_stuck_test.gd` covers both directions.

Wild pals show a floating health bar above the name label within
`PAL_HEALTH_BAR_DISTANCE` **and inside the camera's facing cone**
(`PAL_HEALTH_BAR_FACING_DOT`, a dot against the CameraPivot's flattened
-basis.z), sampled every `PAL_HEALTH_BAR_CHECK_INTERVAL` rather than per
frame. Distance alone put a bar over every pal in an 18 m circle, which with
twenty of them on screen is a field of floating UI. The pal the aim reticule
has locked (`player.locked_pal`, published by `_update_throw_aim`) shows its
bar regardless of the cone, since that is by definition what is being aimed
at. Name labels are NOT gated on facing and never have been; only the bar is.

The bar is five billboarded quads built once in `_ready` and rescaled; the
construction is commented beside the code. Two traps, because both looked
correct until the screenshot: **a billboard is vertex work in the material and
does not touch the node basis**, so a child-node offset stays in world space
and swings out of the bar as the camera moves (every quad is a sibling at one
origin, shifted inside its own mesh with `QuadMesh.center_offset`), and
**`billboard_keep_scale` is required** or every bar renders as a 1 m square
whatever it was scaled to. `test/health_bar_shots.gd` renders it against grass
and ash at three health levels, which is the only way to judge it.

Feedback added in the second juice pass, all constants in one `tuning.gd`
block: a death poof and a grow-in on respawn (`Pal.poof`, `Pal.grow_in`;
the initial scatter opts out, the respawn trickle opts in), an eased sink and
a splash on the land-to-water edge of a ride (one bool, `_was_wading`, so
wading on stays silent), a sting and a message on entering the ash (`_tick_ash`,
polled on `PROMPT_POLL_INTERVAL`, edge-triggered on `_was_in_ash`), knockback
on `take_rival_hit` at `RIVAL_HIT_IMPULSE_FACTOR` of a player punch, a
level-up chime, a punch shake scaled by damage dealt, and a brighter gather
chime while the Glimmerfin buff is up. `Audio.played` is a short ring of cue
names kept only so headless tests can assert a sound fired.
`test/juice2_test.gd` covers all of it; `test/bar_shot.gd` renders shots 31 to
33 for the facing gate.

`take_follower_hit` deliberately still has NO knockback: it keeps a softened
target inside cube range, and `juice2_test` guards that so the rival change
cannot creep into it.

## Assertions that pass while the thing is broken

Four times today a fix shipped green and the bug was still visible on screen.
Every one was the assertion measuring the wrong thing, not the fix being
wrong, so these are worth carrying to any new check.

**An origin is not a footprint.** The cave boulders sat exactly on
`height_at` at their own origin and still floated: the glTF's visual bottom is
5 cm below its origin while the mesh spans 4 to 7 m, and on a 0.72-per-metre
slope the downhill edge hangs 3 to 5 m clear. Assert the extent, on a grid
across the face, not a point. A corner check missed a roof showing through by
half a metre while reporting 6.6 m of cover.

**Frame the check where the player stands, not where the feature is.** A shot
taken at the cave mouth passed twice while the structure was plainly broken
from open grass 30 m away. `test/cave_shots.gd` orbits eight compass points at
eye height for that reason; read several, because one angle lies.

**Write the assertion first and watch it fail.** An assertion written after
the fix proves the fix ran, not that it works. The cave was "fixed" twice
before anyone did this.

**A collider is not a mesh.** `backface_collision` on the trimesh made physics
two-sided while the material stayed single-sided, so the player stood on a
hill they could see through. Anything carved has to be carved in both.

## The cave

A box chamber buried in one hill, mouth cut out of the flank. The constraints
below are all load-bearing; each was rediscovered the hard way.

**The geometry does not fit by itself, and cannot be made to.** The chamber
needs `CAVE_HEIGHT + CAVE_WALL` of hill above its floor plus cover, and a
raised-cosine dome does not climb that fast over `CAVE_DEPTH`. Growing the
hill does not help: the floor is pinned to the hill surface at the mouth, so
a taller hill raises the mouth and the whole chamber with it. What resolves it
is `CAVE_SINK`, which drops the floor below the mouth's grade so the roof is
buried instead of standing proud.

`CAVE_SINK` is bounded on **both** sides and the upper bound is the one that
bites. Sink far enough and the roof goes under the hill surface at the mouth
too, and then there is no opening at all: a hill with no cave in it. At the
shipped 5 the roof still clears the doorway's grass, and the floor comes out
level with the ground `CAVE_RAMP` metres out, which is what lets the approach
be a level cutting with no step at either end. The walk-in is a level cutting, not a tilted ramp.

**The mouth and the roof are the same surface.** A cave you can see into
necessarily breaks the grass at the opening, so the burial assertion exempts
the first `CAVE_APRON` metres and the sightline assertion exempts eyes inside
`CAVE_SIGHT_MOUTH_DOT` of straight ahead. Everything else must be buried.

**The hill mesh AND its collider are both carved** (`_carve_mesh`,
`_hill_shape`, sharing `_inside_cave`). A solid hill collider walls the buried
chamber off; a capsule at floor height hits `HillBody` before it reaches the
back. And once the hill material is two-sided the mesh has to lose the same
triangles, or the doorway is covered by hillside the player walks through. The
carve must cover the approach cutting as well (negative `along`), or the
walk-in is sealed by ground you can see straight through. Do NOT add margin
across: widening there drops hill triangles beside the doorway under intact
visible grass, and the player falls through it.

**The hill material is `CULL_DISABLED`, matching `backface_collision` on its
shape.** This one was upstream of everything else and cost the most time. The
winding is correct (measured: 736 of 768 triangles face up, the rest are
degenerate slivers at the apex), so this is not a fix for an inverted dome. It
is needed because the cave puts the player inside the hill, and a single-sided
dome seen from within disappears. While it was single-sided the dome simply
vanished over the cave and that hole read as the mouth by accident, which is
why the chamber appeared to float in mid-air, why the roof looked like a slab
lying on the grass from overhead, and why two rounds of moving boulders up and
down changed nothing. If geometry near the hill looks like it is floating,
check that you are not seeing through the hill before touching the geometry.

**Buried slabs must not cast shadows.** They sit metres inside the hill and
nothing draws them, but their shadow lands on the hillside above and reads as
a flat grey rectangle lying on the grass. A shadow with nothing attached to it
always reads as broken, and this is what kept showing from open ground after
the geometry was already correct.

**Mouth boulders are bedded from their own measured AABB**, never from a
nominal model height times its scale: the rock scene's origin is not at its
base. Two bounds meet here and they cannot both be met by moving the rock.
`terrain_test.gd` bounds a decoration's ORIGIN against the ground under the
origin; `cave_test.gd` bounds its visible UNDERSIDE against the ground under
the footprint. On a slope, burying a wide rock's lowest corner drives its
origin metres down and trips the first. So `_bed_boulder` satisfies the origin
rule (sampling ground under the origin, exactly as the shared assertion does)
and `CAVE_ROCK_SCALE_MAX` holds the other by keeping rocks too small to
overhang far. `CAVE_ROCK_FLOAT_TOLERANCE` is not zero on purpose: `height_at`
is the ideal dome and the drawn hill is a 32-by-12 approximation that sags
below it between ring vertices.

`test/cave_test.gd` measures all of it and `test/cave_shots.gd` orbits it from
eight compass points at 34 m plus one overhead. Two lessons are baked into the
test. Both are the general lessons in "Assertions that pass while the thing is
broken" above, learned here first. One cave-specific trap: skipping every
`StaticBody3D` in the burial check excluded all nine boulders while reporting
green, so filter on the `*Body` suffix the slabs' own bodies carry.

Every bug this project has hit was invisible on inspection and only showed up
in a headless test: a cube flying over the target's head, a mount jammed at
max_slides, a model facing backwards, a collision mask that matched nothing.
Write the check, run it, read the numbers. Do not reason about whether it works.

The owner can see the game and I cannot. I can verify a scene loads, spawns the
right node count, and runs without errors; I cannot tell whether the jump feels
good or the camera sits too close. Ask, rather than claiming it plays well.
