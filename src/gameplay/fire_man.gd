class_name FireMan
extends Marker2D
## 중앙 캐릭터(불인간). 판정 기준점이자, Miss 시 피격 반응을 한다.

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

## Main이 Miss 판정 시 호출. 빨강 플래시 + 짧은 흔들림.
func take_damage() -> void:
	_sprite.modulate = Color(1.0, 0.3, 0.3)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.3)
	var shake := create_tween()
	shake.tween_property(_sprite, "offset", Vector2(8, 0), 0.04)
	shake.tween_property(_sprite, "offset", Vector2(-8, 0), 0.04)
	shake.tween_property(_sprite, "offset", Vector2.ZERO, 0.04)
