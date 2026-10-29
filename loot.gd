extends Node3D
## A ground loot item: weapon, ammo, armor or medical/boost item.

var loot_type: String = ""
var amount: int = 0
var visual_root: Node3D
var base_y: float = 0.0
var t: float = 0.0

const NAMES: Dictionary = {
	"bandage": "包帯", "firstaid": "応急処置キット", "medkit": "医療キット",
	"drink": "エナジードリンク", "painkiller": "鎮痛剤",
	"helmet1": "ヘルメット Lv1", "helmet2": "ヘルメット Lv2", "helmet3": "ヘルメット Lv3",
	"vest1": "ベスト Lv1", "vest2": "ベスト Lv2", "vest3": "ベスト Lv3",
	"crate": "補給箱", "grenade": "破片手榴弾",
}

static func display_name_for(type: String, amt: int = 0) -> String:
	if Weapons.DATA.has(type):
		return Weapons.display_name(type)
	if type.begins_with("ammo_"):
		var kind: String = type.trim_prefix("ammo_")
		return "%s ×%d" % [Weapons.AMMO_NAMES.get(kind, kind), amt]
	return String(NAMES.get(type, type))

func display_name() -> String:
	return display_name_for(loot_type, amount)

func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _box(parent: Node, size: Vector3, pos: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, emission)
	parent.add_child(mi)
	return mi

func setup(type: String, p_amount: int = 0) -> void:
	loot_type = type
	amount = p_amount
	base_y = position.y
	visual_root = Node3D.new()
	add_child(visual_root)
	var dark := Color(0.16, 0.16, 0.18)
	if Weapons.DATA.has(type):
		var data: Dictionary = Weapons.DATA[type]
		var len_: float = float(data["len"])
		var body_color := Color(0.2, 0.2, 0.22)
		if type == "kar98":
			body_color = Color(0.35, 0.24, 0.14)
		elif type == "s686":
			body_color = Color(0.3, 0.22, 0.16)
		_box(visual_root, Vector3(0.13, 0.16, len_ * 0.62), Vector3(0, 0.3, 0.1), body_color)
		_box(visual_root, Vector3(0.05, 0.05, len_ * 0.45), Vector3(0, 0.34, -len_ * 0.42), dark)
		_box(visual_root, Vector3(0.09, 0.2, 0.12), Vector3(0, 0.17, -0.02), dark)
		if type == "kar98":
			var scope := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.035
			cyl.bottom_radius = 0.035
			cyl.height = 0.22
			scope.mesh = cyl
			scope.rotation_degrees.x = 90
			scope.position = Vector3(0, 0.44, 0.05)
			scope.material_override = _mat(dark)
			visual_root.add_child(scope)
	elif type.begins_with("ammo_"):
		var kind: String = type.trim_prefix("ammo_")
		var col := Color(0.75, 0.6, 0.2)
		match kind:
			"556": col = Color(0.3, 0.55, 0.3)
			"762": col = Color(0.6, 0.35, 0.2)
			"shell": col = Color(0.7, 0.25, 0.2)
		_box(visual_root, Vector3(0.34, 0.18, 0.24), Vector3(0, 0.26, 0), col)
		_box(visual_root, Vector3(0.36, 0.05, 0.26), Vector3(0, 0.37, 0), dark)
	elif type.begins_with("helmet"):
		var lv: int = int(type.trim_prefix("helmet"))
		var cols: Array[Color] = [Color(0.4, 0.45, 0.35), Color(0.3, 0.35, 0.45), Color(0.2, 0.2, 0.22)]
		var dome := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.24
		sphere.height = 0.4
		dome.mesh = sphere
		dome.scale = Vector3(1, 0.72, 1)
		dome.position = Vector3(0, 0.3, 0)
		dome.material_override = _mat(cols[lv - 1])
		visual_root.add_child(dome)
	elif type.begins_with("vest"):
		var lv2: int = int(type.trim_prefix("vest"))
		var cols2: Array[Color] = [Color(0.45, 0.5, 0.4), Color(0.35, 0.4, 0.35), Color(0.22, 0.24, 0.26)]
		_box(visual_root, Vector3(0.44, 0.52, 0.26), Vector3(0, 0.34, 0), cols2[lv2 - 1])
	elif type == "bandage":
		_box(visual_root, Vector3(0.26, 0.1, 0.26), Vector3(0, 0.24, 0), Color(0.92, 0.92, 0.9))
	elif type == "firstaid":
		_box(visual_root, Vector3(0.4, 0.16, 0.3), Vector3(0, 0.26, 0), Color(0.95, 0.95, 0.95))
		_box(visual_root, Vector3(0.2, 0.05, 0.06), Vector3(0, 0.36, 0), Color(0.85, 0.15, 0.15))
		_box(visual_root, Vector3(0.06, 0.05, 0.2), Vector3(0, 0.36, 0), Color(0.85, 0.15, 0.15))
	elif type == "medkit":
		_box(visual_root, Vector3(0.5, 0.24, 0.36), Vector3(0, 0.3, 0), Color(0.9, 0.25, 0.2))
		_box(visual_root, Vector3(0.26, 0.06, 0.08), Vector3(0, 0.44, 0), Color(0.95, 0.95, 0.95))
		_box(visual_root, Vector3(0.08, 0.06, 0.26), Vector3(0, 0.44, 0), Color(0.95, 0.95, 0.95))
	elif type == "drink" or type == "painkiller":
		var can := MeshInstance3D.new()
		var cyl2 := CylinderMesh.new()
		cyl2.top_radius = 0.07 if type == "drink" else 0.09
		cyl2.bottom_radius = cyl2.top_radius
		cyl2.height = 0.24 if type == "drink" else 0.16
		can.mesh = cyl2
		can.position = Vector3(0, 0.28, 0)
		can.material_override = _mat(Color(0.15, 0.75, 0.9) if type == "drink" else Color(0.95, 0.6, 0.15), 0.25)
		visual_root.add_child(can)
	elif type == "grenade":
		var g := MeshInstance3D.new()
		var gs := SphereMesh.new()
		gs.radius = 0.11
		gs.height = 0.22
		g.mesh = gs
		g.position = Vector3(0, 0.26, 0)
		g.material_override = _mat(Color(0.25, 0.32, 0.18))
		visual_root.add_child(g)
		_box(visual_root, Vector3(0.06, 0.08, 0.06), Vector3(0, 0.4, 0), Color(0.6, 0.6, 0.62))
	else: # crate
		_box(visual_root, Vector3(0.55, 0.4, 0.55), Vector3(0, 0.32, 0), Color(0.45, 0.38, 0.2))
		_box(visual_root, Vector3(0.57, 0.08, 0.57), Vector3(0, 0.55, 0), Color(0.35, 0.3, 0.16))
	# Floating name label.
	var label := Label3D.new()
	var main_node: Node = get_tree().get_first_node_in_group("main")
	if main_node != null and main_node.get("game_font") != null:
		label.font = main_node.get("game_font")
	label.text = display_name()
	label.font_size = 42
	label.pixel_size = 0.0038
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_begin = 0.0
	label.visibility_range_end = 26.0
	label.no_depth_test = true
	label.modulate = Color(1, 1, 1, 0.92)
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.position = Vector3(0, 1.05, 0)
	visual_root.add_child(label)

func _process(delta: float) -> void:
	t += delta
	if visual_root != null:
		visual_root.position.y = 0.06 * sin(t * 2.2)
		visual_root.rotation.y += delta * 0.9
