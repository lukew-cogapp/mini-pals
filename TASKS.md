# Tasks

Kept current as work lands.

## Next

- [ ] **Ship to itch.io.** All assets are CC0, so nothing blocks it. Free web
      build, one link, no install. In order: install export templates for
      4.7.2; switch the renderer to Compatibility (Godot 4 web is WebGL2 only,
      and this project has no custom shaders so it should cost nothing, but
      screenshot it and look); make a Web preset with threads off and
      rename-to-index on; export and read the real size, which is unmeasured
      and estimated at 25 to 60 MB; zip with `index.html` at the root; create
      the project as Kind = HTML on a parent's account
- [ ] Credit line for the itch page and the help overlay: "Made with Godot
      Engine (MIT). Models by Quaternius (quaternius.com), CC0 1.0." The
      Quaternius half is courtesy, the Godot half is required
- [ ] `assets/monsters/LICENSE-Quaternius.txt` names the wrong pack (it is the
      platformer licence text). The CC0 grant holds, but re-download the right
      file so the paper trail is clean
- [ ] Build menu should grey out locked recipes rather than hiding them, so
      the level-4 Altar Key unlock is discoverable
- [ ] More islands, now that regions are Zones rather than radii
- [ ] Remaining juice: level-up moment, the win moment, FOV stretch with speed
- [ ] Gather feedback in the world: sound plays, but no hit effect
- [ ] Export smoke test in CI: `--export-release` and fail on any stderr
      error. A broken export is the one failure no gameplay test can catch
- [ ] Pal skills, one job each:
      Mushroom King out means infinite mushrooms to throw instead of cubes
      Demon out means the player hits harder
- [ ] Wings for the cat dragon: primitives read as blades through the body,
      needs a real wing mesh

## Done

- [x] GUT is the only test harness. All 26 suites run under `test/run.sh`,
      the `extends SceneTree` originals and their `_check` helpers are gone,
      and `screenshot.gd`, `start_shot.gd`, `prompt_shot.gd` and
      `compile_check.gd` stay as they were, being renderers and tools
- [x] Shallow water, a rideable Mudwader, and Glimmerfin that never leave it.
      Fish spawn past throw range of the sand, so the mount is the gate
- [x] Start screen, the main scene, with keyboard and gamepad navigation
- [x] Scorched blob at the altar instead of a ring over half the island, and
      four ground materials that are not flat colour
- [x] HUD split: level and XP, cubes, active pal, carried items
- [x] `Hud.flash` queues, so a catch is not overwritten by its own XP
- [x] Palms have collision and give wood
- [x] Cycling the party while riding no longer drops you through the world

- [x] Regions are `Zone` Area3Ds, not distances from the world origin
- [x] Followers fight for you but never land the killing blow
- [x] Camera shake, catch hitstop, hurt flash, and a catch wobble count that
      no longer leaks the roll
- [x] The swing animates and a miss is audible
- [x] Catch odds scale by level instead of subtracting, so damage always
      moves the number and the boss is no longer stuck at 5%
- [x] Quaternius nature kit for trees and rocks; real art on the pal cube

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
