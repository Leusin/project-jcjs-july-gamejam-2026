extends Node2D
## 게임 규칙: 입력을 판정하고, 체력을 깎고, 승패를 정한다.
##
## 곁들이는 두 노드에게 나머지를 맡긴다.
##   Chart      — 언제 어떤 나방이 나오나 (난이도)
##   CanvasLayer(Hud) — 화면에 뭐가 보이나 (표시)
##   Conductor  — 지금 곡의 몇 초인가 (시계)

## 나방이 날아오는 방향. 입력과는 무관하다 —
## 어느 쪽에서 오든 탭 하나로 판정한다. 스폰 위치를 고르는 데만 쓴다.
enum Lane { UP, DOWN, LEFT, RIGHT }
enum Judgement { NONE, PERFECT, GOOD, MISS }

@export_group("판정 (초 단위 오차 허용범위)")
## 이 안에 들어오면 Perfect.
@export var perfect_window: float = 0.07
## 이 안에 들어오면 Good. 이 밖의 입력은 판정 대상이 아니다.
@export var good_window: float = 0.2
## 칠 노트가 없는데 눌렀을 때 콤보에서 깎을 양. 0이면 헛손질에 벌이 없다.
## 버튼이 하나뿐이라, 헛손질이 공짜면 계속 누르고 있는 것이 최적 전략이 되어버린다.
## 체력은 깎지 않는다 — 연타만 손해가 되게 하되 초보자를 죽이지는 않는 선.
## 0으로 밀지 않고 조금씩 깎는 이유: 불인간의 춤 단계가 계단식이라 한 칸씩 내려와야 읽힌다.
@export var bad_tap_combo_penalty: int = 1

@export_group("점수")
@export var perfect_score: int = 5
@export var good_score: int = 1

@export_group("생존")
@export var max_health: int = 5
## 새 나방이 회복 나방으로 나올 확률. 체력이 가득 차 있으면 아예 뽑지 않는다.
@export_range(0.0, 1.0) var heal_chance: float = 0.08
## 회복 나방을 맞혔을 때 돌아오는 체력.
@export var heal_amount: int = 1
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

const NoteScene := preload("res://src/gameplay/note.tscn")

@onready var _spawn_points: Array = [
	$SpawnPoints/SpawnTop,     # Lane.UP
	$SpawnPoints/SpawnBottom,  # Lane.DOWN
	$SpawnPoints/SpawnLeft,    # Lane.LEFT
	$SpawnPoints/SpawnRight,   # Lane.RIGHT
]
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
	_hit_point.sync_dance(_conductor.is_playing)
	_hud.update_time_left(song_duration - _conductor.song_position)

func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
		
	if _is_cheat_key(event):
		invincible = not invincible
		_hud.flash("무적 %s" % ("ON" if invincible else "OFF"), Color(0.6, 0.8, 1.0))
		_refresh_hud()
		return
		
	if not _is_tap(event):
		return

	# 판정과 재시작이 같은 탭을 쓴다.
	# 죽인 그 탭으로 곧바로 재시작되지 않도록 restart_delay가 사이를 벌려준다.
	if _game_over:
		if Time.get_ticks_msec() / 1000.0 - _game_over_at >= restart_delay:
			get_tree().reload_current_scene()
		return

	_hit_point.on_tap()
	_judge()

## 지금 시각에 가장 가까운 노트를 판정한다.
## 방향은 보지 않는다 — 어디서 오든 탭 하나가 전부다.
func _judge() -> void:
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
	note.style = style as Note.Style
	if _health < max_health and randf() < heal_chance:
		note.kind = Note.Kind.HEAL
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
	if _game_over:
		return
		
	for note in _notes.duplicate():
		if _game_over:
			return
		
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
	# 회복 나방은 태우지 않는다 — 구하러 온 놈이라 승천시킨다.
	if note.kind == Note.Kind.HEAL:
		note.ascend()
	else:
		note.burn()   # 둘 다 연출이 끝나면 스스로 사라진다
	_counts[judgement] += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	if note.kind == Note.Kind.HEAL:
		_health = mini(_health + heal_amount, max_health)
	_refresh_hud()
	if note.kind == Note.Kind.HEAL:
		_hud.flash("HEAL +%d" % heal_amount, Hud.COLOR_HEAL)
		_hud.pulse_health()
	elif judgement == Judgement.PERFECT:
		_hud.flash("PERFECT", Hud.COLOR_PERFECT)
		_hit_point.on_perfect()   # 잠깐 팔다리를 흩뜨린다
	else:
		_hud.flash("GOOD", Hud.COLOR_GOOD)
	print("%s  (오차 %+.3f초, 콤보 %d)" % [Judgement.keys()[judgement], signed_error, _combo])

func _on_miss(note: Note) -> void:
	# 회복 나방은 놓쳐도 벌하지 않는다. 구하러 온 나방이 도리어 아프게 하면 이상하다.
	# 회복 기회를 날린 것으로 이미 충분한 손해다.
	if note.kind == Note.Kind.HEAL:
		note.fall()
		return

	_counts[Judgement.MISS] += 1
	_combo = 0
	if not invincible:
		_health -= 1
	_hit_point.take_damage()
	note.fall()   # fall()이 끝나면 스스로 사라진다
	_refresh_hud()
	_hud.flash("MISS", Hud.COLOR_MISS)
	print("MISS  (남은 체력 %d)" % _health)
	if _health <= 0:
		_end_game(false)

## 칠 노트가 없을 때 누른 입력. 체력은 깎지 않고 콤보만 끊는다.
func _on_bad_tap() -> void:
	# 오프셋 보정용: 눌렀을 때 가장 가까운 노트가 얼마나 어긋나 있었는지 남긴다.
	if log_bad_taps:
		var near := _closest_note()
		if near == null:
			print("헛손질 (근처에 노트 없음)")
		else:
			print("헛손질 (가장 가까운 노트와 %+.3f초 — 음수면 너무 일찍)"
				% (_conductor.song_position - near.hit_time))

	# 이미 0인 콤보를 또 깎았다고 알리지 않는다 — 조용히 넘어가는 편이 덜 시끄럽다.
	if bad_tap_combo_penalty > 0 and _combo > 0:
		_combo = maxi(0, _combo - bad_tap_combo_penalty)
		_refresh_hud()
		_hud.flash("빗나감", Hud.COLOR_WRONG)

# ---------------------------------------------------------------- 승패

func _end_game(won: bool) -> void:
	if _game_over:
		print("게임은 이미 종료했습니다.")
		return
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
	# 콤보가 오를수록 불인간의 머리가 커진다. 약중강을 따로 그리는 대신 같은 그림을 키운다.
	_hit_point.set_combo(_combo)

## ₩ 키로 무적을 켜고 끈다.
## ₩는 백슬래시와 같은 자리라, 한글/영문 입력 상태를 안 타도록 물리 위치와 문자 둘 다 본다.
func _is_cheat_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return key.physical_keycode == KEY_BACKSLASH or key.unicode == 0x20A9
	
## 이 게임의 유일한 입력. 스페이스·엔터(ui_accept)와 좌클릭을 하나로 본다.
## 키를 꾹 누르고 있을 때 들어오는 echo는 거른다 — 안 거르면 누르고만 있어도 연타가 된다.
func _is_tap(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return false
