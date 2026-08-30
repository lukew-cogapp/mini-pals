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
