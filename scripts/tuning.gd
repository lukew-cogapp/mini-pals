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

# --- Pal levels and combat ---
const PAL_LEVEL_MIN := 1
const PAL_LEVEL_MAX := 5
const PAL_BASE_HP := 2
const PAL_HP_PER_LEVEL := 1
const PUNCH_DAMAGE := 1
const PAL_HIT_KNOCKBACK := 5.0
const PAL_HIT_POP := 2.0
const PAL_HIT_STUN := 0.25
const PAL_DEATH_TIME := 1.2
const PAL_DROP_BASE := 1
const PAL_LEVEL_SCALE_STEP := 0.07
const PAL_LABEL_HEIGHT := 2.0
const PAL_LABEL_FONT_SIZE := 40
const PAL_LABEL_OUTLINE := 10
## Catch % joins the label only when looked at: wider and longer than punch
## reach, so the number appears before the player commits to a throw.
const CATCH_LABEL_FACING_DOT := 0.85
const CATCH_LABEL_DISTANCE := 15.0

# --- Player health ---
const PLAYER_MAX_HP := 10.0
const PLAYER_REGEN_DELAY := 5.0
const PLAYER_REGEN_RATE := 1.0
const PLAYER_HIT_KNOCKBACK := 4.0
const PLAYER_DEATH_TIME := 2.0
const PLAYER_RESPAWN_INVULN := 3.0
const PLAYER_RESPAWN_FADE := 0.4

# --- Hostile pals ---
const PAL_AGGRO_TIME := 8.0
const PAL_CHASE_SPEED := 4.0
const PAL_ATTACK_RANGE := 1.8
const PAL_ATTACK_DAMAGE := 1.0
const PAL_ATTACK_COOLDOWN := 1.4
const PAL_CHASE_GIVE_UP := 20.0
const PAL_AGGRO_RADIUS := 9.0
const AGGRESSIVE_BONUS_HP := 4
const AGGRESSIVE_ATTACK_DAMAGE := 2.0

# --- Demons ---
const DEMON_COUNT := 5
## Fractions of half the ground size: an annulus at the rim, so the
## middle of the map stays safe to potter about in.
const DEMON_RING_MIN := 0.55
const DEMON_RING_MAX := 0.9

# --- Player XP ---
## 34 XP per pal level: three level 1 catches tip exactly one player level,
## and a kill's half share stays a whole number.
const PLAYER_XP_PER_LEVEL := 100
const XP_PER_PAL_LEVEL := 34
const XP_KILL_FACTOR := 0.5
const PUNCH_DAMAGE_PER_PLAYER_LEVEL := 0.5

# --- Active-pal buffs ---
## speed is a fraction of player speed, gather is bonus items per punch.
const PAL_BUFF_CAPS := {&"speed": 0.5, &"gather": 3.0}

# --- Catching ---
## Horizontal lob pace; lower reads floatier and arcs higher.
const CUBE_LOB_SPEED := 8.0
const CUBE_LOB_TIME_MIN := 0.35  # Point-blank throws still get a visible arc.
const CUBE_LOB_TIME_MAX := 1.4  # Long throws stay a lob, not a mortar shot.
const CUBE_GRAVITY := 10.0
const CUBE_HALF_SIZE := 0.4
const CUBE_CATCH_CHANCE := 0.55
const CUBE_CATCH_LEVEL_PENALTY := 0.09
const CUBE_CATCH_HEALTH_BONUS := 0.35
const CUBE_CATCH_MIN := 0.05
const CUBE_CATCH_MAX := 0.9
const CUBE_LIFETIME := 6.0

# --- Gathering ---
const GATHER_YIELD := 1
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
# Seat height is scene geometry: the Seat marker in each pal scene.
const RIDE_DISMOUNT_SIDE := 1.2
const RIDE_DISMOUNT_UP := 0.5

# --- Party ---
const SUMMON_SIDE := 1.4
const SUMMON_DISTANCE := 2.0

# --- Camera feel ---
const CAMERA_FOV := 60.0

# --- Catch sequence ---
const CATCH_SUCK_TIME := 0.25
const CATCH_SHAKE_COUNT := 3
const CATCH_SHAKE_TIME := 0.28
const CATCH_SETTLE_TIME := 0.22
const CATCH_BURST_TIME := 0.35

## Clear of the cat's own body, or the cube is thrown from inside it.
const CUBE_SPAWN_FORWARD := 2.4
const CUBE_SPAWN_HEIGHT := 1.6

# --- Endgame: key, altar, boss ---
const KEY_UNLOCK_LEVEL := 4
const KEY_RECIPE := {"pelt": 3, "cactus_fruit": 3, "demon_horn": 3}
## Workbench recipes in menu order; the build menu draws one row each.
## min_level gates on player level: below it the row shows locked.
const RECIPES := [
	{"label": "Pal Cube", "item": "cube", "costs": CUBE_RECIPE, "min_level": 1},
	{"label": "Altar Key", "item": "altar_key", "costs": KEY_RECIPE, "min_level": KEY_UNLOCK_LEVEL},
]
## Out in the demon annulus, so reaching the altar is a journey; kept
## inside the island's grass (ISLAND_RADIUS minus the beach).
const ALTAR_POS := Vector3(33.0, 0.0, -33.0)
const ALTAR_CLEAR_RADIUS := 8.0
const ALTAR_RANGE := 5.0
const BOSS_LEVEL := 10
const BOSS_BONUS_HP := 30
const BOSS_ATTACK_DAMAGE := 3.0
## Outside the plinth and the stone circle, so the boss never spawns
## intersecting the altar's colliders.
const BOSS_SPAWN_OFFSET := Vector3(0.0, 0.3, 4.8)

# --- Boss fight ambience ---
const BOSS_DARK_SUN_ENERGY := 0.25
const BOSS_DARK_SUN_COLOR := Color(0.45, 0.4, 0.65)
const BOSS_DARK_AMBIENT_ENERGY := 0.12
const BOSS_DARK_FOG_DENSITY := 0.008
const BOSS_DARK_FOG_COLOR := Color(0.22, 0.17, 0.32)
const BOSS_DARK_TWEEN_TIME := 1.5
## One low omni light per pal; no shadows, so a dozen stays cheap.
const FIGHT_GLOW_ENERGY := 1.4
const FIGHT_GLOW_RANGE := 6.0
const FIGHT_GLOW_HEIGHT := 1.0
const FIGHT_GLOW_COLOR := Color(1.0, 0.55, 0.25)

# --- Island ---
const ISLAND_RADIUS := 58.0
const BEACH_WIDTH := 6.0
const WATER_RADIUS := 400.0
const WATER_LEVEL := -0.9
## Kept just inside the beach so you cannot paddle out to the wall.
const SHORE_WALL_RADIUS := 62.0
const SHORE_WALL_HEIGHT := 14.0
const PALM_COUNT := 26
const SHELL_COUNT := 40

## Thrown from the right shoulder. Straight ahead the cat's own body hides
## the cube for the first few frames, which reads as nothing happening.
const CUBE_SPAWN_SIDE := 1.4

## Where the throw is aimed. The cube leaves the shoulder but converges here,
## so the side offset is visual and does not send it wide.
const CUBE_AIM_DISTANCE := 16.0
