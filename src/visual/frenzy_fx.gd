class_name FrenzyFX
extends Node2D
## 불인간 뒤에서 광란의 기운을 그린다.
## 별도 텍스처 없이 원·광선·궤도 입자를 조합해 콤보 상승과 타격을 즉시 보여준다.

const COLORS: Array[Color] = [
	Color("ffd35c"),
	Color("ffe178"),
	Color("ffefad"),
	Color("fff9e8"),
]

var _stage: int = 0
var _elapsed: float = 0.0
var _rings: Array[Dictionary] = []


func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	set_process(false)


func set_frenzy_stage(stage: int) -> void:
	stage = clampi(stage, 0, COLORS.size() - 1)
	if stage == _stage:
		return
	_stage = stage
	if stage == 0:
		_rings.clear()
		set_process(false)
		queue_redraw()
		return

	set_process(true)


func on_hit(perfect: bool) -> void:
	if _stage == 0:
		return
	var perfect_bonus := 55.0 if perfect else 0.0
	var alpha_bonus := 0.18 if perfect else 0.0
	_spawn_ring(
		82.0,
		175.0 + _stage * 52.0 + perfect_bonus,
		0.26 + _stage * 0.035,
		0.34 + _stage * 0.11 + alpha_bonus
	)


func _spawn_ring(start_radius: float, end_radius: float,
		duration: float, alpha: float) -> void:
	_rings.append({
		"age": 0.0,
		"duration": duration,
		"start_radius": start_radius,
		"end_radius": end_radius,
		"alpha": alpha,
		"color": COLORS[_stage],
	})
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	for index in range(_rings.size() - 1, -1, -1):
		_rings[index]["age"] += delta
		if _rings[index]["age"] >= _rings[index]["duration"]:
			_rings.remove_at(index)
	queue_redraw()


func _draw() -> void:
	if _stage > 0:
		_draw_aura()
		if _stage >= 3:
			_draw_orbiting_sparks()
	_draw_impact_rings()


func _draw_aura() -> void:
	var color := COLORS[_stage]
	var breath := sin(_elapsed * (2.0 + _stage * 0.7))
	var radius := 120.0 + _stage * 28.0 + breath * (8.0 + _stage * 3.0)
	draw_circle(Vector2.ZERO, radius, _with_alpha(color, 0.035 + _stage * 0.018))


func _draw_orbiting_sparks() -> void:
	var color := COLORS[_stage]
	for spark_index in 14:
		var angle := _elapsed * (0.9 if spark_index % 2 == 0 else -0.65)
		angle += TAU * spark_index / 14.0
		var radius := 185.0 + sin(_elapsed * 2.4 + spark_index) * 42.0
		var point := Vector2.from_angle(angle) * radius
		var spark_size := 2.5 + (spark_index % 3)
		draw_circle(point, spark_size, _with_alpha(color, 0.55))


func _draw_impact_rings() -> void:
	for ring in _rings:
		var progress: float = ring["age"] / ring["duration"]
		var eased := 1.0 - pow(1.0 - progress, 2.0)
		var radius := lerpf(ring["start_radius"], ring["end_radius"], eased)
		var alpha: float = ring["alpha"] * pow(1.0 - progress, 1.6)
		var color: Color = ring["color"]
		draw_arc(
			Vector2.ZERO,
			radius,
			0.0,
			TAU,
			96,
			_with_alpha(color, alpha),
			lerpf(8.0, 1.0, progress),
			true
		)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))
