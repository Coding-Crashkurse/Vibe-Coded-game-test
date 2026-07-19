extends Node
## Sfx — Audio-Zentrale.
## Effekte & Stimmen: ElevenLabs-Dateien (assets/sfx/fx, assets/sfx/voice),
## prozedurale Synthese als Fallback, falls eine Datei fehlt.
## Musik: Tracks aus assets/music mit Zuständen (title/exploration/combat/…).

const SR := 22050

var muted := false
var streams := {}
var voice_streams := {}
var music_tracks := {}
var current_music := ""
var _players: Array[AudioStreamPlayer] = []
var _voice_player: AudioStreamPlayer
var _music: AudioStreamPlayer

func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.volume_db = 1.0
	add_child(_voice_player)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	add_child(_music)
	_build_streams()

# ------------------------------------------------------------------ Abspielen

func play(n: String, vol_db := 0.0, pitch_var := 0.08) -> void:
	if muted or not streams.has(n):
		return
	for p in _players:
		if not p.playing:
			p.stream = streams[n]
			p.volume_db = vol_db
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.play()
			return
	_players[0].stream = streams[n]
	_players[0].volume_db = vol_db
	_players[0].play()

## Schritt nach Untergrund ("grass" | "wood" | "stone")
func play_step(surface: String) -> void:
	play("step_" + surface, -3.0, 0.18)

func has_voice(id: String) -> bool:
	return voice_streams.has(id)

## Söldner-/Boss-Stimme (eigener Kanal, unterbricht vorherige Stimme)
func play_voice(id: String, vol_db := 1.0) -> void:
	if muted or not voice_streams.has(id):
		return
	_voice_player.stop()
	_voice_player.stream = voice_streams[id]
	_voice_player.volume_db = vol_db
	_voice_player.play()

func has_music(name: String) -> bool:
	return music_tracks.has(name)

## Musikzustand wechseln; true, wenn der Track existiert und läuft.
func play_music(name := "title") -> bool:
	if not music_tracks.has(name):
		return false
	if current_music == name and _music.playing:
		return true
	current_music = name
	if muted:
		return true
	_music.stream = music_tracks[name]
	_music.play()
	return true

func stop_music() -> void:
	current_music = ""
	_music.stop()

func toggle_mute() -> void:
	muted = not muted
	if muted:
		_music.stop()
		_voice_player.stop()
	elif current_music != "" and music_tracks.has(current_music):
		_music.stream = music_tracks[current_music]
		_music.play()

# ------------------------------------------------------------------ Laden

func _build_streams() -> void:
	# ElevenLabs-Effekte (bevorzugt) — Schlüssel -> Datei in assets/sfx/fx
	var filemap := {
		"shot_p": "shot_pistol", "shot_s": "shot_shotgun", "reload": "reload_mag",
		"explosion": "explosion", "hit": "hit_body", "miss": "miss_whiz",
		"death_m": "death_male", "death_f": "death_female", "throw": "throw_grenade",
		"search": "search_crate", "step_grass": "step_grass", "step_wood": "step_wood",
		"step_stone": "step_stone", "pain_enemy": "pain_enemy",
		"shell": "shell_clink",   # v3-Politur: Huelse landet (Datei optional, Synth-Fallback)
	}
	for k in filemap:
		var path := "res://assets/sfx/fx/%s.mp3" % filemap[k]
		if ResourceLoader.exists(path):
			streams[k] = load(path)
	# Kenney-UI-Sounds
	for n in ["ui_click", "ui_click2", "ui_back", "ui_confirm", "ui_error", "ui_select"]:
		var path := "res://assets/sfx/%s.ogg" % n
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	# Söldner- & Vargo-Stimmen
	var kinds := ["select", "quote", "reply", "pain"]
	for m in Db.MERCS:
		for kind in kinds:
			var id := "%s_%s" % [m["id"], kind]
			var path := "res://assets/sfx/voice/%s.mp3" % id
			if ResourceLoader.exists(path):
				voice_streams[id] = load(path)
	for extra in ["ivan_dialog", "vargo_1", "vargo_2", "vargo_3", "vargo_kampf"]:
		var path := "res://assets/sfx/voice/%s.mp3" % extra
		if ResourceLoader.exists(path):
			voice_streams[extra] = load(path)
	# Musik (Tracks des Spielers + optional generierte Enden)
	for t in ["title", "exploration", "combat", "victory", "defeat"]:
		var path := "res://assets/music/%s.mp3" % t
		if ResourceLoader.exists(path):
			var st = load(path)
			if st is AudioStreamMP3:
				st.loop = t in ["title", "exploration", "combat"]
			music_tracks[t] = st
	# Synthese-Fallbacks für alles, was (noch) fehlt
	_build_synth_fallbacks()

func _build_synth_fallbacks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	_fb("shot_p", _wav(_gen_shot_p(rng)))
	_fb("shot_s", _wav(_gen_shot_s(rng)))
	_fb("explosion", _wav(_gen_explosion(rng)))
	_fb("throw", _wav(_gen_throw(rng)))
	_fb("hit", _wav(_gen_hit(rng)))
	_fb("miss", _wav(_gen_miss(rng)))
	_fb("death_m", _wav(_gen_death(rng)))
	_fb("death_f", _wav(_gen_death(rng)))
	_fb("pain_enemy", _wav(_gen_hit(rng)))
	_fb("reload", _wav(_gen_reload(rng)))
	_fb("search", _wav(_gen_throw(rng)))
	for s in ["step_grass", "step_wood", "step_stone"]:
		_fb(s, _wav(_gen_step(rng)))
	_fb("shell", _wav(_gen_shell(rng)))
	streams["medkit"] = _wav(_gen_medkit())
	streams["interrupt"] = _wav(_gen_interrupt())
	streams["victory"] = _wav(_gen_jingle([523.25, 659.25, 783.99, 1046.5], 0.17, false))
	streams["defeat"] = _wav(_gen_jingle([392.0, 311.13, 261.63, 196.0], 0.24, true))
	_fb("ui_click", _wav(_gen_click(rng)))

func _fb(key: String, stream: AudioStreamWAV) -> void:
	if not streams.has(key):
		streams[key] = stream

# ------------------------------------------------------------------ Synthese

func _wav(frames: PackedFloat32Array) -> AudioStreamWAV:
	var pb := PackedByteArray()
	pb.resize(frames.size() * 2)
	for i in frames.size():
		var v := int(clampf(frames[i], -1.0, 1.0) * 32000.0)
		pb[i * 2] = v & 0xFF
		pb[i * 2 + 1] = (v >> 8) & 0xFF
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = pb
	return s

func _frames(dur: float) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(int(dur * SR))
	return f

func _gen_step(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(0.09)
	for i in f.size():
		var t := float(i) / SR
		f[i] = rng.randf_range(-1, 1) * exp(-t * 120.0) * 0.25
	return f

func _gen_shell(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Huelsen-"Klink": heller Metall-Ping mit schnellem, leiserem Zweit-Huepfer.
	var f := _frames(0.22)
	for start in [0.0, 0.09]:
		var s0 := int(start * SR)
		var amp := 1.0 if start == 0.0 else 0.45
		for i in range(s0, min(f.size(), s0 + int(0.08 * SR))):
			var t := float(i - s0) / SR
			var v := sin(TAU * 3400.0 * t) * exp(-t * 90.0) * 0.22
			v += sin(TAU * 5200.0 * t) * exp(-t * 120.0) * 0.12
			v += rng.randf_range(-1, 1) * exp(-t * 500.0) * 0.15
			f[i] += v * amp
	for i in f.size():
		f[i] = clampf(f[i], -1, 1)
	return f

func _gen_shot_p(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(0.14)
	for i in f.size():
		var t := float(i) / SR
		var n := rng.randf_range(-1, 1) * exp(-t * 48.0)
		var thump := sin(TAU * 175.0 * t) * exp(-t * 30.0) * 0.6
		f[i] = clampf(n * 0.95 + thump, -1, 1)
	return f

func _gen_shot_s(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(0.42)
	var lp := 0.0
	for i in f.size():
		var t := float(i) / SR
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.35)
		var v := lp * 1.6 * exp(-t * 11.0) + sin(TAU * 72.0 * t) * exp(-t * 13.0) * 0.8
		f[i] = clampf(v, -1, 1)
	return f

func _gen_explosion(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(1.0)
	var lp := 0.0
	for i in f.size():
		var t := float(i) / SR
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.16)
		var boom := sin(TAU * (46.0 + 40.0 * exp(-t * 7.0)) * t) * exp(-t * 4.5) * 0.9
		f[i] = clampf(lp * 2.2 * exp(-t * 4.0) + boom, -1, 1)
	return f

func _gen_throw(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(0.28)
	var lp := 0.0
	for i in f.size():
		var t := float(i) / SR
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.5)
		var env := pow(sin(PI * t / 0.28), 2.0)
		f[i] = lp * env * 0.3
	return f

func _gen_hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(0.1)
	for i in f.size():
		var t := float(i) / SR
		f[i] = clampf(rng.randf_range(-1, 1) * exp(-t * 65.0) * 0.7 + sin(TAU * 240.0 * t) * exp(-t * 45.0) * 0.55, -1, 1)
	return f

func _gen_miss(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(0.16)
	var last := 0.0
	for i in f.size():
		var t := float(i) / SR
		var n := rng.randf_range(-1, 1)
		f[i] = (n - last) * 0.5 * exp(-t * 22.0) * 0.6
		last = n
	return f

func _gen_death(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(0.55)
	var ph := 0.0
	for i in f.size():
		var t := float(i) / SR
		var fr := lerpf(150.0, 62.0, t / 0.55)
		ph += fr / SR
		var saw := 2.0 * fmod(ph, 1.0) - 1.0
		f[i] = clampf(saw * exp(-t * 4.5) * 0.55 + rng.randf_range(-1, 1) * exp(-t * 9.0) * 0.18, -1, 1)
	return f

func _gen_reload(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(0.2)
	for start in [0.0, 0.1]:
		var s0 := int(start * SR)
		for i in range(s0, min(f.size(), s0 + int(0.03 * SR))):
			var t := float(i - s0) / SR
			f[i] += rng.randf_range(-1, 1) * exp(-t * 160.0) * 0.5 + sin(TAU * 1350.0 * t) * exp(-t * 220.0) * 0.4
	return f

func _gen_medkit() -> PackedFloat32Array:
	var f := _frames(0.22)
	for i in f.size():
		var t := float(i) / SR
		if t < 0.09:
			f[i] = sin(TAU * 660.0 * t) * sin(PI * t / 0.09) * 0.3
		elif t > 0.11:
			var t2 := t - 0.11
			f[i] = sin(TAU * 880.0 * t2) * sin(PI * t2 / 0.11) * 0.3
	return f

func _gen_interrupt() -> PackedFloat32Array:
	var f := _frames(0.18)
	for i in f.size():
		var t := float(i) / SR
		if t < 0.07:
			f[i] = signf(sin(TAU * 980.0 * t)) * 0.22 * sin(PI * t / 0.07)
		elif t > 0.08:
			var t2 := t - 0.08
			f[i] = signf(sin(TAU * 1470.0 * t2)) * 0.22 * sin(PI * t2 / 0.1)
	return f

func _gen_click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := _frames(0.04)
	for i in f.size():
		var t := float(i) / SR
		f[i] = rng.randf_range(-1, 1) * exp(-t * 300.0) * 0.4
	return f

func _gen_jingle(notes: Array, note_len: float, dark: bool) -> PackedFloat32Array:
	var f := _frames(notes.size() * note_len + 0.3)
	for n in notes.size():
		var s0 := int(n * note_len * SR)
		var freq: float = notes[n]
		var dur := note_len + 0.25
		for i in range(s0, min(f.size(), s0 + int(dur * SR))):
			var t := float(i - s0) / SR
			var v := sin(TAU * freq * t) * 0.28 + sin(TAU * freq * 2.0 * t) * 0.07
			if dark:
				v = sin(TAU * freq * t) * 0.24 + (2.0 * fmod(freq * t, 1.0) - 1.0) * 0.09
			f[i] += v * exp(-t * 6.0)
	for i in f.size():
		f[i] = clampf(f[i], -1, 1)
	return f
