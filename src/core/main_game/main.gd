extends Node2D

@export var perfect_distance: float = 24.0
@export var good_distance: float = 64.0
@export var miss_distance: float = 100.0
@export var spawn_interval: float = 0.6
@export var burn_duration: float = 0.5

const NoteScene := preload("res://src/gameplay/note.tscn")

@onready var _spawn_points: Array = $SpawnPoints.get_children()
@onready var _hit_point: FireMan = $HitPoint

var _note: Node2D = null

func _ready() -> void:
	queue_redraw()
	_spawn_note()

func _process(_delta: float) -> void:
	if _note == null:
		return
	var to_note := _note.global_position - _hit_point.global_position
	var passed := to_note.dot(_note.direction) > 0.0
	if passed and to_note.length() > miss_distance:
		print("Miss (auto)")
		_on_miss()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_tap(event):
		return
	if _note == null:
		return
	var dist := _note.global_position.distance_to(_hit_point.global_position)
	if dist <= good_distance:
		var result := "Perfect" if dist <= perfect_distance else "Good"
		print("%s  (거리 %.1f)" % [result, dist])
		_on_success()
	else:
		print("Miss  (거리 %.1f)" % dist)
		_on_miss()

func _on_success() -> void:
	var note := _note
	_note = null                 # 즉시 비활성 → 중복 판정/자동미스 방지
	note.burn()
	await get_tree().create_timer(burn_duration).timeout
	note.queue_free()
	_schedule_next()

func _on_miss() -> void:
	_hit_point.take_damage()
	var note := _note
	_note = null
	note.fall()
	_schedule_next()

func _spawn_note() -> void:
	var note := NoteScene.instantiate()
	add_child(note)
	var spawn: Marker2D = _spawn_points.pick_random()
	var dir := (_hit_point.global_position - spawn.global_position).normalized()
	note.setup(spawn.global_position, dir)
	_note = note

func _schedule_next() -> void:
	await get_tree().create_timer(spawn_interval).timeout
	_spawn_note()

func _draw() -> void:
	if _hit_point == null:
		return
	var c := _hit_point.global_position
	draw_arc(c, perfect_distance, 0.0, TAU, 64, Color(0.3, 1.0, 0.4), 2.0)
	draw_arc(c, good_distance, 0.0, TAU, 64, Color(1.0, 0.9, 0.3), 2.0)
	draw_arc(c, miss_distance, 0.0, TAU, 64, Color(1.0, 0.4, 0.4), 2.0)

func _is_tap(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	return false
