class_name Hud
extends CanvasLayer
## 화면에 보이는 글자와 HUD 컨트롤을 담당한다.
## 게임 규칙은 모른다 — main.gd가 값과 표시할 문구를 전달한다.

## `practice`는 타이틀에서 연습 모드 체크박스를 켰는지다.
signal start_pressed(practice: bool)
## 결과 화면에서 다시 시작할 때. `practice`는 다음 판에 적용할 모드다.
signal restart_pressed(practice: bool)
## 결과 화면에서 타이틀로 돌아갈 때.
signal title_pressed

const COLOR_PERFECT := Color("b8ff1a")
const COLOR_GOOD := Color("fff23d")
const COLOR_WRONG := Color("ff8a24")
const COLOR_MISS := Color("ff4f70")
const COLOR_HEAL := Color("f6f0ff")
const COLOR_HEAL_ACCENT := Color("ff4f70")
const FRENZY_COMBO_COLORS: Array[Color] = [
	Color("f2e8d5"),
	Color("ff4fbd"),
	Color("b8ff1a"),
	Color("ff6b2c"),
]
const FRENZY_CAPTION_COLORS: Array[Color] = [
	Color("9b9096"),
	Color("d75aa8"),
	Color("87b83e"),
	Color("d95838"),
]

## 꺼진 체력은 같은 머리 스프라이트를 재처럼 식힌 색으로 표시한다.
const HEAD_LIT := Color(1, 1, 1, 1)
const HEAD_DEAD := Color(0.36, 0.30, 0.39, 1)

@onready var _score_label: Label = $ScoreLabel
@onready var _combo_box: VBoxContainer = $ComboBox
@onready var _combo_caption: Label = $ComboBox/ComboCaption
@onready var _combo_label: Label = $ComboBox/ComboLabel
@onready var _health_box: HBoxContainer = $HealthBox
@onready var _practice_badge: Label = $PracticeBadge
@onready var _time_label: Label = $TimeLabel
@onready var _time_bar: ProgressBar = $TimeBar
@onready var _judgement_label: Label = $JudgementLabel

@onready var _title_screen: Control = $TitleScreen
@onready var _subtitle_label: Label = $TitleScreen/Layout/SubtitleLabel
@onready var _start_button: Button = $TitleScreen/Layout/StartButton
@onready var _practice_check: CheckBox = $TitleScreen/Layout/PracticeCheck

@onready var _result_screen: Control = $ResultScreen
@onready var _headline_label: Label = $ResultScreen/Layout/ResultGroup/HeadGroup/HeadlineLabel
@onready var _practice_note: Label = $ResultScreen/Layout/ResultGroup/HeadGroup/PracticeNote
@onready var _stats_label: Label = $ResultScreen/Layout/ResultGroup/StatsLabel
@onready var _judge_label: RichTextLabel = $ResultScreen/Layout/ResultGroup/JudgeLabel
@onready var _restart_button: Button = $ResultScreen/Layout/RestartButton
@onready var _next_practice_check: CheckBox = $ResultScreen/Layout/FooterGroup/NextPracticeCheck
@onready var _title_button: Button = $ResultScreen/Layout/FooterGroup/TitleButton

var _flash_tween: Tween
var _health_tween: Tween
var _subtitle_tween: Tween
var _combo_tween: Tween
var _flames: Array[TextureRect] = []
var _frenzy_stage: int = 0
var _last_combo: int = 0
var _skip_next_combo_pulse: bool = false
## 타이틀·결과 화면에서는 false. update_stats가 숨긴 HUD를 되살리지 않게 한다.
var _game_hud_shown: bool = false


func _ready() -> void:
	for child in _health_box.get_children():
		if child is TextureRect:
			_flames.append(child)

	_start_button.pressed.connect(_on_start_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_title_button.pressed.connect(_on_title_pressed)
	_combo_box.offset_transform_enabled = true
	_combo_box.offset_transform_pivot_ratio = Vector2(1.0, 0.5)
	_set_game_hud_visible(false)
	pulse_subtitle()


func _on_start_pressed() -> void:
	var practice := _practice_check.button_pressed
	_hide_title()
	start_pressed.emit(practice)


func _on_restart_pressed() -> void:
	restart_pressed.emit(_next_practice_check.button_pressed)


func _on_title_pressed() -> void:
	title_pressed.emit()


## 타이틀을 건너뛰고 바로 시작한다(재시작 때).
func skip_title() -> void:
	_hide_title()


## 포커스가 남으면 플레이 중 Space가 버튼이나 체크박스에 다시 들어간다.
func _hide_title() -> void:
	_start_button.release_focus()
	_practice_check.release_focus()
	_title_screen.visible = false
	_set_game_hud_visible(true)
	if _subtitle_tween != null and _subtitle_tween.is_valid():
		_subtitle_tween.kill()


func _set_game_hud_visible(shown: bool) -> void:
	_game_hud_shown = shown
	_score_label.visible = shown
	_health_box.visible = shown
	_time_label.visible = shown
	_time_bar.visible = shown
	# 콤보와 연습 배지는 update_stats가 조건에 따라 다시 켠다.
	if not shown:
		_combo_box.visible = false
		_practice_badge.visible = false


func update_stats(score: int, combo: int,
		health: int, max_health: int, invincible: bool) -> void:
	_score_label.text = "SCORE %06d" % score
	_combo_box.visible = _game_hud_shown and combo > 0
	_combo_label.text = "x%d" % combo
	_practice_badge.visible = _game_hud_shown and invincible
	if combo > _last_combo and _frenzy_stage > 0 and not _skip_next_combo_pulse:
		_pulse_combo(1.04 + _frenzy_stage * 0.025)
	_skip_next_combo_pulse = false
	_last_combo = combo

	for i in _flames.size():
		_flames[i].visible = i < max_health
		_flames[i].modulate = HEAD_LIT if i < health else HEAD_DEAD


func set_frenzy_stage(stage: int, rising: bool) -> void:
	stage = clampi(stage, 0, FRENZY_COMBO_COLORS.size() - 1)
	if stage == _frenzy_stage:
		return
	_frenzy_stage = stage
	_combo_label.add_theme_color_override("font_color", FRENZY_COMBO_COLORS[stage])
	_combo_caption.add_theme_color_override("font_color", FRENZY_CAPTION_COLORS[stage])
	if rising and _game_hud_shown:
		_skip_next_combo_pulse = true
		_pulse_combo(1.12 + stage * 0.06)


func _pulse_combo(amount: float) -> void:
	if _combo_tween != null and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_box.offset_transform_scale = Vector2.ONE * amount
	_combo_tween = create_tween()
	_combo_tween.tween_property(
		_combo_box,
		"offset_transform_scale",
		Vector2.ONE,
		0.18
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 바가 주 표시이고 숫자는 보조다.
func update_time_left(seconds_left: float, total: float) -> void:
	var left := maxf(0.0, seconds_left)
	_time_label.text = "%d:%02d 남음" % [int(left) / 60, int(left) % 60]
	_time_bar.value = 0.0 if total <= 0.0 else left / total * 100.0


## 판정마다 크기를 다르게 주되 문구에는 점수 계산을 섞지 않는다.
func flash(text: String, color: Color, size: int = 44) -> void:
	_judgement_label.add_theme_font_size_override("font_size", size)
	_judgement_label.text = text
	_judgement_label.modulate = Color(color.r, color.g, color.b, 1.0)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	# 원색을 잠깐 유지한 뒤 빠르게 지워 어두운 잔상이 오래 남지 않게 한다.
	_flash_tween.tween_interval(0.3)
	_flash_tween.tween_property(_judgement_label, "modulate:a", 0.0, 0.18)


func pulse_health() -> void:
	if _health_tween != null and _health_tween.is_valid():
		_health_tween.kill()
	_health_box.modulate = COLOR_HEAL_ACCENT
	_health_tween = create_tween()
	_health_tween.tween_property(_health_box, "modulate", Color.WHITE, 0.5)


func pulse_subtitle() -> void:
	_subtitle_label.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	if _subtitle_tween != null and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	_subtitle_tween = create_tween().set_loops()
	_subtitle_tween.tween_property(
		_subtitle_label,
		"offset_transform_scale",
		Vector2(1.06, 1.06), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_subtitle_tween.tween_property(
		_subtitle_label,
		"offset_transform_scale",
		Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## `practice`는 방금 친 판의 모드이며 다음 판 체크박스의 초기값이 된다.
## `input_delay` 동안 버튼을 잠가 마지막 탭이 재시작 버튼까지 누르지 않게 한다.
func show_result(headline: String, stats: String,
		perfect: int, good: int, miss: int,
		practice: bool, input_delay: float) -> void:
	_set_game_hud_visible(false)
	_headline_label.text = headline
	_stats_label.text = stats
	_judge_label.text = "[center][color=#%s]PERFECT %d[/color]   ·   [color=#%s]GOOD %d[/color]   ·   [color=#%s]MISS %d[/color][/center]" % [
		COLOR_PERFECT.to_html(false), perfect,
		COLOR_GOOD.to_html(false), good,
		COLOR_MISS.to_html(false), miss,
	]
	_practice_note.visible = practice
	_next_practice_check.button_pressed = practice
	_restart_button.disabled = true
	_title_button.disabled = true
	_result_screen.visible = true

	await get_tree().create_timer(input_delay).timeout
	if not is_instance_valid(_restart_button):
		return

	_restart_button.disabled = false
	_title_button.disabled = false
	_restart_button.grab_focus()
