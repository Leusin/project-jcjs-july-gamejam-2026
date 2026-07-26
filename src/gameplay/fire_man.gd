class_name FireMan
extends Marker2D
## 중앙 캐릭터(불인간). 판정 기준점이자, Miss 시 피격 반응을 한다.

@onready var _character_sprite: AnimatedSprite2D = $AnimatedSprite2D

@onready var _light: Sprite2D = $LightSprite2D
@onready var _shadow: Sprite2D = $ShadowSprite2D

## 맞은 순간 짧게 때리는 소리. 메트로놈과 같은 음원을 낮춰 쓴다 —
## 박자 위에서 얻어맞는 게임이라 같은 계열 소리가 오히려 손맛으로 붙는다.
@export var hit_pitch: float = 0.6
@export var hit_volume_db: float = -2.0

var _flicker_t: float = 0.0
var _light_base: Vector2
var _shadow_base: Vector2
var _hit_sound: AudioStreamPlayer

## Main이 Miss 판정 시 호출. 빨강 플래시 + 짧은 흔들림 + 타격음.
func take_damage() -> void:
	_hit_sound.play()
	_character_sprite.modulate = Color(1.0, 0.3, 0.3)
	create_tween().tween_property(_character_sprite, "modulate", Color.WHITE, 0.3)
	var shake := create_tween()
	shake.tween_property(_character_sprite, "offset", Vector2(16, 0), 0.04)
	shake.tween_property(_character_sprite, "offset", Vector2(-16, 0), 0.04)
	shake.tween_property(_character_sprite, "offset", Vector2.ZERO, 0.04)

## 승리 연출: 불길이 크게 타오른다.
func celebrate() -> void:
	var t := create_tween().set_parallel()
	t.tween_property(_light, "scale", _light_base * 2.2, 1.0).set_trans(Tween.TRANS_ELASTIC)
	t.tween_property(_character_sprite, "modulate", Color(1.4, 1.2, 0.8), 1.0)
	_light_base *= 2.2   # 일렁임이 커진 크기를 기준으로 계속되도록

## 게임오버 연출: 불이 서서히 꺼진다.
func extinguish() -> void:
	set_process(false)   # 일렁임 정지
	var t := create_tween().set_parallel()
	t.tween_property(_light, "scale", Vector2.ZERO, 1.2)
	t.tween_property(_shadow, "scale", Vector2.ZERO, 1.2)
	t.tween_property(_character_sprite, "modulate", Color(0.25, 0.25, 0.3), 1.2)

func _ready() -> void:
	_light_base = _light.scale
	_shadow_base = _shadow.scale
	_hit_sound = AudioStreamPlayer.new()
	_hit_sound.stream = load("res://assets/audio/debug_click.wav")
	_hit_sound.pitch_scale = hit_pitch
	_hit_sound.volume_db = hit_volume_db
	add_child(_hit_sound)

func _process(delta: float) -> void:
	_flicker_t += delta
	# 주파수 다른 sin 둘을 섞어 불규칙한 불꽃 일렁임
	var wobble := 0.04 * sin(_flicker_t * 7.0) + 0.08 * sin(_flicker_t * 1.0)
	_light.scale = _light_base * (1.0 + wobble)
	_shadow.scale = _shadow_base * (1.0 - wobble)   # 빛 커지면 그림자 살짝 줄게
	
