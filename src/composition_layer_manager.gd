class_name CompositionLayerManager
extends RefCounted

var main
var available: bool = false
var in_use: bool = false

func _init(p_main):
	main = p_main
	available = ClassDB.class_exists("OpenXRCompositionLayerCylinder")

func get_screen_mesh_original_mat() -> Material:
	return main._screen_mesh_original_mat

func get_cyl_params() -> Dictionary:
	return {
		"center": main._comp_cyl_center,
		"radius": main._comp_cyl_radius,
		"central_angle": main._comp_cyl_central_angle
	}

func get_shader_mats() -> Array:
	return [main.comp_shader_mat, main.comp_shader_mat_left, main.comp_shader_mat_right]

func get_stream_cursor_pair(index: int) -> Array:
	match index:
		0: return [main.comp_stream_cursor, main.comp_stream_cursor_circle]
		1: return [main.comp_stream_cursor_left, main.comp_stream_cursor_circle_left]
		_: return [main.comp_stream_cursor_right, main.comp_stream_cursor_circle_right]

func setup():
	if not available:
		main._log("[COMP] OpenXRCompositionLayerCylinder not available")
		return

	main.comp_cylinder = OpenXRCompositionLayerCylinder.new()
	main.comp_cylinder.name = "CompCylinderLayer"
	main.comp_cylinder.set_sort_order(1)
	main.comp_cylinder.set_enable_hole_punch(false)
	main.comp_cylinder.set_alpha_blend(false)
	main.comp_cylinder.visible = false
	main.xr_origin.add_child(main.comp_cylinder)
	if main.comp_cylinder.is_natively_supported():
		main._log("[COMP] Cylinder layer natively supported")
	else:
		main._log("[COMP] Cylinder layer NOT natively supported")

	main.comp_viewport = SubViewport.new()
	main.comp_viewport.name = "CompViewport"
	main.comp_viewport.disable_3d = true
	main.comp_viewport.transparent_bg = true
	main.comp_viewport.size = Vector2i(1920, 1080)
	main._comp_base_size = Vector2i(1920, 1080)
	main.comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.add_child(main.comp_viewport)

	main.comp_bezel_rect = ColorRect.new()
	main.comp_bezel_rect.name = "CompBezelRect"
	main.comp_bezel_rect.color = Color(0, 0, 0, 1)
	main.comp_bezel_rect.anchors_preset = 15
	main.comp_bezel_rect.anchor_right = 1.0
	main.comp_bezel_rect.anchor_bottom = 1.0
	main.comp_bezel_rect.grow_horizontal = 2
	main.comp_bezel_rect.grow_vertical = 2
	main.comp_viewport.add_child(main.comp_bezel_rect)

	main.comp_yuv_rect = ColorRect.new()
	main.comp_yuv_rect.name = "CompYuvRect"
	main.comp_yuv_rect.anchors_preset = 15
	main.comp_yuv_rect.anchor_right = 1.0
	main.comp_yuv_rect.anchor_bottom = 1.0
	main.comp_yuv_rect.grow_horizontal = 2
	main.comp_yuv_rect.grow_vertical = 2
	main.comp_shader_mat = ShaderMaterial.new()
	main.comp_shader_mat.shader = load("res://src/shaders/yuv_display.gdshader")
	main.comp_yuv_rect.material = main.comp_shader_mat
	main.comp_bezel_rect.add_child(main.comp_yuv_rect)

	main.comp_stream_cursor = TextureRect.new()
	main.comp_stream_cursor.name = "CompStreamCursor"
	main.comp_stream_cursor.texture = load("res://src/assets/mouse_pointer_01.png")
	main.comp_stream_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main.comp_stream_cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	main.comp_stream_cursor.visible = false
	main.comp_stream_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.comp_bezel_rect.add_child(main.comp_stream_cursor)

	main.comp_stream_cursor_circle = ColorRect.new()
	main.comp_stream_cursor_circle.name = "CompStreamCursorCircle"
	main.comp_stream_cursor_circle.visible = false
	main.comp_stream_cursor_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle_mat_sq = ShaderMaterial.new()
	circle_mat_sq.shader = preload("res://src/shaders/circle_cursor.gdshader")
	main.comp_stream_cursor_circle.material = circle_mat_sq
	main.comp_bezel_rect.add_child(main.comp_stream_cursor_circle)

	main.comp_ui = OpenXRCompositionLayerQuad.new()
	main.comp_ui.name = "CompUILayer"
	main.comp_ui.set_sort_order(3)
	main.comp_ui.set_enable_hole_punch(false)
	main.comp_ui.set_alpha_blend(true)
	main.comp_ui.set_quad_size(main._ui_mesh_size)
	main.comp_ui.visible = false
	main.xr_origin.add_child(main.comp_ui)
	main.comp_ui.set_layer_viewport(main.ui_viewport)
	main._log("[COMP] UI composition layer created")

	main.comp_cursor = OpenXRCompositionLayerQuad.new()
	main.comp_cursor.name = "CompCursorLayer"
	main.comp_cursor.set_sort_order(4)
	main.comp_cursor.set_enable_hole_punch(false)
	main.comp_cursor.set_alpha_blend(true)
	main.comp_cursor.set_quad_size(Vector2(0.04, 0.04))
	main.comp_cursor.visible = false
	main.xr_origin.add_child(main.comp_cursor)

	main.comp_cursor_viewport = SubViewport.new()
	main.comp_cursor_viewport.name = "CompCursorViewport"
	main.comp_cursor_viewport.disable_3d = true
	main.comp_cursor_viewport.transparent_bg = true
	main.comp_cursor_viewport.size = Vector2i(40, 64)
	main.comp_cursor_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.add_child(main.comp_cursor_viewport)

	var pointer_tex = TextureRect.new()
	pointer_tex.name = "PointerTexture"
	pointer_tex.anchors_preset = 15
	pointer_tex.anchor_right = 1.0
	pointer_tex.anchor_bottom = 1.0
	pointer_tex.expand_mode = 1
	pointer_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pointer_tex.texture = load("res://src/assets/mouse_pointer_01.png")
	main.comp_cursor_viewport.add_child(pointer_tex)

	var circle = ColorRect.new()
	circle.name = "CircleTexture"
	circle.anchors_preset = 15
	circle.anchor_right = 1.0
	circle.anchor_bottom = 1.0
	var circle_mat = ShaderMaterial.new()
	circle_mat.shader = preload("res://src/shaders/circle_cursor.gdshader")
	circle.material = circle_mat
	circle.visible = false
	main.comp_cursor_viewport.add_child(circle)

	main.comp_cursor.set_layer_viewport(main.comp_cursor_viewport)
	main._log("[COMP] Cursor composition layer created")

	main.comp_kb = OpenXRCompositionLayerQuad.new()
	main.comp_kb.name = "CompKBLayer"
	main.comp_kb.set_sort_order(2)
	main.comp_kb.set_enable_hole_punch(false)
	main.comp_kb.set_alpha_blend(true)
	main.comp_kb.set_quad_size(main.virtual_keyboard.mesh_size)
	main.comp_kb.visible = false
	main.xr_origin.add_child(main.comp_kb)
	main.comp_kb.set_layer_viewport(main.virtual_keyboard.viewport)
	main._log("[COMP] Keyboard composition layer created")

	main.comp_cylinder_left = OpenXRCompositionLayerCylinder.new()
	main.comp_cylinder_left.name = "CompCylinderLeft"
	main.comp_cylinder_left.set_sort_order(1)
	main.comp_cylinder_left.set_enable_hole_punch(false)
	main.comp_cylinder_left.set_alpha_blend(false)
	main.comp_cylinder_left.set_eye_visibility(OpenXRCompositionLayer.EYE_VISIBILITY_LEFT)
	main.comp_cylinder_left.visible = false
	main.xr_origin.add_child(main.comp_cylinder_left)

	main.comp_cylinder_right = OpenXRCompositionLayerCylinder.new()
	main.comp_cylinder_right.name = "CompCylinderRight"
	main.comp_cylinder_right.set_sort_order(1)
	main.comp_cylinder_right.set_enable_hole_punch(false)
	main.comp_cylinder_right.set_alpha_blend(false)
	main.comp_cylinder_right.set_eye_visibility(OpenXRCompositionLayer.EYE_VISIBILITY_RIGHT)
	main.comp_cylinder_right.visible = false
	main.xr_origin.add_child(main.comp_cylinder_right)

	main.comp_viewport_left = SubViewport.new()
	main.comp_viewport_left.name = "CompViewportLeft"
	main.comp_viewport_left.disable_3d = true
	main.comp_viewport_left.transparent_bg = true
	main.comp_viewport_left.size = Vector2i(1920, 1080)
	main.comp_viewport_left.render_target_update_mode = SubViewport.UPDATE_DISABLED
	main.add_child(main.comp_viewport_left)

	main.comp_bezel_rect_left = ColorRect.new()
	main.comp_bezel_rect_left.name = "CompBezelRectLeft"
	main.comp_bezel_rect_left.color = Color(0, 0, 0, 1)
	main.comp_bezel_rect_left.anchors_preset = 15
	main.comp_bezel_rect_left.anchor_right = 1.0
	main.comp_bezel_rect_left.anchor_bottom = 1.0
	main.comp_bezel_rect_left.grow_horizontal = 2
	main.comp_bezel_rect_left.grow_vertical = 2
	main.comp_viewport_left.add_child(main.comp_bezel_rect_left)

	main.comp_yuv_rect_left = ColorRect.new()
	main.comp_yuv_rect_left.name = "CompYuvRectLeft"
	main.comp_yuv_rect_left.anchors_preset = 15
	main.comp_yuv_rect_left.anchor_right = 1.0
	main.comp_yuv_rect_left.anchor_bottom = 1.0
	main.comp_yuv_rect_left.grow_horizontal = 2
	main.comp_yuv_rect_left.grow_vertical = 2
	main.comp_shader_mat_left = ShaderMaterial.new()
	main.comp_shader_mat_left.shader = load("res://src/shaders/yuv_display.gdshader")
	main.comp_shader_mat_left.set_shader_parameter("eye_index", 1)
	main.comp_yuv_rect_left.material = main.comp_shader_mat_left
	main.comp_bezel_rect_left.add_child(main.comp_yuv_rect_left)

	main.comp_stream_cursor_left = TextureRect.new()
	main.comp_stream_cursor_left.name = "CompStreamCursorLeft"
	main.comp_stream_cursor_left.texture = load("res://src/assets/mouse_pointer_01.png")
	main.comp_stream_cursor_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main.comp_stream_cursor_left.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	main.comp_stream_cursor_left.visible = false
	main.comp_stream_cursor_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.comp_bezel_rect_left.add_child(main.comp_stream_cursor_left)

	main.comp_stream_cursor_circle_left = ColorRect.new()
	main.comp_stream_cursor_circle_left.name = "CompStreamCursorCircleLeft"
	main.comp_stream_cursor_circle_left.visible = false
	main.comp_stream_cursor_circle_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle_mat_left = ShaderMaterial.new()
	circle_mat_left.shader = preload("res://src/shaders/circle_cursor.gdshader")
	main.comp_stream_cursor_circle_left.material = circle_mat_left
	main.comp_bezel_rect_left.add_child(main.comp_stream_cursor_circle_left)

	main.comp_viewport_right = SubViewport.new()
	main.comp_viewport_right.name = "CompViewportRight"
	main.comp_viewport_right.disable_3d = true
	main.comp_viewport_right.transparent_bg = true
	main.comp_viewport_right.size = Vector2i(1920, 1080)
	main.comp_viewport_right.render_target_update_mode = SubViewport.UPDATE_DISABLED
	main.add_child(main.comp_viewport_right)

	main.comp_bezel_rect_right = ColorRect.new()
	main.comp_bezel_rect_right.name = "CompBezelRectRight"
	main.comp_bezel_rect_right.color = Color(0, 0, 0, 1)
	main.comp_bezel_rect_right.anchors_preset = 15
	main.comp_bezel_rect_right.anchor_right = 1.0
	main.comp_bezel_rect_right.anchor_bottom = 1.0
	main.comp_bezel_rect_right.grow_horizontal = 2
	main.comp_bezel_rect_right.grow_vertical = 2
	main.comp_viewport_right.add_child(main.comp_bezel_rect_right)

	main.comp_yuv_rect_right = ColorRect.new()
	main.comp_yuv_rect_right.name = "CompYuvRectRight"
	main.comp_yuv_rect_right.anchors_preset = 15
	main.comp_yuv_rect_right.anchor_right = 1.0
	main.comp_yuv_rect_right.anchor_bottom = 1.0
	main.comp_yuv_rect_right.grow_horizontal = 2
	main.comp_yuv_rect_right.grow_vertical = 2
	main.comp_shader_mat_right = ShaderMaterial.new()
	main.comp_shader_mat_right.shader = load("res://src/shaders/yuv_display.gdshader")
	main.comp_shader_mat_right.set_shader_parameter("eye_index", 2)
	main.comp_yuv_rect_right.material = main.comp_shader_mat_right
	main.comp_bezel_rect_right.add_child(main.comp_yuv_rect_right)

	main.comp_stream_cursor_right = TextureRect.new()
	main.comp_stream_cursor_right.name = "CompStreamCursorRight"
	main.comp_stream_cursor_right.texture = load("res://src/assets/mouse_pointer_01.png")
	main.comp_stream_cursor_right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main.comp_stream_cursor_right.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	main.comp_stream_cursor_right.visible = false
	main.comp_stream_cursor_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.comp_bezel_rect_right.add_child(main.comp_stream_cursor_right)

	main.comp_stream_cursor_circle_right = ColorRect.new()
	main.comp_stream_cursor_circle_right.name = "CompStreamCursorCircleRight"
	main.comp_stream_cursor_circle_right.visible = false
	main.comp_stream_cursor_circle_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle_mat_right = ShaderMaterial.new()
	circle_mat_right.shader = preload("res://src/shaders/circle_cursor.gdshader")
	main.comp_stream_cursor_circle_right.material = circle_mat_right
	main.comp_bezel_rect_right.add_child(main.comp_stream_cursor_circle_right)

	main.comp_cylinder_left.set_layer_viewport(main.comp_viewport_left)
	main.comp_cylinder_right.set_layer_viewport(main.comp_viewport_right)
	main._log("[COMP] Stereo composition layers created")

	main.comp_layer = main.comp_cylinder
	main.comp_layer.set_layer_viewport(main.comp_viewport)
	available = true
	if main.comp_cylinder.is_natively_supported():
		main._log("[COMP] Composition layer cylinder natively supported")
	else:
		main._log("[COMP] Composition layer cylinder NOT natively supported (using fallback mesh)")

func connect_welcome_texture():
	if not available:
		return
	var mats = [main.comp_shader_mat, main.comp_shader_mat_left, main.comp_shader_mat_right]
	for mat in mats:
		if mat:
			mat.set_shader_parameter("main_texture", main.welcome_viewport.get_texture())
			mat.set_shader_parameter("yuv_mode", 0)
	main.comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func update_bezel():
	if not main.comp_yuv_rect or not main.comp_bezel_rect:
		return
	var base_w = main._comp_base_size.x
	var base_h = main._comp_base_size.y
	if main.bezel_enabled and in_use:
		var px = 8
		main.comp_bezel_rect.color = Color(0, 0, 0, 1)
		main.comp_bezel_rect.anchors_preset = 15
		main.comp_bezel_rect.offset_left = 0
		main.comp_bezel_rect.offset_top = 0
		main.comp_bezel_rect.offset_right = 0
		main.comp_bezel_rect.offset_bottom = 0
		main.comp_yuv_rect.offset_left = px
		main.comp_yuv_rect.offset_top = px
		main.comp_yuv_rect.offset_right = -px
		main.comp_yuv_rect.offset_bottom = -px
		main.comp_yuv_rect.anchor_left = 0.0
		main.comp_yuv_rect.anchor_top = 0.0
		main.comp_yuv_rect.anchor_right = 1.0
		main.comp_yuv_rect.anchor_bottom = 1.0
		main.comp_yuv_rect.anchors_preset = 0
		main.comp_viewport.size = Vector2i(base_w + px * 2, base_h + px * 2)
		var bezel_x = main._mesh_size.x * (1.0 + float(px * 2) / float(base_w))
		var bezel_y = main._mesh_size.y * (1.0 + float(px * 2) / float(base_h))
		if main.comp_cylinder and main.comp_cylinder.visible:
			main.comp_cylinder.set_aspect_ratio(bezel_x / bezel_y)
		if main.comp_bezel_rect_left:
			main.comp_bezel_rect_left.color = Color(0, 0, 0, 1)
			main.comp_bezel_rect_left.anchors_preset = 15
			main.comp_bezel_rect_left.offset_left = 0
			main.comp_bezel_rect_left.offset_top = 0
			main.comp_bezel_rect_left.offset_right = 0
			main.comp_bezel_rect_left.offset_bottom = 0
			main.comp_yuv_rect_left.offset_left = px
			main.comp_yuv_rect_left.offset_top = px
			main.comp_yuv_rect_left.offset_right = -px
			main.comp_yuv_rect_left.offset_bottom = -px
			main.comp_yuv_rect_left.anchor_left = 0.0
			main.comp_yuv_rect_left.anchor_top = 0.0
			main.comp_yuv_rect_left.anchor_right = 1.0
			main.comp_yuv_rect_left.anchor_bottom = 1.0
			main.comp_yuv_rect_left.anchors_preset = 0
			main.comp_viewport_left.size = Vector2i(base_w + px * 2, base_h + px * 2)
		if main.comp_bezel_rect_right:
			main.comp_bezel_rect_right.color = Color(0, 0, 0, 1)
			main.comp_bezel_rect_right.anchors_preset = 15
			main.comp_bezel_rect_right.offset_left = 0
			main.comp_bezel_rect_right.offset_top = 0
			main.comp_bezel_rect_right.offset_right = 0
			main.comp_bezel_rect_right.offset_bottom = 0
			main.comp_yuv_rect_right.offset_left = px
			main.comp_yuv_rect_right.offset_top = px
			main.comp_yuv_rect_right.offset_right = -px
			main.comp_yuv_rect_right.offset_bottom = -px
			main.comp_yuv_rect_right.anchor_left = 0.0
			main.comp_yuv_rect_right.anchor_top = 0.0
			main.comp_yuv_rect_right.anchor_right = 1.0
			main.comp_yuv_rect_right.anchor_bottom = 1.0
			main.comp_yuv_rect_right.anchors_preset = 0
			main.comp_viewport_right.size = Vector2i(base_w + px * 2, base_h + px * 2)
		if main.comp_cylinder_left and main.comp_cylinder_left.visible:
			main.comp_cylinder_left.set_aspect_ratio(bezel_x / bezel_y)
		if main.comp_cylinder_right and main.comp_cylinder_right.visible:
			main.comp_cylinder_right.set_aspect_ratio(bezel_x / bezel_y)
	else:
		main.comp_bezel_rect.color = Color(0, 0, 0, 0)
		main.comp_bezel_rect.anchors_preset = 15
		main.comp_bezel_rect.offset_left = 0
		main.comp_bezel_rect.offset_top = 0
		main.comp_bezel_rect.offset_right = 0
		main.comp_bezel_rect.offset_bottom = 0
		main.comp_yuv_rect.offset_left = 0
		main.comp_yuv_rect.offset_top = 0
		main.comp_yuv_rect.offset_right = 0
		main.comp_yuv_rect.offset_bottom = 0
		main.comp_yuv_rect.anchors_preset = 15
		main.comp_viewport.size = Vector2i(base_w, base_h)
		if main.comp_cylinder and main.comp_cylinder.visible:
			main.comp_cylinder.set_aspect_ratio(main._mesh_size.x / main._mesh_size.y)
		if main.comp_bezel_rect_left:
			main.comp_bezel_rect_left.color = Color(0, 0, 0, 0)
			main.comp_bezel_rect_left.anchors_preset = 15
			main.comp_bezel_rect_left.offset_left = 0
			main.comp_bezel_rect_left.offset_top = 0
			main.comp_bezel_rect_left.offset_right = 0
			main.comp_bezel_rect_left.offset_bottom = 0
			main.comp_yuv_rect_left.offset_left = 0
			main.comp_yuv_rect_left.offset_top = 0
			main.comp_yuv_rect_left.offset_right = 0
			main.comp_yuv_rect_left.offset_bottom = 0
			main.comp_yuv_rect_left.anchors_preset = 15
			main.comp_viewport_left.size = Vector2i(base_w, base_h)
		if main.comp_bezel_rect_right:
			main.comp_bezel_rect_right.color = Color(0, 0, 0, 0)
			main.comp_bezel_rect_right.anchors_preset = 15
			main.comp_bezel_rect_right.offset_left = 0
			main.comp_bezel_rect_right.offset_top = 0
			main.comp_bezel_rect_right.offset_right = 0
			main.comp_bezel_rect_right.offset_bottom = 0
			main.comp_yuv_rect_right.offset_left = 0
			main.comp_yuv_rect_right.offset_top = 0
			main.comp_yuv_rect_right.offset_right = 0
			main.comp_yuv_rect_right.offset_bottom = 0
			main.comp_yuv_rect_right.anchors_preset = 15
			main.comp_viewport_right.size = Vector2i(base_w, base_h)
		if main.comp_cylinder_left and main.comp_cylinder_left.visible:
			main.comp_cylinder_left.set_aspect_ratio(main._mesh_size.x / main._mesh_size.y)
		if main.comp_cylinder_right and main.comp_cylinder_right.visible:
			main.comp_cylinder_right.set_aspect_ratio(main._mesh_size.x / main._mesh_size.y)

func update_cylinder_params():
	if not main.comp_cylinder and not main.comp_cylinder_left:
		return
	var cam_to_screen = main.screen_mesh.global_position - main.xr_camera.global_position
	var view_dist = cam_to_screen.length()
	if view_dist < 0.5:
		view_dist = 3.0
	var radius = view_dist * 100.0
	if main.curvature == 1:
		radius = view_dist * 3.0
	elif main.curvature == 2:
		radius = view_dist * 2.0
	var screen_forward = -main.screen_mesh.global_transform.basis.z
	var central_angle = main._mesh_size.x / radius
	var aspect = main._mesh_size.x / main._mesh_size.y
	main._comp_cyl_radius = radius
	main._comp_cyl_central_angle = central_angle
	main._comp_cyl_center = main.screen_mesh.global_position - screen_forward * radius
	if main.comp_cylinder and main.comp_cylinder.visible:
		main.comp_cylinder.set_radius(radius)
		main.comp_cylinder.set_central_angle(central_angle)
		main.comp_cylinder.set_aspect_ratio(aspect)
		main.comp_cylinder.global_position = main.screen_mesh.global_position - screen_forward * radius
		main.comp_cylinder.global_rotation = main.screen_mesh.global_rotation
	if main.comp_cylinder_left and main.comp_cylinder_left.visible:
		main.comp_cylinder_left.set_radius(radius)
		main.comp_cylinder_left.set_central_angle(central_angle)
		main.comp_cylinder_left.set_aspect_ratio(aspect)
		main.comp_cylinder_left.global_position = main.screen_mesh.global_position - screen_forward * radius
		main.comp_cylinder_left.global_rotation = main.screen_mesh.global_rotation
	if main.comp_cylinder_right and main.comp_cylinder_right.visible:
		main.comp_cylinder_right.set_radius(radius)
		main.comp_cylinder_right.set_central_angle(central_angle)
		main.comp_cylinder_right.set_aspect_ratio(aspect)
		main.comp_cylinder_right.global_position = main.screen_mesh.global_position - screen_forward * radius
		main.comp_cylinder_right.global_rotation = main.screen_mesh.global_rotation

func make_screen_transparent():
	main.screen_mesh.visible = false

func make_ui_transparent():
	main.ui_panel_3d.visible = false

func make_kb_transparent():
	if not main.virtual_keyboard:
		return
	main.virtual_keyboard.mesh_instance.visible = false

func restore_screen_material():
	main.screen_mesh.visible = true
	var screen_bar = main.get_node_or_null("%ScreenGrabBar")
	if screen_bar:
		screen_bar.visible = true

func restore_ui_material():
	main.ui_panel_3d.visible = main.ui_visible

func restore_kb_material():
	if main.virtual_keyboard:
		main.virtual_keyboard.mesh_instance.visible = main.virtual_keyboard.visible

func bind_yuv_textures():
	var mat = main.stream_backend.get_shader_material()
	if not mat:
		main._log("[YUV] No shader material from stream backend, using SubViewport path")
		var stream_tex = main.stream_viewport.get_texture()
		if not in_use and main.screen_mesh.material_override is ShaderMaterial:
			main.screen_mesh.material_override.set_shader_parameter("main_texture", stream_tex)
			main.screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
		bind_fallback_texture(stream_tex)
		return
	var tex_y = mat.get_shader_parameter("tex_y")
	var tex_u = mat.get_shader_parameter("tex_u")
	var tex_v = mat.get_shader_parameter("tex_v")
	var is_nv12_rd = mat.get_shader_parameter("is_nv12_rd")
	var is_semi_planar = mat.get_shader_parameter("is_semi_planar")
	var cmt = mat.get_shader_parameter("color_matrix_type")
	var cr = mat.get_shader_parameter("color_range")
	if tex_y:
		var yuv_mode_val = 0
		if is_nv12_rd:
			yuv_mode_val = 1
		elif is_semi_planar:
			yuv_mode_val = 2
		else:
			yuv_mode_val = 3
		if not in_use and main.screen_mesh.material_override is ShaderMaterial:
			main.screen_mesh.material_override.set_shader_parameter("tex_y", tex_y)
			main.screen_mesh.material_override.set_shader_parameter("tex_u", tex_u)
			main.screen_mesh.material_override.set_shader_parameter("tex_v", tex_v)
			main.screen_mesh.material_override.set_shader_parameter("color_matrix_type", cmt)
			main.screen_mesh.material_override.set_shader_parameter("color_range", cr)
			main.screen_mesh.material_override.set_shader_parameter("yuv_mode", yuv_mode_val)
		main._log("[YUV] Direct YUV binding: mode=%d nv12_rd=%s semi_planar=%s" % [yuv_mode_val, str(is_nv12_rd), str(is_semi_planar)])
		bind_comp_yuv_textures(tex_y, tex_u, tex_v, yuv_mode_val, cmt, cr)
	else:
		var stream_tex = main.stream_viewport.get_texture()
		if not in_use and main.screen_mesh.material_override is ShaderMaterial:
			main.screen_mesh.material_override.set_shader_parameter("main_texture", stream_tex)
			main.screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
		bind_fallback_texture(stream_tex)

func bind_comp_yuv_textures(tex_y, tex_u, tex_v, yuv_mode: int, cmt, cr):
	var mats = [main.comp_shader_mat, main.comp_shader_mat_left, main.comp_shader_mat_right]
	for mat in mats:
		if not mat:
			continue
		mat.set_shader_parameter("tex_y", tex_y)
		mat.set_shader_parameter("tex_u", tex_u)
		mat.set_shader_parameter("tex_v", tex_v)
		mat.set_shader_parameter("yuv_mode", yuv_mode)
		mat.set_shader_parameter("color_matrix_type", cmt)
		mat.set_shader_parameter("color_range", cr)
	main._log("[COMP] YUV textures bound to composition layer shader (mode=%d)" % yuv_mode)

func bind_fallback_texture(stream_tex):
	var mats = [main.comp_shader_mat, main.comp_shader_mat_left, main.comp_shader_mat_right]
	for mat in mats:
		if not mat:
			continue
		mat.set_shader_parameter("main_texture", stream_tex)
		mat.set_shader_parameter("yuv_mode", 0)

func switch_to_comp_layer():
	if not available:
		in_use = false
		main._log("[COMP] Not available, using mesh rendering")
		return
	var stereo = main.settings_controller.get_stereo_mode() if main.settings_controller else 0
	if stereo > 0:
		switch_to_stereo_comp_layer()
		return
	in_use = true
	main.stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if main.comp_cylinder_left: main.comp_cylinder_left.visible = false
	if main.comp_cylinder_right: main.comp_cylinder_right.visible = false
	if main.comp_viewport_left: main.comp_viewport_left.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if main.comp_viewport_right: main.comp_viewport_right.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if main.comp_cylinder:
		main.comp_layer = main.comp_cylinder
		main.comp_layer.set_layer_viewport(main.comp_viewport)
		main.comp_layer.visible = true
		update_cylinder_params()
		main._log("[COMP] Switched to composition layer (cylinder, curv=%d)" % main.curvature)
	else:
		main.comp_layer.set_layer_viewport(main.comp_viewport)
		main.comp_layer.visible = true
		main._log("[COMP] Switched to composition layer (quad fallback)")
	main.comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.comp_shader_mat.set_shader_parameter("stereo_mode", 0)
	main.settings_controller.apply_filter()
	make_screen_transparent()
	main.bezel_mesh.visible = false
	update_bezel()

func switch_to_stereo_comp_layer():
	if not available:
		in_use = false
		main._log("[COMP] Not available, cannot use stereo comp layer")
		return
	in_use = true
	main.stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if main.comp_cylinder: main.comp_cylinder.visible = false
	main.comp_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var stereo = main.settings_controller.get_stereo_mode()
	main.comp_cylinder_left.visible = true
	main.comp_cylinder_right.visible = true
	main.comp_cylinder_left.set_layer_viewport(main.comp_viewport_left)
	main.comp_cylinder_right.set_layer_viewport(main.comp_viewport_right)
	main.comp_shader_mat_left.set_shader_parameter("stereo_mode", stereo)
	main.comp_shader_mat_left.set_shader_parameter("eye_index", 1)
	main.comp_shader_mat_right.set_shader_parameter("stereo_mode", stereo)
	main.comp_shader_mat_right.set_shader_parameter("eye_index", 2)
	main.comp_viewport_left.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.comp_viewport_right.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	make_screen_transparent()
	main.bezel_mesh.visible = false
	update_cylinder_params()
	update_bezel()
	if main.is_streaming:
		bind_yuv_textures()
	main._log("[COMP] Switched to stereo composition layer (mode=%d)" % stereo)

func switch_to_mesh_rendering():
	in_use = false
	main.stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if main.is_streaming else SubViewport.UPDATE_DISABLED
	if main.comp_cylinder: main.comp_cylinder.visible = false
	if main.comp_cylinder_left: main.comp_cylinder_left.visible = false
	if main.comp_cylinder_right: main.comp_cylinder_right.visible = false
	if main.comp_ui: main.comp_ui.visible = false
	if main.comp_kb: main.comp_kb.visible = false
	if main.comp_cursor: main.comp_cursor.visible = false
	if main.comp_viewport:
		main.comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if main.comp_viewport_left:
		main.comp_viewport_left.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if main.comp_viewport_right:
		main.comp_viewport_right.render_target_update_mode = SubViewport.UPDATE_DISABLED
	restore_screen_material()
	restore_ui_material()
	restore_kb_material()
	main.bezel_mesh.visible = main.bezel_enabled
	if main.is_streaming:
		main.stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var mat = main.screen_mesh.material_override
		main._log("[MESH] material type=%s" % str(mat.get_class()) if mat else "[MESH] material is null")
		mat.set_shader_parameter("main_texture", main.stream_viewport.get_texture())
		mat.set_shader_parameter("yuv_mode", 0)
		bind_yuv_textures()
		var mode = main.settings_controller.get_stereo_mode()
		mat.set_shader_parameter("stereo_mode", mode)
		mat.set_shader_parameter("filter_mode", main.smooth_mode)
		mat.set_shader_parameter("sharpen", float(main.sharpen_mode) * 0.016)
		main._log("[MESH] stereo=%d yuv_mode=%d filter=%d sharpen=%.3f" % [mode, mat.get_shader_parameter("yuv_mode"), main.smooth_mode, float(main.sharpen_mode) * 0.016])

func update_layer_size():
	update_cylinder_params()

func clear_yuv_textures():
	var mats = [main.comp_shader_mat, main.comp_shader_mat_left, main.comp_shader_mat_right]
	for mat in mats:
		if not mat:
			continue
		mat.set_shader_parameter("tex_y", null)
		mat.set_shader_parameter("tex_u", null)
		mat.set_shader_parameter("tex_v", null)
		mat.set_shader_parameter("yuv_mode", 0)
		mat.set_shader_parameter("main_texture", null)
		mat.set_shader_parameter("stereo_mode", 0)
		mat.set_shader_parameter("depth_texture", null)

static func set_grab_bar_color(viewport: SubViewport, color: Color):
	if not viewport:
		return
	var bar = viewport.find_child("CompGrabBar", true, false)
	if bar and bar is PanelContainer:
		var style = bar.get_theme_stylebox("panel")
		if style and style is StyleBoxFlat:
			style = style.duplicate()
			style.bg_color = Color(1, 1, 1, color.a)
			bar.add_theme_stylebox_override("panel", style)
