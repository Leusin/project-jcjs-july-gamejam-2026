class_name Conductor
extends Node
## 곡의 현재 재생 위치를 '초'와 '박자'로 알려준다.
## 게임의 모든 타이밍은 이 값을 기준으로 계산한다.

@export var bpm: float = 120.0
@export var manual_offset: float = 0.0
@export var loop_beats: float = 4.0   # 루프 한 바퀴가 몇 박인가
## 디버그용 박자 클릭. 음악과 맞물려 들리면 시계가 정확한 것이다.
@export var metronome: bool = true

var sec_per_beat: float = 0.0
var song_position: float = 0.0           # 곡 시작으로부터 몇 초
var song_position_in_beats: float = 0.0  # 곡 시작으로부터 몇 박
var is_playing: bool = false

@onready var _player: AudioStreamPlayer = $AudioStreamPlayer

var _click: AudioStreamPlayer
var _loop_length: float = 0.0
var _loops_completed: int = 0
var _last_raw_position: float = 0.0
var _last_reported_beat: int = -1

func _ready() -> void:
	sec_per_beat = 60.0 / bpm
	_click = AudioStreamPlayer.new()
	_click.stream = load("res://assets/audio/debug_click.wav")
	_click.volume_db = -6.0
	add_child(_click)

func start_song() -> void:
	_loop_length = loop_beats * sec_per_beat   # 4박 × 0.5초 = 2.0초
	_loops_completed = 0
	_last_raw_position = 0.0
	_last_reported_beat = -1
	_player.play()
	is_playing = true

func stop_song() -> void:
	_player.stop()
	is_playing = false

func _process(_delta: float) -> void:
	if not is_playing:
		return

	var raw := _player.get_playback_position()
	# 재생 위치가 뒤로 점프하면 한 바퀴 돈 것이다.
	if raw < _last_raw_position - 0.1:
		_loops_completed += 1
	_last_raw_position = raw

	song_position = _loops_completed * _loop_length + raw \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency() \
		+ manual_offset

	song_position_in_beats = song_position / sec_per_beat

	var b := int(song_position_in_beats)
	if b != _last_reported_beat:
		_last_reported_beat = b
		if metronome:
			# 루프 첫 박만 높은 소리로 → 마디 시작이 들린다
			_click.pitch_scale = 1.5 if b % int(loop_beats) == 0 else 1.0
			_click.play()
