extends CanvasLayer
## HUD + menus + smartphone touch controls.

const Joystick := preload("res://joystick.gd")

var main
var player

var hp_bar: ProgressBar
var hp_label: Label
var stat_label: Label
var ammo_label: Label
var center_label: Label
var hint_label: Label
var damage_rect: ColorRect
var panel: PanelContainer
var panel_dim: ColorRect
var panel_title: Label
var panel_text: Label
var panel_button: Button

var touch_root: Control
var joystick: Control
var fire_button: Button
var jump_button: Button
var reload_button: Button
var touch_shown: bool = false

var look_touch_active: bool = false
var look_start_was_button: bool = false

func bind(p_main, p_player) -> void:
	main = p_main
	player = p_player

func _ready() -> void:
	_build_widgets()
	set_process(true)

func _build_widgets() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Damage flash overlay.
	damage_rect = ColorRect.new()
	damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_rect.color = Color(0.9, 0.1, 0.1, 0.0)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_rect)

	# Crosshair (4 thin bars + dot).
	var ch_color := Color(1, 1, 1, 0.9)
	for spec: Array in [[-14.0, -1.0, 9.0, 2.0], [5.0, -1.0, 9.0, 2.0], [-1.0, -14.0, 2.0, 9.0], [-1.0, 5.0, 2.0, 9.0], [-1.5, -1.5, 3.0, 3.0]]:
		var bar := ColorRect.new()
		bar.set_anchors_preset(Control.PRESET_CENTER)
		bar.position = Vector2(spec[0], spec[1])
		bar.size = Vector2(spec[2], spec[3])
		bar.color = ch_color
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)

	# Top-left: HP.
	hp_label = _make_label(root, Vector2(18, 12), 24, "HP 100")
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

	# Top-right: kills / remaining.
	stat_label = _make_label(root, Vector2(-320, 12), 24, "")
	stat_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_label.size = Vector2(300, 34)

	# Bottom-right: ammo.
	ammo_label = _make_label(root, Vector2(-240, -52), 26, "")
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.size = Vector2(220, 36)

	# Center message.
	center_label = _make_label(root, Vector2(-400, -120), 40, "")
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.size = Vector2(800, 60)
	center_label.modulate.a = 0.0

	# Bottom-center hint.
	hint_label = _make_label(root, Vector2(-400, -40), 18, "")
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.size = Vector2(800, 30)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))

	_build_panel(root)
	_build_touch_controls(root)

func _make_label(parent: Control, pos: Vector2, font_size: int, text: String) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_panel(root: Control) -> void:
	panel_dim = ColorRect.new()
	panel_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_dim.color = Color(0, 0, 0, 0.45)
	panel_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel_dim)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-260, -170)
	panel.size = Vector2(520, 340)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	panel_title = Label.new()
	panel_title.text = "POCKET TPS"
	panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_title.add_theme_font_size_override("font_size", 44)
	vbox.add_child(panel_title)

	panel_text = Label.new()
	panel_text.text = "ボットを全て倒せば勝ち。\n移動: WASD / 左スティック\n視点: マウス / 右側をドラッグ\n射撃: クリック長押し / FIREボタン"
	panel_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_text.add_theme_font_size_override("font_size", 20)
	vbox.add_child(panel_text)

	panel_button = Button.new()
	panel_button.text = "スタート"
	panel_button.custom_minimum_size = Vector2(0, 58)
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

	fire_button = _make_touch_button(touch_root, "FIRE", Vector2(-196, -196), Vector2(150, 150), Control.PRESET_BOTTOM_RIGHT)
	fire_button.button_down.connect(func() -> void: if player != null: player.set("touch_firing", true))
	fire_button.button_up.connect(func() -> void: if player != null: player.set("touch_firing", false))

	jump_button = _make_touch_button(touch_root, "JUMP", Vector2(-366, -140), Vector2(96, 96), Control.PRESET_BOTTOM_RIGHT)
	jump_button.pressed.connect(func() -> void: if player != null and player.has_method("request_jump"): player.request_jump())

	reload_button = _make_touch_button(touch_root, "RELOAD", Vector2(-176, -290), Vector2(96, 64), Control.PRESET_BOTTOM_RIGHT)
	reload_button.pressed.connect(func() -> void: if player != null and player.has_method("start_reload"): player.start_reload())

func _make_touch_button(parent: Control, text: String, pos: Vector2, btn_size: Vector2, preset: Control.LayoutPreset) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.set_anchors_preset(preset)
	btn.position = pos
	btn.size = btn_size
	btn.modulate.a = 0.8
	btn.add_theme_font_size_override("font_size", 20)
	parent.add_child(btn)
	return btn

func _process(_delta: float) -> void:
	# Show touch controls automatically on touch devices (or after first touch).
	if not touch_shown:
		if DisplayServer.is_touchscreen_available() or OS.has_feature("web_ios") or OS.has_feature("web_android"):
			_show_touch_controls()
	if touch_shown and player != null and joystick != null:
		player.set("touch_move", joystick.get("value"))
	# Keep hint in sync with mouse capture state.
	if main != null:
		var started: bool = main.get("started")
		var over: bool = main.get("is_game_over")
		if started and not over and not touch_shown and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			hint_label.text = "クリックで視点操作を再開（右ドラッグでも回せる）"
		elif started and not over:
			hint_label.text = ""
		else:
			hint_label.text = ""

func _show_touch_controls() -> void:
	touch_shown = true
	touch_root.visible = true

func _input(event: InputEvent) -> void:
	# First real touch anywhere: enable touch UI.
	if event is InputEventScreenTouch:
		if not touch_shown:
			_show_touch_controls()
	# Look-drag on touch devices: mouse-emulated motion with left button held,
	# starting on the right half and not on a button.
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
	for btn: Button in [fire_button, jump_button, reload_button]:
		if btn != null and btn.get_global_rect().has_point(pos):
			return true
	if joystick != null and (joystick as Control).get_global_rect().has_point(pos):
		return true
	return false

# --- Called from main ---

func set_hp(hp: int, max_hp: int) -> void:
	hp_label.text = "HP %d" % hp
	hp_bar.max_value = max_hp
	hp_bar.value = hp

func set_stats(kills: int, remaining: int, total: int) -> void:
	stat_label.text = "KILLS %d  残り %d / %d" % [kills, remaining, total]

func set_ammo(ammo: int, max_ammo: int, reloading: bool) -> void:
	ammo_label.text = "RELOAD中..." if reloading else "AMMO %d / %d" % [ammo, max_ammo]

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
