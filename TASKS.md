# Tasks

Kept current as work lands.

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
- [x] Pals give up after five seconds without landing a hit; either side's
      hit resets that timer, so running away breaks the chase
- [x] Shore wall blocks walking and riding before the player reaches visible
      water
- [x] Endgame: altar key at level 4, stone circle, Mushroom King boss with
      music, world darkening and glowing creatures; catching it wins
- [x] Player health, death and respawn; punched pals fight back and demons
      attack on sight at the map edge
- [x] Pal levels, HP, drops, live catch labels, duplicate-catch merging,
      player XP and active-pal buffs
- [x] Orientation settled: art is flipped at source by
      `scripts/tools/face_forward.py`, game code uses plain Godot -Z forward,
      and `test/orientation_test.gd` covers facing, camera, throw and punch
- [x] Procedural sound bank, synthesised at startup, no asset files
- [x] Catch chance shown in the HUD
- [x] Overlay styling: shared styles in `ui/`, amber on dark, matching HUD,
      build menu and help
- [x] Thrown cubes solve a ballistic arc onto the crosshair, visible leaving
      the shoulder
- [x] Caught pals follow: the player lookup ran before the player existed
- [x] Start with five cubes
- [x] Island: bounded land, beach, water, palms, shells, shore wall
- [x] Starlight wiki at ../godot-world-wiki
- [x] Cactoro as a second species, 8 pals now, alternating
- [x] 1 and 3 step through the party, Tab still cycles
- [x] Party system: caught pals are stored, Tab cycles, one out at a time
- [x] Q throws a pal cube, and `/` toggles a controls overlay
- [x] HUD messages on catch, escape, and empty pockets
- [x] Proper workbench: legs, plank top, tool rack, anvil
- [x] Pal cubes: renamed from spheres, tumbling red box
- [x] Build menu verified visually, affordable and greyed states
- [x] Resource HUD along the bottom
- [x] Sunset lighting, warm low sun and light fog
- [x] Screenshot harness, 20 shots including UI, rig throw and facing checks
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
- [ ] More sound polish
- [ ] Export to itch.io so Aubrey can share a link
