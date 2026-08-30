extends Node
## Every number worth fiddling with lives here, so playtesting means editing
## one file. Autoloaded as `Tuning`.

# --- Player movement ---
const PLAYER_SPEED := 5.0
const PLAYER_RUN_SPEED := 9.0
const PLAYER_JUMP_STRENGTH := 5.0
const PLAYER_TURN_SPEED := 10.0

# --- Camera ---
const MOUSE_SENSITIVITY := 0.003
const CAMERA_PITCH_MIN := -1.2
const CAMERA_PITCH_MAX := 0.4
const CAMERA_DISTANCE := 5.0

# --- World ---
const GROUND_SIZE := 120.0

# --- Scenery scatter ---
const SCATTER_SEED := 20260830
const TREE_COUNT := 90
const ROCK_COUNT := 70
const SCATTER_CLEAR_RADIUS := 6.0
const TREE_SCALE_MIN := 0.7
const TREE_SCALE_MAX := 1.6
const ROCK_SCALE_MIN := 0.5
const ROCK_SCALE_MAX := 1.8

# --- Stepping over low obstacles ---
const STEP_HEIGHT := 0.45
const STEP_FORWARD_PROBE := 0.35

# --- Pals ---
const PAL_WALK_SPEED := 2.2
const PAL_FLEE_SPEED := 5.5
const PAL_WANDER_RADIUS := 12.0
const PAL_IDLE_MIN := 1.5
const PAL_IDLE_MAX := 4.0
const PAL_FLEE_DISTANCE := 6.0
const PAL_TURN_SPEED := 6.0
const PAL_FOLLOW_DISTANCE := 3.0
const PAL_FOLLOW_SPEED := 6.0
const PAL_COUNT := 8

# --- Catching ---
const CUBE_THROW_SPEED := 20.0
const CUBE_THROW_LIFT := 1.2
const CUBE_GRAVITY := 9.0
const CUBE_HALF_SIZE := 0.275
const CUBE_CATCH_CHANCE := 0.55
const CUBE_LIFETIME := 6.0

# --- Gathering ---
const GATHER_RANGE := 2.5
const GATHER_FACING_DOT := 0.3
const GATHER_HITS := 3
const GATHER_RESPAWN_DELAY := 30.0
const GATHER_PUNCH_SCALE := 0.85
const GATHER_PUNCH_TIME := 0.08

# --- Crafting ---
const WORKBENCH_RANGE := 3.0
const CUBE_RECIPE := {"wood": 1, "stone": 1}

# --- Riding ---
const RIDE_SPEED := 11.0
const RIDE_TURN_SPEED := 3.0
const RIDE_MOUNT_DISTANCE := 3.0
const RIDE_SEAT_HEIGHT := 1.1

# --- Camera feel ---
const CAMERA_FOV := 60.0

# --- Catch sequence ---
const CATCH_SUCK_TIME := 0.25
const CATCH_SHAKE_COUNT := 3
const CATCH_SHAKE_TIME := 0.28
const CATCH_SETTLE_TIME := 0.22
const CATCH_BURST_TIME := 0.35

## Clear of the cat's own body, or the cube is thrown from inside it.
const CUBE_SPAWN_FORWARD := 1.5
const CUBE_SPAWN_HEIGHT := 1.0
