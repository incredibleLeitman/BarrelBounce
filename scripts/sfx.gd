class_name Sfx
extends RefCounted
## Tiny procedural sound effects, synthesised into AudioStreamWAV at first use so the project
## ships without audio files.

const RATE := 22050

static var _cache: Dictionary = {}


## A "wrong answer" buzzer: two detuned square waves with a fast decay.
static func buzzer() -> AudioStreamWAV:
	if not _cache.has("buzzer"):
		_cache["buzzer"] = _synth(0.55, func(time: float) -> float:
			var env := 1.0 - time / 0.55
			var a := 1.0 if fmod(time * 110.0, 1.0) < 0.5 else -1.0
			var b := 1.0 if fmod(time * 146.0, 1.0) < 0.5 else -1.0
			return (a * 0.6 + b * 0.4) * env * env)
	return _cache["buzzer"]


## A short soft "pop" for launches.
static func pop() -> AudioStreamWAV:
	if not _cache.has("pop"):
		_cache["pop"] = _synth(0.12, func(time: float) -> float:
			var env := 1.0 - time / 0.12
			var f := 420.0 - 2000.0 * time
			return sin(TAU * f * time) * env)
	return _cache["pop"]


## A rising two-note chime for finishing a level.
static func chime() -> AudioStreamWAV:
	if not _cache.has("chime"):
		_cache["chime"] = _synth(0.5, func(time: float) -> float:
			var f := 660.0 if time < 0.18 else 990.0
			var local := time if time < 0.18 else time - 0.18
			var env := maxf(0.0, 1.0 - local / 0.32)
			return (sin(TAU * f * time) * 0.7 + sin(TAU * f * 2.0 * time) * 0.2) * env)
	return _cache["chime"]


static func _synth(seconds: float, wave: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(wave.call(i / float(RATE)), -1.0, 1.0)
		var s := int(v * 32767.0 * 0.5)
		data.encode_s16(i * 2, s)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream


## Plays a stream once on a throw-away player attached to [param parent].
static func play(parent: Node, stream: AudioStream, volume_db: float = 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
