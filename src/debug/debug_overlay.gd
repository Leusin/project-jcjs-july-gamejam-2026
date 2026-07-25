extends CanvasLayer
## 디버그 오버레이: FPS와 게임 버전을 좌상단에 표시한다.
## DebugLayer(Layer 128) 아래에 두거나 단독으로 씬에 추가한다.
## 일시정지 중에도 갱신되도록 process_mode를 Always로 둔다(씬에서 지정).

@onready var _label: Label = $Label

func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	# 버전은 프로젝트 설정 application/config/version 값을 그대로 읽는다.
	var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_label.text = "FPS %d\nv%s" % [fps, version]
