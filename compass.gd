extends Control
## PUBG-style compass strip: heading ticks and cardinal directions.

var font_to_use: Font = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var yaw: float = float(player.get("yaw"))
	var heading: float = wrapf(rad_to_deg(-yaw), 0.0, 360.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.28))
	var cx: float = size.x * 0.5
	var px_per_deg: float = 3.2
	var font: Font = font_to_use if font_to_use != null else ThemeDB.fallback_font
	for deg_i in range(0, 360, 15):
		var deg: float = float(deg_i)
		var rel: float = wrapf(deg - heading + 180.0, 0.0, 360.0) - 180.0
		var x: float = cx + rel * px_per_deg
		if x < 4.0 or x > size.x - 4.0:
			continue
		var is_cardinal: bool = deg_i % 90 == 0
		var is_mid: bool = deg_i % 45 == 0
		var tick_h: float = 12.0 if is_cardinal else (9.0 if is_mid else 6.0)
		draw_line(Vector2(x, size.y - tick_h - 2), Vector2(x, size.y - 2), Color(1, 1, 1, 0.85), 1.6)
		var label_text: String = ""
		match deg_i:
			0: label_text = "N"
			45: label_text = "NE"
			90: label_text = "E"
			135: label_text = "SE"
			180: label_text = "S"
			225: label_text = "SW"
			270: label_text = "W"
			315: label_text = "NW"
		if label_text != "":
			var col: Color = Color(1.0, 0.35, 0.3) if label_text == "N" else Color(1, 1, 1, 0.95)
			draw_string(font, Vector2(x - 9, 15), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	# Center marker.
	draw_line(Vector2(cx, 2), Vector2(cx, 9), Color(1.0, 0.8, 0.2), 2.4)
