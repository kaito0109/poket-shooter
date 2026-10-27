extends Node3D
## Pocket TPS: world building, spawning, zone, loot, game state, effects.

const PlayerScript := preload("res://player.gd")
const EnemyScript := preload("res://enemy.gd")
const HudScript := preload("res://hud.gd")
const TracerScript := preload("res://tracer.gd")
const ZoneScript := preload("res://zone.gd")
const SfxScript := preload("res://sfx.gd")
const LootScript := preload("res://loot.gd")

const BOT_COUNT: int = 8
const WORLD_HALF: float = 68.0

var player: CharacterBody3D
var hud
var zone
var sfx: Node
var started: bool = false
var is_game_over: bool = false
var kills: int = 0
var bots_alive: int = 0
var panel_mode: String = "start"
var zone_tick_timer: float = 0.0
var loot_poll_timer: float = 0.0
var building_rects: Array = []

func _ready() -> void:
	add_to_group("main")
	_build_environment()
	_build_world()

	zone = ZoneScript.new()
	add_child(zone)
	zone.phase_changed.connect(_on_zone_phase_changed)

	sfx = SfxScript.new()
	add_child(sfx)

	player = PlayerScript.new()
	player.position = Vector3(0, 0.2, 26)
	add_child(player)

	_spawn_bots()
	_spawn_loot()

	hud = HudScript.new()
	add_child(hud)
	hud.bind(self, player)
	hud.set_minimap_buildings(building_rects)
	sync_hud()
	hud.show_panel("POCKET TPS",
		"最後の1人になるまで生き残れ！ ゾーンはどんどん縮まる。\n移動: WASD / 左スティック　視点: マウス\n射撃: クリック / FIRE　狙う: 右クリック長押し\nしゃがみ: C　一人称: V　回復: H（医療）/ F（ドリンク）",
		"スタート")

func _process(delta: float) -> void:
	if not started or is_game_over:
		return
	# Zone status + player zone damage.
	var player_outside: bool = zone.is_outside(player.global_position)
	hud.set_zone_status(zone.status_text(), player_outside)
	if player_outside and zone.current_dps > 0:
		zone_tick_timer += delta
		if zone_tick_timer >= 1.0:
			zone_tick_timer = 0.0
			player.call("take_damage", zone.current_dps, null, true)
			var center3 := Vector3(zone.center.x, player.global_position.y, zone.center.y)
			hud.show_hit_direction(center3, player.global_position, float(player.get("yaw")))
	else:
		zone_tick_timer = 0.0
	# Loot pickup polling.
	loot_poll_timer += delta
	if loot_poll_timer >= 0.15:
		loot_poll_timer = 0.0
		_poll_loot()

func _poll_loot() -> void:
	for item: Node in get_tree().get_nodes_in_group("loot"):
		var item3: Node3D = item as Node3D
		if item3.global_position.distance_to(player.global_position) < 1.8:
			var message: String = player.call("apply_loot", item.get("loot_type"))
			if message != "":
				hud.show_toast(message)
				sfx.call("play", "pickup", -4.0)
			item.queue_free()

func _on_zone_phase_changed() -> void:
	if not started or is_game_over:
		return
	if zone.state == "shrinking":
		hud.show_center_message("ゾーンが縮小している！")
		sfx.call("play", "zone", -4.0)

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.75)
	sky_mat.sky_horizon_color = Color(0.78, 0.83, 0.9)
	sky_mat.ground_bottom_color = Color(0.2, 0.24, 0.2)
	sky_mat.ground_horizon_color = Color(0.78, 0.83, 0.9)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.82, 0.92)
	env.fog_density = 0.003
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -38, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	add_child(sun)

func _static_box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
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
	add_child(body)
	return body

func _build_world() -> void:
	_static_box(Vector3(0, -0.5, 0), Vector3(WORLD_HALF * 2.0 + 8.0, 1.0, WORLD_HALF * 2.0 + 8.0), Color(0.36, 0.52, 0.3))

	var wall_color := Color(0.45, 0.47, 0.5)
	_static_box(Vector3(0, 1.5, -WORLD_HALF), Vector3(WORLD_HALF * 2.0, 3.0, 1.0), wall_color)
	_static_box(Vector3(0, 1.5, WORLD_HALF), Vector3(WORLD_HALF * 2.0, 3.0, 1.0), wall_color)
	_static_box(Vector3(-WORLD_HALF, 1.5, 0), Vector3(1.0, 3.0, WORLD_HALF * 2.0), wall_color)
	_static_box(Vector3(WORLD_HALF, 1.5, 0), Vector3(1.0, 3.0, WORLD_HALF * 2.0), wall_color)

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
		[Vector3(-4, 0, -6), Vector3(9, 5, 9), Color(0.6, 0.57, 0.5)],
		[Vector3(10, 0, 20), Vector3(8, 6, 8), Color(0.56, 0.6, 0.63)],
		[Vector3(-18, 0, 30), Vector3(10, 4, 7), Color(0.63, 0.6, 0.54)],
		[Vector3(34, 0, -12), Vector3(8, 7, 10), Color(0.59, 0.62, 0.59)],
	]
	for b: Array in buildings:
		var pos: Vector3 = b[0]
		var size: Vector3 = b[1]
		_static_box(Vector3(pos.x, size.y * 0.5, pos.z), size, b[2])
		_static_box(Vector3(pos.x, size.y + 0.25, pos.z), Vector3(size.x + 0.6, 0.5, size.z + 0.6), Color(0.3, 0.3, 0.33))
		building_rects.append(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z))

	# Low walls for crouch cover.
	var low_walls: Array = [
		[Vector3(-10, 0, -22), 0.0], [Vector3(6, 0, -14), 90.0], [Vector3(20, 0, 26), 0.0],
		[Vector3(-26, 0, -2), 90.0], [Vector3(2, 0, 36), 0.0], [Vector3(-38, 0, 30), 0.0],
		[Vector3(44, 0, 14), 90.0], [Vector3(-14, 0, -38), 0.0],
	]
	for w: Array in low_walls:
		var wpos: Vector3 = w[0]
		var rot_y: float = w[1]
		var wsize := Vector3(4.2, 1.1, 0.4) if rot_y == 0.0 else Vector3(0.4, 1.1, 4.2)
		_static_box(Vector3(wpos.x, 0.55, wpos.z), wsize, Color(0.58, 0.56, 0.52))

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	for i in 14:
		var cx: float = rng.randf_range(-55.0, 55.0)
		var cz: float = rng.randf_range(-55.0, 55.0)
		_static_box(Vector3(cx, 0.6, cz), Vector3(1.2, 1.2, 1.2), Color(0.55, 0.42, 0.28))

	# Rocks.
	for i in 9:
		var rx: float = rng.randf_range(-58.0, 58.0)
		var rz: float = rng.randf_range(-58.0, 58.0)
		var rock := StaticBody3D.new()
		rock.collision_layer = 1
		rock.collision_mask = 0
		rock.position = Vector3(rx, 0, rz)
		var rm := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var rr: float = rng.randf_range(0.9, 1.5)
		sphere.radius = rr
		sphere.height = rr * 2.0
		rm.mesh = sphere
		rm.scale = Vector3(1.3, 0.75, 1.1)
		rm.position.y = rr * 0.5
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.5, 0.5, 0.52)
		rm.material_override = rmat
		rock.add_child(rm)
		var rshape := CollisionShape3D.new()
		var rbox := BoxShape3D.new()
		rbox.size = Vector3(rr * 2.0, rr * 1.1, rr * 1.8)
		rshape.shape = rbox
		rshape.position.y = rr * 0.5
		rock.add_child(rshape)
		add_child(rock)

	for i in 16:
		var tx: float = rng.randf_range(-60.0, 60.0)
		var tz: float = rng.randf_range(-60.0, 60.0)
		_make_tree(Vector3(tx, 0, tz), rng)

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
	for i in spots.size():
		var bot: CharacterBody3D = EnemyScript.new()
		bot.position = spots[i]
		add_child(bot)
		var heavy: bool = (i == 2 or i == 5)
		bot.call("configure", "BOT-%02d" % (i + 1), 140 if heavy else 100, 1.06 if heavy else 1.0)

func _spawn_loot() -> void:
	var loot_spots: Array = [
		["medkit", Vector3(-20, 0, -12)], ["medkit", Vector3(14, 0, -20)],
		["medkit", Vector3(26, 0, 14)], ["medkit", Vector3(-28, 0, 20)],
		["medkit", Vector3(2, 0, -36)], ["medkit", Vector3(-2, 0, 2)],
		["drink", Vector3(-16, 0, -24)], ["drink", Vector3(22, 0, -32)],
		["drink", Vector3(36, 0, 4)], ["drink", Vector3(-36, 0, 8)],
		["drink", Vector3(6, 0, 30)],
		["rifle", Vector3(0, 0, -20)], ["rifle", Vector3(-40, 0, -28)],
		["vest", Vector3(18, 0, 14)], ["vest", Vector3(-10, 0, 40)],
		["vest", Vector3(44, 0, -32)],
	]
	for entry: Array in loot_spots:
		var item: Node3D = LootScript.new()
		item.add_to_group("loot")
		add_child(item)
		item.position = entry[1]
		item.call("setup", entry[0])

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
	zone.start_match()
	request_mouse_capture()
	hud.show_center_message("生き残れ！ ゾーンは縮小していく")

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
		sfx.call("play", "win", -2.0)
		hud.show_panel("CHICKEN DINNER!", "WINNER WINNER CHICKEN DINNER!\n全てのボットを倒した！（キル数: %d）" % kills, "もう一度プレイ")
	else:
		var rank: int = bots_alive + 1
		hud.show_panel("GAME OVER", "#%d 位 / %d 人中\nキル数: %d" % [rank, BOT_COUNT + 1, kills], "もう一度プレイ")

func on_bot_killed(bot: Node) -> void:
	bots_alive -= 1
	var bot_name: String = bot.get("bot_name")
	if bool(bot.get("last_hit_by_player")):
		kills += 1
		hud.add_feed("You ▸ %s を倒した" % bot_name)
		sfx.call("play", "die", -6.0)
		if bots_alive > 0:
			hud.show_center_message("キル！ 残り %d 体" % bots_alive)
	else:
		hud.add_feed("%s はゾーンで力尽きた" % bot_name)
	sync_hud()
	if bots_alive <= 0:
		game_over(true)

func on_player_damaged(_hp: int, _max_hp: int, attacker: Node3D = null) -> void:
	if attacker != null:
		hud.flash_damage()
		hud.show_hit_direction(attacker.global_position, player.global_position, float(player.get("yaw")))

func on_player_hit() -> void:
	hud.flash_hitmarker()
	sfx.call("play", "hit", -10.0)

func sync_hud() -> void:
	if hud == null or player == null:
		return
	hud.set_hp(player.get("hp"), 100)
	hud.set_ammo(player.get("ammo"), player.get("max_ammo"), player.get("reloading"))
	hud.set_items(player.get("medkits"), player.get("drinks"), player.get("has_vest"), player.get("rifle_upgraded"))
	var alive: int = bots_alive + (0 if bool(player.get("dead")) else 1)
	hud.set_stats(alive, kills)
	hud.set_heal_progress(player.call("heal_progress"))

# --- Effects ---

func spawn_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var tracer: MeshInstance3D = TracerScript.new()
	add_child(tracer)
	tracer.setup_line(from, to, color)

func spawn_spark(at_position: Vector3, color: Color) -> void:
	var spark: MeshInstance3D = TracerScript.new()
	add_child(spark)
	spark.setup_spark(at_position, color)
