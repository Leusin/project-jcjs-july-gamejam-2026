class_name FireMan
extends Marker2D
## 중앙 캐릭터(불인간). 판정 기준점이자, Miss 시 피격 반응을 한다.

@onready var _character_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _head: AnimatedSprite2D = $HeadSprite

@onready var _light: Sprite2D = $LightSprite2D
@onready var _shadow: Sprite2D = $ShadowSprite2D

const FRENZY_LIGHT_COLORS: Array[Color] = [
	Color("ffd35c"),
	Color("ffe178"),
	Color("ffefad"),
	Color("fff9e8"),
]
const FRENZY_LIGHT_SCALES: Array[float] = [1.0, 1.25, 1.55, 1.9]
const FRENZY_FLICKER_FAST: Array[float] = [0.04, 0.08, 0.12, 0.05]
const FRENZY_FLICKER_SLOW: Array[float] = [0.08, 0.14, 0.20, 0.10]
const FRENZY_FLICKER_SPEED: Array[float] = [1.0, 1.25, 1.65, 1.15]

@export_group("춤")
@export var dance_animations: Array[StringName] = [
	&"dance_bob", &"dance_hop", &"dance_full"
]
## 각 단계로 올라가는 콤보 문턱. dance_animations보다 하나 짧아야 한다.
@export var dance_thresholds: PackedInt32Array = PackedInt32Array([1, 20])
@export var perfect_animation: StringName = &"dance_flailing"
@export var perfect_duration: float = 0.5

@export_group("탭 반응")
@export var tap_punch: float = 0.8
@export var punch_decay: float = 6.0
@export var idle_animation: StringName = &"default"

@export_group("머리")
@export var head_scale_steps: PackedFloat32Array = PackedFloat32Array([1.0, 1.15, 1.35, 1.6])
@export var head_scale_thresholds: PackedInt32Array = PackedInt32Array([10, 30, 50])

var _flicker_t: float = 0.0
var _light_base: Vector2
var _shadow_base: Vector2
var _head_scale_tween: Tween
var _frenzy_tween: Tween
var _head_step: int = -1
var _frenzy_stage: int = 0
var _light_scale_multiplier: float = 1.0
## 콤보로 정해진 머리 크기. tween이 이 값을 움직인다.
var _head_scale_base: float = 1.0
## 탭으로 얹힌 부풀기. _process에서 위 값에 더해지며 서서히 빠진다.
## 둘을 따로 두는 이유: 한 property를 tween 둘이 잡으면 서로 덮어쓴다.
var _head_punch: float = 0.0
## Main이 알려준 지금 콤보. 춤 단계를 고르는 데 쓴다.
var _combo: int = 0
## PERFECT 동작이 언제까지 이어지는가(초, 엔진 기동 기준).
var _perfect_until: float = 0.0
## 곡이 도는 동안만 춤춘다. 멈추면 머리가 그려진 idle 한 장으로 돌아간다.
var _dancing: bool = false

## Main이 매 프레임 호출. 지금 상태에 맞는 애니메이션만 골라준다.
## 프레임 진행은 건드리지 않는다 — SpriteFrames에 박힌 speed로 알아서 돈다.
func sync_dance(playing: bool) -> void:
	if playing != _dancing:
		_set_dancing(playing)
	if not playing:
		return
	var anim := _dance_animation()
	if _character_sprite.animation != anim:
		_character_sprite.play(anim)

## Main이 탭할 때마다 호출. 판정 성패는 보지 않는다 —
## 누른 순간 화면이 반응하는 것 자체가 손맛이라, 헛손질에도 똑같이 반응한다.
func on_tap() -> void:
	# 좌우로 홱 돈다
	var f := not _character_sprite.flip_h
	_character_sprite.flip_h = f
	_head.flip_h = f

	# 머리가 확 커졌다 줄어든다. _process에서 콤보 크기와 합쳐지므로 값만 올려둔다.
	_head_punch = tap_punch

## Main이 PERFECT 판정에 호출. 잠깐 팔다리를 흩뜨렸다가 원래 단계로 돌아온다.
func on_perfect() -> void:
	_perfect_until = Time.get_ticks_msec() / 1000.0 + perfect_duration

## 지금 내야 할 몸통 애니메이션. PERFECT 여운이 콤보 단계보다 우선한다.
func _dance_animation() -> StringName:
	if Time.get_ticks_msec() / 1000.0 < _perfect_until:
		return perfect_animation
	if dance_animations.is_empty():
		return idle_animation
	var step := 0
	for t in dance_thresholds:
		if _combo >= t:
			step += 1
	return dance_animations[mini(step, dance_animations.size() - 1)]

## 곡이 돌 때만 머리를 따로 띄운다.
## idle 그림에는 머리가 이미 그려져 있어서, 같이 켜면 머리가 둘이 된다.
func _set_dancing(on: bool) -> void:
	_dancing = on
	_head.visible = on
	if on:
		_character_sprite.play(_dance_animation())
		_head.play()
	else:
		_head.stop()
		_character_sprite.flip_h = false
		_head.flip_h = false
		_character_sprite.play(idle_animation)

## Main이 콤보가 바뀔 때 호출. 약중강을 따로 그리는 대신 같은 머리를 키운다.
func set_combo(combo: int) -> void:
	_combo = combo
	var step := 0
	for t in head_scale_thresholds:
		if combo >= t:
			step += 1
	step = mini(step, head_scale_steps.size() - 1)
	if step == _head_step:
		return
	_head_step = step
	# 원점이 목이라 커져도 목은 제자리고 불꽃만 위로 자란다.
	# scale을 직접 tween하지 않는다 — 탭 부풀기와 같은 property를 두고 싸우기 때문이다.
	if _head_scale_tween != null and _head_scale_tween.is_valid():
		_head_scale_tween.kill()
	_head_scale_tween = create_tween()
	_head_scale_tween.tween_method(
		func(v: float) -> void: _head_scale_base = v,
		_head_scale_base, head_scale_steps[step], 0.25
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_frenzy_stage(stage: int) -> void:
	stage = clampi(stage, 0, FRENZY_LIGHT_COLORS.size() - 1)
	if stage == _frenzy_stage:
		return
	_frenzy_stage = stage
	if _frenzy_tween != null and _frenzy_tween.is_valid():
		_frenzy_tween.kill()
	_frenzy_tween = create_tween().set_parallel()
	_frenzy_tween.tween_property(
		_light,
		"modulate",
		FRENZY_LIGHT_COLORS[stage],
		0.22
	)
	_frenzy_tween.tween_method(
		func(value: float) -> void: _light_scale_multiplier = value,
		_light_scale_multiplier,
		FRENZY_LIGHT_SCALES[stage],
		0.22
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Miss visual feedback: red flash and short shake.
func take_damage() -> void:
	for s in [_character_sprite, _head]:
		s.modulate = Color(1.0, 0.3, 0.3)
		create_tween().tween_property(s, "modulate", Color.WHITE, 0.3)
	var shake := create_tween()
	shake.tween_property(_character_sprite, "offset", Vector2(16, 0), 0.04)
	shake.tween_property(_character_sprite, "offset", Vector2(-16, 0), 0.04)
	shake.tween_property(_character_sprite, "offset", Vector2.ZERO, 0.04)

## 승리 연출: 불길이 크게 타오른다.
## 춤은 마지막 자세에서 멈춘 채로 둔다 — 곡이 끝났으니 프레임도 멎는 게 맞다.
func celebrate() -> void:
	var t := create_tween().set_parallel()
	t.tween_property(_light, "scale", _light_base * 2.2, 1.0).set_trans(Tween.TRANS_ELASTIC)
	t.tween_property(_character_sprite, "modulate", Color(1.4, 1.2, 0.8), 1.0)
	t.tween_property(_head, "modulate", Color(1.6, 1.4, 1.0), 1.0)
	_light_base *= 2.2   # 일렁임이 커진 크기를 기준으로 계속되도록

## 게임오버 연출: 불이 서서히 꺼진다.
func extinguish() -> void:
	set_process(false)   # 일렁임 정지
	var t := create_tween().set_parallel()
	t.tween_property(_light, "scale", Vector2.ZERO, 1.2)
	t.tween_property(_shadow, "scale", Vector2.ZERO, 1.2)
	t.tween_property(_character_sprite, "modulate", Color(0.25, 0.25, 0.3), 1.2)
	t.tween_property(_head, "modulate", Color(0.25, 0.25, 0.3), 1.2)

func _ready() -> void:
	_light_base = _light.scale
	_shadow_base = _shadow.scale
	# 타이틀에서는 머리가 그려진 idle 한 장으로 버틴다.
	_head.visible = false
	_character_sprite.play(idle_animation)

func _process(delta: float) -> void:
	_flicker_t += delta
	# 주파수 다른 sin 둘을 섞어 불규칙한 불꽃 일렁임
	var speed := FRENZY_FLICKER_SPEED[_frenzy_stage]
	var wobble := (
		FRENZY_FLICKER_FAST[_frenzy_stage] * sin(_flicker_t * 7.0 * speed)
		+ FRENZY_FLICKER_SLOW[_frenzy_stage] * sin(_flicker_t * speed)
	)
	_light.scale = _light_base * _light_scale_multiplier * (1.0 + wobble)
	_shadow.scale = _shadow_base * (1.0 - wobble)   # 빛 커지면 그림자 살짝 줄게

	# 콤보로 정해진 크기에 탭 부풀기를 얹는다. 부풀기는 시간이 지나면 빠진다.
	_head_punch = move_toward(_head_punch, 0.0, punch_decay * delta)
	_head.scale = Vector2.ONE * (_head_scale_base + _head_punch)
	
