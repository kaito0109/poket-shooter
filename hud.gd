extends CanvasLayer
## HUD + menus + smartphone touch controls + minimap + kill feed.

const Joystick := preload("res://joystick.gd")
const Minimap := preload("res://minimap.gd")

var main
var player

var hp_bar: ProgressBar
var hp_label: Label
var items_label: Label
var stat_label: Label
var stat2_label: Label
var ammo_label: Label
var zone_label: Label
var center_label: Label
var hint_label: Label
var toast_label: Label
var damage_rect: ColorRect
var panel: PanelContainer
var panel_dim: ColorRect
var panel_title: Label
var panel_text: Label
var panel_button: Button
var minimap: Control
var heal_bar: ProgressBar
var heal_label: Label

var feed_labels: Array = []
var feed_index: int = 0
var hitmarker_parts: Array = []
var hit_markers: Array = []
var hit_marker_index: int = 0

var touch_root: Control
var joystick: Control
var fire_button: Button
var touch_shown: bool = false
var look_touch_active: bool = false
var look_start_was_button: bool = false

func bind(p_main, p_player) -> void:
	main = p_main
	player = p_player

func _ready() -> void:
	_build_widgets()
	set_process(true)

func _make_label(parent: Control, font_size: int, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_widgets() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	damage_rect = ColorRect.new()
	damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_rect.color = Color(0.9, 0.1, 0.1, 0.0)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_rect)

	# Crosshair.
	var ch_color := Color(1, 1, 1, 0.9)
	for spec: Array in [[-14.0, -1.0, 9.0, 2.0], [5.0, -1.0, 9.0, 2.0], [-1.0, -14.0, 2.0, 9.0], [-1.0, 5.0, 2.0, 9.0], [-1.5, -1.5, 3.0, 3.0]]:
		var bar := ColorRect.new()
		bar.set_anchors_preset(Control.PRESET_CENTER)
		bar.position = Vector2(spec[0], spec[1])
		bar.size = Vector2(spec[2], spec[3])
		bar.color = ch_color
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)

	# Hitmarker (diagonal ticks, flashed on hit).
	for spec: Array in [[-16.0, -16.0, 45.0], [7.0, -16.0, -45.0], [-16.0, 7.0, -45.0], [7.0, 7.0, 45.0]]:
		var tick := ColorRect.new()
		tick.set_anchors_preset(Control.PRESET_CENTER)
		tick.size = Vector2(11, 3)
		tick.pivot_offset = tick.size * 0.5
		tick.position = Vector2(spec[0], spec[1])
		tick.rotation_degrees = spec[2]
		tick.color = Color(1, 0.3, 0.2, 0.95)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.modulate.a = 0.0
		root.add_child(tick)
		hitmarker_parts.append(tick)

	# Directional hit indicators.
	for i in 6:
		var marker := ColorRect.new()
		marker.size = Vector2(34, 12)
		marker.pivot_offset = marker.size * 0.5
		marker.color = Color(1.0, 0.2, 0.15, 0.9)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.visible = false
		root.add_child(marker)
		hit_markers.append(marker)

	# Top-left: HP + items.
	hp_label = _make_label(root, 24, "HP 100")
	hp_label.position = Vector2(18, 12)
	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(18, 46)
	hp_bar.size = Vector2(250, 20)
	hp_bar.min_value = 0
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.85, 0.4)
	fill.set_corner_radius_all(4)
	hp_bar.add_theme_stylebox_override("background", bg)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_bar)
	items_label = _make_label(root, 17, "")
	items_label.position = Vector2(18, 74)

	# Top-right: ALIVE / KILLS.
	stat_label = _make_label(root, 26, "")
	stat_label.size = Vector2(300, 36)
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat2_label = _make_label(root, 19, "")
	stat2_label.size = Vector2(300, 28)
	stat2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Minimap under the stats.
	minimap = Minimap.new()
	root.add_child(minimap)

	# Kill feed under the minimap.
	for i in 4:
		var feed := _make_label(root, 16, "")
		feed.size = Vector2(330, 24)
		feed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		feed.modulate.a = 0.0
		feed_labels.append(feed)

	# Top-center: zone status.
	zone_label = _make_label(root, 20, "")
	zone_label.size = Vector2(460, 30)
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Bottom-right: ammo.
	ammo_label = _make_label(root, 26, "")
	ammo_label.size = Vector2(220, 36)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Center message + toast + hint.
	center_label = _make_label(root, 40, "")
	center_label.size = Vector2(800, 60)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.modulate.a = 0.0
	toast_label = _make_label(root, 19, "")
	toast_label.size = Vector2(700, 30)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate.a = 0.0
	hint_label = _make_label(root, 18, "")
	hint_label.size = Vector2(800, 30)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))

	# Heal progress.
	heal_label = _make_label(root, 16, "回復中…")
	heal_label.size = Vector2(240, 22)
	heal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heal_label.visible = false
	heal_bar = ProgressBar.new()
	heal_bar.size = Vector2(240, 10)
	heal_bar.min_value = 0
	heal_bar.max_value = 100
	heal_bar.value = 0
	heal_bar.show_percentage = false
	var hbg := StyleBoxFlat.new()
	hbg.bg_color = Color(0, 0, 0, 0.55)
	hbg.set_corner_radius_all(3)
	var hfill := StyleBoxFlat.new()
	hfill.bg_color = Color(0.95, 0.95, 0.95)
	hfill.set_corner_radius_all(3)
	heal_bar.add_theme_stylebox_override("background", hbg)
	heal_bar.add_theme_stylebox_override("fill", hfill)
	heal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heal_bar.visible = false
	root.add_child(heal_bar)

	_build_panel(root)
	_build_touch_controls(root)
	_layout_labels()
	get_viewport().size_changed.connect(_layout_labels)

func _layout_labels() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if stat_label != null:
		stat_label.position = Vector2(vp.x - 316.0, 10.0)
	if stat2_label != null:
		stat2_label.position = Vector2(vp.x - 316.0, 48.0)
	if minimap != null:
		minimap.position = Vector2(vp.x - 184.0, 84.0)
	for i in feed_labels.size():
		(feed_labels[i] as Label).position = Vector2(vp.x - 346.0, 262.0 + float(i) * 26.0)
	if zone_label != null:
		zone_label.position = Vector2(vp.x * 0.5 - 230.0, 10.0)
	if ammo_label != null:
		ammo_label.position = Vector2(vp.x - 236.0, vp.y - 54.0)
	if center_label != null:
		center_label.position = Vector2(vp.x * 0.5 - 400.0, vp.y * 0.5 - 170.0)
	if toast_label != null:
		toast_label.position = Vector2(vp.x * 0.5 - 350.0, vp.y - 186.0)
	if hint_label != null:
		hint_label.position = Vector2(vp.x * 0.5 - 400.0, vp.y - 44.0)
	if heal_bar != null:
		heal_bar.position = Vector2(vp.x * 0.5 - 120.0, vp.y - 128.0)
	if heal_label != null:
		heal_label.position = Vector2(vp.x * 0.5 - 120.0, vp.y - 154.0)

func _build_panel(root: Control) -> void:
	panel_dim = ColorRect.new()
	panel_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_dim.color = Color(0, 0, 0, 0.45)
	panel_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel_dim)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-270, -185)
	panel.size = Vector2(540, 370)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	panel_title = Label.new()
	panel_title.text = "POCKET TPS"
	panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_title.add_theme_font_size_override("font_size", 42)
	vbox.add_child(panel_title)

	panel_text = Label.new()
	panel_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_text.add_theme_font_size_override("font_size", 19)
	vbox.add_child(panel_text)

	panel_button = Button.new()
	panel_button.text = "スタート"
	panel_button.custom_minimum_size = Vector2(0, 56)
	panel_button.add_theme_font_size_override("font_size", 26)
	panel_button.pressed.connect(_on_panel_button_pressed)
	vbox.add_child(panel_button)

func _on_panel_button_pressed() -> void:
	if main != null and main.has_method("on_panel_button"):
		main.on_panel_button()

func show_panel(title: String, text: String, button_text: String) -> void:
	panel_title.text = title
	panel_text.text = text
	panel_button.text = button_text
	panel.visible = true
	panel_dim.visible = true

func hide_panel() -> void:
	panel.visible = false
	panel_dim.visible = false

func _build_touch_controls(root: Control) -> void:
	touch_root = Control.new()
	touch_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_root.visible = false
	root.add_child(touch_root)

	joystick = Joystick.new()
	joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick.position = Vector2(36, -230)
	touch_root.add_child(joystick)

	fire_button = _make_touch_button(touch_root, "FIRE", Vector2(-196, -196), Vector2(150, 150))
	fire_button.button_down.connect(func() -> void: if player != null: player.set("touch_firing", true))
	fire_button.button_up.connect(func() -> void: if player != null: player.set("touch_firing", false))

	var jump_button: Button = _make_touch_button(touch_root, "JUMP", Vector2(-372, -150), Vector2(96, 96))
	jump_button.pressed.connect(func() -> void: if player != null and player.has_method("request_jump"): player.request_jump())

	var reload_button: Button = _make_touch_button(touch_root, "RELOAD", Vector2(-176, -300), Vector2(96, 64))
	reload_button.pressed.connect(func() -> void: if player != null and player.has_method("start_reload"): player.start_reload())

	var aim_button: Button = _make_touch_button(touch_root, "狙う", Vector2(-372, -262), Vector2(96, 96))
	aim_button.toggle_mode = true
	aim_button.toggled.connect(func(on: bool) -> void: if player != null: player.set("touch_aiming", on))

	var crouch_button: Button = _make_touch_button(touch_root, "しゃがみ", Vector2(-276, -300), Vector2(88, 64))
	crouch_button.toggle_mode = true
	crouch_button.toggled.connect(func(_on: bool) -> void: if player != null and player.has_method("toggle_crouch"): player.toggle_crouch())

	var heal_button: Button = _make_touch_button(touch_root, "回復", Vector2(-372, -362), Vector2(96, 64))
	heal_button.pressed.connect(func() -> void: if player != null and player.has_method("start_heal"): player.start_heal())

	var drink_button: Button = _make_touch_button(touch_root, "ドリンク", Vector2(-276, -372), Vector2(88, 56))
	drink_button.pressed.connect(func() -> void: if player != null and player.has_method("use_drink"): player.use_drink())

func _make_touch_button(parent: Control, text: String, pos: Vector2, btn_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.position = pos
	btn.size = btn_size
	btn.modulate.a = 0.8
	btn.add_theme_font_size_override("font_size", 19)
	parent.add_child(btn)
	return btn

func _process(_delta: float) -> void:
	if not touch_shown:
		if DisplayServer.is_touchscreen_available() or OS.has_feature("web_ios") or OS.has_feature("web_android"):
			_show_touch_controls()
	if touch_shown and player != null and joystick != null:
		player.set("touch_move", joystick.get("value"))
	if main != null:
		var started: bool = main.get("started")
		var over: bool = main.get("is_game_over")
		if started and not over and not touch_shown and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			hint_label.text = "クリックで視点操作を再開（右ドラッグでも回せる）"
		else:
			hint_label.text = ""

func _show_touch_controls() -> void:
	touch_shown = true
	touch_root.visible = true

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not touch_shown:
			_show_touch_controls()
	if touch_shown and player != null:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var vp: Vector2 = get_viewport().get_visible_rect().size
				look_start_was_button = _point_on_touch_button(mb.position)
				look_touch_active = mb.pressed and mb.position.x > vp.x * 0.35 and not look_start_was_button
		elif event is InputEventMouseMotion and look_touch_active:
			var mm: InputEventMouseMotion = event as InputEventMouseMotion
			if player.has_method("add_look_input"):
				player.add_look_input(mm.relative)

func _point_on_touch_button(pos: Vector2) -> bool:
	if touch_root == null:
		return false
	for child: Node in touch_root.get_children():
		if child is Button and (child as Control).get_global_rect().has_point(pos):
			return true
	if joystick != null and (joystick as Control).get_global_rect().has_point(pos):
		return true
	return false

# --- Called from main ---

func set_hp(hp: int, max_hp: int) -> void:
	hp_label.text = "HP %d" % hp
	hp_bar.max_value = max_hp
	hp_bar.value = hp

func set_items(med: int, drink: int, vest: bool, rifle: bool) -> void:
	var line: String = "医療 %d   ドリンク %d" % [med, drink]
	var extras: Array[String] = []
	if vest:
		extras.append("ベスト装備")
	if rifle:
		extras.append("強化ライフル")
	if not extras.is_empty():
		line += "   ｜ " + " ・ ".join(extras)
	items_label.text = line

func set_stats(alive: int, kills: int) -> void:
	stat_label.text = "ALIVE %d" % alive
	stat2_label.text = "KILLS %d" % kills

func set_ammo(ammo: int, max_ammo: int, reloading: bool) -> void:
	ammo_label.text = "RELOAD中..." if reloading else "AMMO %d / %d" % [ammo, max_ammo]

func set_zone_status(text: String, danger: bool) -> void:
	zone_label.text = text
	zone_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if danger else Color(1, 1, 1, 0.85))

func set_minimap_buildings(rects: Array) -> void:
	if minimap != null and minimap.has_method("set_buildings"):
		minimap.set_buildings(rects)

func add_feed(text: String) -> void:
	var label: Label = feed_labels[feed_index]
	feed_index = (feed_index + 1) % feed_labels.size()
	label.text = text
	label.modulate.a = 1.0
	if label.has_meta("tween"):
		var old: Tween = label.get_meta("tween")
		if old != null and old.is_valid():
			old.kill()
	var tween: Tween = create_tween()
	label.set_meta("tween", tween)
	tween.tween_interval(4.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)

func flash_hitmarker() -> void:
	for part: ColorRect in hitmarker_parts:
		part.modulate.a = 1.0
		var tween: Tween = create_tween()
		tween.tween_property(part, "modulate:a", 0.0, 0.14)

func set_heal_progress(p: float) -> void:
	if p < 0.0:
		heal_bar.visible = false
		heal_label.visible = false
	else:
		heal_bar.visible = true
		heal_label.visible = true
		heal_bar.value = p * 100.0

func show_toast(text: String) -> void:
	toast_label.text = text
	if toast_label.has_meta("tween"):
		var old: Tween = toast_label.get_meta("tween")
		if old != null and old.is_valid():
			old.kill()
	var tween: Tween = create_tween()
	toast_label.set_meta("tween", tween)
	toast_label.modulate.a = 1.0
	tween.tween_interval(2.2)
	tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)

func flash_damage() -> void:
	var tween: Tween = create_tween()
	damage_rect.color.a = 0.32
	tween.tween_property(damage_rect, "color:a", 0.0, 0.45)

func show_center_message(text: String) -> void:
	center_label.text = text
	var tween: Tween = create_tween()
	center_label.modulate.a = 1.0
	tween.tween_interval(1.6)
	tween.tween_property(center_label, "modulate:a", 0.0, 0.6)

func show_hit_direction(attacker_pos: Vector3, player_pos: Vector3, yaw: float) -> void:
	if hit_markers.is_empty():
		return
	var dir3: Vector3 = attacker_pos - player_pos
	dir3.y = 0.0
	if dir3.length() < 0.5:
		return
	dir3 = dir3.normalized()
	var dir2 := Vector2(dir3.x, dir3.z)
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var ang: float = atan2(dir2.dot(right), dir2.dot(forward))
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var marker: ColorRect = hit_markers[hit_marker_index]
	hit_marker_index = (hit_marker_index + 1) % hit_markers.size()
	marker.position = center + Vector2(sin(ang), -cos(ang)) * 120.0 - marker.size * 0.5
	marker.rotation = ang
	marker.modulate.a = 1.0
	marker.visible = true
	if marker.has_meta("tween"):
		var old: Tween = marker.get_meta("tween")
		if old != null and old.is_valid():
			old.kill()
	var tween: Tween = create_tween()
	marker.set_meta("tween", tween)
	tween.tween_property(marker, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func() -> void: marker.visible = false)
