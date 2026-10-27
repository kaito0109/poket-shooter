extends Node3D
## PUBG-style safe zone: a circular wall that shrinks in phases.
## Outside the circle, everyone takes damage over time.

signal phase_changed

# phases: [wait_time, shrink_time, radius_factor_of_previous, dps]
const PHASES: Array = [
	[22.0, 18.0, 0.58, 1],
	[18.0, 15.0, 0.55, 2],
	[15.0, 12.0, 0.5, 4],
	[12.0, 10.0, 0.45, 7],
	[10.0, 8.0, 0.4, 10],
]

var running: bool = false
var phase_index: int = -1  # -1 = before first wait ends / initial
var state: String = "waiting"  # waiting | shrinking | final
var time_left: float = 0.0

var center: Vector2 = Vector2.ZERO  # XZ
var radius: float = 96.0
var from_center: Vector2 = Vector2.ZERO
var from_radius: float = 96.0
var target_center: Vector2 = Vector2.ZERO
var target_radius: float = 96.0
var current_dps: int = 0

var wall: MeshInstance3D
var ring: MeshInstance3D
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("zone")
	rng.randomize()
	_build_meshes()
	_update_meshes()

func _build_meshes() -> void:
	# Vertical translucent wall (open cylinder side surface, radius 1 -> scaled).
	var segments: int = 72
	var height: float = 42.0
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		var a: float = TAU * float(i) / float(segments)
		var x: float = cos(a)
		var z: float = sin(a)
		verts.append(Vector3(x, 0.0, z))
		verts.append(Vector3(x, height, z))
	for i in segments:
		var b: int = i * 2
		indices.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var wall_mesh := ArrayMesh.new()
	wall_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	wall = MeshInstance3D.new()
	wall.mesh = wall_mesh
	var wall_mat := StandardMaterial3D.new()
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.albedo_color = Color(0.25, 0.55, 1.0, 0.16)
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall_mat.no_depth_test = false
	wall.material_override = wall_mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)

	# Bright ground ring at the boundary.
	var ring_verts := PackedVector3Array()
	var ring_indices := PackedInt32Array()
	var inner: float = 0.985
	for i in segments + 1:
		var a2: float = TAU * float(i) / float(segments)
		var ca: float = cos(a2)
		var sa: float = sin(a2)
		ring_verts.append(Vector3(ca * inner, 0.0, sa * inner))
		ring_verts.append(Vector3(ca, 0.0, sa))
	for i in segments:
		var b2: int = i * 2
		ring_indices.append_array([b2, b2 + 2, b2 + 1, b2 + 1, b2 + 2, b2 + 3])
	var ring_arrays: Array = []
	ring_arrays.resize(Mesh.ARRAY_MAX)
	ring_arrays[Mesh.ARRAY_VERTEX] = ring_verts
	ring_arrays[Mesh.ARRAY_INDEX] = ring_indices
	var ring_mesh := ArrayMesh.new()
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ring_arrays)
	ring = MeshInstance3D.new()
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.4, 0.7, 1.0, 0.55)
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.06
	add_child(ring)

func _update_meshes() -> void:
	if wall != null:
		wall.position = Vector3(center.x, 0.0, center.y)
		wall.scale = Vector3(radius, 1.0, radius)
	if ring != null:
		ring.position = Vector3(center.x, 0.06, center.y)
		ring.scale = Vector3(radius, 1.0, radius)

func start_match() -> void:
	running = true
	phase_index = -1
	state = "waiting"
	time_left = PHASES[0][0]
	current_dps = 0
	center = Vector2.ZERO
	radius = 96.0
	_pick_next_target()

func _pick_next_target() -> void:
	var next_index: int = phase_index + 1
	if next_index >= PHASES.size():
		state = "final"
		target_center = center
		target_radius = radius
		return
	var factor: float = PHASES[next_index][2]
	target_radius = radius * factor
	# New center must keep the target circle inside the current one.
	var max_offset: float = maxf(radius - target_radius - 2.0, 0.0)
	var offset := Vector2(rng.randf_range(-max_offset, max_offset), rng.randf_range(-max_offset, max_offset))
	if offset.length() > max_offset:
		offset = offset.normalized() * max_offset
	target_center = center + offset

func _process(delta: float) -> void:
	if not running:
		return
	time_left -= delta
	if state == "waiting":
		current_dps = PHASES[maxi(phase_index, 0)][3] if phase_index >= 0 else 0
		if phase_index < 0:
			current_dps = 0
		if time_left <= 0.0:
			phase_index += 1
			if phase_index >= PHASES.size():
				state = "final"
				phase_changed.emit()
				return
			state = "shrinking"
			from_center = center
			from_radius = radius
			time_left = PHASES[phase_index][1]
			phase_changed.emit()
	elif state == "shrinking":
		current_dps = PHASES[phase_index][3]
		var duration: float = PHASES[phase_index][1]
		var t: float = clampf(1.0 - time_left / duration, 0.0, 1.0)
		center = from_center.lerp(target_center, t)
		radius = lerpf(from_radius, target_radius, t)
		_update_meshes()
		if time_left <= 0.0:
			center = target_center
			radius = target_radius
			_update_meshes()
			_pick_next_target()
			if state != "final":
				state = "waiting"
				var next_index: int = phase_index + 1
				time_left = PHASES[next_index][0] if next_index < PHASES.size() else 0.0
			phase_changed.emit()

func is_outside(pos: Vector3) -> bool:
	var d: float = Vector2(pos.x, pos.z).distance_to(center)
	return d > radius

func distance_outside(pos: Vector3) -> float:
	var d: float = Vector2(pos.x, pos.z).distance_to(center)
	return maxf(d - radius, 0.0)

func status_text() -> String:
	if not running:
		return ""
	if state == "waiting":
		return "ゾーン縮小まで %d 秒" % int(ceil(time_left))
	elif state == "shrinking":
		return "ゾーン縮小中！"
	return "最終ゾーン"

# Test/debug helper: jump straight to a tiny zone somewhere else.
func debug_set(new_center: Vector2, new_radius: float, dps: int) -> void:
	running = true
	state = "final"
	center = new_center
	radius = new_radius
	target_center = new_center
	target_radius = new_radius
	current_dps = dps
	_update_meshes()
