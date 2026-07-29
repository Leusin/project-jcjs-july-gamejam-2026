class_name BackgroundPassers
extends Sprite2D
## 거대한 관절나방 2인조가 게임 뒤편을 끝없이 횡단한다.
## 장식 전용이며 판정·게임 상태에는 관여하지 않는다.

const FRENZY_COLORS: Array[Color] = [
	Color(0.38, 0.30, 0.72, 0.14),
	Color(0.72, 0.18, 0.86, 0.22),
	Color(0.55, 0.88, 0.20, 0.28),
	Color(1.00, 0.22, 0.12, 0.34),
]
const FRENZY_SPEEDS: Array[float] = [1.0, 1.18, 1.42, 1.8]
const FRENZY_WOBBLES: Array[float] = [1.0, 1.2, 1.5, 1.9]

@export var speed: float = 72.0
@export var wrap_margin: float = 260.0
@export var vertical_wobble: float = 18.0
@export var wobble_speed: float = 1.4

var _start_y: float
var _elapsed: float = 0.0
var _frenzy_stage: int = 0
var _stage_color: Color = FRENZY_COLORS[0]
var _color_tween: Tween

func _ready() -> void:
	_start_y = position.y

func _process(delta: float) -> void:
	_elapsed += delta
	position.x += speed * FRENZY_SPEEDS[_frenzy_stage] * delta
	position.y = (
		_start_y
		+ sin(_elapsed * wobble_speed * FRENZY_WOBBLES[_frenzy_stage])
		* vertical_wobble
		* FRENZY_WOBBLES[_frenzy_stage]
	)
	var breath := (
		1.0
		+ sin(_elapsed * (1.2 + _frenzy_stage * 0.7))
		* (0.02 + _frenzy_stage * 0.025)
	)
	modulate = Color(
		_stage_color.r,
		_stage_color.g,
		_stage_color.b,
		clampf(_stage_color.a * breath, 0.0, 1.0)
	)

	var half_width := texture.get_width() * absf(scale.x) * 0.5 if texture != null else 0.0
	var viewport_width := get_viewport_rect().size.x
	if position.x - half_width > viewport_width + wrap_margin:
		position.x = -half_width - wrap_margin


func set_frenzy_stage(stage: int) -> void:
	stage = clampi(stage, 0, FRENZY_COLORS.size() - 1)
	if stage == _frenzy_stage:
		return
	_frenzy_stage = stage
	if _color_tween != null and _color_tween.is_valid():
		_color_tween.kill()
	_color_tween = create_tween()
	_color_tween.tween_method(
		func(color: Color) -> void: _stage_color = color,
		_stage_color,
		FRENZY_COLORS[stage],
		0.24
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
