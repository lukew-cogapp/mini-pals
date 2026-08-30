# Tasks

## Done

- [x] Godot 4.7 project scaffold, third-person controller
- [x] Ground texture + 160 seeded trees/rocks for motion cues
- [x] Fix player facing backwards (`atan2(-x, -z)`)
- [x] Quaternius Ultimate Monsters, 50 rigged CC0 creatures
- [x] Collision on trees/rocks; step over rocks, trees block
- [x] Wolf pal: wander, flee, catch, follow, ride
- [x] Player is a cat dragon (Cat body + wings), walk/idle animation
- [x] Camera FOV 60, window 1600x900 maximised
- [x] Xbox pad bindings on every action
- [x] Gathering, inventory, workbench, build menu (agent-built)

## Next

- [ ] Rename spheres to **pal cubes**: box mesh, rename scene/script/vars
- [ ] Verify the crafting system end to end myself (agent-built, unverified by me)
- [ ] On-screen controls hint: list has grown past what anyone can guess
- [ ] Adopt a real test suite; every bug so far was invisible without one

## Ride improvements (researched, not yet applied)

Current implementation works. Research says these are the idiomatic upgrades:

- [ ] `reparent()` rider to the Seat marker instead of assigning `global_position`
      each frame, which lags one physics frame
- [ ] Invert control: pal always drives its own `move_and_slide()`, rider only
      feeds it an input vector
- [ ] `set_deferred("disabled", ...)` on the rider collider, safe from signal
      callbacks
- [ ] Enable `physics/common/physics_interpolation`, and
      `reset_physics_interpolation()` on mount/dismount snaps
- [ ] Shape-test dismount spots, refuse dismount when all are blocked

## Step-up improvements (researched, not yet applied)

Current implementation works. Research says:

- [ ] Move step-up to BEFORE `move_and_slide()` (avoids a one-frame hitch)
- [ ] Check the landing normal against `floor_max_angle` so steep faces are
      rejected
- [ ] Add a step-DOWN pass, or walking off a rock leaves you briefly airborne
- [ ] Probe by `velocity * delta` rather than a fixed distance

## Ideas, unscheduled

- [ ] Tree colour variation, they are all identical
- [ ] More pal species; several have `_Evolved` variants
- [ ] Sound
- [ ] Export to itch.io so Aubrey can share a link
