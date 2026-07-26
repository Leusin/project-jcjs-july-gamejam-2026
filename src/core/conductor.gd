extends Node
## 곡의 현재 재생 위치를 '초'와 '박자'로 알려준다.
## 게임의 모든 타이밍은 이 값을 기준으로 계산한다.

@export var bpm: float = 120.0
## 기기마다 소리가 늦게 나오는 정도가 달라서 손으로 맞추는 보정값(초).
@export var manual_offset: float = 0.0

@onready var _player: AudioStreamPlayer = $AudioStreamPlayer

var sec_per_beat: float = 0.0
var song_position: float = 0.0           # 곡 시작으로부터 몇 초
var song_position_in_beats: float = 0.0  # 곡 시작으로부터 몇 박
var is_playing: bool = false

var _last_reported_beat: int = -1

func _ready() -> void:
	sec_per_beat = 60.0 / bpm

func start_song() -> void:
	_player.play()
	is_playing = true

func _process(_delta: float) -> void:
	if not is_playing:
		return

	song_position = _player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency() \
		+ manual_offset

	song_position_in_beats = song_position / sec_per_beat

	# 검증용: 박이 바뀔 때만 출력한다 (나중에 지울 것)
	var b := int(song_position_in_beats)
	if b != _last_reported_beat:
		_last_reported_beat = b
		print("beat ", b)
