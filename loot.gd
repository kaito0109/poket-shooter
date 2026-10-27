extends Node3D
## A ground pickup: medkit / drink / rifle upgrade / vest.
## Main polls distance and applies the effect.

var loot_type: String = "medkit"
var bob_phase: float = 0.0
var base_y: float = 0.55
var visual_root: Node3D

const COLORS: Dictionary = {
	"medkit": Color(0.95, 0.95, 0.95),
	"drink": Color(0.3, 0.75, 0.95),
	"rifle": Color(0.25, 0.25, 0.28),
	"vest": Color(0.35, 0.6, 0.35),
}

func setup(p_type: String) -> void:
	loot_type = p_type
	visual_root = Node3D.new()
	add_child(visual_root)
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	match p_type:
		"medkit":
			mesh.size = Vector3(0.55, 0.35, 0.55)
		"drink":
			mesh.size = Vector3(0.25, 0.4, 0.25)
		"rifle":
			mesh.size = Vector3(0.18, 0.25, 0.95)
		"vest":
			mesh.size = Vector3(0.55, 0.5, 0.4)
	body.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS.get(p_type, Color.WHITE)
	mat.emission_enabled = true
	mat.emission = COLORS.get(p_type, Color.WHITE) * 0.35
	body.material_override = mat
	visual_root.add_child(body)
	if p_type == "medkit":
		# Red cross on top.
		var cross := MeshInstance3D.new()
		var cross_mesh := BoxMesh.new()
		cross_mesh.size = Vector3(0.4, 0.06, 0.14)
		cross.mesh = cross_mesh
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.9, 0.15, 0.15)
		cross.material_override = red
		cross.position.y = 0.2
		visual_root.add_child(cross)
	bob_phase = randf() * TAU
	position.y = base_y

func _process(delta: float) -> void:
	bob_phase += delta * 2.2
	if visual_root != null:
		visual_root.position.y = sin(bob_phase) * 0.08
		visual_root.rotation.y += delta * 1.4

func display_name() -> String:
	match loot_type:
		"medkit":
			return "医療キット"
		"drink":
			return "エナジードリンク"
		"rifle":
			return "強化ライフル"
		"vest":
			return "防弾ベスト"
	return loot_type
