class_name VirtualTrackpad
extends Node3D

var main: Node3D
var viewport: SubViewport
var mesh_instance: MeshInstance3D
var area: Area3D
var collision_shape: CollisionShape3D
var mesh_size := Vector2(0.25, 0.25)
var viewport_size := Vector2i(500, 500)
var _tp_root: Control
var _border: PanelContainer
var _bg: PanelContainer

var trackpad_active: bool = false
var _last_hand_pos: Vector3 = Vector3.ZERO
var _sensitivity: float = 20000.0
var _dead_zone: float = 0.001

var _saved_offset: Vector3 = Vector3.ZERO
var _saved_rot_y: float = 0.0
var _saved_rot_x: float = 0.0
var _has_saved_offset: bool = false

func _init(owner: Node3D):
	main = owner

func build():
	viewport = SubViewport.new()
	viewport.name = "TPViewport"
	viewport.size = viewport_size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	_tp_root = Control.new()
	_tp_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tp_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(_tp_root)

	_bg = PanelContainer.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.06, 0.12, 0.85)
	bg_style.set_corner_radius_all(24)
	bg_style.set_border_width_all(3)
	bg_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
	_bg.add_theme_stylebox_override("panel", bg_style)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tp_root.add_child(_bg)

	_build_arrows()

	_border = PanelContainer.new()
	_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.set_corner_radius_all(24)
	border_style.set_border_width_all(3)
	border_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
	_border.add_theme_stylebox_override("panel", border_style)
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tp_root.add_child(_border)

	var bottom_box = HBoxContainer.new()
	bottom_box.anchor_left = 0.0
	bottom_box.anchor_right = 1.0
	bottom_box.anchor_top = 1.0
	bottom_box.anchor_bottom = 1.0
	bottom_box.offset_top = -40
	bottom_box.offset_bottom = -8
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_theme_constant_override("separation", 0)
	viewport.add_child(bottom_box)

	var left_spacer = Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_child(left_spacer)

	var grab_bar = PanelContainer.new()
	grab_bar.name = "CompGrabBar"
	grab_bar.custom_minimum_size = Vector2(0, 28)
	grab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grab_style = StyleBoxFlat.new()
	grab_style.bg_color = Color(1, 1, 1, 0.08)
	grab_style.set_corner_radius_all(14)
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
	mesh_instance.name = "TPPanel"
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
	area.name = "TPArea3D"
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

func _build_arrows():
	var cw = viewport_size.x
	var ch = viewport_size.y
	var cx = cw / 2.0
	var cy = ch / 2.0 - 20

	var arrow_color = Color(0.4, 0.4, 0.5, 0.35)
	var arrow_len = 60
	var arrow_head = 16

	var up_label = Label.new()
	up_label.text = "▲"
	up_label.position = Vector2(cx - 10, cy - arrow_len - arrow_head)
	up_label.size = Vector2(20, 20)
	up_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	up_label.add_theme_font_size_override("font_size", 22)
	up_label.add_theme_color_override("font_color", arrow_color)
	up_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tp_root.add_child(up_label)

	var down_label = Label.new()
	down_label.text = "▼"
	down_label.position = Vector2(cx - 10, cy + arrow_len)
	down_label.size = Vector2(20, 20)
	down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	down_label.add_theme_font_size_override("font_size", 22)
	down_label.add_theme_color_override("font_color", arrow_color)
	down_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tp_root.add_child(down_label)

	var left_label = Label.new()
	left_label.text = "◀"
	left_label.position = Vector2(cx - arrow_len - arrow_head - 10, cy - 10)
	left_label.size = Vector2(20, 20)
	left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_label.add_theme_font_size_override("font_size", 22)
	left_label.add_theme_color_override("font_color", arrow_color)
	left_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tp_root.add_child(left_label)

	var right_label = Label.new()
	right_label.text = "▶"
	right_label.position = Vector2(cx + arrow_len, cy - 10)
	right_label.size = Vector2(20, 20)
	right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_label.add_theme_font_size_override("font_size", 22)
	right_label.add_theme_color_override("font_color", arrow_color)
	right_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tp_root.add_child(right_label)

	var title = Label.new()
	title.text = "TRACKPAD"
	title.position = Vector2(0, 12)
	title.size = Vector2(cw, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.6))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tp_root.add_child(title)

	var hint = Label.new()
	hint.text = "Hold trigger &\nmove controller"
	hint.position = Vector2(0, cy - 16)
	hint.size = Vector2(cw, 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5, 0.4))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tp_root.add_child(hint)

func handle_pointer(pixel_pos: Vector2, clicking: bool, was_clicking: bool):
	if not visible:
		return

	if clicking and not was_clicking:
		trackpad_active = true
		_last_hand_pos = main.right_hand.global_position
		_set_active_visual(true)

	if not clicking and was_clicking:
		trackpad_active = false
		_set_active_visual(false)

func _set_active_visual(active: bool):
	if not _border:
		return
	var style = _border.get_theme_stylebox("panel")
	if style and style is StyleBoxFlat:
		style = style.duplicate()
		if active:
			style.border_color = Color(0.3, 0.6, 1.0, 0.9)
		else:
			style.border_color = Color(0.3, 0.3, 0.4, 0.5)
		_border.add_theme_stylebox_override("panel", style)

func _process(_delta):
	if not visible or not main.is_streaming:
		if trackpad_active:
			trackpad_active = false
			_set_active_visual(false)
		return

	if trackpad_active:
		var trigger = main.right_hand.get_float("trigger") if main.right_hand else 0.0
		if trigger < 0.5:
			trackpad_active = false
			_set_active_visual(false)
			return

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
		trackpad_active = false
		_set_active_visual(false)

func _save_offset():
	var scr_basis = main.screen_mesh.global_transform.basis.inverse()
	_saved_offset = scr_basis * (global_position - main.screen_mesh.global_position)
	_saved_rot_y = rotation.y - main.screen_mesh.global_rotation.y
	_saved_rot_x = rotation.x
	_has_saved_offset = true
