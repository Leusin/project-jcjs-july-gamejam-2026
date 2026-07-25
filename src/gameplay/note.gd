extends Node2D

@export var speed: float = 120.0
@export var direction: Vector2 = Vector2.RIGHT
@export var radius: float = 20.0
@export var fall_gravity: float = 500.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _burning: bool = false

var _falling: bool = false
var _fall_velocity: Vector2 = Vector2.ZERO

func setup(start_position: Vector2, move_direction: Vector2) -> void:
	global_position = start_position
	direction = move_direction
	# 아트가 왼쪽을 향하므로, 오른쪽으로 갈 때 좌우 반전해 진행 방향을 보게 한다.
	# 아래로 내려갈 땐 왼쪽, 위로 올라갈 땐 오른쪽.
	if move_direction.x != 0.0:
		_sprite.flip_h = move_direction.x > 0.0
	else:
		_sprite.flip_h = move_direction.y < 0.0

func _process(delta: float) -> void:
	if _burning:
		return
	if _falling:
		_fall_velocity.y += fall_gravity * delta  # 중력 가속
		global_position += _fall_velocity * delta
		return
	global_position += direction * speed * delta

func burn() -> void:
	_burning = true
	_sprite.play("burn")

## 어둠으로 추락하며 스스로 사라진다.
func fall() -> void:
	_falling = true
	_fall_velocity = Vector2(direction.x * 40.0, -120.0)
	var t := create_tween()
	t.tween_property(_sprite, "modulate", Color(0.3, 0.3, 0.4, 0.0), 0.8)
	t.parallel().tween_property(_sprite, "rotation", _sprite.rotation + 4.0, 0.8)
	t.tween_callback(queue_free)
