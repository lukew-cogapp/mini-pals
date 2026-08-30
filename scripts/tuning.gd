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
const TREE_COUNT := 260
const ROCK_COUNT := 190
const SCATTER_CLEAR_RADIUS := 6.0
## Kit trees stand ~7m and rocks ~2m at scale 1, so these are smaller than
## the primitives they replaced to keep the same spread of sizes on screen.
const TREE_SCALE_MIN := 0.45
const TREE_SCALE_MAX := 1.0
const ROCK_SCALE_MIN := 0.25
const ROCK_SCALE_MAX := 0.9

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
const PAL_COUNT := 20

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
const PAL_NO_HIT_GIVE_UP_TIME := 5.0
const PAL_CHASE_GIVE_UP := 20.0
const PAL_AGGRO_RADIUS := 9.0
const AGGRESSIVE_BONUS_HP := 4
const AGGRESSIVE_ATTACK_DAMAGE := 2.0

# --- Follower defence ---
## A caught pal picks fights with whatever is hostile to the player, but
## never lands the killing blow: catching is the loop, so the target is
## always left on FOLLOWER_MIN_TARGET_HP for the player to cube.
const FOLLOWER_DEFEND_RADIUS := 12.0
const FOLLOWER_DEFEND_DAMAGE := 1
const FOLLOWER_ATTACK_COOLDOWN := 1.2
const FOLLOWER_ATTACK_RANGE := 2.0
const FOLLOWER_CHASE_SPEED := 5.0
const FOLLOWER_MIN_TARGET_HP := 1
## Beyond this from the player the follower breaks off, so defending can
## never strand it on the far side of the map.
const FOLLOWER_LEASH := 16.0

# --- Demons ---
const DEMON_COUNT := 12
## The scorched blob is one place on the island rather than a band around
## it, so it is described from its own centre out: ALTAR_POS with a wobbly
## radius. About 12% of the island's area, leaving most of the map green.
const ASH_RADIUS := 38.0
## How far the edge radius swings either side of ASH_RADIUS, as a fraction
## of it. Without this the blob is a circle, which reads as painted-on as
## the ring it replaced did.
const ASH_EDGE_WOBBLE := 0.22
## Noise driving that wobble. Sampled by angle around the blob, so the
## frequency is in turns: about five lobes around the full circle.
const ASH_EDGE_FREQUENCY := 0.75
const ASH_EDGE_OCTAVES := 3
const ASH_EDGE_SEED := 7
## Demons and dead trees are placed by rejection sampling in the blob's
## bounding circle, so the sampler needs the widest the edge can reach.
const ASH_MAX_RADIUS := ASH_RADIUS * (1.0 + ASH_EDGE_WOBBLE)
## Above the grass disc by less than the step height, so nothing has to be
## climbed at the biome edge. 2 cm was inside the depth buffer's precision at
## the distance the biome is seen from, and the grass won often enough that
## the blob did not read as scorched at all.
const ASH_LIFT := 0.12
const DEAD_TREE_COUNT := 70
const DEAD_TREE_SCALE_MIN := 0.3
const DEAD_TREE_SCALE_MAX := 0.7

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
const CUBE_AIM_ASSIST_RADIUS := 0.8
const CUBE_AIM_ASSIST_GROWTH := 0.18
## A miss holds long enough for the burst to read before the cube frees.
const CUBE_MISS_TIME := 0.35
const CUBE_LOB_TIME_MIN := 0.35  # Point-blank throws still get a visible arc.
const CUBE_LOB_TIME_MAX := 1.4  # Long throws stay a lob, not a mortar shot.
const CUBE_GRAVITY := 10.0
const CUBE_HALF_SIZE := 0.4
const CUBE_CATCH_CHANCE := 0.55
## Level scales the chance rather than subtracting from it. A subtraction
## large enough to make a level 10 boss hard also sank the whole curve below
## CUBE_CATCH_MIN, so damage stopped moving the number at all.
const CUBE_CATCH_LEVEL_FALLOFF := 0.88
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
## The cat rig has no Punch clip, so the swing is Bite_Front. Held long
## enough that Walk or Idle does not stomp it on the next frame.
const BITE_ANIM_TIME := 0.32

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
const RIDE_DISMOUNT_CLEARANCE := 0.75

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
## The scorched blob is centred here, so the altar sits at the heart of the
## demon ground. Far enough out that reaching it is a journey, near enough
## that the blob's widest edge still lands on grass rather than the beach.
const ALTAR_POS := Vector3(40.0, 0.0, -40.0)
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

# --- Inventory readout ---
## Icon per item for the top-left resource list. An item with no icon here
## still gets a row, just without a picture, so a new drop is never invisible.
const ITEM_ICONS := {
	"wood": "res://ui/icons/wood.svg",
	"stone": "res://ui/icons/stone.svg",
	"cube": "res://ui/icons/cube.svg",
	"pelt": "res://ui/icons/pelt.svg",
	"cactus_fruit": "res://ui/icons/cactus_fruit.svg",
	"demon_horn": "res://ui/icons/demon_horn.svg",
	"altar_key": "res://ui/icons/altar_key.svg",
}
## Rows are built once and reused, so the list needs a ceiling. Well above the
## seven items that exist; extra items past it are not shown.
const ITEM_ROWS_MAX := 14
const ITEM_ICON_SIZE := 22

# --- Island ---
const ISLAND_RADIUS := 110.0
const BEACH_WIDTH := 6.0
const WATER_RADIUS := 400.0
const WATER_LEVEL := -0.9
## Kept just inside the beach so you cannot paddle out to the wall.
const SHORE_WALL_RADIUS := 114.0
const SHORE_WALL_HEIGHT := 14.0
## Zones are queried flat, at y = 0, so their height only has to clear the
## terrain either side of it.
const ZONE_HEIGHT := 200.0
const PALM_COUNT := 48
const SHELL_COUNT := 72
## Shore dressing bands, as fractions of ISLAND_RADIUS. Palms start beyond
## the ash so no living palm stands on scorched ground.
const PALM_BAND := Vector2(0.94, 0.99)
const SHELL_BAND := Vector2(1.0, 1.07)

## Thrown from the right shoulder. Straight ahead the cat's own body hides
## the cube for the first few frames, which reads as nothing happening.
const CUBE_SPAWN_SIDE := 1.4

## Where the throw is aimed. The cube leaves the shoulder but converges here,
## so the side offset is visual and does not send it wide.
const CUBE_AIM_DISTANCE := 30.0

## A handful to start with, so the first thing a player does can be to throw
## one rather than gather for a workbench they have not found yet.
const STARTING_CUBES := 5

## Following. The pal walks a trail of where the player has been rather than
## chasing their current position, which reads as a companion instead of a
## magnet, and sits off to one side so it is not underfoot.
const FOLLOW_TRAIL_SPACING := 0.4
const FOLLOW_TRAIL_LENGTH := 40
const FOLLOW_SIDE_OFFSET := 1.3
const FOLLOW_SLOW_RADIUS := 0.9
const FOLLOW_ACCEL := 8.0

## A pal that tops out below the player's run speed drifts back then sprints
## to catch up. It speeds up with distance instead, up to this.
const FOLLOW_CATCHUP_SPEED := 11.0
const FOLLOW_CATCHUP_RADIUS := 7.0

## --- Juice: camera shake, catch slow-mo, hurt feedback ---------------------

## Shake is a strength that decays toward zero and is applied as a random
## offset to the spring arm. Decay is per second, so at 6.0 a kick is gone in
## well under half a second.
const SHAKE_DECAY := 6.0
const SHAKE_MAX := 0.35  ## Metres of offset at full strength, so a big hit stays readable.
## Hurt shake scales with the fraction of max HP taken, so a scratch barely
## registers and a boss hit rattles the screen.
const SHAKE_HURT := 0.9
const SHAKE_PUNCH := 0.25
const SHAKE_SUMMON := 1.0

## Catch slow-mo. The burst is the payoff, so the world crawls for a moment
## once the roll has already been decided.
const CATCH_SLOWMO_SCALE := 0.25
const CATCH_SLOWMO_TIME := 0.45

## Health bar feedback. The bar slides to its new width, the fill blinks
## white, and the whole screen takes a red wash.
const HEALTH_TWEEN_TIME := 0.25
const HURT_FLASH_TIME := 0.18
const HURT_FLASH_ALPHA := 0.32
const HURT_FLASH_COLOR := Color(0.7, 0.05, 0.05)
const HEALTH_FLASH_COLOR := Color(1.0, 1.0, 1.0)
const HEALTH_FILL_COLOR := Color(0.85, 0.25, 0.25)

## Catch shakes lean further each time, so the third reads as more desperate
## than the first.
const CATCH_SHAKE_LEAN := 0.5
const CATCH_SHAKE_LEAN_GROWTH := 0.18
