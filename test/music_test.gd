extends GutTest
## The generated music loops.
##
## Both themes are synthesised at startup from note arrays, so a bad edit to
## one produces silence, clipping, or a loop that clicks, none of which any
## other test would notice. The world loop is the one that matters: it plays
## for the whole session.

var _audio: Node


func before_all() -> void:
	_audio = load("res://scripts/audio.gd").new()
	add_child(_audio)
	await wait_process_frames(1)


func after_all() -> void:
	_audio.free()


func _samples(name: String) -> PackedFloat32Array:
	var wav: AudioStreamWAV = _audio._bank[name]
	var out := PackedFloat32Array()
	out.resize(wav.data.size() / 2)
	for i in out.size():
		out[i] = wav.data.decode_s16(i * 2) / 32767.0
	return out


func test_both_themes_are_audible_and_unclipped() -> void:
	for name in ["world_music", "boss_music"]:
		var s := _samples(name)
		var peak := 0.0
		var sum := 0.0
		for v in s:
			peak = maxf(peak, absf(v))
			sum += absf(v)
		assert_gt(sum / s.size(), 0.02, "%s is near silent" % name)
		assert_lt(peak, 0.999, "%s clips" % name)


## A loop that ends mid-swing pops on every repeat. Both edges have to sit
## near zero for the seam to be inaudible.
func test_the_loop_seam_does_not_click() -> void:
	for name in ["world_music", "boss_music"]:
		var s := _samples(name)
		var step := absf(s[0] - s[s.size() - 1])
		assert_lt(step, 0.35, "%s jumps %.3f across the loop seam" % [name, step])


## The overworld phrase must not resolve back to its own opening halfway
## through, or the second half is the first one again and the loop is really
## half as long as it reads.
##
## Compared as energy per beat, not sample by sample: the bass phase runs
## freely across beats, so two halves built from identical notes still differ
## in every sample while sounding the same. The first version of this test
## compared samples and passed against a deliberately duplicated half.
func test_the_world_phrase_does_not_repeat_itself() -> void:
	var s := _samples("world_music")
	var beats := 32
	var per := s.size() / beats
	var energy := PackedFloat32Array()
	energy.resize(beats)
	for b in beats:
		var sum := 0.0
		for i in range(b * per, (b + 1) * per):
			sum += absf(s[i])
		energy[b] = sum / per
	var diff := 0.0
	for b in beats / 2:
		diff += absf(energy[b] - energy[b + beats / 2])
	assert_gt(
		diff / (beats / 2.0), 0.004,
		"the second half of the world loop repeats the first",
	)


## No test asserts the drum pulse. Three metrics were tried and all three
## scored drumless music the same as the real thing: the saw bass restarts
## every beat and its envelope decays every beat, so beat-edge transients and
## head-versus-tail energy are the bass, not the kick, which sits well under
## it. Judge the drums by ear; a test that cannot tell them from silence is
## worse than none, because it reads as cover.
