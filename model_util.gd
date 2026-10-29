extends RefCounted
## Shared helper: attach a free GLB character model to a body node,
## scale it to a target height, prepare its locomotion animation and tint.

static func attach_character(parent: Node3D, scene_path: String, target_height: float, tint: Color) -> Dictionary:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return {}
	var model: Node3D = packed.instantiate() as Node3D
	parent.add_child(model)

	# Find the first mesh and measure the model height to normalize scale.
	var mesh_instance: MeshInstance3D = _find_mesh(model)
	if mesh_instance != null:
		var aabb: AABB = mesh_instance.get_aabb()
		if aabb.size.y > 0.01:
			var s: float = target_height / aabb.size.y
			model.scale = Vector3.ONE * s
			# Keep feet on the ground: aabb position is in model space.
			model.position.y = -aabb.position.y * s
		if tint != Color.WHITE:
			var src_mat: Material = null
			if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
				src_mat = mesh_instance.mesh.surface_get_material(0)
			var mat := StandardMaterial3D.new()
			if src_mat is StandardMaterial3D and src_mat.albedo_texture != null:
				mat.albedo_texture = src_mat.albedo_texture
			mat.albedo_color = tint
			mesh_instance.material_override = mat

	var anim_player: AnimationPlayer = _find_anim_player(model)
	if anim_player != null:
		for anim_name: String in anim_player.get_animation_list():
			var anim: Animation = anim_player.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
	return {"model": model, "mesh": mesh_instance, "anim_player": anim_player}

static func set_locomotion(anim_player: AnimationPlayer, moving: bool, speed_ratio: float) -> void:
	if anim_player == null:
		return
	if moving:
		if not anim_player.is_playing():
			anim_player.play("Animation")
		anim_player.speed_scale = clampf(0.6 + speed_ratio * 0.9, 0.6, 1.6)
	else:
		if anim_player.is_playing():
			anim_player.pause()
		elif not anim_player.has_meta("idle_pose_set"):
			# Never played yet: settle into a neutral mid-cycle frame instead of the T-pose rest pose.
			anim_player.play("Animation")
			anim_player.seek(0.5, true)
			anim_player.pause()
			anim_player.set_meta("idle_pose_set", true)

static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh(child)
		if found != null:
			return found
	return null

static func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_anim_player(child)
		if found != null:
			return found
	return null

static func build_gear(model: Node3D) -> Dictionary:
	## PUBG-style worn gear attached to a character model: helmet dome,
	## armored vest block and a backpack. Positions are in model space
	## (feet at origin, character faces -Z, ~1.75m tall).
	var gear := {}
	var helmet := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.155
	dome.height = 0.28
	helmet.mesh = dome
	helmet.scale = Vector3(1.05, 0.75, 1.05)
	helmet.position = Vector3(0, 1.565, 0)
	helmet.visible = false
	model.add_child(helmet)
	gear["helmet"] = helmet
	var vest := MeshInstance3D.new()
	var vest_mesh := BoxMesh.new()
	vest_mesh.size = Vector3(0.37, 0.46, 0.26)
	vest.mesh = vest_mesh
	vest.position = Vector3(0, 1.06, -0.02)
	vest.visible = false
	model.add_child(vest)
	gear["vest"] = vest
	var pack := MeshInstance3D.new()
	var pack_mesh := BoxMesh.new()
	pack_mesh.size = Vector3(0.34, 0.46, 0.19)
	pack.mesh = pack_mesh
	pack.position = Vector3(0, 1.1, 0.21)
	pack.visible = false
	var pack_mat := StandardMaterial3D.new()
	pack_mat.albedo_color = Color(0.25, 0.32, 0.2)
	pack.material_override = pack_mat
	model.add_child(pack)
	gear["pack"] = pack
	return gear

static func set_gear(gear: Dictionary, helmet_lv: int, vest_lv: int, has_pack: bool) -> void:
	if gear.is_empty():
		return
	if int(gear.get("h_lv", -1)) == helmet_lv and int(gear.get("v_lv", -1)) == vest_lv and bool(gear.get("pack_on", false)) == has_pack:
		return
	gear["h_lv"] = helmet_lv
	gear["v_lv"] = vest_lv
	gear["pack_on"] = has_pack
	var helmet_cols: Array[Color] = [Color(0.42, 0.47, 0.36), Color(0.3, 0.36, 0.48), Color(0.16, 0.16, 0.18)]
	var vest_cols: Array[Color] = [Color(0.45, 0.5, 0.38), Color(0.34, 0.4, 0.34), Color(0.2, 0.22, 0.25)]
	var helmet: MeshInstance3D = gear.get("helmet")
	var vest: MeshInstance3D = gear.get("vest")
	var pack: MeshInstance3D = gear.get("pack")
	if helmet != null:
		helmet.visible = helmet_lv > 0
		if helmet_lv > 0:
			var hm := StandardMaterial3D.new()
			hm.albedo_color = helmet_cols[helmet_lv - 1]
			helmet.material_override = hm
	if vest != null:
		vest.visible = vest_lv > 0
		if vest_lv > 0:
			var vm := StandardMaterial3D.new()
			vm.albedo_color = vest_cols[vest_lv - 1]
			vest.material_override = vm
	if pack != null:
		pack.visible = has_pack
