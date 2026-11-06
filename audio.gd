extends Node

var whisper_timer := 18.0
var thunder_p: AudioStreamPlayer
var whisper_p: AudioStreamPlayer
var bark_p: AudioStreamPlayer


func _ready() -> void:
	_add_player(_make_rain(), -15.0, true)
	_add_player(_make_drone(), -13.0, true)
	_add_player(_make_voice(), -19.0, true)
	thunder_p = _add_player(_make_thunder(), -2.0, false)
	whisper_p = _add_player(_make_whisper(), -9.0, false)
	bark_p = _add_player(_make_bark(), -3.0, false)
	bark_p.max_polyphony = 3


func _process(delta: float) -> void:
	whisper_timer -= delta
	if whisper_timer <= 0.0:
		whisper_timer = randf_range(25.0, 55.0)
		whisper_p.pitch_scale = randf_range(0.75, 1.1)
		whisper_p.play()


func thunder() -> void:
	thunder_p.pitch_scale = randf_range(0.85, 1.1)
	thunder_p.play()


func bark() -> void:
	bark_p.pitch_scale = randf_range(0.85, 1.05)
	bark_p.play()


func _add_player(stream: AudioStream, db: float, auto: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	if auto:
		p.play()
	return p


func _to_wav(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _make_rain() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 6
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.5
		lp2 += (lp - lp2) * 0.08
		s[i] = (lp - lp2) * 0.6
	return _to_wav(s, rate, true)


func _make_drone() -> AudioStreamWAV:
	# All frequencies are multiples of 1/8 Hz so the 8 s loop is seamless
	var rate := 11025
	var n := rate * 8
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / rate
		var v := sin(TAU * 55.0 * t) * 0.35
		v += sin(TAU * 55.5 * t) * 0.35
		v += sin(TAU * 82.25 * t) * 0.18
		v += sin(TAU * 110.75 * t + 1.3) * 0.1
		var lfo := 0.65 + 0.35 * sin(TAU * t / 8.0)
		s[i] = v * lfo * 0.6
	return _to_wav(s, rate, true)


func _make_voice() -> AudioStreamWAV:
	# Ghostly choir: detuned voices with vocal formants, slow vibrato
	var rate := 11025
	var n := rate * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var f0s := [98.0, 98.5]
	var amps := [1.0, 0.8]
	var weights := []
	for j in 2:
		var row := []
		for k in range(1, 9):
			var fk: float = f0s[j] * k
			var w := exp(-pow((fk - 450.0) / 250.0, 2.0)) + 0.6 * exp(-pow((fk - 950.0) / 350.0, 2.0))
			row.append(w / pow(float(k), 0.5))
		weights.append(row)
	for i in n:
		var t := float(i) / rate
		var vib := 0.5 * sin(TAU * 0.5 * t)
		var v := 0.0
		for j in 2:
			var f0: float = f0s[j]
			var ph := TAU * f0 * t + vib * (j + 1)
			var voice := 0.0
			for k in range(1, 9):
				voice += sin(k * ph) * weights[j][k - 1]
			v += voice * amps[j]
		var env := 0.55 + 0.45 * sin(TAU * t / 8.0 - 1.0)
		s[i] = v * env * 0.12
	return _to_wav(s, rate, true)


func _make_thunder() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 5
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.06
		lp2 += (w - lp2) * 0.4
		var env := exp(-t * 0.7) * (0.65 + 0.35 * sin(t * 9.0 + sin(t * 3.0) * 2.0))
		var crack := exp(-t * 14.0) * lp2 * 1.2
		var fade := clampf((5.0 - t) / 0.3, 0.0, 1.0)
		s[i] = (lp * 5.0 * env + crack) * 0.8 * fade
	return _to_wav(s, rate, false)


func _make_whisper() -> AudioStreamWAV:
	var rate := 16000
	var n := int(rate * 2.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var centers := []
	for j in 5:
		centers.append(randf_range(0.2, 2.2))
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		var env := 0.0
		for c in centers:
			env += exp(-pow((t - float(c)) / 0.13, 2.0))
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.55
		lp2 += (lp - lp2) * 0.12
		s[i] = (lp - lp2) * minf(env, 1.0) * 0.8
	return _to_wav(s, rate, false)


func _make_bark() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var tb := fmod(t, 0.24)
		var env := minf(tb / 0.008, 1.0) * exp(-tb * 14.0)
		var f := 380.0 - 700.0 * tb
		var ph := TAU * f * tb
		var tone := sin(ph) + 0.6 * sin(2.0 * ph) + 0.4 * sin(3.0 * ph) + 0.25 * sin(5.0 * ph)
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.3
		s[i] = (tone * 0.35 + lp * 0.8) * env * 0.8
	return _to_wav(s, rate, false)
