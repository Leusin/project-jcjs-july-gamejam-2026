extends Node2D
## 판정 범위 띠를 불인간 조명 **위에** 그린다.
##
## Main의 _draw()로 그리면 안 보인다. Godot은 부모를 먼저 그리고 자식을 그 위에 덮는데,
## 불인간의 LightSprite2D(356px, 가산 블렌드)가 자식이라 띠(약 114px)를 통째로 삼켜버린다.
## 그래서 z_index를 올린 별도 노드로 뺐다.
##
## 무엇을 그릴지는 Main이 정한다(꺼져 있으면 빈 목록을 준다). 이 노드는 받아서 그리기만 한다.

@export var band_width: float = 36.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var main := get_parent()
	if main == null or not main.has_method("judgement_bands"):
		return
	for band in main.judgement_bands():
		draw_line(band["a"], band["b"], band["color"], band_width)
