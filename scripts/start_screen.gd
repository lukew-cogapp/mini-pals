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
	["Bite tree, rock or pal", "F", "Y"],
	["Build menu (at bench)", "B", "B"],
	["Aim / throw pal cube", "Q", "Trigger"],
	["Ride a caught pal", "E", "X"],
	["Swap active pal", "Tab", "LB"],
	["Use the altar", "R", "D-pad up"],
	["Toggle the minimap", "M", "D-pad down"],
]

@onready var _turntable: Node3D = $Turntable
@onready var _play: Button = $UI/Menu/Play
@onready var _quit: Button = $UI/Menu/Quit


func _ready() -> void:
	# From the project settings, so a rename does not leave the title stale.
	$UI/Title/Name.text = ProjectSettings.get_setting("application/config/name")
	_fill_controls()
	_play.pressed.connect(_on_play)
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
	get_tree().change_scene_to_file(WORLD)


func _on_quit() -> void:
	get_tree().quit()
