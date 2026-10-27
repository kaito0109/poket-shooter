extends Node2D
## Short expanding-circle explosion effect.

var age: float = 0.0
var duration: float = 0.35

func _ready() -> void:
	z_index = 20

func _process(delta: float) -> void:
	age += delta
	queue_redraw()
	if age >= duration:
		queue_free()

func _draw() -> void:
	var t := clampf(age / duration, 0.0, 1.0)
	var alpha := 1.0 - t
	draw_circle(Vector2.ZERO, 8.0 + t * 26.0, Color(1.0, 0.65, 0.3, alpha * 0.8))
	draw_arc(Vector2.ZERO, 12.0 + t * 34.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.5, alpha), 3.0)
