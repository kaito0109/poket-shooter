extends Control
## PUBG-style minimap: whole arena, zone circles, nearby bots, player arrow.

const WORLD_RADIUS: float = 80.0

var buildings: Array = []  # Array of Rect2 in world XZ coords

func _ready() -> void:
	custom_minimum_size = Vector2(168, 168)
	size = custom_minimum_size
	mouse_filter = MOUSE_FILTER_IGNORE

func set_buildings(rects: Array) -> void:
	buildings = rects

func _process(_delta: float) -> void:
	queue_redraw()

func _world_to_map(p: Vector2) -> Vector2:
	var s: float = size.x * 0.5 / WORLD_RADIUS
	return Vector2(size.x * 0.5 + p.x * s, size.y * 0.5 + p.y * s)

func _draw() -> void:
	var zone: Node = get_tree().get_first_node_in_group("zone")
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	# Background: blue (outside zone) then dark disc for the current zone.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.35, 0.8, 0.75))
	if zone != null:
		var zc: Vector2 = zone.get("center")
		var zr: float = zone.get("radius")
		var s: float = size.x * 0.5 / WORLD_RADIUS
		draw_circle(_world_to_map(zc), zr * s, Color(0.05, 0.08, 0.1, 0.85))
		# Next zone outline.
		var tc: Vector2 = zone.get("target_center")
		var tr: float = zone.get("target_radius")
		draw_arc(_world_to_map(tc), tr * s, 0.0, TAU, 48, Color(0.4, 0.75, 1.0, 0.95), 1.6)
		draw_arc(_world_to_map(zc), zr * s, 0.0, TAU, 48, Color(1, 1, 1, 0.95), 1.6)
	# Buildings.
	for r: Rect2 in buildings:
		var top_left: Vector2 = _world_to_map(r.position)
		var bottom_right: Vector2 = _world_to_map(r.position + r.size)
		draw_rect(Rect2(top_left, bottom_right - top_left), Color(0.55, 0.55, 0.58, 0.8))
	# Bots within 40m of the player.
	if player != null:
		var ppos: Vector2 = Vector2(player.global_position.x, player.global_position.z)
		for bot: Node in get_tree().get_nodes_in_group("enemies"):
			if bot.get("dead"):
				continue
			var b3: Node3D = bot as Node3D
			var bpos: Vector2 = Vector2(b3.global_position.x, b3.global_position.z)
			if ppos.distance_to(bpos) <= 40.0:
				draw_circle(_world_to_map(bpos), 3.0, Color(1.0, 0.25, 0.2))
		# Player arrow (points where the camera faces).
		var yaw: float = player.get("yaw")
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var c: Vector2 = _world_to_map(ppos)
		var pts := PackedVector2Array([
			c + fwd * 8.0,
			c - fwd * 6.0 + right * 5.0,
			c - fwd * 6.0 - right * 5.0,
		])
		draw_colored_polygon(pts, Color.WHITE)
	# Frame.
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.5), false, 2.0)
