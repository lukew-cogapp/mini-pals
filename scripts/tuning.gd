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
## Where the camera starts. Tilted down onto the ground ahead rather than out
## at the horizon, so what the player can walk into is on screen.
const CAMERA_PITCH_START := -0.31


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

# --- Pal health bars ---
## Bars are drawn above the name label, but only near the player: a bar on
## every pal in the world reads as clutter and costs a draw call each.
const PAL_HEALTH_BAR_DISTANCE := 18.0
## How often a pal re-checks that distance. Every frame for 30-odd pals is
## work for a value that changes at walking pace.
const PAL_HEALTH_BAR_CHECK_INTERVAL := 0.25
const PAL_HEALTH_BAR_WIDTH := 1.1
const PAL_HEALTH_BAR_HEIGHT := 0.16
## Clearance above the name label, so the bar sits over the text, not on it.
const PAL_HEALTH_BAR_RISE := 0.45
## Near-black backing behind the fill, which is what makes the bar read
## against pale grass and scorched ground alike.
const PAL_HEALTH_BAR_BACK_COLOUR := Color(0.05, 0.04, 0.06)
## Border thickness, as a fraction of the bar height.
const PAL_HEALTH_BAR_BORDER := 0.22
## The empty part of the bar, drawn inside the border at full width behind
## the fill. Without it the missing health is a black void the same colour as
## the border, and a nearly-dead bar reads as a black slab with a red chip on
## it rather than as a bar that is nearly empty.
const PAL_HEALTH_BAR_TRACK_COLOUR := Color(0.19, 0.17, 0.2)

## A drop shadow behind the backing: the same quad, grown and pushed down and
## right, in translucent black. Without it a dark bar over dark ash has no
## edge at all and reads as a smudge on the ground behind it.
const PAL_HEALTH_BAR_SHADOW_COLOUR := Color(0.0, 0.0, 0.0, 0.22)
## How far the shadow is offset, in bar heights. Small: at 0.35 it read as a
## second grey rectangle beside the bar rather than as a shadow under it.
const PAL_HEALTH_BAR_SHADOW_DROP := 0.12
## How much wider and taller the shadow is than the backing, again in bar
## heights, so it shows on every side as a dark halo rather than only below.
const PAL_HEALTH_BAR_SHADOW_GROW := 0.3

## Colour ramp, high to low. The old bar had one step at 0.35, which snapped
## from green to red between two hits and gave no warning that the next one
## mattered. Three stops with the fill lerped between them reads as a slide.
const PAL_HEALTH_BAR_FILL_COLOUR := Color(0.36, 0.86, 0.36)
const PAL_HEALTH_BAR_MID_COLOUR := Color(0.96, 0.78, 0.22)
const PAL_HEALTH_BAR_LOW_COLOUR := Color(0.92, 0.24, 0.2)
## Fraction the ramp passes through mid on its way to low. Below
## PAL_HEALTH_BAR_LOW_FRACTION the fill is fully the low colour.
const PAL_HEALTH_BAR_MID_FRACTION := 0.6
const PAL_HEALTH_BAR_LOW_FRACTION := 0.25

## A lighter strip along the top of the fill, so the bar has a direction of
## light instead of reading as one flat rectangle. Height is a fraction of
## the fill's height, and the colour is the fill lightened by this much
## towards white.
const PAL_HEALTH_BAR_SHEEN_HEIGHT := 0.45
const PAL_HEALTH_BAR_SHEEN_LIGHTEN := 0.5

# --- Per-species speed ---
## Every pal shares the speed constants above; `Pal.speed_factor` scales them
## per species, the way `model_scale` scales size. A factor rather than a
## replacement, so the relationship between walking, fleeing, chasing and
## following survives a retune of the constants themselves.
##
## The player is the reference: PLAYER_SPEED 5.0, PLAYER_RUN_SPEED 9.0.
## Chasing is PAL_CHASE_SPEED 4.0, so a factor of 1.25 is exactly the
## player's walk and 2.25 is their run. Nothing here reaches 2.25: a pal that
## can run a fleeing player down at full sprint leaves no way out of a fight.
## Fleeing is PAL_FLEE_SPEED 5.5, so anything above 0.91 outwalks the player
## and only a factor over 1.64 outruns them.
const PAL_SPEED_FACTOR_MIN := 0.4
const PAL_SPEED_FACTOR_MAX := 2.0
## A follower must never fall behind a sprinting player, whatever its species,
## or it trails to FOLLOWER_LEASH and the party reads as broken. So the
## catch-up end of the follow ramp keeps this floor after scaling: above
## PLAYER_RUN_SPEED, with headroom to actually close a gap.
const FOLLOW_CATCHUP_FLOOR := 10.0

# --- Pal unsticking ---
## A pal wanting to move but covering less than STUCK_SPEED_FRACTION of the
## speed it asked for is making no progress. Held that way for STUCK_TIME it
## backs off along a fresh heading for STUCK_ESCAPE_TIME, then resumes
## whatever it was doing.
const PAL_STUCK_TIME := 0.8
const PAL_STUCK_SPEED_FRACTION := 0.3
const PAL_STUCK_ESCAPE_TIME := 0.9
## How far off the blocked heading the escape run aims, in radians either
## side. Near a right angle, so it slides along the obstacle rather than
## bouncing straight back into it.
const PAL_STUCK_TURN_MIN := 1.2
const PAL_STUCK_TURN_MAX := 2.2
const PAL_STUCK_ESCAPE_SPEED := 3.0

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

# --- Species jobs: demon damage, king cubes, wild rivalry ---
## Cap on the demon's extra punch damage; the per-level rate is on the scene
## with every other species' buff_per_level. A level 5 demon adds 2 to a base
## punch of 1, and the cap holds it there: a level 1 pal has 2 hp and the boss
## has far more, so no catch becomes a one-hit kill.
const DEMON_DAMAGE_BUFF_CAP := 2.0

## Species whose active-pal job is unlimited throws instead of a buff value.
## Winning the game ends the crafting grind rather than speeding it up.
const INFINITE_CUBE_SPECIES := "Mushroom King"
## Shown in place of the count while that species is out, so the bottom bar
## does not read "0" and look like a bug.
const INFINITE_CUBE_TEXT := "∞"

## Wild aggression. An aggressive species picks fights with other species,
## not just the player, so the world looks inhabited rather than staged.
## Shorter reach than PAL_AGGRO_RADIUS: the player is the point of the game,
## and a demon that has already noticed them must not be distracted.
const RIVAL_RADIUS := 7.0
const RIVAL_GIVE_UP := 14.0
## Rivalry is rechecked on this interval rather than every frame, staggered
## per pal by its instance id, so 30 pals scanning each other stays cheap.
const RIVAL_SCAN_INTERVAL := 0.75
const RIVAL_ATTACK_RANGE := 2.0
const RIVAL_ATTACK_COOLDOWN := 1.5
const RIVAL_DAMAGE := 1
## Backstop on a fight that cannot finish because it never closes to attack
## range. It does not bound a brawl that is landing hits: each side re-arms
## this on the next hit taken, so what ends those is one of them dying. The
## world is kept populated by the respawn block below.
const RIVAL_FIGHT_TIME := 12.0

## How long after trading blows with the player a pal's death still pays out
## the drop, the XP and the message. Participation, not the final blow: a
## demon the player softened and a wolf finished is the player's kill, and two
## pals brawling across the island while the player gathers wood are nobody's.
const PAL_CREDIT_TIME := 20.0

# --- Respawning ---
## Wild fights kill and so does the player, so the island trickles pals back
## in. See scripts/scenery.gd; test/respawn_test.gd covers the pacing.

## Headcount the island aims to hold, which is what the initial scatter puts
## there: PAL_COUNT + DEMON_COUNT + AMPHIBIAN_COUNT + FISH_COUNT. At or above
## it nothing respawns at all.
const PAL_POPULATION := 52
## Seconds between respawn rolls, sampled per roll so the trickle is not a
## metronome. Long on purpose: a cull the player could not walk home from
## before it was undone would not be a cull.
const RESPAWN_INTERVAL_MIN := 20.0
const RESPAWN_INTERVAL_MAX := 45.0
## Multiplies the deficit fraction to get the odds a roll spawns anything, so
## a nearly full island rarely does and a gutted one nearly always does. Above
## 1.0 so a badly depleted world refills at close to one pal per interval.
const RESPAWN_URGENCY := 1.6
## Nothing appears this close to the player: a pal fading in ahead of them
## reads as a glitch rather than as the world going on without them.
const RESPAWN_CLEAR_RADIUS := 30.0
## Placement retries before the respawn is abandoned, matching the scatter's
## own retry loop.
const RESPAWN_PLACE_TRIES := 12
## Fraction of the island radius the ordinary species scatter within, so the
## green stays populated and the shoreline stays for the amphibians.
const PAL_BAND := 0.6

# --- Active-pal buffs ---
## speed is a fraction of player speed, gather is bonus items per punch,
## damage is extra hitpoints per punch. See the species-jobs block below.
const PAL_BUFF_CAPS := {
	&"speed": 0.5,
	&"gather": 3.0,
	&"damage": DEMON_DAMAGE_BUFF_CAP,
	&"stone": GROTTOLO_STONE_CAP,
}

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
## A cube that lands beside a pal still catches it. The flight sweep is a
## sphere rather than a ray, so a near miss in the air counts, and a cube
## that reaches the ground looks around before giving up. Without this, a
## throw that visibly lands at a pal's feet reads as a bug.
const CUBE_HIT_RADIUS := 0.55
const CUBE_LANDING_GRAB := 1.9
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
# --- Pal auto-gathering ---
## The active pal works the scenery beside you, by species: PAL_GATHER_GROUPS
## maps display_name to the resource_node group it will bite. A species not
## listed here never auto-gathers.
const PAL_GATHER_GROUPS := {"Cactoro": "tree", "Wolf": "rock"}
## How far from the PLAYER a node may be and still be worth walking to. Kept
## under FOLLOWER_LEASH so a pal cannot pick a job it would be yanked off.
const PAL_GATHER_RADIUS := 10.0
## Close enough to bite. Trees are wide, so this is looser than the player's
## own GATHER_RANGE.
const PAL_GATHER_RANGE := 2.6
const PAL_GATHER_SPEED := 4.0
## Slower than the player's swing, so helping never out-earns doing it
## yourself.
const PAL_GATHER_COOLDOWN := 1.6
## Beyond this from the player the pal drops the job and comes back, the
## same bound follower defence uses.
const PAL_GATHER_LEASH := FOLLOWER_LEASH
## A breather after a node depletes before looking for the next one, so the
## pal does not teleport its attention across the clearing.
const PAL_GATHER_REST := 1.0

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
## Workbenches, hand-placed. One bench on a 110 m island meant walking back
## across the map to spend what you gathered, so there are a few, spread far
## enough apart that you are usually near one but never beside two.
const WORKBENCH_POSITIONS := [
	Vector3(0.0, 0.0, -8.0),
	Vector3(-52.0, 0.0, 34.0),
	Vector3(46.0, 0.0, 44.0),
	Vector3(16.0, 0.0, -74.0),
	Vector3(-62.0, 0.0, -30.0),
]

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
	"fin": "res://ui/icons/fin.svg",
	"scale": "res://ui/icons/scale.svg",
	"glow_cap": "res://ui/icons/glow_cap.svg",
}
## Rows are built once and reused, so the list needs a ceiling. Well above the
## seven items that exist; extra items past it are not shown.
const ITEM_ROWS_MAX := 14
const ITEM_ICON_SIZE := 22

# --- Objectives panel ---
## How many pals to catch before the panel stops nagging about catching. Low
## enough to clear on the way to KEY_UNLOCK_LEVEL rather than as a detour.
const OBJECTIVE_CATCH_TARGET := 3
## The cave is off the main chain: finding it is optional, so it sits as its
## own line rather than blocking the altar. A glow cap in the pack is proof
## the player got there, since the Grottolo lives nowhere else.
const OBJECTIVE_CAVE_ITEM := "glow_cap"
## Catching the King wins. Defeating him is the consolation, and his crown is
## the only way to tell after the fact, since the body is gone either way.
const OBJECTIVE_CROWN_ITEM := "kings_crown"
## Rows drawn at once: the current objective plus this many done ones above it,
## so the player sees the chain they are on without a wall of twenty lines.
const OBJECTIVE_DONE_ROWS := 2
const OBJECTIVE_ROWS_MAX := OBJECTIVE_DONE_ROWS + 1
const OBJECTIVE_FONT_SIZE := 15
const OBJECTIVE_TITLE_FONT_SIZE := 16
## Warm sunset amber for the live objective, dimmed cream for finished ones.
const OBJECTIVE_ACTIVE_COLOR := Color(0.98, 0.82, 0.52)
const OBJECTIVE_DONE_COLOR := Color(0.72, 0.74, 0.72, 0.75)

# --- Minimap ---
## Side of the square control, in pixels. The disc fills it.
const MINIMAP_SIZE := 168.0
## World metres from edge to edge of the map. Framed on the island
## (ISLAND_RADIUS 110) plus a band of the shallows, rather than on the whole
## reachable 368 across: at that width the island was a quarter of the disc
## and the dots on it were indistinguishable.
const MINIMAP_WORLD_SPAN := 280.0
const MINIMAP_BG_COLOR := Color(0.07, 0.07, 0.11, 0.72)
const MINIMAP_LAND_COLOR := Color(0.34, 0.46, 0.26)
const MINIMAP_SHALLOW_COLOR := Color(0.24, 0.38, 0.48)
const MINIMAP_ASH_COLOR := Color(0.26, 0.2, 0.22)
const MINIMAP_ALTAR_COLOR := Color(0.98, 0.82, 0.52)
const MINIMAP_ALTAR_SIZE := 4.0
const MINIMAP_PLAYER_COLOR := Color(1.0, 0.96, 0.86)
## Half-length of the player wedge, in pixels.
const MINIMAP_PLAYER_SIZE := 7.0
const MINIMAP_PAL_COLOR := Color(0.72, 0.78, 0.86)
const MINIMAP_PAL_ACTIVE_COLOR := Color(0.55, 0.85, 1.0)
const MINIMAP_PAL_HOSTILE_COLOR := Color(0.9, 0.28, 0.24)
const MINIMAP_PAL_DOT := 1.8
const MINIMAP_PAL_ACTIVE_DOT := 3.2

# --- Minimap fog of war ---
## Metres revealed around the player. A quarter of ISLAND_RADIUS (110), so
## crossing the island uncovers a broad band without clearing it in one walk.
const FOG_REVEAL_RADIUS := 28.0
## Metres per fog cell. Three metres over the 280 m span is a 94x94 grid: 9k
## booleans, cheap to mark and to draw, and just under two screen pixels per
## cell at MINIMAP_SIZE, so the revealed edge does not read as blocky.
const FOG_CELL_SIZE := 3.0

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

## --- Shallows: the water ring only a swimmer can reach --------------------

## Outer edge of the wadeable ring. A wall stands here for everyone, rider
## and pal alike, so the shallows are the last place the game is playable.
const SHALLOW_WALL_RADIUS := 184.0
const SHALLOW_WALL_HEIGHT := 14.0

## Where fish are allowed to be, spawning and wandering both. The inner edge
## is what gates the loop: a cube thrown from the shore wall reaches
## SHORE_WALL_RADIUS + CUBE_AIM_DISTANCE, so keeping every fish beyond that
## makes the mount the only way to a catch. test/water_test.gd asserts it,
## because retuning any one of the three would otherwise reopen the gate.
const FISH_RING_MIN := 148.0
const FISH_RING_MAX := 179.0
const FISH_COUNT := 14

## Amphibians wade ashore to be caught on land, so they spawn on the sand
## band rather than in the water.
const AMPHIBIAN_COUNT := 6
const AMPHIBIAN_BAND := Vector2(0.95, 1.03)

## Swim feel. A ridden swimmer off the land sits lower and moves faster: the
## water is its element, so reaching it is the reward for catching one.
const SWIM_SINK := 0.55
const SWIM_SPEED_FACTOR := 1.45

## The deep water disc is drawn over the shallow one, so the shallow ring
## needs lifting clear of it or the two z-fight.
const SHALLOW_LEVEL := -0.55

## Extra inland steps a dismount in the water tries past the shore wall, so
## it walks clear of the wall instead of landing against it.
const DISMOUNT_BEACH_STEPS := 8

## How far a fish's model drops below the ground plane. The shallow surface
## is at SHALLOW_LEVEL, so anything less than that gap leaves the fish
## visibly floating on top of the water instead of in it.
const FISH_SINK := 1.1


## --- Contextual key prompts and the debug start ---------------------------

## How often the prompt re-scans for something to act on. Every frame is
## wasted work on a check that walks three node groups, and a tenth of a
## second is under the time it takes to walk out of any of the ranges above.
const PROMPT_POLL_INTERVAL := 0.1

## Fade in and out, so walking past a tree does not strobe the panel.
const PROMPT_FADE_TIME := 0.14

## The debug start hands over a King at the level the altar would have
## summoned him at, so he reads and fights exactly like a real one.
const DEBUG_KING_LEVEL := BOSS_LEVEL
## Player level that goes with him. KEY_UNLOCK_LEVEL is the endgame gate, so
## starting there means the bench shows the key recipe without a playthrough.
const DEBUG_START_PLAYER_LEVEL := KEY_UNLOCK_LEVEL


## --- Juice pass 2: spawn and death poofs, water entry, biome and buff cues -

## A dying pal bursts a handful of particles where it stood before the corpse
## frees, and a respawning one grows in from nothing rather than popping.
## Both are one-shot: a persistent particle node per pal would cost thirty
## emitters in a world that only ever needs one at a time.
const PAL_POOF_TIME := 0.7
const PAL_POOF_COUNT := 18
const PAL_POOF_COLOUR := Color(0.85, 0.82, 0.9)
const RESPAWN_GROW_TIME := 0.45
## Where the grow starts from, as a fraction of the pal's final scale. Not
## zero: a mesh scaled to nothing for a frame reads as a flicker.
const RESPAWN_GROW_FROM := 0.05

## Riding into the water. The model sinks over this rather than snapping down
## SWIM_SINK in one frame, and the land-to-water crossing gets a splash and a
## camera kick. Wading on is silent: the kick fires on the edge only.
const SWIM_SINK_TIME := 0.35
const SHAKE_SPLASH := 0.45

## Walking onto the scorched ground. Polled on PROMPT_POLL_INTERVAL, and the
## sting and the message fire once per entry, not once per poll.
const ASH_ENTER_MESSAGE := "The ground is scorched here. Demons hunt this place."

## Punch shake scales with the damage the swing actually dealt, so the demon's
## buff is felt per swing instead of being invisible. A base punch of
## PUNCH_DAMAGE keeps SHAKE_PUNCH exactly; the cap holds a buffed one short of
## a hurt-sized rattle.
const SHAKE_PUNCH_PER_DAMAGE := 0.18
const SHAKE_PUNCH_MAX := 0.7

## The Glimmerfin's gather buff is otherwise silent, so a buffed punch plays a
## brighter chime than a bare one.
const GATHER_BUFF_SOUND := "gather_buff"

## A rival's hit lands with the same knockback, pop and stun a player punch
## does, scaled by this. Two brawling pals with none of it looked like two
## pals standing next to each other; at full strength they scattered across
## the island instead of fighting.
const RIVAL_HIT_IMPULSE_FACTOR := 0.6

## How near the middle of the view a pal must be for its health bar to show,
## as a dot product against the camera's forward. 0.8 is a cone about 37
## degrees off centre either way: comfortably "looking at it" rather than
## "somewhere ahead of me", which at the 90 degree cone GATHER_FACING_DOT
## describes would still light up most of the screen.
const PAL_HEALTH_BAR_FACING_DOT := 0.8

## --- Hills and the cave ---------------------------------------------------

## The island was one flat plane and read as flat. These are hand-placed
## mounds sitting on that plane rather than a heightmap: the ground body,
## the shore wall, the zones and the seeded scatter all still work off a
## flat y = 0 world, and a mound is just scenery with a shape.
##
## Each entry is [centre x, centre z, radius, height]. A mound is a radial
## cosine dome, so `Terrain.height_at` has a closed form and scatter can sit
## a prop on the surface without a raycast, which is what matters: the world
## is built inside _ready, before the physics server has seen any of it.
##
## Placement rules these obey, and any new mound must too:
##   - clear of the spawn at the origin by SCATTER_CLEAR_RADIUS, so the
##     player does not start on a slope,
##   - clear of the shore wall, so no mound lets anything climb it,
##   - off the scorched blob, so the altar's ground stays flat.
##
## Steepness is the whole point, and 45 degrees is the hard ceiling: that is
## the player's `floor_max_angle`, and a dome past it is not a hill but a
## wall. Measured rather than assumed, by walking the controller up a sweep
## of domes: 43.3 degrees summits, 45.3 stalls at 71% of the height, and
## anything steeper never leaves the skirt. A cosine dome is steepest at half
## its radius, at atan(PI * height / (2 * radius)), so these sit at 36 to 40
## degrees, which reads as a hill with margin left before the cliff.
##
## Four rather than the original five, and narrower: the first set covered
## about 42% of the island at 12 to 17 degrees, so standing on a slope was
## the default and none of it read as anything but flat ground. These cover
## about 13%, which leaves real flat between them to see them from.
const HILLS := [
	[-46.0, -30.0, 26.0, 12.0],
	[-30.0, 34.0, 18.0, 9.5],
	[30.0, 44.0, 16.0, 8.5],
	[-64.0, 14.0, 14.0, 7.5],
]

## Radial and ring segments per mound. 32 wide is smooth enough that the
## silhouette does not read as faceted from across the island, and 12 deep
## keeps the slope even; both feed the trimesh collider too, so higher costs
## collision time as well as vertices.
const HILL_SEGMENTS := 32
const HILL_RINGS := 12

## How far past its nominal radius a mound's skirt is drawn, so the mesh
## meets the ground plane at zero height instead of ending on a lip the
## player would have to step over.
const HILL_SKIRT := 1.06

## Slope shading. A mound uses the same grass material as the flat ground, and
## StandardMaterial3D does not vary with slope, so a lit dome and level ground
## catch the light almost identically and the shape does not read even when
## the geometry is right. These tint the mesh's own vertex colours by height,
## dark in the hollows and light on the crown, which the hill material shows
## through `vertex_color_use_as_albedo`. No shader, and it costs nothing.
const HILL_SHADE_LOW := Color(0.72, 0.78, 0.68)
const HILL_SHADE_HIGH := Color(1.06, 1.05, 0.94)

## The cave, dug into the side of the biggest hill. Not a real interior: a
## mouth of scaled rocks with a dark hollow behind it, big enough to walk
## into and stand up in.
##
## Sits on the far side of the island from the spawn, so finding it is a
## walk rather than something you trip over on the way out of camp.
const CAVE_POS := Vector3(-46.0, 0.0, -30.0)
## Which way the mouth faces, in radians about Y. Pointed back towards the
## spawn so the opening is visible on the approach rather than round the
## back of the hill.
const CAVE_FACING := 0.9
## Distance from the hill centre out to the mouth. Two bounds meet here and
## the value has to satisfy both. Too far out and the hill is shallower than
## CAVE_HEIGHT, so the roof stands proud of the grass and the cave reads as a
## doorway on a lawn. Too far in and the hollow, which runs CAVE_DEPTH back
## towards the centre, passes under the summit and out the far side, and the
## mouth ends up inside the hill with no way to walk out.
##
## At 13 m into the 26 m mound the surface is about 6 m, matching the hollow,
## and its back wall sits under about 12 m of hill.
const CAVE_MOUTH_DISTANCE := 13.0
## Inside dimensions. Wide and tall enough that the player's capsule and a
## following pal both fit through the opening with room either side.
const CAVE_WIDTH := 7.0
const CAVE_DEPTH := 11.0
const CAVE_HEIGHT := 4.5
## Boulders ringing the mouth, and how big each is. The rock model is about
## 3 m across at scale 1, so these read as cliff faces rather than pebbles.
const CAVE_ROCK_COUNT := 9
const CAVE_ROCK_SCALE_MIN := 1.8
const CAVE_ROCK_SCALE_MAX := 3.2
## Floor of the hollow, relative to the hill surface at the mouth. Slightly
## sunk, so walking in reads as going inside rather than past.
const CAVE_FLOOR_DROP := 0.3
## The dark. One low, cold omni light deep in the hollow rather than no
## light at all: pitch black reads as a bug, a dim glow reads as a cave.
const CAVE_LIGHT_ENERGY := 0.85
const CAVE_LIGHT_RANGE := 12.0
const CAVE_LIGHT_COLOR := Color(0.42, 0.5, 0.72)
const CAVE_LIGHT_HEIGHT := 2.6



## --- Distant islands on the horizon ---------------------------------------

## Pure decoration, out past everything the player can reach. No collider, no
## zone, nothing spawns on them: they exist so the horizon is land and sky
## rather than an empty ring of water, and so the map looks like it could
## grow later.
##
## Each entry is [bearing in radians, distance, radius, height]. Placed by
## hand at uneven bearings and distances, so the horizon does not read as a
## ring of identical bumps.
##
## The heights are much larger than they look like they should be, and that
## is the point: at 300 m a 20 m dome sits below the horizon line and the
## fog erases what little of it shows. These read as headlands because they
## are tall enough to break the skyline, not because of their colour, which
## was the first thing tried and made no difference in either direction. The gap between the last bearing and the first is
## deliberate: one stretch of open sea keeps the world from feeling walled.
##
## Distances all sit between DISTANT_ISLAND_MIN_RADIUS and the water's edge,
## which the terrain test asserts: one placed inside the shallow wall would
## be swimmable-to, and a dome with no collider would be swum straight
## through.
const DISTANT_ISLANDS := [
	[0.35, 276.0, 46.0, 42.0],
	[1.15, 330.0, 62.0, 58.0],
	[2.05, 262.0, 34.0, 27.0],
	[2.80, 310.0, 52.0, 64.0],
	[3.95, 290.0, 40.0, 34.0],
	[4.60, 326.0, 70.0, 72.0],
]

## Nothing may be placed nearer than this. The shallow wall is the last thing
## the player reaches, so a decorative island has to start beyond it with
## room to spare, or its skirt would meet water the player can swim in.
const DISTANT_ISLAND_MIN_RADIUS := SHALLOW_WALL_RADIUS + 40.0

## Coarser than the hills: at 300 m these are a few dozen pixels tall, and
## the segments would cost vertices nobody can see.
const DISTANT_ISLAND_SEGMENTS := 20
const DISTANT_ISLAND_RINGS := 5

## How far the dome's base is pushed below the water surface, so the island
## meets the sea rather than floating over it or showing a rim underneath.
## Measured from WATER_LEVEL, which is where the far water actually is.
const DISTANT_ISLAND_SINK := 2.0

## --- Grottolo: the cave species -------------------------------------------

## Spawns in the cave and nowhere else, so the cave is worth finding.
const GROTTOLO_COUNT := 5
## Metres from the cave mouth a Grottolo may be, spawning and wandering
## alike, which is what makes the species a reason to go in. Derived from the
## hollow rather than picked: a spawn at the back corner is CAVE_DEPTH along
## and half CAVE_WIDTH across, and the bound has to cover that or the species
## does not fit in the room it lives in.
const GROTTOLO_RADIUS := CAVE_DEPTH + CAVE_WIDTH * 0.5
## Its job is stone yield, in extra items per punch per level, capped like
## every other buff. A cave species paying out in stone is the one thing
## the mouth of a rock hill should give you.
## How far a Grottolo strays from where it spawned. Small: the hollow is
## CAVE_DEPTH deep, and a wander radius approaching that would walk them out
## of the mouth one at a time until the cave was empty.
const GROTTOLO_WANDER_RADIUS := 3.0
const GROTTOLO_STONE_PER_LEVEL := 0.25
const GROTTOLO_STONE_CAP := 1.5
