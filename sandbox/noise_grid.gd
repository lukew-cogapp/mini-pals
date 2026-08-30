extends SceneTree
## Renders candidate crack patterns as flat texture sheets, so the pattern can
## be judged before it is put on a plane.
##
## cellular_return_type 0 is CELL_VALUE (a flat random colour per cell), not
## distance to edge. The crack network is DISTANCE2_SUB (4): F2 minus F1 goes
## to zero exactly along the boundary between two cells.
##
##   godot --headless --path . -s sandbox/noise_grid.gd

const OUT := "res://sandbox/shots/noise/"


func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for ret in [4, 6]:
		for freq in [0.01, 0.02, 0.035, 0.06]:
			var n := FastNoiseLite.new()
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = freq
			n.cellular_return_type = ret
			n.cellular_jitter = 1.0
			n.fractal_octaves = 1
			var tex := NoiseTexture2D.new()
			tex.width = 512
			tex.height = 512
			tex.seamless = true
			tex.noise = n
			var waited := 0
			while tex.get_image() == null and waited < 600:
				await process_frame
				waited += 1
			var img := tex.get_image()
			var tag := "f_ret%d_%0.3f" % [ret, freq]
			if img == null:
				printerr("no image ", tag)
				continue
			img.save_png(OUT + tag + ".png")
			print("wrote ", tag)
	quit()
