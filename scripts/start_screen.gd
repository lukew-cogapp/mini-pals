extends Node3D
## Title screen. The project's main scene; Play swaps in the world.
##
## The backdrop is its own small 3D set rather than the real world scene:
## world.tscn scatters hundreds of props and spawns every pal on load, and
## paying for that before the player has pressed anything would put the delay
## in the worst possible place.

const WORLD := "res://scenes/world.tscn"
## Degrees per second for the backdrop pal. Slow enough to read as a display
## turntable rather than a spin. Move to Tuning if it wants playtesting.
const TURN_SPEED := 14.0
## Wording tracks the in-game help overlay in hud.tscn. Keep the two in step.
const CONTROLS := [
	["Move", "WASD", "Left stick"],
	["Run", "Shift", "Stick click"],
	["Jump", "Space", "A"],
	["Bite tree, rock or pal", "Click or F", "Y"],
	["Send your pal at a target", "Middle click / T", "RB"],
	["Build menu (at bench)", "B", "B"],
	["Aim a pal cube (free)", "Right click", "Left trigger"],
	["Throw while aiming", "Q", "Right trigger"],
	["Ride a caught pal", "E", "X"],
	["Swap active pal", "Tab", "LB"],
	["Use the altar", "R", "D-pad up"],
	["Toggle the minimap", "M", "D-pad down"],
]

@onready var _turntable: Node3D = $Turntable
@onready var _play: Button = $UI/Menu/Play
@onready var _debug: Button = $UI/Menu/Debug
@onready var _quit: Button = $UI/Menu/Quit
@onready var _loading: Label = $UI/Menu/Loading

## Set once Play is pressed; `_process` then polls the load until it lands.
var _loading_king := false
var _loading_world := false


func _ready() -> void:
	# From the project settings, so a rename does not leave the title stale.
	$UI/Title/Name.text = ProjectSettings.get_setting("application/config/name")
	_fill_controls()
	_play.pressed.connect(_on_play)
	_debug.pressed.connect(_on_debug)
	_quit.pressed.connect(_on_quit)
	# Without a focused control, a gamepad or the arrow keys have nowhere to
	# start from and the screen can only be driven by the mouse.
	_play.grab_focus()
	# The title screen is the one place the pointer should be usable.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Hud is an autoload, so it is already on screen before the world exists
	# and draws its health bar and item list over the title.
	_set_hud_visible(false)


func _exit_tree() -> void:
	_set_hud_visible(true)


func _set_hud_visible(on: bool) -> void:
	var hud := get_node_or_null(^"/root/Hud")
	if hud:
		hud.visible = on


func _process(delta: float) -> void:
	_turntable.rotate_y(deg_to_rad(TURN_SPEED) * delta)
	if _loading_world:
		_poll_load()


## The world is ~300 ms of resource loading, and change_scene_to_file pays it
## in one blocking lump at the end of the frame: on the web that reads as the
## tab having hung, then the game appearing. Requested across frames instead,
## so the title stays up and animating with a progress figure on it.
##
## load_threaded_request works without thread support, which the web export
## cannot have (it needs cross-origin isolation headers, and Pages sets
## none). It returns in slices rather than in parallel, which is the point:
## the frames keep coming.
func _begin_load() -> void:
	_loading_world = true
	_play.disabled = true
	_debug.disabled = true
	_play.visible = false
	_debug.visible = false
	_quit.visible = false
	_loading.visible = true
	ResourceLoader.load_threaded_request(WORLD)


func _poll_load() -> void:
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(WORLD, progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if progress.size() > 0:
			_loading.text = "Loading... %d%%" % roundi(float(progress[0]) * 100.0)
		return
	_loading_world = false
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		# Nothing to fall back to but the blocking path, which at least starts.
		get_tree().change_scene_to_file(WORLD)
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(WORLD)
	get_tree().change_scene_to_packed(packed)
	if _loading_king:
		Party.grant_king_when_world_ready.call_deferred()


func _fill_controls() -> void:
	var grid: GridContainer = $UI/Controls/Col/Grid
	_add_row(grid, "", "Keyboard", "Gamepad", true)
	for row in CONTROLS:
		_add_row(grid, row[0], row[1], row[2], false)


func _add_row(grid: GridContainer, action: String, key: String, pad: String, head: bool) -> void:
	grid.add_child(_cell(action, Color(0.88, 0.9, 0.94), 16, 0))
	grid.add_child(_cell(key, Color(0.98, 0.82, 0.52) if not head else Color(0.7, 0.68, 0.76), 16, 2))
	grid.add_child(_cell(pad, Color(0.98, 0.82, 0.52) if not head else Color(0.7, 0.68, 0.76), 16, 2))


func _cell(
	text: String,
	colour: Color,
	size: int,
	align: HorizontalAlignment,
) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = align
	return label


func _on_play() -> void:
	_begin_load()


## Same start, plus a caught Mushroom King, for testing the endgame without
## playing to it.
##
## The grant is deferred onto Party, NOT awaited here. Swapping the scene
## frees this node with it, so a coroutine resuming on process_frame resumes
## inside a freed start screen and the call after it never runs. That
## shipped, and the debug start silently granted nothing. A deferred call
## belongs to Party, which is an autoload and outlives the swap.
func _on_debug() -> void:
	_loading_king = true
	_begin_load()


func _on_quit() -> void:
	get_tree().quit()
