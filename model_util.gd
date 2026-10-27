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
