class_name FireMan
extends Marker2D
## 중앙 캐릭터(불인간). 판정 기준점이자, Miss 시 피격 반응을 한다.

@onready var _character_sprite: AnimatedSprite2D = $AnimatedSprite2D

@onready var _light: Sprite2D = $LightSprite2D
@onready var _shadow: Sprite2D = $ShadowSprite2D

var _flicker_t: float = 0.0
var _light_base: Vector2
var _shadow_base: Vector2

## Main이 Miss 판정 시 호출. 빨강 플래시 + 짧은 흔들림.
func take_damage() -> void:
	_character_sprite.modulate = Color(1.0, 0.3, 0.3)
	create_tween().tween_property(_character_sprite, "modulate", Color.WHITE, 0.3)
	var shake := create_tween()
	shake.tween_property(_character_sprite, "offset", Vector2(16, 0), 0.04)
	shake.tween_property(_character_sprite, "offset", Vector2(-16, 0), 0.04)
	shake.tween_property(_character_sprite, "offset", Vector2.ZERO, 0.04)

func _ready() -> void:
	_light_base = _light.scale
	_shadow_base = _shadow.scale

func _process(delta: float) -> void:
	_flicker_t += delta
	# 주파수 다른 sin 둘을 섞어 불규칙한 불꽃 일렁임
	var wobble := 0.04 * sin(_flicker_t * 7.0) + 0.08 * sin(_flicker_t * 1.0)
	_light.scale = _light_base * (1.0 + wobble)
	_shadow.scale = _shadow_base * (1.0 - wobble)   # 빛 커지면 그림자 살짝 줄게
	
