extends Node2D

enum Lane { UP, DOWN, LEFT, RIGHT }
enum Judgement { NONE, PERFECT, GOOD, MISS }

const NoteScene := preload("res://src/gameplay/note.tscn")

@export_group("판정 (초 단위 오차 허용범위)")
@export var perfect_window: float = 0.07
@export var good_window: float = 0.2
@export var bad_tap_combo_penalty: int = 1

@export_group("점수")
@export var perfect_score: int = 5
@export var good_score: int = 1

@export_group("생존")
@export var max_health: int = 3
@export_range(0.0, 1.0) var heal_chance: float = 0.08
@export var heal_amount: int = 1
## 음악은 반복하지 않으며, 플레이는 정확히 90초에 끝난다.
@export var song_duration: float = 90.0
## 게임오버 후 이 시간이 지나야 결과 화면 버튼이 살아난다(죽인 그 탭으로 바로 재시작되는 것 방지).
@export var restart_delay: float = 1.5

@export_group("디버그 치트")
@export var invincible: bool = false
@export var start_stage: int = 0
@export var log_bad_taps: bool = true

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
@onready var _debug_overlay: CanvasLayer = $DebugOverlay
@onready var _title_neon_hum: AudioStreamPlayer = $Audio/TitleNeonHum
@onready var _ignite_sound: AudioStreamPlayer = $Audio/IgniteSound
@onready var _miss_sound: AudioStreamPlayer = $Audio/MissSound
@onready var _heal_sound: AudioStreamPlayer = $Audio/HealSound

## 재시작은 씬을 통째로 다시 만들기 때문에 static인 값만 살아남는다.
static var _seen_title: bool = false
## 직전 판에서 고른 모드. 재시작할 때 이어받는다.
static var _last_practice: bool = false

## 화면에 떠 있는, 아직 판정되지 않은 노트들.
var _notes: Array[Note] = []

var _health: int = 0
var _combo: int = 0
var _max_combo: int = 0
var _score: int = 0
var _counts := { Judgement.PERFECT: 0, Judgement.GOOD: 0, Judgement.MISS: 0 }

var _playing: bool = false
var _game_over: bool = false


func _ready() -> void:
	_health = max_health

	# FPS·버전 표시는 타이틀을 가리지 않게 두었다가 플레이가 시작되면 되돌린다.
	_debug_overlay.visible = false

	_refresh_hud()
	_hud.start_pressed.connect(_begin_play)
	_hud.restart_pressed.connect(_on_restart_pressed)
	_hud.title_pressed.connect(_on_title_pressed)

	if _seen_title:
		_hud.skip_title()
		_begin_play(_last_practice)
	else:
		var neon_stream := _title_neon_hum.stream as AudioStreamMP3
		if neon_stream != null:
			neon_stream.loop = true
		_title_neon_hum.play()

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
	_hud.update_time_left(song_duration - _conductor.song_position, song_duration)

func _unhandled_input(event: InputEvent) -> void:
	# 게임오버 뒤의 입력은 전부 무시한다 — 재시작은 결과 화면 버튼으로만 한다.
	# 치트 키까지 막아야 결과 화면 위로 플레이용 HUD가 되살아나지 않는다.
	if not _playing or _game_over:
		return

	if _is_cheat_key(event):
		invincible = not invincible
		_hud.flash("무적 %s" % ("ON" if invincible else "OFF"), Color(0.6, 0.8, 1.0))
		_refresh_hud()
		return

	if _is_tap(event):
		_hit_point.on_tap()
		_judge()

func _begin_play(practice: bool) -> void:
	_seen_title = true
	_title_neon_hum.stop()
	_last_practice = practice
	invincible = practice
	_playing = true
	_debug_overlay.visible = true
	_refresh_hud()
	_conductor.start_song()
	_chart.begin(_conductor, start_stage, song_duration)

func _on_restart_pressed(practice: bool) -> void:
	_last_practice = practice
	get_tree().reload_current_scene()

func _on_title_pressed() -> void:
	# 이걸 되돌려야 새 씬이 타이틀을 다시 띄운다.
	_seen_title = false
	get_tree().reload_current_scene()

## 가장 가까운 노트에 대한 타이밍을 판정한다.
func _judge() -> void:
	var closest_note := _closest_note()
	if closest_note == null:
		_on_bad_tap()
		return

	# 음수면 이른 입력, 양수면 늦은 입력이다.
	var signed_time_difference := _conductor.song_position - closest_note.hit_time
	var absolute_time_difference := absf(_conductor.song_position - closest_note.hit_time)
	var is_outside_good_window := absolute_time_difference > good_window
	if is_outside_good_window:
		_on_bad_tap()
		return

	_notes.erase(closest_note)

	var is_perfect := absolute_time_difference <= perfect_window
	if is_perfect:
		_on_success(closest_note,
			Judgement.PERFECT,
			signed_time_difference)
	else:
		_on_success(
			closest_note,
			Judgement.GOOD,
			signed_time_difference
	)

# ---------------------------------------------------------------- 노트

func _spawn_note(hit_beat: float, style: int) -> void:
	var note: Note = NoteScene.instantiate()
	add_child(note)

	note.style = style as Note.Style

	var can_spawn_healing_note := _health < max_health and randf() < heal_chance
	if can_spawn_healing_note:
		note.kind = Note.Kind.HEAL

	var lane_index := randi() % _spawn_points.size()
	var spawn_point: Marker2D = _spawn_points[lane_index]
	var hit_time_seconds := hit_beat * _conductor.sec_per_beat
	var travel_time_seconds := _chart.travel_beats * _conductor.sec_per_beat
	note.setup(_conductor,
		spawn_point.global_position,
		_hit_point.global_position,
		hit_time_seconds,
		travel_time_seconds)

	_notes.append(note)

func _drop_passed_notes() -> void:
	if _game_over:
		return

	var notes_to_check := _notes.duplicate()
	for note: Note in notes_to_check:
		if _game_over:
			return

		var judgement_deadline := note.hit_time + good_window
		var has_missed_deadline := _conductor.song_position > judgement_deadline
		if not has_missed_deadline:
			continue
		else:
			_notes.erase(note)
			_on_miss(note)

## 지금 시각에 가장 가까운 노트. 없으면 null.
func _closest_note() -> Note:
	var closest_note: Note = null
	var closest_time_difference := INF
	for note in _notes:
		var time_difference := absf(_conductor.song_position - note.hit_time)
		if time_difference < closest_time_difference:
			closest_note = note
			closest_time_difference = time_difference
	return closest_note

# ---------------------------------------------------------------- 판정 결과

func _on_success(note: Note, judgement: Judgement, signed_error: float) -> void:
	# 회복 나방은 태우지 않는다 — 구하러 온 놈이라 승천시킨다.
	if note.kind == Note.Kind.HEAL:
		note.ascend()
		_heal_sound.play()
	else:
		note.burn()   # 둘 다 연출이 끝나면 스스로 사라진다
		_ignite_sound.play()
	_counts[judgement] += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	var multiplier := _score_multiplier(_combo)
	var base_score := perfect_score if judgement == Judgement.PERFECT else good_score
	var earned_score := base_score * multiplier
	_score += earned_score
	if note.kind == Note.Kind.HEAL:
		_health = mini(_health + heal_amount, max_health)
	_refresh_hud()
	if note.kind == Note.Kind.HEAL:
		_hud.flash("HEAL +%d" % heal_amount, Hud.COLOR_HEAL, 42)
		_hud.pulse_health()
	elif judgement == Judgement.PERFECT:
		_hud.flash("PERFECT", Hud.COLOR_PERFECT, 60)
		_hit_point.on_perfect()   # 잠깐 팔다리를 흩뜨린다
	else:
		_hud.flash("GOOD", Hud.COLOR_GOOD, 40)
	print("%s +%d (배율 x%d, 오차 %+.3f초, 콤보 %d)" % [
		Judgement.keys()[judgement],
		earned_score,
		multiplier,
		signed_error,
		_combo
	])

func _on_miss(note: Note) -> void:
	if note.kind == Note.Kind.HEAL:
		note.fall()
		return

	_miss_sound.play()

	_counts[Judgement.MISS] += 1
	_combo = 0
	if not invincible:
		_health -= 1
	_hit_point.take_damage()
	note.fall()   # fall()이 끝나면 스스로 사라진다
	_refresh_hud()
	_hud.flash("MISS", Hud.COLOR_MISS, 52)
	print("MISS  (남은 체력 %d)" % _health)
	if _health <= 0:
		_end_game(false)

## 칠 노트가 없을 때 누른 입력. 체력은 깎지 않고 콤보만 끊는다.
func _on_bad_tap() -> void:
	if log_bad_taps:
		var near := _closest_note()
		if near == null:
			print("헛손질 (근처에 노트 없음)")
		else:
			print("헛손질 (가장 가까운 노트와 %+.3f초 — 음수면 너무 일찍)"
				% (_conductor.song_position - near.hit_time))

	# 이미 0인 콤보를 또 깎았다고 알리지 않는다
	if bad_tap_combo_penalty > 0 and _combo > 0:
		_combo = maxi(0, _combo - bad_tap_combo_penalty)
		_refresh_hud()
		_hud.flash("빗나감", Hud.COLOR_WRONG, 32)

# ---------------------------------------------------------------- 승패

func _end_game(won: bool) -> void:
	if _game_over:
		print("게임은 이미 종료했습니다.(_end_game)")
		return
	_game_over = true
	# 타이틀과 마찬가지로 결과 화면에도 개발용 표시를 남기지 않는다.
	_debug_overlay.visible = false
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
	var stats := "SCORE %06d\nMAX COMBO %d" % [_score, _max_combo]
	# 판정 개수는 hud가 판정 색을 입혀 따로 그린다. 연습 판이면 '연습 기록' 표시도 함께 켠다.
	_hud.show_result(headline, stats,
		_counts[Judgement.PERFECT],
		_counts[Judgement.GOOD],
		_counts[Judgement.MISS],
		invincible, restart_delay)

# ---------------------------------------------------------------- 입력·표시

## 광란 연출 단계와 같은 콤보 문턱을 사용한다.
func _score_multiplier(combo: int) -> int:
	if combo >= 50:
		return 4
	if combo >= 30:
		return 3
	if combo >= 10:
		return 2
	return 1

func _refresh_hud() -> void:
	_hud.update_stats(_score, _combo, _health, max_health, invincible)
	_hit_point.set_combo(_combo)

## ₩ 키로 무적을 켜고 끈다.
func _is_cheat_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null:
		return false

	return (
		key.pressed
		and not key.echo
		and (
			key.physical_keycode == KEY_BACKSLASH
			or key.unicode == 0x20A9 # ₩
		)
	)

func _is_tap(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null:
		return (
			key.pressed
			and not key.echo
			and key.physical_keycode == KEY_SPACE
		)

	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		return (mouse_button.pressed
			and mouse_button.button_index == MOUSE_BUTTON_LEFT)

	return false
