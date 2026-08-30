extends Node
## Small procedural sound bank.
##
## Tones are synthesised at startup rather than shipped as files: the whole
## bank is a few lines here, and there are no assets to license or lose.

const RATE := 22050.0
const VOICES := 12
## Below the effect voices, so catch and hit feedback cuts through.
const MUSIC_VOLUME_DB := -9.0

var _bank: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _music_player: AudioStreamPlayer


func _ready() -> void:
	# name: [start hz, end hz, seconds, waveform, volume]
	_bank["suck"] = _tone(900.0, 180.0, 0.30, "sine", 0.5)
	_bank["shake"] = _tone(320.0, 260.0, 0.10, "square", 0.28)
	_bank["caught"] = _chime([523.0, 659.0, 784.0, 1047.0], 0.45)
	_bank["escape"] = _tone(200.0, 520.0, 0.28, "saw", 0.4)
	_bank["gather"] = _tone(420.0, 300.0, 0.09, "square", 0.3)
	_bank["bite"] = _tone(520.0, 240.0, 0.08, "saw", 0.3)
	# Duller and lower than "bite": a swing that connected with nothing.
	_bank["whiff"] = _tone(180.0, 95.0, 0.07, "sine", 0.22)
	_bank["craft"] = _chime([659.0, 880.0], 0.25)
	_bank["throw"] = _tone(680.0, 900.0, 0.09, "sine", 0.25)
	# A cube costs wood and stone, so a miss has to be audible.
	_bank["cube_miss"] = _tone(150.0, 60.0, 0.14, "sine", 0.3)
	_bank["hit"] = _tone(220.0, 90.0, 0.09, "square", 0.35)
	_bank["defeat"] = _tone(480.0, 120.0, 0.4, "saw", 0.38)
	_bank["player_hurt"] = _tone(300.0, 130.0, 0.16, "square", 0.4)
	_bank["player_death"] = _tone(440.0, 60.0, 0.7, "saw", 0.42)
	_bank["demon_attack"] = _tone(150.0, 330.0, 0.16, "saw", 0.38)
	_bank["summon"] = _tone(60.0, 420.0, 0.9, "saw", 0.5)
	_bank["boss_attack"] = _tone(110.0, 45.0, 0.3, "saw", 0.45)
	# A-minor bass under a sparse melody; loops seamlessly (see _music).
	_bank["boss_music"] = _music(
		[55.0, 55.0, 65.41, 55.0, 55.0, 55.0, 98.0, 82.41],
		[220.0, 0.0, 261.63, 0.0, 329.63, 0.0, 246.94, 220.0],
		0.42,
	)

	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		add_child(p)
		_players.append(p)

	# Music gets its own non-positional player: it must not fade with
	# distance nor be recycled out from under a loop by the voice pool.
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = MUSIC_VOLUME_DB
	add_child(_music_player)


func play(sound: String, at := Vector3.ZERO) -> void:
	if not _bank.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _bank[sound]
	p.global_position = at
	p.play()


func play_music(sound: String) -> void:
	if not _bank.has(sound):
		return
	if _music_player.playing and _music_player.stream == _bank[sound]:
		return
	_music_player.stream = _bank[sound]
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


## One beat per entry; a 0.0 melody entry is a rest. The saw bass keeps
## running phase across beat boundaries, so the loop point never clicks.
func _music(bass: Array, melody: Array, beat_secs: float) -> AudioStreamWAV:
	var frames := int(RATE * beat_secs * bass.size())
	var data := PackedByteArray()
	data.resize(frames * 2)
	var bass_phase := 0.0
	var mel_phase := 0.0
	for i in frames:
		var beat_pos := float(i) / (RATE * beat_secs)
		var b := int(beat_pos) % bass.size()
		var local := beat_pos - floorf(beat_pos)
		bass_phase += TAU * float(bass[b]) / RATE
		var s := _wave("saw", bass_phase) * 0.4 * pow(1.0 - local, 0.5)
		var hz := float(melody[b])
		if hz > 0.0:
			mel_phase += TAU * hz / RATE
			s += sin(mel_phase) * 0.3 * minf(local * 8.0, 1.0) * pow(1.0 - local, 1.2)
		_put(data, i, s * 0.8)
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = frames
	return w


func _tone(from_hz: float, to_hz: float, secs: float, wave: String, vol: float) -> AudioStreamWAV:
	var frames := int(RATE * secs)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	for i in frames:
		var t := float(i) / frames
		var hz: float = lerpf(from_hz, to_hz, t)
		phase += TAU * hz / RATE
		var s := _wave(wave, phase)
		# Short attack, long decay, so nothing clicks at the edges.
		var env: float = minf(t * 12.0, 1.0) * pow(1.0 - t, 1.6)
		_put(data, i, s * env * vol)
	return _wav(data)


func _chime(notes: Array, secs: float) -> AudioStreamWAV:
	var frames := int(RATE * secs)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var per := frames / notes.size()
	for i in frames:
		# Deliberate integer division: `per` samples map to one note.
		@warning_ignore("integer_division")
		var idx: int = mini(i / per, notes.size() - 1)
		var local := float(i - idx * per) / per
		var phase := TAU * float(notes[idx]) * float(i) / RATE
		var env: float = minf(local * 14.0, 1.0) * pow(1.0 - local, 1.4)
		_put(data, i, sin(phase) * env * 0.42)
	return _wav(data)


func _wave(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if sin(phase) >= 0.0 else -1.0
		"saw":
			return fmod(phase, TAU) / PI - 1.0
		_:
			return sin(phase)


func _put(data: PackedByteArray, i: int, value: float) -> void:
	var v := int(clampf(value, -1.0, 1.0) * 32767.0)
	data.encode_s16(i * 2, v)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(RATE)
	w.stereo = false
	w.data = data
	return w
