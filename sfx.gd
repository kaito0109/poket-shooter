extends Node
## Tiny procedural sound effects (no audio files needed).
## Generates short WAV streams in code and plays them through a small pool.

const MIX_RATE: int = 22050

var streams: Dictionary = {}
var pool: Array[AudioStreamPlayer] = []
var pool_index: int = 0

func _ready() -> void:
	add_to_group("sfx")
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		pool.append(p)
	streams["shot"] = _make_shot(0.5)
	streams["bot_shot"] = _make_shot(0.22)
	streams["shotgun"] = _make_shot(0.95)
	streams["sniper"] = _make_sniper()
	streams["chute"] = _make_tone(300.0, 0.25, 0.2, 520.0)
	streams["boom"] = _make_boom()
	streams["hit"] = _make_tone(1900.0, 0.045, 0.25, 0.0)
	streams["hurt"] = _make_tone(240.0, 0.1, 0.3, 0.0)
	streams["pickup"] = _make_tone(880.0, 0.09, 0.3, 660.0)
	streams["heal"] = _make_tone(520.0, 0.3, 0.22, 780.0)
	streams["reload"] = _make_tone(320.0, 0.05, 0.25, 180.0)
	streams["zone"] = _make_tone(660.0, 0.16, 0.3, 0.0)
	streams["win"] = _make_melody([523.0, 659.0, 784.0, 1047.0], 0.13, 0.3)
	streams["die"] = _make_tone(160.0, 0.35, 0.35, 60.0)

func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(sound_name):
		return
	var player: AudioStreamPlayer = pool[pool_index]
	pool_index = (pool_index + 1) % pool.size()
	player.stream = streams[sound_name]
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.96, 1.04)
	player.play()

func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v: float = clampf(samples[i], -1.0, 1.0)
		var s16: int = int(v * 32767.0)
		if s16 < 0:
			s16 += 65536
		bytes[i * 2] = s16 & 0xFF
		bytes[i * 2 + 1] = (s16 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes
	return wav

func _make_shot(strength: float) -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.11)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in count:
		var t: float = float(i) / float(count)
		var env: float = pow(1.0 - t, 2.2)
		var noise: float = rng.randf_range(-1.0, 1.0)
		var thump: float = sin(TAU * 120.0 * float(i) / MIX_RATE) * 0.6
		samples[i] = (noise * 0.8 + thump) * env * strength
	return _to_wav(samples)

func _make_sniper() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.3)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in count:
		var t: float = float(i) / float(count)
		var crack: float = rng.randf_range(-1.0, 1.0) * pow(1.0 - t, 3.5) * 0.9
		var boom: float = sin(TAU * 90.0 * float(i) / MIX_RATE) * pow(1.0 - t, 1.6) * 0.7
		samples[i] = crack + boom
	return _to_wav(samples)

func _make_boom() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.55)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	for i in count:
		var t: float = float(i) / float(count)
		var env: float = pow(1.0 - t, 1.8)
		var noise: float = rng.randf_range(-1.0, 1.0) * (1.0 - t * 0.7)
		var thump: float = sin(TAU * 55.0 * float(i) / MIX_RATE) * 0.9
		samples[i] = (noise * 0.55 + thump) * env * 0.95
	return _to_wav(samples)

func _make_tone(freq: float, duration: float, volume: float, slide_to: float) -> AudioStreamWAV:
	var count: int = int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in count:
		var t: float = float(i) / float(maxi(count, 1))
		var f: float = freq if slide_to <= 0.0 else lerpf(freq, slide_to, t)
		phase += TAU * f / MIX_RATE
		var env: float = sin(PI * clampf(t, 0.0, 1.0))
		samples[i] = sin(phase) * env * volume
	return _to_wav(samples)

func _make_melody(freqs: Array, note_dur: float, volume: float) -> AudioStreamWAV:
	var per: int = int(MIX_RATE * note_dur)
	var count: int = per * freqs.size()
	var samples := PackedFloat32Array()
	samples.resize(count)
	for n in freqs.size():
		var f: float = freqs[n]
		for i in per:
			var idx: int = n * per + i
			var t: float = float(i) / float(per)
			var env: float = 1.0 - t * 0.6
			samples[idx] = sin(TAU * f * float(i) / MIX_RATE) * env * volume
	return _to_wav(samples)
