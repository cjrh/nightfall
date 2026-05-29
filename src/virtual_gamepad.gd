class_name VirtualGamepad
extends Node3D

var main: Node3D
var viewport: SubViewport
var mesh_instance: MeshInstance3D
var area: Area3D
var collision_shape: CollisionShape3D
var mesh_size := Vector2(0.6, 0.36)
var viewport_size := Vector2i(1200, 720)
var _gp_root: Control

var _button_flags: int = 0
var _left_trigger: int = 0
var _right_trigger: int = 0
var _left_stick := Vector2.ZERO
var _right_stick := Vector2.ZERO
var _active: bool = false
var _send_timer: float = 0.0

var _left_stick_center: Vector2
var _right_stick_center: Vector2
var _left_stick_knob: Control
var _right_stick_knob: Control
var _left_stick_zone: Control
var _right_stick_zone: Control
var _stick_radius: float = 0.0

var _dragging_left_stick: bool = false
var _dragging_right_stick: bool = false
var _dragging_left_trigger: bool = false
var _dragging_right_trigger: bool = false

var _left_trigger_fill: ColorRect
var _right_trigger_fill: ColorRect
var _left_trigger_zone: Control
var _right_trigger_zone: Control

var _btn_data: Dictionary = {}

var _BTN_FLAGS = {
	"a": 0x1000,
	"b": 0x2000,
	"x": 0x4000,
	"y": 0x8000,
	"dp_up": 0x0001,
	"dp_down": 0x0002,
	"dp_left": 0x0004,
	"dp_right": 0x0008,
	"start": 0x0010,
	"back": 0x0020,
	"l3": 0x0040,
	"r3": 0x0080,
	"lb": 0x0100,
	"rb": 0x0200,
}

var _saved_offset: Vector3 = Vector3.ZERO
var _saved_rot_y: float = 0.0
var _saved_rot_x: float = 0.0
var _has_saved_offset: bool = false

func _init(owner: Node3D):
	main = owner

func build():
	viewport = SubViewport.new()
	viewport.name = "GPViewport"
	viewport.size = viewport_size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	_gp_root = Control.new()
	_gp_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gp_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(_gp_root)

	var bg = PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.04, 0.04, 0.1, 0.85)
	bg_style.set_corner_radius_all(48)
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gp_root.add_child(bg)

	_build_layout()

	var bottom_box = HBoxContainer.new()
	bottom_box.anchor_left = 0.0
	bottom_box.anchor_right = 1.0
	bottom_box.anchor_top = 1.0
	bottom_box.anchor_bottom = 1.0
	bottom_box.offset_top = -50
	bottom_box.offset_bottom = -10
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_theme_constant_override("separation", 0)
	viewport.add_child(bottom_box)

	var left_spacer = Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_child(left_spacer)

	var grab_bar = PanelContainer.new()
	grab_bar.name = "CompGrabBar"
	grab_bar.custom_minimum_size = Vector2(0, 34)
	grab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grab_style = StyleBoxFlat.new()
	grab_style.bg_color = Color(1, 1, 1, 0.08)
	grab_style.set_corner_radius_all(17)
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
	mesh_instance.name = "GPPanel"
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
	area.name = "GPArea3D"
	area.collision_layer = 2
	mesh_instance.add_child(area)
	var shape = BoxShape3D.new()
	shape.size = Vector3(mesh_size.x, mesh_size.y, 0.02)
	collision_shape = CollisionShape3D.new()
	collision_shape.shape = shape
	collision_shape.position = Vector3(0, 0, 0.01)
	area.add_child(collision_shape)

	visible = false
	if area:
		area.process_mode = Node.PROCESS_MODE_DISABLED
		area.monitorable = false
		area.monitoring = false

func _make_btn_style(bg: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_bg_color(bg)
	s.set_border_width_all(0)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(4)
	return s

func _make_btn(label: String, x: float, y: float, w: float, h: float, id: String) -> Button:
	var btn = Button.new()
	btn.name = id
	btn.position = Vector2(x, y)
	btn.size = Vector2(w, h)
	btn.text = label
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	btn.add_theme_stylebox_override("normal", _make_btn_style(Color(0.2, 0.2, 0.22, 0.9)))
	btn.add_theme_stylebox_override("hover", _make_btn_style(Color(0.3, 0.3, 0.35, 0.95)))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(Color(0.45, 0.5, 0.65, 1.0)))
	_gp_root.add_child(btn)
	_btn_data[id] = {"btn": btn, "flag": _BTN_FLAGS.get(id, 0), "type": "button"}
	return btn

func _make_stick_zone(x: float, y: float, r: float, id: String) -> Control:
	var zone = Control.new()
	zone.name = id + "_zone"
	zone.position = Vector2(x - r, y - r)
	zone.size = Vector2(r * 2, r * 2)
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gp_root.add_child(zone)

	var bg_circle = ColorRect.new()
	bg_circle.position = Vector2(0, 0)
	bg_circle.size = Vector2(r * 2, r * 2)
	bg_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://src/shaders/circle_cursor.gdshader")
	bg_circle.material = mat
	zone.add_child(bg_circle)

	var knob = Control.new()
	knob.name = id + "_knob"
	knob.position = Vector2(r, r)
	knob.size = Vector2(1, 1)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(knob)

	var knob_circle = ColorRect.new()
	knob_circle.position = Vector2(-r * 0.25, -r * 0.25)
	knob_circle.size = Vector2(r * 0.5, r * 0.5)
	knob_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var knob_mat = ShaderMaterial.new()
	knob_mat.shader = preload("res://src/shaders/circle_cursor.gdshader")
	knob_mat.set_shader_parameter("color", Color(0.7, 0.7, 0.75, 0.9))
	knob_circle.material = knob_mat
	knob.add_child(knob_circle)

	_btn_data[id] = {"zone": zone, "knob": knob, "center": Vector2(x, y), "radius": r, "type": "stick"}
	return zone

func _make_trigger_zone(x: float, y: float, w: float, h: float, id: String) -> Control:
	var zone = Control.new()
	zone.name = id + "_zone"
	zone.position = Vector2(x, y)
	zone.size = Vector2(w, h)
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gp_root.add_child(zone)

	var bg = ColorRect.new()
	bg.position = Vector2(0, 0)
	bg.size = Vector2(w, h)
	bg.color = Color(0.15, 0.15, 0.18, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(bg)

	var fill = ColorRect.new()
	fill.position = Vector2(0, h)
	fill.size = Vector2(w, 0)
	fill.color = Color(0.35, 0.5, 0.7, 0.9)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(fill)

	var label = Label.new()
	label.text = "LT" if id == "lt" else "RT"
	label.position = Vector2(0, 0)
	label.size = Vector2(w, h)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(label)

	_btn_data[id] = {"zone": zone, "fill": fill, "zone_h": h, "type": "trigger"}
	return zone

func _build_layout():
	var pad = 30
	var cw = viewport_size.x
	var ch = viewport_size.y
	var center_y = ch * 0.52

	var bumper_w = 80
	var bumper_h = 36
	var bumper_y = 55

	_make_btn("LB", 60, bumper_y, bumper_w, bumper_h, "lb")
	_make_btn("RB", cw - 60 - bumper_w, bumper_y, bumper_w, bumper_h, "rb")

	_make_trigger_zone(45, bumper_y + bumper_h + 8, 55, 100, "lt")
	_make_trigger_zone(cw - 45 - 55, bumper_y + bumper_h + 8, 55, 100, "rt")

	_left_trigger_zone = _btn_data["lt"]["zone"]
	_left_trigger_fill = _btn_data["lt"]["fill"]
	_right_trigger_zone = _btn_data["rt"]["zone"]
	_right_trigger_fill = _btn_data["rt"]["fill"]

	_stick_radius = 55.0
	var left_stick_x = 160.0
	var right_stick_x = cw - 160.0
	var stick_y = center_y + 20

	_left_stick_zone = _make_stick_zone(left_stick_x, stick_y, _stick_radius, "l_stick")
	_right_stick_zone = _make_stick_zone(right_stick_x, stick_y, _stick_radius, "r_stick")
	_left_stick_center = Vector2(left_stick_x, stick_y)
	_right_stick_center = Vector2(right_stick_x, stick_y)
	_left_stick_knob = _btn_data["l_stick"]["knob"]
	_right_stick_knob = _btn_data["r_stick"]["knob"]

	_make_btn("L3", left_stick_x - 22, stick_y - 12, 44, 24, "l3")
	_make_btn("R3", right_stick_x - 22, stick_y - 12, 44, 24, "r3")

	var dp_size = 52
	var dp_gap = 4
	var dp_cx = left_stick_x
	var dp_cy = stick_y + _stick_radius + 30

	_make_btn("▲", dp_cx - dp_size / 2, dp_cy - dp_size - dp_gap, dp_size, dp_size, "dp_up")
	_make_btn("▼", dp_cx - dp_size / 2, dp_cy + dp_gap, dp_size, dp_size, "dp_down")
	_make_btn("◀", dp_cx - dp_size - dp_gap, dp_cy - dp_size / 2, dp_size, dp_size, "dp_left")
	_make_btn("▶", dp_cx + dp_gap, dp_cy - dp_size / 2, dp_size, dp_size, "dp_right")

	var ab_size = 56
	var ab_gap = 6
	var ab_cx = right_stick_x
	var ab_cy = dp_cy

	_make_btn("Y", ab_cx - ab_size / 2, ab_cy - ab_size - ab_gap, ab_size, ab_size, "y")
	_make_btn("X", ab_cx - ab_size - ab_gap, ab_cy - ab_size / 2, ab_size, ab_size, "x")
	_make_btn("B", ab_cx + ab_gap, ab_cy - ab_size / 2, ab_size, ab_size, "b")
	_make_btn("A", ab_cx - ab_size / 2, ab_cy + ab_gap, ab_size, ab_size, "a")

	var menu_w = 52
	var menu_h = 36
	var menu_y = center_y - 30

	_make_btn("◀", cw / 2 - menu_w - 8, menu_y, menu_w, menu_h, "back")
	_make_btn("▶", cw / 2 + 8, menu_y, menu_w, menu_h, "start")

	var title = Label.new()
	title.text = "GAMEPAD"
	title.position = Vector2(0, 10)
	title.size = Vector2(cw, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.7))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gp_root.add_child(title)

func handle_pointer(pixel_pos: Vector2, clicking: bool, was_clicking: bool):
	if not visible:
		return

	if clicking and not was_clicking:
		_check_stick_start(pixel_pos)
		_check_trigger_start(pixel_pos)
		_check_button_press(pixel_pos)

	if clicking:
		if _dragging_left_stick:
			_update_stick_drag(pixel_pos, "l_stick", _left_stick_center)
		if _dragging_right_stick:
			_update_stick_drag(pixel_pos, "r_stick", _right_stick_center)
		if _dragging_left_trigger:
			_update_trigger_drag(pixel_pos, "lt")
		if _dragging_right_trigger:
			_update_trigger_drag(pixel_pos, "rt")

	elif not clicking and was_clicking:
		if _dragging_left_stick:
			_release_stick("l_stick")
		if _dragging_right_stick:
			_release_stick("r_stick")
		if _dragging_left_trigger:
			_release_trigger("lt")
		if _dragging_right_trigger:
			_release_trigger("rt")
		_release_all_buttons()

	_send_controller_state()
	_send_timer = 0.033

func _check_stick_start(pixel_pos: Vector2):
	for stick_id in ["l_stick", "r_stick"]:
		var data = _btn_data[stick_id]
		var center = data["center"]
		var r = data["radius"]
		var dist = pixel_pos.distance_to(center)
		if dist <= r:
			if stick_id == "l_stick":
				_dragging_left_stick = true
			else:
				_dragging_right_stick = true
			_update_stick_drag(pixel_pos, stick_id, center)
			return

func _check_trigger_start(pixel_pos: Vector2):
	for trig_id in ["lt", "rt"]:
		var data = _btn_data[trig_id]
		var zone: Control = data["zone"]
		var local = pixel_pos - zone.position
		if local.x >= 0 and local.x <= zone.size.x and local.y >= 0 and local.y <= zone.size.y:
			if trig_id == "lt":
				_dragging_left_trigger = true
			else:
				_dragging_right_trigger = true
			_update_trigger_drag(pixel_pos, trig_id)
			return

func _check_button_press(pixel_pos: Vector2):
	for id in _btn_data:
		var data = _btn_data[id]
		if data["type"] != "button":
			continue
		var btn: Button = data["btn"]
		if pixel_pos.x >= btn.position.x and pixel_pos.x <= btn.position.x + btn.size.x \
			and pixel_pos.y >= btn.position.y and pixel_pos.y <= btn.position.y + btn.size.y:
			_button_flags |= data["flag"]
			btn.add_theme_stylebox_override("normal", _make_btn_style(Color(0.45, 0.5, 0.65, 1.0)))
			_active = true
			_send_timer = 0.016
			return

func _update_stick_drag(pixel_pos: Vector2, stick_id: String, center: Vector2):
	var data = _btn_data[stick_id]
	var r = data["radius"]
	var offset = pixel_pos - center
	var dist = offset.length()
	if dist > r:
		offset = offset.normalized() * r
	var norm = offset / r
	var knob: Control = data["knob"]
	knob.position = center + offset - data["zone"].position

	if stick_id == "l_stick":
		_left_stick = norm
	else:
		_right_stick = norm
	_active = true
	_send_timer = 0.016

func _update_trigger_drag(pixel_pos: Vector2, trig_id: String):
	var data = _btn_data[trig_id]
	var zone: Control = data["zone"]
	var fill: ColorRect = data["fill"]
	var zone_h: float = data["zone_h"]
	var local_y = clampf(pixel_pos.y - zone.position.y, 0, zone_h)
	var val = 1.0 - (local_y / zone_h)
	fill.position.y = zone_h * (1.0 - val)
	fill.size.y = zone_h * val
	if trig_id == "lt":
		_left_trigger = int(val * 255.0)
	else:
		_right_trigger = int(val * 255.0)
	_active = true
	_send_timer = 0.016

func _release_stick(stick_id: String):
	var data = _btn_data[stick_id]
	var knob: Control = data["knob"]
	knob.position = data["center"] - data["zone"].position
	if stick_id == "l_stick":
		_dragging_left_stick = false
		_left_stick = Vector2.ZERO
	else:
		_dragging_right_stick = false
		_right_stick = Vector2.ZERO
	_send_timer = 0.016

func _release_trigger(trig_id: String):
	var data = _btn_data[trig_id]
	var fill: ColorRect = data["fill"]
	fill.position.y = data["zone_h"]
	fill.size.y = 0
	if trig_id == "lt":
		_dragging_left_trigger = false
		_left_trigger = 0
	else:
		_dragging_right_trigger = false
		_right_trigger = 0
	_send_timer = 0.016

func _release_all_buttons():
	for id in _btn_data:
		var data = _btn_data[id]
		if data["type"] != "button":
			continue
		if _button_flags & data["flag"]:
			_button_flags &= ~data["flag"]
			data["btn"].add_theme_stylebox_override("normal", _make_btn_style(Color(0.2, 0.2, 0.22, 0.9)))
	_send_timer = 0.016

func _process(delta):
	if not visible or not main.is_streaming:
		return
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_controller_state()
		_send_timer = 0.033

func _send_controller_state():
	var lx = int(_left_stick.x * 32767.0)
	var ly = int(-_left_stick.y * 32767.0)
	var rx = int(_right_stick.x * 32767.0)
	var ry = int(-_right_stick.y * 32767.0)
	main.stream_backend.send_multi_controller_event(0, 1, _button_flags, _left_trigger, _right_trigger, lx, ly, rx, ry)

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
			global_position = cam_pos + cam_fwd * 1.0 + Vector3(0, -0.35, 0)
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
		_button_flags = 0
		_left_trigger = 0
		_right_trigger = 0
		_left_stick = Vector2.ZERO
		_right_stick = Vector2.ZERO
		_dragging_left_stick = false
		_dragging_right_stick = false
		_dragging_left_trigger = false
		_dragging_right_trigger = false
		_send_controller_state()

func _save_offset():
	var scr_basis = main.screen_mesh.global_transform.basis.inverse()
	_saved_offset = scr_basis * (global_position - main.screen_mesh.global_position)
	_saved_rot_y = rotation.y - main.screen_mesh.global_rotation.y
	_saved_rot_x = rotation.x
	_has_saved_offset = true
