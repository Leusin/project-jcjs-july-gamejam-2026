extends Node2D
## 게임 규칙: 입력을 판정하고, 체력을 깎고, 승패를 정한다.
##
## 곁들이는 두 노드에게 나머지를 맡긴다.
##   Chart      — 언제 어떤 나방이 나오나 (난이도)
##   CanvasLayer(Hud) — 화면에 뭐가 보이나 (표시)
##   Conductor  — 지금 곡의 몇 초인가 (시계)

enum Judgement { NONE, PERFECT, GOOD, MISS }

@export_group("판정 (초 단위 오차 허용범위)")
## 이 안에 들어오면 Perfect.
@export var perfect_window: float = 0.07
## 이 안에 들어오면 Good. 이 밖의 입력은 판정 대상이 아니다.
@export var good_window: float = 0.2
## 판정 범위 밖에서 누르면 콤보가 끊긴다. 나방은 죽지 않고 체력도 안 깎인다.
@export var miss_on_bad_tap: bool = true

@export_group("점수")
@export var perfect_score: int = 5
@export var good_score: int = 1

@export_group("생존")
@export var max_health: int = 5
## 한 판의 길이(초). 이만큼 버티면 승리.
@export var song_duration: float = 180.0
## 게임오버 후 이 시간이 지나야 재시작 입력을 받는다(죽인 그 탭으로 바로 재시작되는 것 방지).
@export var restart_delay: float = 1.5

@export_group("디버그 치트")
## ₩ 키로도 켜고 끌 수 있다. 켜면 체력이 안 깎인다.
@export var invincible: bool = false
## 이 구간부터 시작한다(0 = 1구간). 사인파는 2, 한바퀴 나방은 3으로 두면 바로 보인다.
@export var start_stage: int = 0
## 헛손질할 때도 가장 가까운 노트와의 오차를 찍는다. manual_offset 보정의 핵심 정보.
@export var log_bad_taps: bool = true
## 판정 범위를 레인 위에 띠로 표시한다. 평소엔 끄고, 필요할 때 D 키로 켠다.
@export var show_judgement_range: bool = false

const NoteScene := preload("res://src/gameplay/note.tscn")

@onready var _spawn_points: Array = $SpawnPoints.get_children()
@onready var _hit_point: FireMan = $HitPoint
@onready var _conductor: Conductor = $Conductor
@onready var _chart: Chart = $Chart
@onready var _hud: Hud = $CanvasLayer

## 화면에 떠 있는, 아직 판정되지 않은 노트들.
var _notes: Array[Note] = []

var _health: int = 0
var _combo: int = 0
var _max_combo: int = 0
var _score: int = 0
var _counts := { Judgement.PERFECT: 0, Judgement.GOOD: 0, Judgement.MISS: 0 }

var _game_over: bool = false
var _game_over_at: float = 0.0
## 시작 버튼을 누르기 전에는 곡도 노트도 돌지 않는다.
var _playing: bool = false

## 한 번이라도 시작했으면 재시작 때 타이틀을 건너뛴다.
## static이라 씬을 다시 불러도 값이 남는다.
static var _seen_title: bool = false

func _ready() -> void:
	_health = max_health
	_refresh_hud()
	_hud.start_pressed.connect(_begin_play)
	if _seen_title:
		_hud.skip_title()
		_begin_play()

## 곡을 시작한다. 웹에서는 반드시 사용자 클릭 이후여야 소리가 난다.
func _begin_play() -> void:
	_seen_title = true
	_playing = true
	_conductor.start_song()
	_chart.begin(_conductor, start_stage)

func _process(_delta: float) -> void:
	if not _playing or _game_over:
		return
	if _conductor.song_position >= song_duration:
		_end_game(true)
		return
	for due in _chart.take_due_notes():
		_spawn_note(due["hit_beat"], due["style"])
	_drop_passed_notes()
	_hud.update_time_left(song_duration - _conductor.song_position)

func _unhandled_input(event: InputEvent) -> void:
	if _is_cheat_key(event):
		invincible = not invincible
		_hud.flash("무적 %s" % ("ON" if invincible else "OFF"), Color(0.6, 0.8, 1.0))
		_refresh_hud()
		return

	if _is_key(event, KEY_D):
		show_judgement_range = not show_judgement_range
		_hud.flash("판정 범위 %s" % ("ON" if show_judgement_range else "OFF"), Color(0.8, 0.8, 0.8))
		return

	if not _is_tap(event):
		return

	# 타이틀 화면에서는 시작 버튼만 받는다.
	if not _playing:
		return

	if _game_over:
		# 게임오버 화면에서는 탭이 재시작이다.
		if Time.get_ticks_msec() / 1000.0 - _game_over_at >= restart_delay:
			get_tree().reload_current_scene()
		return

	var note := _closest_note()
	if note == null:
		_on_bad_tap()
		return

	# 부호 있는 오차: 음수면 일찍 누른 것, 양수면 늦게 누른 것.
	var signed_error := _conductor.song_position - note.hit_time
	if absf(signed_error) > good_window:
		_on_bad_tap()
		return

	_notes.erase(note)
	if absf(signed_error) <= perfect_window:
		_score += perfect_score
		_on_success(note, Judgement.PERFECT, signed_error)
	else:
		_score += good_score
		_on_success(note, Judgement.GOOD, signed_error)

# ---------------------------------------------------------------- 노트

func _spawn_note(hit_beat: float, style: int) -> void:
	var note: Note = NoteScene.instantiate()
	add_child(note)
	var lane := randi() % _spawn_points.size()
	var spawn: Marker2D = _spawn_points[lane]
	note.lane = lane
	note.style = style as Note.Style
	note.setup(
		_conductor,
		spawn.global_position,
		_hit_point.global_position,
		hit_beat * _conductor.sec_per_beat,
		_chart.travel_beats * _conductor.sec_per_beat
	)
	_notes.append(note)

## 판정 시각을 지나쳐버린 노트를 미스 처리한다.
func _drop_passed_notes() -> void:
	for note in _notes.duplicate():
		if _conductor.song_position > note.hit_time + good_window:
			_notes.erase(note)
			_on_miss(note)

## 지금 시각에 가장 가까운 노트. 없으면 null.
func _closest_note() -> Note:
	var best: Note = null
	var best_error := INF
	for note in _notes:
		var error := absf(_conductor.song_position - note.hit_time)
		if error < best_error:
			best_error = error
			best = note
	return best

# ---------------------------------------------------------------- 판정 결과

func _on_success(note: Note, judgement: Judgement, signed_error: float) -> void:
	note.burn()   # burn()이 끝나면 스스로 사라진다
	_counts[judgement] += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_refresh_hud()
	if judgement == Judgement.PERFECT:
		_hud.flash("PERFECT", Color(0.4, 1.0, 0.5))
	else:
		_hud.flash("GOOD", Color(1.0, 0.9, 0.4))
	print("%s  (오차 %+.3f초, 콤보 %d)" % [Judgement.keys()[judgement], signed_error, _combo])

func _on_miss(note: Note) -> void:
	_counts[Judgement.MISS] += 1
	_combo = 0
	if not invincible:
		_health -= 1
	_hit_point.take_damage()
	note.fall()   # fall()이 끝나면 스스로 사라진다
	_refresh_hud()
	_hud.flash("MISS", Color(1.0, 0.4, 0.4))
	print("MISS  (남은 체력 %d)" % _health)
	if _health <= 0:
		_end_game(false)

## 판정 범위 밖의 헛손질. 나방은 죽지 않고 체력도 안 깎이지만 콤보는 끊긴다.
func _on_bad_tap() -> void:
	# 오프셋 보정용: 눌렀을 때 가장 가까운 노트가 얼마나 어긋나 있었는지 남긴다.
	if log_bad_taps:
		var near := _closest_note()
		if near == null:
			print("헛손질 (근처에 노트 없음)")
		else:
			print("헛손질 (가장 가까운 노트와 %+.3f초 — 음수면 너무 일찍)"
				% (_conductor.song_position - near.hit_time))
	if not miss_on_bad_tap or _combo == 0:
		return
	_combo = 0
	_refresh_hud()

# ---------------------------------------------------------------- 승패

func _end_game(won: bool) -> void:
	_game_over = true
	_game_over_at = Time.get_ticks_msec() / 1000.0
	_conductor.stop_song()

	for note in _notes:
		if is_instance_valid(note):
			note.queue_free()
	_notes.clear()

	if won:
		_hit_point.celebrate()
	else:
		_hit_point.extinguish()

	var headline := "날이 밝았다" if won else "불이 꺼졌다"
	_hud.show_result("%s\n\nSCORE %06d\n최대 콤보 %d\nPERFECT %d   GOOD %d   MISS %d\n\n탭하면 다시 시작" % [
		headline, _score, _max_combo,
		_counts[Judgement.PERFECT], _counts[Judgement.GOOD], _counts[Judgement.MISS]
	])

# ---------------------------------------------------------------- 입력·표시

func _refresh_hud() -> void:
	_hud.update_stats(_score, _combo, _health, max_health, invincible)

## ₩ 키로 무적을 켜고 끈다.
## ₩는 백슬래시와 같은 자리라, 한글/영문 입력 상태를 안 타도록 물리 위치와 문자 둘 다 본다.
func _is_cheat_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return key.physical_keycode == KEY_BACKSLASH or key.unicode == 0x20A9

## 자판 배열이나 입력기(한/영)에 안 흔들리도록 물리 키 위치로 본다.
## F 키는 쓰지 않는다 — macOS가 밝기·볼륨으로, 브라우저가 도움말로 먼저 가로챈다.
func _is_key(event: InputEvent, physical_code: Key) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.physical_keycode == physical_code

func _is_tap(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	return false

## 판정 범위 띠의 좌표를 계산한다. 그리는 것은 JudgementOverlay가 한다
## (여기서 그리면 불인간 조명 아래에 깔려 안 보인다).
##
## 판정은 시간(±window초)으로 하는데 레인마다 길이가 달라 속도가 다르다.
## 그래서 같은 시간 창이라도 레인마다 **길이가 다른 띠**가 된다.
## 띠는 중앙을 가운데 두고 양옆으로 뻗는다 — 아직 도착 전(바깥)과 이미 지나침(안쪽) 둘 다 유효하므로.
func judgement_bands() -> Array:
	var bands: Array = []
	if not show_judgement_range or _hit_point == null or _conductor == null:
		return bands
	var travel_time := _chart.travel_beats * _conductor.sec_per_beat
	if travel_time <= 0.0:
		return bands
	var center := _hit_point.global_position
	for spawn in _spawn_points:
		var to_spawn: Vector2 = spawn.global_position - center
		var dir := to_spawn.normalized()
		var speed := to_spawn.length() / travel_time   # 이 레인의 픽셀/초
		var good_len := good_window * speed
		var perfect_len := perfect_window * speed
		bands.append({
			"a": center + dir * good_len, "b": center - dir * good_len,
			"color": Color(1.0, 0.85, 0.2, 0.45),
		})
		bands.append({
			"a": center + dir * perfect_len, "b": center - dir * perfect_len,
			"color": Color(0.3, 1.0, 0.45, 0.75),
		})
	return bands
