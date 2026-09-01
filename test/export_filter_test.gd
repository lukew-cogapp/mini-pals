extends GutTest
## The web export's exclude list against what the scenes actually reference.
##
## Excluding an unused kit model saves several MB, so the list is long and is
## edited whenever art is added. Twice it has dropped a file a shipped scene
## needed: the cube's mushroom mesh and the llama's Alpaking. Desktop loads
## from disk whatever the list says, so both looked correct in the editor and
## broke only in the browser, where the throw spent a cube and drew nothing.


func _excluded() -> Array[String]:
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var found := RegEx.create_from_string('exclude_filter="(.*?)"').search(cfg)
	assert_not_null(found, "no exclude_filter in export_presets.cfg")
	var out: Array[String] = []
	for item in found.get_string(1).split(","):
		var trimmed := item.strip_edges()
		if not trimmed.is_empty():
			out.append(trimmed)
	return out


## Every res:// path named by a scene, script or project.godot, minus the
## `test/*` and `sandbox/*` globs the list carries for whole directories.
func _referenced() -> Dictionary:
	var refs := {}
	var re := RegEx.create_from_string("res://([^\"')\\s]+)")
	for path in _files(["res://scenes", "res://scripts"], [".tscn", ".gd"]) + ["res://project.godot"]:
		var text := FileAccess.get_file_as_string(path)
		for hit in re.search_all(text):
			var target := hit.get_string(1)
			if not refs.has(target):
				refs[target] = []
			refs[target].append(path)
	return refs


func _files(roots: Array, suffixes: Array) -> Array[String]:
	var out: Array[String] = []
	for root in roots:
		var stack: Array[String] = [root]
		while not stack.is_empty():
			var dir_path: String = stack.pop_back()
			var dir := DirAccess.open(dir_path)
			if dir == null:
				continue
			dir.list_dir_begin()
			var entry := dir.get_next()
			while entry != "":
				var full := dir_path.path_join(entry)
				if dir.current_is_dir():
					stack.append(full)
				else:
					for suffix in suffixes:
						if entry.ends_with(suffix):
							out.append(full)
				entry = dir.get_next()
			dir.list_dir_end()
	return out


func test_no_referenced_asset_is_excluded_from_the_web_build() -> void:
	var excluded := _excluded()
	var broken := PackedStringArray()
	var refs := _referenced()
	for key in refs:
		var target: String = key
		if excluded.has(target):
			broken.append("%s <- %s" % [target, ", ".join(refs[target])])
	assert_eq(
		broken.size(), 0,
		"excluded from the web export but referenced by a shipped scene:\n  %s"
		% "\n  ".join(broken),
	)


## A .gltf ships as three files. Keeping the model while dropping its buffer
## or texture fails at load exactly as dropping the model does.
func test_a_shipped_gltf_keeps_its_buffer_and_textures() -> void:
	var excluded := _excluded()
	var re := RegEx.create_from_string('"uri"\\s*:\\s*"([^"]+)"')
	var broken := PackedStringArray()
	for key in _referenced():
		var target: String = key
		if not target.ends_with(".gltf") or excluded.has(target):
			continue
		var res: String = "res://" + target
		if not FileAccess.file_exists(res):
			continue
		var base: String = res.get_base_dir()
		for hit in re.search_all(FileAccess.get_file_as_string(res)):
			var uri := hit.get_string(1)
			if uri.begins_with("data:"):
				continue
			var dep: String = base.path_join(uri.uri_decode()).replace("res://", "")
			if excluded.has(dep):
				broken.append("%s needs %s" % [target, dep])
	assert_eq(
		broken.size(), 0,
		"shipped .gltf whose sidecar is excluded:\n  %s" % "\n  ".join(broken),
	)
