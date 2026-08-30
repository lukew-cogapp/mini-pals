# Tasks

Kept current as work lands. Newest changes at the top of each section.

## Next

- [ ] Wings for the cat dragon: PrismMesh slabs read as flat blades stuck
      through the body. Needs a real wing mesh, not a primitive

- [ ] Verify the agent-built crafting system myself, gather/craft/menu untested
- [ ] Adopt **GUT** for tests (researched, recommended over GdUnit4)
      `godot --headless -d -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
      First tests: facing maths, step-up over rock vs tree, inventory/crafting
- [ ] Seed `pal_cube.gd`'s `randf()` via an injected RNG so catches are testable
- [ ] On-screen controls hint, the list has grown past guessing

## Done

- [x] Rename spheres to **pal cubes**: box mesh, scene/script/vars renamed

- [x] Resource HUD along the bottom: wood, stone, cubes
- [x] Fix facing for real: models face +Z, so `atan2(x, z)`, verified by
      screenshot from ahead of travel
- [x] Sunset lighting: warm low sun, orange horizon, light fog
- [x] Screenshot harness `test/screenshot.gd`, 9 angles including walk and jump
- [x] Revert the wrong 180 degree model flip, models were already correct
- [x] Blue cat: recoloured atlas via `scripts/tools/recolour_texture.py`, wings
      left purple
- [x] Confirm facing convention: Quaternius heads point +Z, Godot forward is -Z,
      so the 180 degree model flip is correct (measured, not assumed)
- [x] Flip Quaternius models, cat and wolf
- [x] Cat dragon player: Cat body, wings, walk/idle animation
- [x] Xbox pad bindings on all ten actions
- [x] Camera FOV 60, window 1600x900 maximised
- [x] Gathering, inventory, workbench, build menu (agent-built)
- [x] Wolf pal: wander, flee, catch, follow, ride
- [x] Collision on trees and rocks, step over rocks, trees block
- [x] Quaternius Ultimate Monsters, 50 rigged CC0 creatures
- [x] Ground texture and 160 seeded trees/rocks for motion cues
- [x] Fix player facing backwards, `atan2(-x, -z)`
- [x] Godot 4.7 scaffold, third-person controller

## Ride improvements (researched, not applied)

Works as is. Research says these are the idiomatic upgrades:

- [ ] `reparent()` rider to the Seat marker instead of per-frame `global_position`
- [ ] Invert control: pal drives its own `move_and_slide()`, rider feeds input
- [ ] `set_deferred("disabled", ...)` on the rider collider
- [ ] Enable `physics/common/physics_interpolation`, reset on mount/dismount
- [ ] Shape-test dismount spots, refuse when all blocked

## Step-up improvements (researched, not applied)

- [ ] Move step-up BEFORE `move_and_slide()`, avoids a one-frame hitch
- [ ] Check landing normal against `floor_max_angle`, reject steep faces
- [ ] Add a step-DOWN pass, else walking off a rock leaves you airborne
- [ ] Probe by `velocity * delta` rather than a fixed distance

## Ideas, unscheduled

- [ ] Tree colour variation, they are all identical
- [ ] More pal species, several have `_Evolved` variants
- [ ] Sound
- [ ] Export to itch.io so Aubrey can share a link
