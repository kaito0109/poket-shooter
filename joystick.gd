extends Control
## Virtual joystick: drag inside the base circle. Works with mouse events,
## which on mobile web are emulated from touch by Godot.

var value: Vector2 = Vector2.ZERO
var knob_offset: Vector2 = Vector2.ZERO
var dragging: bool = false
var radius: float = 85.0

func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	size = custom_minimum_size
	mouse_filter = MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			dragging = mb.pressed
			if dragging:
				_update_knob(mb.position)
			else:
				value = Vector2.ZERO
				knob_offset = Vector2.ZERO
				queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_update_knob(mm.position)
		accept_event()

func _update_knob(local_pos: Vector2) -> void:
	var center: Vector2 = size * 0.5
	var delta: Vector2 = local_pos - center
	if delta.length() > radius:
		delta = delta.normalized() * radius
	knob_offset = delta
	value = delta / radius
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	draw_circle(center, radius, Color(1, 1, 1, 0.13))
	draw_arc(center, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.45), 2.0)
	draw_circle(center + knob_offset, radius * 0.42, Color(1, 1, 1, 0.35))
