extends SceneTree
## Dumps ash.tres's generated noise textures so the crack pattern and the glow
## mask can be looked at directly, rather than inferred from the gradient stops.
##
##   godot --headless --path . -s sandbox/dump_tex.gd


func _init() -> void:
	await process_frame
	var mat: StandardMaterial3D = load("res://materials/ash.tres")
	for prop in ["albedo_texture", "emission_texture", "roughness_texture"]:
		var tex := mat.get(prop) as NoiseTexture2D
		if tex == null:
			continue
		var waited := 0
		while tex.get_image() == null and waited < 600:
			await process_frame
			waited += 1
		var img := tex.get_image()
		if img == null:
			printerr("no image for ", prop)
			continue
		img.save_png("res://sandbox/shots/tex_" + prop + ".png")
		# Mean and max, to say how much of the surface actually emits.
		var total := 0.0
		var peak := 0.0
		var above := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var v := img.get_pixel(x, y).r
				total += v
				peak = max(peak, v)
				if v > 0.5:
					above += 1
		var n := (img.get_width() / 2) * (img.get_height() / 2)
		print(prop, " mean=", total / n, " max=", peak, " frac>0.5=", float(above) / n)
	quit()
