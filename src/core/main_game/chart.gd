class_name Chart
extends Node
## 언제 어떤 나방이 나올지를 정한다.
## 이 게임의 난이도는 전부 이 파일 안에 있다. 판정도 점수도 여기서는 모른다.

## 곡 구성. 곡이 at(초)를 지나면 그 구간으로 넘어간다.
##   beats  = 루프 한 바퀴(4박) 안에서 노트가 도착하는 박. 0.5는 8분음표, 0.25는 16분음표.
##   travel = 스폰에서 중앙까지 몇 박에 걸쳐 오는가. 작을수록 빠르고 반응할 시간이 짧다.
##   styles = 이 구간에 나오는 나방 종류(무작위로 뽑는다). 0=직선 1=사인파 2=한바퀴
##
## 무한히 어려워지지 않는다. 45초 안에 밀도를 다 올리고 75초까지 나방 세 종류를 다 보여준 뒤,
## 그 뒤로는 이동 시간만 조금씩 줄여 조인다. 마지막 25초만 살짝 몰아치고 끝난다.
## 새로 볼 것이 없는 구간이 길면 지루해지므로, 앞쪽을 짧게 끊는 것을 우선한다.
const STAGES := [
	{ "at":   0.0, "beats": [0.0, 2.0],                "travel": 4.5,  "styles": [0] },
	{ "at":  20.0, "beats": [0.0, 2.0, 3.0],           "travel": 4.0,  "styles": [0] },
	{ "at":  45.0, "beats": [0.0, 1.0, 2.0, 3.0],      "travel": 4.0,  "styles": [0, 1] },
	{ "at":  75.0, "beats": [0.0, 1.0, 2.0, 3.0],      "travel": 3.75, "styles": [0, 1, 2] },
	{ "at": 115.0, "beats": [0.0, 1.0, 2.0, 3.0],      "travel": 3.5,  "styles": [0, 1, 2] },
	{ "at": 155.0, "beats": [0.0, 1.0, 2.0, 2.5, 3.0], "travel": 3.5,  "styles": [0, 1, 2] },
]

## 곡 시작 후 몇 박 뒤부터 노트가 나오는가(플레이어가 박을 잡을 여유).
@export var lead_in_beats: float = 8.0

## 지금 구간의 이동 시간(박). 노트를 만들 때와 판정선을 그릴 때 쓴다.
var travel_beats: float = 4.5
var stage: int = -1

var _conductor: Conductor = null
var _beatmap: Array = []
var _styles: Array = [0]
## 비트맵을 몇 번째 항목까지 스폰했는가.
var _next_index: int = 0
## 비트맵을 몇 바퀴 돌았는가.
var _next_loop: int = 0

func begin(conductor: Conductor, start_stage: int = 0) -> void:
	_conductor = conductor
	_apply_stage(clampi(start_stage, 0, STAGES.size() - 1))
	# 첫 노트는 lead_in 이후부터. 마디 경계에 맞춰 시작한다.
	_next_loop = int(ceil(lead_in_beats / _conductor.loop_beats))
	_next_index = 0

## 곡을 지금 시각까지 진행시키고, 이번 프레임에 스폰해야 할 노트를 돌려준다.
## 각 항목은 { "hit_beat": float, "style": int }.
## while인 이유: 한 프레임에 여러 개가 걸릴 수 있다.
func take_due_notes() -> Array:
	var due: Array = []
	if _conductor == null or _beatmap.is_empty():
		return due
	_update_stage()
	while _conductor.song_position_in_beats >= _next_hit_beat() - travel_beats:
		due.append({ "hit_beat": _next_hit_beat(), "style": _styles.pick_random() })
		_advance_index()
	return due

## 곡 진행 시간에 따라 구간을 올린다.
func _update_stage() -> void:
	var next := stage + 1
	if next < STAGES.size() and _conductor.song_position >= STAGES[next]["at"]:
		_apply_stage(next)

func _apply_stage(index: int) -> void:
	stage = index
	_beatmap = (STAGES[index]["beats"] as Array).duplicate()
	_beatmap.sort()   # 시각 순서대로 스폰해야 한다
	travel_beats = STAGES[index]["travel"]
	_styles = (STAGES[index]["styles"] as Array).duplicate()

	if _conductor != null and _conductor.is_playing:
		# 이미 날아오는 노트를 건드리지 않도록, 다음 마디 경계부터 새 패턴을 시작한다.
		var frontier: float = _conductor.song_position_in_beats + travel_beats
		_next_loop = int(ceil(frontier / _conductor.loop_beats))
		_next_index = 0
	print("구간 %d (마디당 %d개, 이동 %.2f박)" % [index + 1, _beatmap.size(), travel_beats])

## 다음에 스폰할 노트가 도착해야 하는 박(곡 시작 기준).
func _next_hit_beat() -> float:
	return _next_loop * _conductor.loop_beats + _beatmap[_next_index]

func _advance_index() -> void:
	_next_index += 1
	if _next_index >= _beatmap.size():
		_next_index = 0
		_next_loop += 1
