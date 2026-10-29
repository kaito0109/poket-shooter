extends Control
## Virtual joystick with true multitouch: tracks one touch index (or the
## mouse) so the camera can be dragged with another finger at the same time.

var value: Vector2 = Vector2.ZERO
var knob_offset: Vector2 = Vector2.ZERO
var dragging: bool = false
var radius: float = 85.0
var _pointer_id: int = -2  # -2 = none, -1 = mouse, >=0 = touch index

func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	size = custom_minimum_size
	mouse_filter = MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed and _pointer_id == -2 and get_global_rect().has_point(st.position):
			_pointer_id = st.index
			dragging = true
			_update_knob(st.position)
		elif not st.pressed and st.index == _pointer_id:
			_release()
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if sd.index == _pointer_id:
			_update_knob(sd.position)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _pointer_id == -2 and get_global_rect().has_point(mb.position):
				_pointer_id = -1
				dragging = true
				_update_knob(mb.position)
			elif not mb.pressed and _pointer_id == -1:
				_release()
	elif event is InputEventMouseMotion:
		if _pointer_id == -1 and dragging:
			_update_knob((event as InputEventMouseMotion).position)

func _release() -> void:
	_pointer_id = -2
	dragging = false
	value = Vector2.ZERO
	knob_offset = Vector2.ZERO
	queue_redraw()

func _update_knob(global_pos: Vector2) -> void:
	var local_pos: Vector2 = get_global_transform().affine_inverse() * global_pos
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
