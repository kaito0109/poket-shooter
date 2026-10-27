extends Node3D
## Pocket TPS: world building, spawning, game state, effects.

const PlayerScript := preload("res://player.gd")
const EnemyScript := preload("res://enemy.gd")
const HudScript := preload("res://hud.gd")
const TracerScript := preload("res://tracer.gd")

const BOT_COUNT: int = 8
const WORLD_HALF: float = 68.0

var player: CharacterBody3D
var hud
var started: bool = false
var is_game_over: bool = false
var kills: int = 0
var bots_alive: int = 0
var panel_mode: String = "start"

func _ready() -> void:
	add_to_group("main")
	_build_environment()
	_build_world()

	player = PlayerScript.new()
	player.position = Vector3(0, 0.2, 26)
	add_child(player)

	_spawn_bots()

	hud = HudScript.new()
	add_child(hud)
	hud.bind(self, player)
	hud.set_hp(100, 100)
	hud.set_stats(0, bots_alive, BOT_COUNT)
	hud.set_ammo(30, 30, false)
	hud.show_panel("POCKET TPS",
		"ボットを全て倒せば勝ち。\n移動: WASD / 左スティック\n視点: マウス / 右側をドラッグ\n射撃: クリック長押し / FIREボタン",
		"スタート")

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.46, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.92)
	sky_mat.ground_bottom_color = Color(0.2, 0.24, 0.2)
	sky_mat.ground_horizon_color = Color(0.72, 0.82, 0.92)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.82, 0.92)
	env.fog_density = 0.0035
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

func _static_box(pos: Vector3, size: Vector3, color: Color, parent: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	(parent if parent != null else self).add_child(body)
	return body

func _build_world() -> void:
	# Ground.
	_static_box(Vector3(0, -0.5, 0), Vector3(WORLD_HALF * 2.0 + 8.0, 1.0, WORLD_HALF * 2.0 + 8.0), Color(0.36, 0.52, 0.3))

	# Perimeter walls.
	var wall_color := Color(0.45, 0.47, 0.5)
	_static_box(Vector3(0, 1.5, -WORLD_HALF), Vector3(WORLD_HALF * 2.0, 3.0, 1.0), wall_color)
	_static_box(Vector3(0, 1.5, WORLD_HALF), Vector3(WORLD_HALF * 2.0, 3.0, 1.0), wall_color)
	_static_box(Vector3(-WORLD_HALF, 1.5, 0), Vector3(1.0, 3.0, WORLD_HALF * 2.0), wall_color)
	_static_box(Vector3(WORLD_HALF, 1.5, 0), Vector3(1.0, 3.0, WORLD_HALF * 2.0), wall_color)

	# Buildings (deterministic layout).
	var buildings: Array = [
		[Vector3(-22, 0, -18), Vector3(12, 7, 10), Color(0.62, 0.58, 0.52)],
		[Vector3(16, 0, -26), Vector3(10, 10, 12), Color(0.55, 0.6, 0.66)],
		[Vector3(28, 0, 8), Vector3(14, 5, 9), Color(0.66, 0.6, 0.5)],
		[Vector3(-30, 0, 14), Vector3(11, 6, 11), Color(0.58, 0.63, 0.58)],
		[Vector3(0, 0, -42), Vector3(16, 8, 8), Color(0.6, 0.55, 0.62)],
		[Vector3(-8, 0, 44), Vector3(12, 4, 10), Color(0.64, 0.62, 0.55)],
		[Vector3(40, 0, -38), Vector3(9, 12, 9), Color(0.52, 0.58, 0.64)],
		[Vector3(-44, 0, -34), Vector3(10, 5, 14), Color(0.6, 0.64, 0.6)],
		[Vector3(48, 0, 34), Vector3(12, 6, 12), Color(0.63, 0.59, 0.53)],
		[Vector3(-48, 0, 40), Vector3(9, 9, 9), Color(0.57, 0.61, 0.67)],
	]
	for b: Array in buildings:
		var pos: Vector3 = b[0]
		var size: Vector3 = b[1]
		_static_box(Vector3(pos.x, size.y * 0.5, pos.z), size, b[2])
		# Roof trim.
		_static_box(Vector3(pos.x, size.y + 0.25, pos.z), Vector3(size.x + 0.6, 0.5, size.z + 0.6), Color(0.3, 0.3, 0.33))

	# Crates (cover).
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	for i in 14:
		var cx: float = rng.randf_range(-55.0, 55.0)
		var cz: float = rng.randf_range(-55.0, 55.0)
		_static_box(Vector3(cx, 0.6, cz), Vector3(1.2, 1.2, 1.2), Color(0.55, 0.42, 0.28))

	# Trees: trunk + foliage, collision on trunk only.
	for i in 16:
		var tx: float = rng.randf_range(-60.0, 60.0)
		var tz: float = rng.randf_range(-60.0, 60.0)
		_make_tree(Vector3(tx, 0, tz), rng)

	# Grass patches for texture.
	for i in 26:
		var px: float = rng.randf_range(-62.0, 62.0)
		var pz: float = rng.randf_range(-62.0, 62.0)
		var patch := MeshInstance3D.new()
		var plane := BoxMesh.new()
		plane.size = Vector3(rng.randf_range(4.0, 9.0), 0.04, rng.randf_range(4.0, 9.0))
		patch.mesh = plane
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.3, 0.46, 0.26)
		patch.material_override = pmat
		patch.position = Vector3(px, 0.02, pz)
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(patch)

func _make_tree(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.24
	trunk_mesh.height = 2.2
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.29, 0.18)
	trunk.material_override = trunk_mat
	body.add_child(trunk)
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 2.2
	shape_node.shape = shape
	shape_node.position.y = 1.1
	body.add_child(shape_node)
	var foliage := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = rng.randf_range(1.1, 1.6)
	sphere.height = sphere.radius * 2.0
	foliage.mesh = sphere
	foliage.position.y = 2.2 + sphere.radius * 0.8
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.24, 0.45, 0.22)
	foliage.material_override = leaf_mat
	body.add_child(foliage)
	add_child(body)

func _spawn_bots() -> void:
	var spots: Array[Vector3] = [
		Vector3(-34, 0.2, -30), Vector3(30, 0.2, -40), Vector3(44, 0.2, 0),
		Vector3(-44, 0.2, 22), Vector3(12, 0.2, -8), Vector3(-14, 0.2, -48),
		Vector3(52, 0.2, 48), Vector3(-56, 0.2, -6),
	]
	bots_alive = spots.size()
	for spot: Vector3 in spots:
		var bot: CharacterBody3D = EnemyScript.new()
		bot.position = spot
		add_child(bot)

# --- Game flow ---

func on_panel_button() -> void:
	if panel_mode == "start":
		start_game()
	else:
		get_tree().reload_current_scene()

func start_game() -> void:
	started = true
	panel_mode = "restart"
	hud.hide_panel()
	player.set("input_enabled", true)
	for bot: Node in get_tree().get_nodes_in_group("enemies"):
		bot.set("active", true)
	request_mouse_capture()
	hud.show_center_message("ボットを全て倒せ！")

func request_mouse_capture() -> void:
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func game_over(won: bool) -> void:
	if is_game_over:
		return
	is_game_over = true
	player.set("input_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if won:
		hud.show_panel("WINNER!", "ボットを全て倒した！\nキル数: %d" % kills, "もう一度プレイ")
	else:
		hud.show_panel("GAME OVER", "やられてしまった…\nキル数: %d / %d" % [kills, BOT_COUNT], "もう一度プレイ")

func on_bot_killed(_bot: Node) -> void:
	kills += 1
	bots_alive -= 1
	hud.set_stats(kills, bots_alive, BOT_COUNT)
	if bots_alive <= 0:
		game_over(true)
	else:
		hud.show_center_message("キル！ 残り %d 体" % bots_alive)

func on_player_damaged(hp: int, max_hp: int) -> void:
	hud.set_hp(hp, max_hp)
	hud.flash_damage()

func on_ammo_changed(ammo: int, max_ammo: int, reloading: bool) -> void:
	hud.set_ammo(ammo, max_ammo, reloading)

# --- Effects ---

func spawn_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var tracer: MeshInstance3D = TracerScript.new()
	add_child(tracer)
	tracer.setup_line(from, to, color)

func spawn_spark(at_position: Vector3, color: Color) -> void:
	var spark: MeshInstance3D = TracerScript.new()
	add_child(spark)
	spark.setup_spark(at_position, color)
