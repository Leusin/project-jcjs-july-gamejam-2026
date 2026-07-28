class_name Conductor
extends Node
## 곡의 현재 재생 위치를 '초'와 '박자'로 알려준다.
## 게임의 모든 타이밍은 이 값을 기준으로 계산한다.

@export var bpm: float = 120.0
@export var manual_offset: float = 0.0
@export var loop_beats: float = 4.0   # 루프 한 바퀴가 몇 박인가
@export var music_player: AudioStreamPlayer

var sec_per_beat: float = 0.0
var song_position: float = 0.0           # 곡 시작으로부터 몇 초
var song_position_in_beats: float = 0.0  # 곡 시작으로부터 몇 박
var is_playing: bool = false

var _loop_length: float = 0.0
var _loops_completed: int = 0
var _last_raw_position: float = 0.0

func _ready() -> void:
	sec_per_beat = 60.0 / bpm

func start_song() -> void:
	var stream := music_player.stream
	assert(stream != null, "MusicPlayer에 음악이 없습니다.")
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV

		if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			var loop_samples := wav.loop_end - wav.loop_begin
			_loop_length = float(loop_samples) / wav.mix_rate
		else:
			_loop_length = wav.get_length()
	else:
		_loop_length = stream.get_length()

	_loops_completed = 0
	_last_raw_position = 0.0

	music_player.play()
	is_playing = true

func stop_song() -> void:
	music_player.stop()
	is_playing = false

func _process(_delta: float) -> void:
	if not is_playing:
		return

	var raw := music_player.get_playback_position()
	# 재생 위치가 뒤로 점프하면 한 바퀴 돈 것이다.
	if raw < _last_raw_position - 0.1:
		_loops_completed += 1
	_last_raw_position = raw

	song_position = (_loops_completed * _loop_length + raw 
		+ AudioServer.get_time_since_last_mix() 
		- AudioServer.get_output_latency() 
		+ manual_offset)

	song_position_in_beats = song_position / sec_per_beat
