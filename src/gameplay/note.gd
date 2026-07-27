class_name Note
extends Node2D

## 나방이 중앙으로 다가오는 경로 모양.
## 어떤 모양이든 hit_time에 정확히 중앙에 도착한다(판정에 영향 없음).
##   STRAIGHT — 곧장 온다
##   SINE     — 진행 방향 좌우로 흔들리며 온다
##   ORBIT    — 불인간 둘레를 돌며 빨려들듯 다가온다
enum Style { STRAIGHT, SINE, ORBIT }

## 맞혔을 때 무슨 일이 생기는가. 이동 스타일과는 별개 축이라 자유롭게 조합된다.
##   NORMAL — 점수와 콤보
##   HEAL   — 거기에 더해 체력을 돌려준다
enum Kind { NORMAL, HEAL }

const STRAIGHT_TINT := Color(1.0, 1.0, 1.0, 1.0)
const SINE_TINT := Color(0.48, 0.82, 1.0, 1.0)
const ORBIT_TINT := Color(0.88, 0.5, 1.0, 1.0)
const HEAL_TINT := Color(1.0, 1.0, 1.0, 1.0)

@export var fall_gravity: float = 1000.0
@export var burn_duration: float = 0.5
@export var ascend_duration: float = 0.9

@export_group("경로 모양")
@export var sine_amplitude: float = 90.0
@export var sine_waves: float = 2.0
@export var orbit_turns: float = 1.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var hit_time: float = 0.0      # 중앙에 도착해야 하는 곡 시각(초)
var travel_time: float = 2.0   # 스폰에서 중앙까지 걸리는 시간(초)
var perfect_locked: bool = false
var style: Style = Style.STRAIGHT
var kind: Kind = Kind.NORMAL

var _conductor: Conductor = null
var _spawn_pos: Vector2 = Vector2.ZERO
var _hit_pos: Vector2 = Vector2.ZERO

var _burning: bool = false
var _falling: bool = false
var _fall_velocity: Vector2 = Vector2.ZERO

func setup(conductor: Conductor, spawn_pos: Vector2, hit_pos: Vector2, note_hit_time: float, note_travel_time: float) -> void:
	_conductor = conductor
	_spawn_pos = spawn_pos
	_hit_pos = hit_pos
	hit_time = note_hit_time
	travel_time = note_travel_time
	global_position = spawn_pos

	# 무엇으로 보이는가. 
	if kind == Kind.HEAL:
		_sprite.play("heal")
		_sprite.self_modulate = HEAL_TINT
	elif style == Style.SINE:
		_sprite.play("sine")
		_sprite.self_modulate = SINE_TINT
	elif style == Style.ORBIT:
		_sprite.self_modulate = ORBIT_TINT
	else:
		_sprite.self_modulate = STRAIGHT_TINT

	# 아트가 왼쪽을 향하므로, 진행 방향을 보도록 뒤집는다.
	var dir := hit_pos - spawn_pos
	if dir.x != 0.0:
		_sprite.flip_h = dir.x > 0.0
	else:
		_sprite.flip_h = dir.y < 0.0

func _process(delta: float) -> void:
	if _burning:
		return
	if _falling:
		_fall_velocity.y += fall_gravity * delta
		global_position += _fall_velocity * delta
		return

	# 곡 시각이 위치를 결정한다. t: 1.0(스폰) → 0.0(중앙)
	var t := (hit_time - _conductor.song_position) / travel_time
	var next_position := _position_at(t)

	# 움직이는 쪽을 보게 한다. 원을 그리며 오는 나방은 방향이 계속 바뀐다.
	if absf(next_position.x - global_position.x) > 0.5:
		_sprite.flip_h = next_position.x > global_position.x

	global_position = next_position

## t 시점의 위치. t는 1.0(스폰)에서 0.0(중앙 도착)으로 줄어든다.
## 어떤 모양이든 t=0에서 정확히 _hit_pos가 나와야 판정 위치가 어긋나지 않는다.
func _position_at(t: float) -> Vector2:
	var straight := _hit_pos.lerp(_spawn_pos, t)
	match style:
		Style.SINE:
			# 진행 방향의 직각으로 흔든다. 진폭에 t를 곱해 도착할수록 잦아든다.
			var forward := (_hit_pos - _spawn_pos).normalized()
			return straight + forward.orthogonal() * sin(t * TAU * sine_waves) * sine_amplitude * t
		Style.ORBIT:
			# 불인간을 원점으로 한 극좌표로 움직인다.
			# 반지름은 t에 비례해 줄고(=빨려든다), 각도는 다가올수록 계속 돈다.
			# 안쪽으로 갈수록 둘레가 짧아져 저절로 빨라 보인다 — 불에 빨려드는 나방.
			var from_center := _spawn_pos - _hit_pos
			var radius := from_center.length() * t
			var angle := from_center.angle() + TAU * orbit_turns * (1.0 - t)
			return _hit_pos + Vector2(radius, 0.0).rotated(angle)
	return straight

func burn() -> void:
	_burning = true
	_sprite.play("burn")
	var t := create_tween()
	# 확 밝아졌다가(불꽃) 투명해지며, 재처럼 살짝 떠오른다.
	t.tween_property(_sprite, "modulate", Color(1.8, 1.1, 0.5, 0.0), burn_duration)
	t.parallel().tween_property(_sprite, "position", _sprite.position + Vector2(0, -36), burn_duration)
	t.tween_callback(queue_free)

func ascend() -> void:
	_burning = true
	var t := create_tween()
	t.tween_property(_sprite, "position", _sprite.position + Vector2(0, -110), ascend_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_sprite, "modulate", Color(2.2, 2.2, 2.4, 0.0), ascend_duration)
	t.tween_callback(queue_free)

func fall() -> void:
	_falling = true
	var dir := (_hit_pos - _spawn_pos).normalized()
	_fall_velocity = Vector2(dir.x * 80.0, -240.0)
	var t := create_tween()
	t.tween_property(_sprite, "modulate", Color(0.3, 0.3, 0.4, 0.0), 0.8)
	t.parallel().tween_property(_sprite, "rotation", _sprite.rotation + 4.0, 0.8)
	t.tween_callback(queue_free)
