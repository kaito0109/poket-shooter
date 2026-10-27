extends MeshInstance3D
## Short-lived visual effect: a tracer line or a hit spark sphere that fades out.

var life: float = 0.08
var age: float = 0.0
var mat: StandardMaterial3D

func setup_line(from: Vector3, to: Vector3, color: Color) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	mesh = im
	_setup_material(color)
	life = 0.07

func setup_spark(at_position: Vector3, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	sphere.radial_segments = 10
	sphere.rings = 6
	mesh = sphere
	global_position = at_position
	_setup_material(color)
	life = 0.14

func _setup_material(color: Color) -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = false
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(delta: float) -> void:
	age += delta
	var t: float = clampf(age / life, 0.0, 1.0)
	if mat != null:
		mat.albedo_color.a = 1.0 - t
	if age >= life:
		queue_free()
