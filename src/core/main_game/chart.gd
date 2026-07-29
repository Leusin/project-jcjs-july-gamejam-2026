class_name Chart
extends Node
## 언제 어떤 나방이 나올지를 정한다.
## 이 게임의 난이도는 전부 이 파일 안에 있다. 판정도 점수도 여기서는 모른다.

## 곡 구성. 곡이 at(초)를 지나면 그 구간으로 넘어간다.
##   patterns = 여러 마디에 사용할 박자 배열. 한 마디가 끝날 때마다 다음 배열로 넘어간다.
##              각 숫자는 4박 안에서 노트가 도착하는 박이다. 0.5는 8분음표, 0.25는 16분음표.
##   travel = 스폰에서 중앙까지 몇 박에 걸쳐 오는가. 작을수록 빠르고 반응할 시간이 짧다.
##   styles = 이 구간에 나오는 나방 종류(무작위로 뽑는다). 0=직선 1=사인파 2=한바퀴
##            같은 값을 여러 번 넣으면 그만큼 자주 나온다 — 오타가 아니라 가중치다.
##            한바퀴 나방이 제일 읽기 어려우므로 일부러 드물게 둔다.
##
## v0.2 곡의 실제 강약 구간을 따른다.
## 0~8 도입 → 8~16 첫 상승 → 16~20 브레이크 → 20~48 전개 →
## 48~52 브레이크 → 52~64 최고조 → 64~76 냉각 → 76~84 재폭주 →
## 84초부터 음악만 남는 아웃트로 순서다.
const STAGES := [
	{ "name": "도입", "at": 0.0, "patterns": [[0.0, 2.0], [0.0, 2.0]], "travel": 4.5, "styles": [0] },
	{ "name": "첫 상승", "at": 8.0, "patterns": [[0.0, 1.0, 2.0], [0.0, 2.0, 3.0], [0.0, 1.0, 2.0, 3.0], [0.0, 2.0]], "travel": 4.25, "styles": [0] },
	{ "name": "첫 브레이크", "at": 16.0, "patterns": [[0.0, 2.0]], "travel": 4.75, "styles": [0] },
	{ "name": "전개", "at": 20.0, "patterns": [[0.0, 2.0, 3.0], [0.0, 1.0, 2.0], [0.0, 1.0, 2.0, 3.0], [0.0, 0.5, 2.0, 3.0]], "travel": 4.0, "styles": [0, 0, 1] },
	{ "name": "가속", "at": 32.0, "patterns": [[0.0, 1.0, 2.0, 3.0], [0.0, 1.5, 2.0, 3.0], [0.0, 0.5, 2.0, 3.0], [0.0, 1.0, 2.0, 2.5, 3.0]], "travel": 3.75, "styles": [0, 0, 1, 1, 2] },
	{ "name": "두 번째 브레이크", "at": 48.0, "patterns": [[0.0, 2.0], [0.0, 1.0, 2.0]], "travel": 4.25, "styles": [0, 0, 1] },
	{ "name": "최고조", "at": 52.0, "patterns": [[0.0, 0.5, 1.0, 2.0, 3.0], [0.0, 1.0, 1.5, 2.0, 3.0], [0.0, 0.5, 1.0, 2.0, 2.5, 3.0], [0.0, 1.0, 2.0, 3.0]], "travel": 3.5, "styles": [0, 0, 1, 1, 2] },
	{ "name": "냉각", "at": 64.0, "patterns": [[0.0, 2.0], [0.0, 1.0, 2.0], [0.0, 2.0, 3.0]], "travel": 4.25, "styles": [0, 0, 1] },
	{ "name": "마지막 재폭주", "at": 76.0, "patterns": [[0.0, 1.0, 2.0, 3.0], [0.0, 0.5, 1.0, 2.0, 3.0], [0.0, 1.0, 2.0, 2.5, 3.0], [0.0, 0.5, 1.0, 2.0, 2.5, 3.0]], "travel": 3.25, "styles": [0, 0, 1, 1, 2] },
]

## 곡 시작 후 몇 박 뒤부터 노트가 나오는가(플레이어가 박을 잡을 여유).
@export var lead_in_beats: float = 8.0
## 마지막 몇 박은 새 나방 없이 음악과 화면만 남긴다.
@export var outro_beats: float = 12.0

## 지금 구간의 이동 시간(박). 노트를 만들 때와 판정선을 그릴 때 쓴다.
var travel_beats: float = 4.5
var stage: int = -1

var _conductor: Conductor = null
var _patterns: Array = []
var _styles: Array = [0]
var _next_beat_index: int = 0
var _next_pattern_index: int = 0
var _next_bar: int = 0
var _last_hit_time_seconds: float = INF
var _last_scheduled_hit_beat: float = -INF
var _finished: bool = false

func begin(conductor: Conductor, start_stage: int = 0, song_end_time: float = INF) -> void:
	_conductor = conductor
	_last_hit_time_seconds = song_end_time - outro_beats * _conductor.sec_per_beat
	_last_scheduled_hit_beat = -INF
	_finished = false
	_apply_stage(clampi(start_stage, 0, STAGES.size() - 1))
	# 첫 노트는 lead_in 이후부터. 마디 경계에 맞춰 시작한다.
	_next_bar = int(ceil(lead_in_beats / _conductor.loop_beats))
	_next_pattern_index = 0
	_next_beat_index = 0

## 곡을 지금 시각까지 진행시키고, 이번 프레임에 스폰해야 할 노트를 돌려준다.
## 각 항목은 { "hit_beat": float, "style": int }.
## while인 이유: 한 프레임에 여러 개가 걸릴 수 있다.
func take_due_notes() -> Array:
	var due: Array = []
	if _conductor == null or _patterns.is_empty() or _finished:
		return due
	_update_stage()
	while _conductor.song_position_in_beats >= _next_hit_beat() - travel_beats:
		var next_hit_beat := _next_hit_beat()
		var next_hit_time_seconds := next_hit_beat * _conductor.sec_per_beat
		if next_hit_time_seconds > _last_hit_time_seconds:
			_finished = true
			break
		due.append({ "hit_beat": next_hit_beat, "style": _styles.pick_random() })
		_last_scheduled_hit_beat = next_hit_beat
		_advance_note()
	return due

## 곡 진행 시간에 따라 구간을 올린다.
func _update_stage() -> void:
	var next := stage + 1
	if next < STAGES.size() and _conductor.song_position >= STAGES[next]["at"]:
		_apply_stage(next)

func _apply_stage(index: int) -> void:
	stage = index
	_patterns = (STAGES[index]["patterns"] as Array).duplicate(true)
	for pattern: Array in _patterns:
		pattern.sort()
	travel_beats = STAGES[index]["travel"]
	_styles = (STAGES[index]["styles"] as Array).duplicate()

	if _conductor != null and _conductor.is_playing:
		# 이미 날아오는 노트를 건드리지 않도록, 다음 마디 경계부터 새 패턴을 시작한다.
		var frontier: float = _conductor.song_position_in_beats + travel_beats
		# 직전 구간이 같은 박의 노트를 이미 예약했다면 그 다음 마디로 넘겨 중복을 막는다.
		frontier = maxf(frontier, _last_scheduled_hit_beat + 0.001)
		_next_bar = int(ceil(frontier / _conductor.loop_beats))
		_next_pattern_index = 0
		_next_beat_index = 0
	print("구간 %d '%s' (%d마디 패턴, 이동 %.2f박)" % [
		index + 1,
		STAGES[index]["name"],
		_patterns.size(),
		travel_beats
	])

## 다음에 스폰할 노트가 도착해야 하는 박(곡 시작 기준).
func _next_hit_beat() -> float:
	var pattern: Array = _patterns[_next_pattern_index]
	return _next_bar * _conductor.loop_beats + pattern[_next_beat_index]

func _advance_note() -> void:
	var pattern: Array = _patterns[_next_pattern_index]
	_next_beat_index += 1
	if _next_beat_index < pattern.size():
		return

	_next_beat_index = 0
	_next_pattern_index = (_next_pattern_index + 1) % _patterns.size()
	_next_bar += 1
