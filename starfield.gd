extends Node2D
## Scrolling starfield background.

var stars: Array[Vector3] = []
var bounds := Vector2(720, 960)

func _ready() -> void:
	bounds = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 720),
		ProjectSettings.get_setting("display/window/size/viewport_height", 960)
	)
	for i in 90:
		stars.append(Vector3(
			randf_range(0.0, bounds.x),
			randf_range(0.0, bounds.y),
			randf_range(0.4, 1.6)  # z = speed / brightness factor
		))

func _process(delta: float) -> void:
	for i in stars.size():
		var s := stars[i]
		s.y += 42.0 * s.z * delta
		if s.y > bounds.y + 4.0:
			s.y = -4.0
			s.x = randf_range(0.0, bounds.x)
		stars[i] = s
	queue_redraw()

func _draw() -> void:
	for s in stars:
		var alpha := clampf(s.z * 0.55, 0.2, 0.9)
		draw_circle(Vector2(s.x, s.y), s.z * 1.4, Color(1, 1, 1, alpha))
