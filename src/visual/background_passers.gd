extends Sprite2D
## 거대한 관절나방 2인조가 게임 뒤편을 끝없이 횡단한다.
## 장식 전용이며 판정·게임 상태에는 관여하지 않는다.

@export var speed: float = 72.0
@export var wrap_margin: float = 260.0
@export var vertical_wobble: float = 18.0
@export var wobble_speed: float = 1.4

var _start_y: float
var _elapsed: float = 0.0

func _ready() -> void:
	_start_y = position.y

func _process(delta: float) -> void:
	_elapsed += delta
	position.x += speed * delta
	position.y = _start_y + sin(_elapsed * wobble_speed) * vertical_wobble

	var half_width := texture.get_width() * absf(scale.x) * 0.5 if texture != null else 0.0
	var viewport_width := get_viewport_rect().size.x
	if position.x - half_width > viewport_width + wrap_margin:
		position.x = -half_width - wrap_margin
