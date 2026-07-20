extends Node
## Sfx — audio hub.
## Effects & voices: baked files (assets/sfx/fx, assets/sfx/voice) with
## procedural synthesis as a fallback whenever a file is missing.
## Music: tracks from assets/music with states (title/exploration/combat/…).

const SR := 22050

## SPEC §5.1 — voice manifest, the single source of truth for spoken lines.
## Loaded lazily and entirely optional: if it is missing, voice lookup falls
## back to the <char>_<kind>.mp3 naming convention below.
const VOICE_MANIFEST_PATH := "res://assets/audio/voice_manifest.json"
## Clip kinds per character. "spot" (enemy-sighting callout) is an extra on top
## of the spec list; "reply" is the legacy filename of move_ack variant 1.
const VOICE_KINDS := ["select", "reply", "move_ack", "quote", "pain", "death", "spot"]
## Legacy filename aliases: requested kind -> kind actually on disk.
const VOICE_KIND_ALIAS := {"move_ack": "reply"}
## Variant 1 = <char>_<kind>.mp3, variant n>1 = <char>_<kind>_<n>.mp3.
const MAX_VOICE_VARIANTS := 3

var muted := false
var streams := {}
var voice_streams := {}
var music_tracks := {}
var current_music := ""
var _players: Array[AudioStreamPlayer] = []
var _voice_player: AudioStreamPlayer
var _music: AudioStreamPlayer
var _manifest: Dictionary = {}
var _manifest_loaded := false

## Bus-Namen. project.godot definiert NUR "Master" — die beiden Kanaele legen wir
## zur Laufzeit an, damit es keine binaere Bus-Layout-Ressource braucht und ein
## fehlendes Layout nichts kaputtmachen kann.
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

func _ready() -> void:
	_ensure_buses()
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.volume_db = 1.0
	_voice_player.bus = BUS_SFX
	add_child(_voice_player)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	_music.bus = BUS_MUSIC
	add_child(_music)
	_build_streams()

## Legt "Music" und "SFX" an (beide leiten auf Master weiter), falls sie fehlen.
## Idempotent — ein zweiter Aufruf tut nichts.
func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(String(bus_name)) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, String(bus_name))
		AudioServer.set_bus_send(idx, "Master")

# ------------------------------------------------------------------ Lautstaerke
# Linear 0.0 .. 1.0 nach aussen, intern dB. 0 schaltet den Bus stumm (linear2db
# liefert bei 0 minus unendlich, das mag der AudioServer nicht).

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))

func _get_bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)

func set_music_volume(linear: float) -> void:
	_set_bus_volume(BUS_MUSIC, linear)

func get_music_volume() -> float:
	return _get_bus_volume(BUS_MUSIC)

func set_sfx_volume(linear: float) -> void:
	_set_bus_volume(BUS_SFX, linear)

func get_sfx_volume() -> float:
	return _get_bus_volume(BUS_SFX)

# ------------------------------------------------------------------ Playback

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

## Footstep by surface ("grass" | "wood" | "stone")
func play_step(surface: String) -> void:
	play("step_" + surface, -3.0, 0.18)

func has_voice(id: String) -> bool:
	return voice_streams.has(id)

## Character voice by exact clip id (own channel, cuts off the previous line).
## An unknown id is a silent no-op — retired clips (e.g. the cut boss dialogue)
## therefore never crash or spam a caller that has not been updated yet.
func play_voice(id: String, vol_db := 1.0) -> void:
	if muted or not voice_streams.has(id):
		return
	_voice_player.stop()
	_voice_player.stream = voice_streams[id]
	_voice_player.volume_db = vol_db
	_voice_player.play()

## Character voice by kind, picking a random available variant.
## Fallback chain: requested kind -> variant 1 -> borrowed voice (manifest
## "voice_ref") -> wordless synth grunt (pain/death only) -> silent no-op.
func play_voice_kind(char_id: String, kind: String) -> void:
	if muted:
		return
	var ids := _voice_ids_for(char_id, kind)
	if ids.size() > 0:
		play_voice(ids[randi() % ids.size()])
		return
	var st := _synth_voice(kind)
	if st == null:
		return
	_voice_player.stop()
	_voice_player.stream = st
	_voice_player.volume_db = 1.0
	_voice_player.play()

## SPEC §5.1 manifest, parsed lazily; {} when the file is absent or malformed.
## The test harness reads this to assert line coverage against the files on disk.
func voice_manifest() -> Dictionary:
	if not _manifest_loaded:
		_manifest_loaded = true
		_manifest = _read_manifest()
	return _manifest

func _read_manifest() -> Dictionary:
	if not FileAccess.file_exists(VOICE_MANIFEST_PATH):
		return {}
	var f := FileAccess.open(VOICE_MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var dict: Dictionary = parsed
	return dict

## Loaded clip ids for one character + kind, manifest first, convention second.
func _voice_ids_for(char_id: String, kind: String) -> PackedStringArray:
	var out := _voice_ids_direct(char_id, kind)
	if out.size() > 0:
		return out
	# Borrowed voice (Tobias uses the "opa" clips) — exactly one hop, no loops.
	var ref := _voice_ref(char_id)
	if ref != "" and ref != char_id:
		out = _voice_ids_direct(ref, kind)
	return out

func _voice_ids_direct(char_id: String, kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	# 1) Manifest: every line whose key is <kind> or <kind>_<n>.
	var entry := _manifest_char(char_id)
	var lines = entry.get("lines", {})
	if typeof(lines) == TYPE_DICTIONARY:
		for key in lines:
			var k := String(key)
			if k != kind and not k.begins_with(kind + "_"):
				continue
			var line = lines[key]
			if typeof(line) != TYPE_DICTIONARY:
				continue
			var fname := String(line.get("file", ""))
			if fname == "":
				continue
			var vid := fname.get_basename()
			if voice_streams.has(vid):
				out.append(vid)
	if out.size() > 0:
		return out
	# 2) Convention: <char>_<kind>.mp3 and its numbered variants.
	var base := String(VOICE_KIND_ALIAS.get(kind, kind))
	for v in range(1, MAX_VOICE_VARIANTS + 1):
		var vid: String = "%s_%s" % [char_id, base]
		if v > 1:
			vid = "%s_%s_%d" % [char_id, base, v]
		if voice_streams.has(vid):
			out.append(vid)
	return out

func _manifest_char(char_id: String) -> Dictionary:
	var chars = voice_manifest().get("characters", {})
	if typeof(chars) != TYPE_DICTIONARY or not chars.has(char_id):
		return {}
	var entry = chars[char_id]
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var dict: Dictionary = entry
	return dict

func _voice_ref(char_id: String) -> String:
	return String(_manifest_char(char_id).get("voice_ref", ""))

## Wordless grunt so a missing pain/death clip still reads as a hit. Spoken
## kinds (select/move_ack/quote/spot) stay silent — a synth blip cannot fake words.
func _synth_voice(kind: String) -> AudioStream:
	if kind != "pain" and kind != "death":
		return null
	if not streams.has("voice_grunt"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711
		streams["voice_grunt"] = _wav(_gen_death(rng))
	var st: AudioStream = streams["voice_grunt"]
	return st

func has_music(name: String) -> bool:
	return music_tracks.has(name)

## Switch music state; true if the track exists and is playing.
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

# ------------------------------------------------------------------ Loading

func _build_streams() -> void:
	# Baked effects (preferred) — key -> file in assets/sfx/fx
	var filemap := {
		"shot_p": "shot_pistol", "shot_s": "shot_shotgun", "shot_r": "shot_rifle",
		"reload": "reload_mag",
		"explosion": "explosion", "hit": "hit_body", "miss": "miss_whiz",
		"death_m": "death_male", "death_f": "death_female", "throw": "throw_grenade",
		"search": "search_crate", "step_grass": "step_grass", "step_wood": "step_wood",
		"step_stone": "step_stone", "pain_enemy": "pain_enemy",
		"shell": "shell_clink",   # v3 polish: casing hits the ground (file optional, synth fallback)
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
	# Merc voices, all kinds and numbered variants. Everything is optional:
	# whatever is on disk gets loaded, the rest simply stays unavailable.
	# The retired boss dialogue (vargo_*, ivan_dialog) is deliberately NOT
	# listed any more — SPEC §3.2 cuts that fight; the mp3s live on in
	# assets/sfx/voice/_archive/de/.
	for m in Db.MERCS:
		for kind in VOICE_KINDS:
			for v in range(1, MAX_VOICE_VARIANTS + 1):
				var id: String = "%s_%s" % [m["id"], kind]
				if v > 1:
					id = "%s_%s_%d" % [m["id"], kind, v]
				var path := "res://assets/sfx/voice/%s.mp3" % id
				if ResourceLoader.exists(path):
					voice_streams[id] = load(path)
	for extra in ["tobias_rescue", "tobias_1", "tobias_2", "tobias_3",
			"tobias_base_welcome", "tobias_battle_1", "tobias_battle_2",
			"narrator_intro", "narrator_demo_end"]:
		var path := "res://assets/sfx/voice/%s.mp3" % extra
		if ResourceLoader.exists(path):
			voice_streams[extra] = load(path)
	# Music (player-supplied tracks + optional generated endings)
	for t in ["title", "exploration", "combat", "victory", "defeat"]:
		var path := "res://assets/music/%s.mp3" % t
		if ResourceLoader.exists(path):
			var st = load(path)
			if st is AudioStreamMP3:
				st.loop = t in ["title", "exploration", "combat"]
			music_tracks[t] = st
	# Synth fallbacks for everything that is (still) missing
	_build_synth_fallbacks()

func _build_synth_fallbacks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	_fb("shot_p", _wav(_gen_shot_p(rng)))
	_fb("shot_s", _wav(_gen_shot_s(rng)))
	_fb("shot_r", _wav(_gen_shot_r(rng)))
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

# ------------------------------------------------------------------ Synthesis

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
	# Casing "clink": bright metal ping plus a quick, quieter second bounce.
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

func _gen_shot_r(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# SVD: hard crack + deep boom + short reverb tail (louder/longer than the pistol)
	var f := _frames(0.6)
	var lp := 0.0
	for i in f.size():
		var t := float(i) / SR
		var crack := rng.randf_range(-1, 1) * exp(-t * 55.0) * 1.3
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.2)
		var boom := sin(TAU * 90.0 * t) * exp(-t * 14.0) * 0.85
		var echo := lp * exp(-t * 5.5) * 0.45
		f[i] = clampf(crack + boom + echo, -1, 1)
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
