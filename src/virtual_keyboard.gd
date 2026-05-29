class_name VirtualKeyboard
extends Node3D

var main: Node3D
var viewport: SubViewport
var mesh_instance: MeshInstance3D
var area: Area3D
var collision_shape: CollisionShape3D
var grab_bar: MeshInstance3D = null
var grab_bar_area: Area3D = null
var mesh_size := Vector2(1.04, 0.3)
var viewport_size := Vector2i(2080, 600)
var _kb_width := 1640
var _tp_width := 440
var _key_area_width := 1600
var _kb_root: Control
var _key_data: Array = []
var _held_keys: Dictionary = {}
var _shift_on: bool = false
var _ctrl_on: bool = false
var _alt_on: bool = false
var _caps_on: bool = false

var trackpad_active: bool = false
var _last_hand_pos: Vector3 = Vector3.ZERO
var _sensitivity: float = 20000.0
var _dead_zone: float = 0.001
var _tp_border: PanelContainer
var _tp_hint_label: Label = null
var _tp_left_clicking: bool = false
var _tp_right_clicking: bool = false
var _tp_was_stick_click: bool = false

var _KEY_ROWS = [
	[{"k": KEY_ESCAPE, "l": "Esc", "w": 1.5}, {"k": KEY_F1, "l": "F1"}, {"k": KEY_F2, "l": "F2"}, {"k": KEY_F3, "l": "F3"}, {"k": KEY_F4, "l": "F4"}, {"k": KEY_F5, "l": "F5"}, {"k": KEY_F6, "l": "F6"}, {"k": KEY_F7, "l": "F7"}, {"k": KEY_F8, "l": "F8"}, {"k": KEY_F9, "l": "F9"}, {"k": KEY_F10, "l": "F10"}, {"k": KEY_F11, "l": "F11"}, {"k": KEY_F12, "l": "F12"}, {"k": KEY_DELETE, "l": "Del", "w": 1.5}],
	[{"k": KEY_QUOTELEFT, "l": "`"}, {"k": KEY_1, "l": "1"}, {"k": KEY_2, "l": "2"}, {"k": KEY_3, "l": "3"}, {"k": KEY_4, "l": "4"}, {"k": KEY_5, "l": "5"}, {"k": KEY_6, "l": "6"}, {"k": KEY_7, "l": "7"}, {"k": KEY_8, "l": "8"}, {"k": KEY_9, "l": "9"}, {"k": KEY_0, "l": "0"}, {"k": KEY_MINUS, "l": "-"}, {"k": KEY_EQUAL, "l": "="}, {"k": KEY_BACKSPACE, "l": "Bksp", "w": 2.0}],
	[{"k": KEY_TAB, "l": "Tab", "w": 1.5}, {"k": KEY_Q, "l": "Q"}, {"k": KEY_W, "l": "W"}, {"k": KEY_E, "l": "E"}, {"k": KEY_R, "l": "R"}, {"k": KEY_T, "l": "T"}, {"k": KEY_Y, "l": "Y"}, {"k": KEY_U, "l": "U"}, {"k": KEY_I, "l": "I"}, {"k": KEY_O, "l": "O"}, {"k": KEY_P, "l": "P"}, {"k": KEY_BRACKETLEFT, "l": "["}, {"k": KEY_BRACKETRIGHT, "l": "]"}, {"k": KEY_BACKSLASH, "l": "\\", "w": 1.5}],
	[{"k": KEY_CAPSLOCK, "l": "Caps", "w": 1.75}, {"k": KEY_A, "l": "A"}, {"k": KEY_S, "l": "S"}, {"k": KEY_D, "l": "D"}, {"k": KEY_F, "l": "F"}, {"k": KEY_G, "l": "G"}, {"k": KEY_H, "l": "H"}, {"k": KEY_J, "l": "J"}, {"k": KEY_K, "l": "K"}, {"k": KEY_L, "l": "L"}, {"k": KEY_SEMICOLON, "l": ";"}, {"k": KEY_APOSTROPHE, "l": "'"}, {"k": KEY_ENTER, "l": "Enter", "w": 2.25}],
	[{"k": KEY_SHIFT, "l": "Shift", "w": 2.25, "mod": "shift"}, {"k": KEY_Z, "l": "Z"}, {"k": KEY_X, "l": "X"}, {"k": KEY_C, "l": "C"}, {"k": KEY_V, "l": "V"}, {"k": KEY_B, "l": "B"}, {"k": KEY_N, "l": "N"}, {"k": KEY_M, "l": "M"}, {"k": KEY_COMMA, "l": ","}, {"k": KEY_PERIOD, "l": "."}, {"k": KEY_SLASH, "l": "/"}, {"k": KEY_SHIFT, "l": "Shift", "w": 2.75, "mod": "shift"}],
	[{"k": KEY_CTRL, "l": "Ctrl", "w": 1.5, "mod": "ctrl"}, {"k": KEY_ALT, "l": "Alt", "w": 1.5, "mod": "alt"}, {"k": KEY_META, "l": "Super", "w": 1.5}, {"k": KEY_SPACE, "l": "Space", "w": 6.0}, {"k": KEY_META, "l": "Super", "w": 1.5}, {"k": KEY_ALT, "l": "Alt", "w": 1.5, "mod": "alt"}, {"k": KEY_CTRL, "l": "Ctrl", "w": 1.5, "mod": "ctrl"}],
]

func _init(owner: Node3D):
	main = owner

func build():
	viewport = SubViewport.new()
	viewport.name = "KBViewport"
	viewport.size = viewport_size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	_kb_root = Control.new()
	_kb_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kb_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(_kb_root)

	var kb_bg = PanelContainer.new()
	kb_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var kb_style = StyleBoxFlat.new()
	kb_style.bg_color = Color(0.04, 0.04, 0.1, 0.85)
	kb_style.set_corner_radius_all(48)
	kb_bg.add_theme_stylebox_override("panel", kb_style)
	kb_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(kb_bg)

	_build_keys()
	_build_trackpad()

	var bottom_box = HBoxContainer.new()
	bottom_box.anchor_left = 0.0
	bottom_box.anchor_right = 1.0
	bottom_box.anchor_top = 1.0
	bottom_box.anchor_bottom = 1.0
	bottom_box.offset_top = -79
	bottom_box.offset_bottom = -37
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_theme_constant_override("separation", 0)
	viewport.add_child(bottom_box)

	var left_spacer = Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_child(left_spacer)

	var grab_bar = PanelContainer.new()
	grab_bar.name = "CompGrabBar"
	grab_bar.custom_minimum_size = Vector2(0, 38)
	grab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grab_style = StyleBoxFlat.new()
	grab_style.bg_color = Color(1, 1, 1, 0.08)
	grab_style.set_corner_radius_all(19)
	grab_bar.add_theme_stylebox_override("panel", grab_style)
	bottom_box.add_child(grab_bar)

	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_child(right_spacer)

	var quad = QuadMesh.new()
	quad.size = mesh_size
	quad.flip_faces = true
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "KBPanel"
	mesh_instance.mesh = quad
	var tex_mat = StandardMaterial3D.new()
	tex_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tex_mat.albedo_color = Color(1, 1, 1, 0.85)
	tex_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tex_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tex_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tex_mat.albedo_texture = viewport.get_texture()
	mesh_instance.set_surface_override_material(0, tex_mat)
	mesh_instance.extra_cull_margin = 10.0
	add_child(mesh_instance)

	area = Area3D.new()
	area.name = "Area3D"
	area.collision_layer = 2
	mesh_instance.add_child(area)
	var shape = BoxShape3D.new()
	shape.size = Vector3(mesh_size.x, mesh_size.y, 0.02)
	collision_shape = CollisionShape3D.new()
	collision_shape.shape = shape
	collision_shape.position = Vector3(0, 0, 0.01)
	area.add_child(collision_shape)

	grab_bar = null

	visible = false
	if area:
		area.process_mode = Node.PROCESS_MODE_DISABLED
		area.monitorable = false
		area.monitoring = false

func _build_keys():
	var key_h = 72
	var gap = 6
	var start_y = 16
	var base_w = (_key_area_width - 12 - gap * 14) / 15.0
	for row_idx in range(_KEY_ROWS.size()):
		var row = _KEY_ROWS[row_idx]
		var x = 26
		var y = start_y + row_idx * (key_h + gap)
		for key_idx in range(row.size()):
			var key_data = row[key_idx]
			var w_unit = key_data.get("w", 1.0)
			var btn_w = w_unit * base_w + (w_unit - 1.0) * gap
			var btn = Button.new()
			btn.name = "Key_%d_%d" % [row_idx, key_idx]
			btn.position = Vector2(x, y)
			btn.size = Vector2(btn_w, key_h)
			btn.text = key_data["l"]
			btn.add_theme_font_size_override("font_size", 24)
			btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
			btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
			var norm = _make_key_style(Color(0.2, 0.2, 0.22, 0.9), Color(0.35, 0.35, 0.38, 1.0))
			btn.add_theme_stylebox_override("normal", norm)
			var hover = _make_key_style(Color(0.3, 0.3, 0.35, 0.95), Color(0.5, 0.5, 0.55, 1.0))
			btn.add_theme_stylebox_override("hover", hover)
			var pressed = _make_key_style(Color(0.45, 0.5, 0.65, 1.0), Color(0.6, 0.65, 0.8, 1.0))
			btn.add_theme_stylebox_override("pressed", pressed)
			_kb_root.add_child(btn)
			_key_data.append({"btn": btn, "key": key_data["k"], "mod": key_data.get("mod", "")})
			x += btn_w + gap
	_apply_modifier_visuals()

func _build_trackpad():
	var margin = 26
	var tp_x = _kb_width + margin / 2
	var tp_visual_w = _tp_width - margin / 2 - margin
	var key_start_y = 16
	var key_h = 72
	var key_gap = 6
	var key_rows = 6
	var keys_height = key_rows * key_h + (key_rows - 1) * key_gap
	var tp_y = key_start_y
	var tp_h = keys_height

	var tp_bg = PanelContainer.new()
	tp_bg.position = Vector2(tp_x, tp_y)
	tp_bg.size = Vector2(tp_visual_w, tp_h)
	var tp_bg_style = StyleBoxFlat.new()
	tp_bg_style.bg_color = Color(0.05, 0.05, 0.1, 0.7)
	tp_bg_style.set_corner_radius_all(20)
	tp_bg_style.set_border_width_all(2)
	tp_bg_style.border_color = Color(0.25, 0.25, 0.35, 0.4)
	tp_bg.add_theme_stylebox_override("panel", tp_bg_style)
	tp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(tp_bg)

	_tp_border = PanelContainer.new()
	_tp_border.name = "TPBorder"
	_tp_border.position = Vector2(tp_x, tp_y)
	_tp_border.size = Vector2(tp_visual_w, tp_h)
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.set_corner_radius_all(20)
	border_style.set_border_width_all(3)
	border_style.border_color = Color(0.25, 0.25, 0.35, 0.4)
	_tp_border.add_theme_stylebox_override("panel", border_style)
	_tp_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(_tp_border)

	var cx = tp_x + tp_visual_w / 2.0
	var cy = tp_y + tp_h / 2.0

	var title = Label.new()
	title.text = "TRACKPAD"
	title.position = Vector2(tp_x, tp_y + 8)
	title.size = Vector2(tp_visual_w, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.6))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(title)

	var arrow_color = Color(0.4, 0.4, 0.5, 0.35)
	var arrow_len = 50

	var up_label = Label.new()
	up_label.text = "▲"
	up_label.position = Vector2(cx - 10, cy - arrow_len - 20)
	up_label.size = Vector2(20, 20)
	up_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	up_label.add_theme_font_size_override("font_size", 22)
	up_label.add_theme_color_override("font_color", arrow_color)
	up_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(up_label)

	var down_label = Label.new()
	down_label.text = "▼"
	down_label.position = Vector2(cx - 10, cy + arrow_len)
	down_label.size = Vector2(20, 20)
	down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	down_label.add_theme_font_size_override("font_size", 22)
	down_label.add_theme_color_override("font_color", arrow_color)
	down_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(down_label)

	var left_label = Label.new()
	left_label.text = "◀"
	left_label.position = Vector2(cx - arrow_len - 20, cy - 10)
	left_label.size = Vector2(20, 20)
	left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_label.add_theme_font_size_override("font_size", 22)
	left_label.add_theme_color_override("font_color", arrow_color)
	left_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(left_label)

	var right_label = Label.new()
	right_label.text = "▶"
	right_label.position = Vector2(cx + arrow_len, cy - 10)
	right_label.size = Vector2(20, 20)
	right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_label.add_theme_font_size_override("font_size", 22)
	right_label.add_theme_color_override("font_color", arrow_color)
	right_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(right_label)

	var hint = Label.new()
	hint.text = "Click trigger\nto activate"
	hint.name = "TPHint"
	hint.position = Vector2(tp_x, cy - 16)
	hint.size = Vector2(tp_visual_w, 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5, 0.4))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(hint)
	_tp_hint_label = hint

func _make_key_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_bg_color(bg)
	s.set_border_width_all(0)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(4)
	return s

func handle_pointer(pixel_pos: Vector2, clicking: bool, was_clicking: bool):
	if not visible:
		return

	if pixel_pos.x >= _kb_width:
		if clicking and not was_clicking and not trackpad_active:
			trackpad_active = true
			_last_hand_pos = main.right_hand.global_position
			_set_tp_active_visual(true)
			_update_tp_hint()
		return

	var ev_motion = InputEventMouseMotion.new()
	ev_motion.position = pixel_pos
	ev_motion.global_position = pixel_pos
	ev_motion.button_mask = MOUSE_BUTTON_MASK_LEFT if clicking else 0
	viewport.push_input(ev_motion)
	if clicking and not was_clicking:
		var ev = InputEventMouseButton.new()
		ev.position = pixel_pos
		ev.global_position = pixel_pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		viewport.push_input(ev)
		var key_code = _key_from_pos(pixel_pos)
		if key_code >= 0:
			_on_key_press(key_code)
	elif not clicking and was_clicking:
		var ev = InputEventMouseButton.new()
		ev.position = pixel_pos
		ev.global_position = pixel_pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = false
		viewport.push_input(ev)
		for kc in _held_keys.keys():
			_on_key_release(kc)
		_held_keys.clear()

func _set_tp_active_visual(active: bool):
	if not _tp_border:
		return
	var style = _tp_border.get_theme_stylebox("panel")
	if style and style is StyleBoxFlat:
		style = style.duplicate()
		if active:
			style.border_color = Color(0.3, 0.6, 1.0, 0.9)
		else:
			style.border_color = Color(0.25, 0.25, 0.35, 0.4)
		_tp_border.add_theme_stylebox_override("panel", style)
	_update_tp_hint()

func _update_tp_hint():
	if not _tp_hint_label:
		return
	if trackpad_active:
		_tp_hint_label.text = "Click thumbstick\nto exit"
		_tp_hint_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.8))
	else:
		_tp_hint_label.text = "Click trigger\nto activate"
		_tp_hint_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5, 0.4))

func _process(_delta):
	if not visible or not main.is_streaming:
		if trackpad_active:
			_deactivate_trackpad()
		return

	if not trackpad_active:
		return

	if main.right_hand:
		var stick_click = main.right_hand.is_button_pressed("primary_click")
		if stick_click and not _tp_was_stick_click:
			_deactivate_trackpad()
			_tp_was_stick_click = stick_click
			return
		_tp_was_stick_click = stick_click

	var trigger = main.right_hand.get_float("trigger") if main.right_hand else 0.0
	if trigger > 0.5 and not _tp_left_clicking:
		main.stream_backend.send_mouse_button_event(7, 1)
		_tp_left_clicking = true
	elif trigger <= 0.5 and _tp_left_clicking:
		main.stream_backend.send_mouse_button_event(8, 1)
		_tp_left_clicking = false

	var gripping = false
	if main.right_hand:
		gripping = main.right_hand.is_button_pressed("grip_click") or main.right_hand.get_float("grip") > 0.5
	if gripping and not _tp_right_clicking:
		main.stream_backend.send_mouse_button_event(7, 3)
		_tp_right_clicking = true
	elif not gripping and _tp_right_clicking:
		main.stream_backend.send_mouse_button_event(8, 3)
		_tp_right_clicking = false

	if main.right_hand:
		var stick_y = main.right_hand.get_vector2("primary").y
		if absf(stick_y) > 0.4:
			var clicks = int(stick_y * 0.8)
			if clicks != 0:
				main.stream_backend.send_scroll_event(clicks)

	var hand_pos = main.right_hand.global_position
	var delta_3d = hand_pos - _last_hand_pos

	if delta_3d.length() < _dead_zone:
		_last_hand_pos = hand_pos
		return

	var cam_right = main.xr_camera.global_transform.basis.x
	var cam_up = main.xr_camera.global_transform.basis.y

	var dx = delta_3d.dot(cam_right) * _sensitivity
	var dy = -delta_3d.dot(cam_up) * _sensitivity

	var idx = int(dx)
	var idy = int(dy)

	if idx != 0 or idy != 0:
		main.stream_backend.send_mouse_move_event(idx, idy)

	_last_hand_pos = hand_pos

func _deactivate_trackpad():
	trackpad_active = false
	_set_tp_active_visual(false)
	if _tp_left_clicking:
		main.stream_backend.send_mouse_button_event(8, 1)
		_tp_left_clicking = false
	if _tp_right_clicking:
		main.stream_backend.send_mouse_button_event(8, 3)
		_tp_right_clicking = false

func _key_from_pos(pixel_pos: Vector2) -> int:
	for kd in _key_data:
		var btn = kd["btn"]
		if pixel_pos.x >= btn.position.x and pixel_pos.x <= btn.position.x + btn.size.x \
			and pixel_pos.y >= btn.position.y and pixel_pos.y <= btn.position.y + btn.size.y:
			return kd["key"]
	return -1

func _on_key_press(key_code: int):
	if key_code == KEY_SHIFT:
		_shift_on = not _shift_on
		_apply_modifier_visuals()
		main.stream_backend.send_keyboard_event(KEY_SHIFT, 3 if _shift_on else 4, 0)
		if _shift_on:
			_held_keys[key_code] = true
		return
	if key_code == KEY_CTRL:
		_ctrl_on = not _ctrl_on
		_apply_modifier_visuals()
		main.stream_backend.send_keyboard_event(KEY_CTRL, 3 if _ctrl_on else 4, 0)
		if _ctrl_on:
			_held_keys[key_code] = true
		return
	if key_code == KEY_ALT:
		_alt_on = not _alt_on
		_apply_modifier_visuals()
		main.stream_backend.send_keyboard_event(KEY_ALT, 3 if _alt_on else 4, 0)
		if _alt_on:
			_held_keys[key_code] = true
		return
	if key_code == KEY_CAPSLOCK:
		_caps_on = not _caps_on
		_apply_modifier_visuals()
		main.stream_backend.send_keyboard_event(KEY_CAPSLOCK, 3, 0)
		main.stream_backend.send_keyboard_event(KEY_CAPSLOCK, 4, 0)
		return
	main.stream_backend.send_keyboard_event(key_code, 3, 0)
	_held_keys[key_code] = true

func _on_key_release(key_code: int):
	if key_code == KEY_SHIFT or key_code == KEY_CTRL or key_code == KEY_ALT:
		return
	main.stream_backend.send_keyboard_event(key_code, 4, 0)

func _apply_modifier_visuals():
	for kd in _key_data:
		var btn = kd["btn"]
		var mod = kd["mod"]
		var is_on = false
		if mod == "shift":
			is_on = _shift_on
		elif mod == "ctrl":
			is_on = _ctrl_on
		elif mod == "alt":
			is_on = _alt_on
		elif kd["key"] == KEY_CAPSLOCK:
			is_on = _caps_on
		else:
			continue
		var bg = Color(0.35, 0.45, 0.6, 1.0) if is_on else Color(0.2, 0.2, 0.22, 0.9)
		var border = Color(0.5, 0.6, 0.75, 1.0) if is_on else Color(0.35, 0.35, 0.38, 1.0)
		btn.add_theme_stylebox_override("normal", _make_key_style(bg, border))

var _saved_offset: Vector3 = Vector3.ZERO
var _saved_rot_y: float = 0.0
var _saved_rot_x: float = 0.0
var _has_saved_offset: bool = false

func toggle():
	var new_vis = not visible
	if new_vis:
		if _has_saved_offset:
			global_position = main.screen_mesh.global_position + main.screen_mesh.global_transform.basis * _saved_offset
			rotation.y = main.screen_mesh.global_rotation.y + _saved_rot_y
			rotation.x = _saved_rot_x
		else:
			var cam_pos = main.xr_camera.global_position
			var cam_fwd = -main.xr_camera.global_transform.basis.z
			global_position = cam_pos + cam_fwd * 1.0 + Vector3(0, -0.3, 0)
			var to_cam = (cam_pos - global_position).normalized()
			rotation = Vector3.ZERO
			rotation.y = atan2(to_cam.x, to_cam.z)
			rotation.x = -PI / 4.0
			_has_saved_offset = true
		_save_offset()
	visible = new_vis
	if area:
		area.process_mode = Node.PROCESS_MODE_INHERIT if new_vis else Node.PROCESS_MODE_DISABLED
		area.monitorable = new_vis
		area.monitoring = new_vis
	if not new_vis:
		_deactivate_trackpad()

func _save_offset():
	var scr_basis = main.screen_mesh.global_transform.basis.inverse()
	_saved_offset = scr_basis * (global_position - main.screen_mesh.global_position)
	_saved_rot_y = rotation.y - main.screen_mesh.global_rotation.y
	_saved_rot_x = rotation.x
	_has_saved_offset = true
