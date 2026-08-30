extends Node
## Small procedural sound bank.
##
## Tones are synthesised at startup rather than shipped as files: the whole
## bank is a few lines here, and there are no assets to license or lose.

const RATE := 22050.0
const VOICES := 12

var _bank: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0


func _ready() -> void:
	# name: [start hz, end hz, seconds, waveform, volume]
	_bank["suck"] = _tone(900.0, 180.0, 0.30, "sine", 0.5)
	_bank["shake"] = _tone(320.0, 260.0, 0.10, "square", 0.28)
	_bank["caught"] = _chime([523.0, 659.0, 784.0, 1047.0], 0.45)
	_bank["escape"] = _tone(200.0, 520.0, 0.28, "saw", 0.4)
	_bank["gather"] = _tone(420.0, 300.0, 0.09, "square", 0.3)
	_bank["craft"] = _chime([659.0, 880.0], 0.25)
	_bank["throw"] = _tone(680.0, 900.0, 0.09, "sine", 0.25)

	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		add_child(p)
		_players.append(p)


func play(sound: String, at := Vector3.ZERO) -> void:
	if not _bank.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _bank[sound]
	p.global_position = at
	p.play()


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
