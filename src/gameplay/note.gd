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

@export var fall_gravity: float = 1000.0
## 태워 없어지기까지 걸리는 시간(초).
@export var burn_duration: float = 0.5
## 회복 나방이 승천해 사라지기까지 걸리는 시간(초). 타는 것보다 느긋해야 승천으로 읽힌다.
@export var ascend_duration: float = 0.9

@export_group("경로 모양")
## 좌우로 흔들리는 폭(픽셀).
@export var sine_amplitude: float = 90.0
## 오는 동안 몇 번 흔들리는가.
@export var sine_waves: float = 2.0
## 불인간 둘레를 몇 바퀴 도는가.
@export var orbit_turns: float = 1.25

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var hit_time: float = 0.0      # 중앙에 도착해야 하는 곡 시각(초)
var travel_time: float = 2.0   # 스폰에서 중앙까지 걸리는 시간(초)
## 어느 방향에서 왔는가(Main의 Lane 값). 이 방향의 키를 눌러야 판정된다.
var lane: int = 0
## 방향을 틀린 적이 있는 나방. 이후 아무리 정확해도 Good이 최대다.
## 세우는 것도 읽는 것도 Main이 한다 — 여기서는 들고만 있는다.
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
	elif style == Style.SINE:
		_sprite.play("sine")

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

## 타서 사그라진다. 다 타면 스스로 사라진다.
func burn() -> void:
	_burning = true
	_sprite.play("burn")
	var t := create_tween()
	# 확 밝아졌다가(불꽃) 투명해지며, 재처럼 살짝 떠오른다.
	t.tween_property(_sprite, "modulate", Color(1.8, 1.1, 0.5, 0.0), burn_duration)
	t.parallel().tween_property(_sprite, "position", _sprite.position + Vector2(0, -36), burn_duration)
	t.tween_callback(queue_free)

## 회복 나방이 사라지는 방식. 태우지 않는다 — 구하러 온 놈을 태우면 앞뒤가 안 맞는다.
## 흰빛이 되어 위로 승천한다. 다 오르면 스스로 사라진다.
func ascend() -> void:
	_burning = true   # 경로 이동을 멈추는 플래그를 같이 쓴다
	var t := create_tween()
	t.tween_property(_sprite, "position", _sprite.position + Vector2(0, -110), ascend_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_sprite, "modulate", Color(2.2, 2.2, 2.4, 0.0), ascend_duration)
	t.tween_callback(queue_free)

## 어둠으로 추락하며 스스로 사라진다.
func fall() -> void:
	_falling = true
	var dir := (_hit_pos - _spawn_pos).normalized()
	_fall_velocity = Vector2(dir.x * 80.0, -240.0)
	var t := create_tween()
	t.tween_property(_sprite, "modulate", Color(0.3, 0.3, 0.4, 0.0), 0.8)
	t.parallel().tween_property(_sprite, "rotation", _sprite.rotation + 4.0, 0.8)
	t.tween_callback(queue_free)
