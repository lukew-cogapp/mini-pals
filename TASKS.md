# Tasks

No TodoWrite tool in this session, so this file is the task list. Kept current
as work lands.

## In progress

Nothing in flight.

## Next

- [ ] Gather feedback in the world: sound plays, but no hit effect
- [ ] Adopt **GUT** for tests (researched, recommended over GdUnit4)
      `godot --headless -d -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
      First tests: facing maths, step-up over rock vs tree, inventory/crafting
- [ ] Wings for the cat dragon: primitives read as blades through the body,
      needs a real wing mesh

## Done

- [x] Catch sequence: pal shrinks into the cube, three shakes, particle burst,
      escape bursts the pal back out at full size
- [x] Procedural sound bank, synthesised at startup, no asset files
- [x] Catch chance shown in the HUD
- [x] Overlay styling: shared styles in `ui/`, amber on dark, matching HUD,
      build menu and help
- [x] Party system: caught pals are stored, Tab cycles, one out at a time
- [x] Q throws a pal cube, and `/` toggles a controls overlay
- [x] HUD messages on catch, escape, and empty pockets
- [x] Proper workbench: legs, plank top, tool rack, anvil
- [x] Pal cubes: renamed from spheres, tumbling red box
- [x] Build menu verified visually, affordable and greyed states
- [x] Resource HUD along the bottom
- [x] Facing: models face +Z so `atan2(x, z)`, verified by screenshot
- [x] Sunset lighting, warm low sun and light fog
- [x] Screenshot harness, 12 angles including UI
- [x] Blue cat via recoloured atlas
- [x] Gathering, inventory, workbench, build menu
- [x] Wolf pal: wander, flee, catch, follow, ride
- [x] Collision: step over rocks, trees block
- [x] Quaternius Ultimate Monsters, 50 rigged CC0 creatures
- [x] Ground texture and 160 seeded trees/rocks
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
