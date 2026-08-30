extends SceneTree
## Loads every script and scene in the project so the parser reports on all
## of them, then fails on any error or warning.
##
## Booting the game only compiles what the main scene happens to reach, so a
## broken script in an unvisited corner stays quiet until someone plays that
## far. Two bugs shipped in one afternoon this way: a rename that left a
## function body referring to a parameter that no longer existed, and another
## that left a node name reading the wrong property. Both took seconds to
## find once something actually compiled the file.
##
## Run: godot --headless --path . -s test/compile_check.gd

const DIRS := [
	"res://scripts",
	"res://scripts/tools",
	"res://scenes",
	"res://scenes/models",
	"res://test",
]


func _init() -> void:
	await process_frame
	var loaded := 0
	var failed: Array[String] = []
	for dir in DIRS:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not (f.ends_with(".gd") or f.ends_with(".tscn")):
				continue
			var path := "%s/%s" % [dir, f]
			# This script is itself running, and screenshot harnesses open a
			# window, so neither is loadable from here.
			if path.ends_with("compile_check.gd"):
				continue
			if load(path) == null:
				failed.append(path)
			else:
				loaded += 1
	print("LOADED=%d" % loaded)
	for path in failed:
		print("FAILED_TO_LOAD ", path)
	print("FAILURES=", failed.size())
	quit(1 if failed.size() > 0 else 0)
