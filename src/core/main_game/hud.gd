class_name Hud
extends CanvasLayer
## 화면에 보이는 글자를 전부 담당한다.
## 게임 규칙은 모른다 — main.gd가 "이 숫자를 보여줘"라고 시키면 보여줄 뿐이다.

## 시작 버튼을 눌렀을 때. 웹 브라우저는 사용자 입력이 있어야 소리를 허락하므로,
## 이 클릭이 곧 오디오 잠금 해제를 겸한다.
signal start_pressed

@onready var _score_label: Label = $ScoreLabel
@onready var _combo_label: Label = $ComboLabel
@onready var _health_label: Label = $HealthLabel
@onready var _time_label: Label = $TimeLabel
@onready var _judgement_label: Label = $JudgementLabel
@onready var _result_label: Label = $GameOverLabel
@onready var _title_screen: Control = $TitleScreen
@onready var _start_button: Button = $TitleScreen/StartButton

func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	_title_screen.visible = false
	start_pressed.emit()

## 타이틀을 건너뛰고 바로 시작(재시작 때).
func skip_title() -> void:
	_title_screen.visible = false

func update_stats(score: int, combo: int, health: int, max_health: int, invincible: bool) -> void:
	_score_label.text = "SCORE %06d" % score
	_combo_label.text = "COMBO x%d" % combo
	_health_label.text = "HP %d / %d%s" % [health, max_health, "   [무적]" if invincible else ""]

## 얼마나 버텼는지 보여준다. 목표가 있어야 버티는 맛이 난다.
func update_time_left(seconds_left: float) -> void:
	var left := maxf(0.0, seconds_left)
	_time_label.text = "%d:%02d 남음" % [int(left) / 60, int(left) % 60]

## 판정 결과를 화면 중앙에 잠깐 띄운다.
func flash(text: String, color: Color) -> void:
	_judgement_label.text = text
	_judgement_label.modulate = Color(color.r, color.g, color.b, 1.0)
	var t := create_tween()
	t.tween_property(_judgement_label, "modulate:a", 0.0, 0.6).set_delay(0.15)

func show_result(text: String) -> void:
	_result_label.text = text
	_result_label.visible = true
