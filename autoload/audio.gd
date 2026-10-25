extends Node
## Sound bank and music crossfades.

const SFX_NAMES := ["step_0", "step_1", "step_2", "step_3", "push", "goal", "ungoal",
		"win", "click", "undo", "error", "locked", "hint", "start", "boom"]
const MUSIC_TRACKS := ["music_menu", "music_game"]

var _streams: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _active_music := 0
var _current_music := ""
var _music_tween: Tween
## The headless dummy driver never retires playbacks; skip playback there to keep logs clean.
var _can_play := true


func _ready() -> void:
	_can_play = DisplayServer.get_name() != "headless"
	_setup_buses()
	for sfx_name in SFX_NAMES:
		var path := "res://assets/audio/%s.wav" % sfx_name
		if ResourceLoader.exists(path):
			_streams[sfx_name] = load(path)
	for track in MUSIC_TRACKS:
		var path := "res://assets/audio/%s.wav" % track
		if ResourceLoader.exists(path):
			_streams[track] = _prepare_loop(load(path))
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = 0.0
		add_child(p)
		_sfx_players.append(p)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_music_players.append(p)
	SaveManager.settings_changed.connect(apply_settings)
	apply_settings()


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _prepare_loop(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		var bytes_per_sample := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
		var channels := 2 if wav.stereo else 1
		if wav.data.size() > 0:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.data.size() / float(bytes_per_sample * channels))
		return wav
	return stream


func apply_settings() -> void:
	var master := clampf(float(SaveManager.get_setting("master_volume", 0.9)), 0.0, 1.0)
	var music := clampf(float(SaveManager.get_setting("music_volume", 0.55)), 0.0, 1.0)
	var sfx := clampf(float(SaveManager.get_setting("sfx_volume", 0.85)), 0.0, 1.0)
	_set_bus_volume("Master", master)
	_set_bus_volume("Music", music)
	_set_bus_volume("SFX", sfx)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func has_sfx(sfx_name: String) -> bool:
	return _streams.has(sfx_name)


func play_sfx(sfx_name: String, volume_db := 0.0, pitch_variation := 0.05) -> void:
	var stream: AudioStream = _streams.get(sfx_name)
	if stream == null or not _can_play:
		return
	for p in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
			p.play()
			return
	# all busy: reuse the first
	var first := _sfx_players[0]
	first.stream = stream
	first.volume_db = volume_db
	first.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	first.play()


func play_step() -> void:
	play_sfx("step_%d" % randi_range(0, 3), -10.0, 0.08)


func play_music(track: String, fade := 0.9) -> void:
	if track == _current_music:
		return
	_current_music = track
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if track.is_empty():
		_fade_out_music(fade)
		return
	var stream: AudioStream = _streams.get(track)
	if stream == null or not _can_play:
		return
	var old_index := _active_music
	_active_music = 1 - _active_music
	var next := _music_players[_active_music]
	var old := _music_players[old_index]
	next.stream = stream
	next.volume_db = -40.0
	next.play()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(next, "volume_db", 0.0, fade).set_trans(Tween.TRANS_SINE)
	_music_tween.tween_property(old, "volume_db", -40.0, fade).set_trans(Tween.TRANS_SINE)
	_music_tween.chain().tween_callback(old.stop)


func _fade_out_music(fade := 0.6) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	for p in _music_players:
		_music_tween.tween_property(p, "volume_db", -40.0, fade)
	_music_tween.chain().tween_callback(_stop_music)


func _stop_music() -> void:
	for p in _music_players:
		p.stop()


func stop_music() -> void:
	_current_music = ""
	_stop_music()


func current_music() -> String:
	return _current_music


func _exit_tree() -> void:
	# Release playbacks and cached streams so nothing is left playing at shutdown.
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	for p in _music_players:
		p.stop()
		p.stream = null
	for p in _sfx_players:
		p.stop()
		p.stream = null
	_music_players.clear()
	_sfx_players.clear()
	_streams.clear()
