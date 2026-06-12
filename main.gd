extends Node3D

@onready var screen_mesh = $MeshInstance3D
@onready var ui_panel_3d = %UIPanel3D
@onready var ui_viewport = %UIViewport
@onready var stream_viewport = %StreamViewport
@onready var stream_target = %StreamTarget
@onready var detection_viewport = %DetectionViewport
@onready var detection_target = %DetectionTarget
@onready var welcome_viewport = %WelcomeViewport
@onready var config_mgr = ClassDB.instantiate("NightfallConfigManager") if ClassDB.class_exists("NightfallConfigManager") else null
@onready var comp_mgr = ClassDB.instantiate("NightfallComputerManager") if ClassDB.class_exists("NightfallComputerManager") else null
var mdns
var stream_backend: StreamBackend

func _get_mdns():
	if not mdns and ClassDB.class_exists("MdnsBrowser"):
		mdns = ClassDB.instantiate("MdnsBrowser")
	return mdns
@onready var xr_origin = $XROrigin3D
@onready var xr_camera = $XROrigin3D/XRCamera3D
@onready var mouse_raycast = %RayCast3D
@onready var hand_raycast = %HandRayCast
@onready var right_hand = %RightHand
@onready var left_hand = %LeftHand
@onready var audio_player = %StreamAudioPlayer
@onready var world_env = $WorldEnvironment

var current_host_id: int = -1
var _last_hostname: String = ""
var _selected_app_id: int = 881448767
var _selected_app_idx: int = 0
var _available_apps: Array = []
var _welcome_screen: String = "welcome"
var _pair_pin: String = ""
var _connecting_ip: String = ""
var _connect_timeout_pending: bool = false
var _auto_connect: bool = false
var _restarting_stream: bool = false
var is_streaming: bool = false
var sbs_mode: int = 0
var ai_3d_mode: int = 0
var is_xr_active: bool = false
var was_clicking: bool = false
var was_right_clicking: bool = false
var right_click_cooldown: float = 0.0
var _was_b_pressed: bool = false
var _was_a_pressed: bool = false
var _was_r_stick_click: bool = false
var _startup_reposition: bool = true
var mouse_captured_by_stream: bool = false
var suppress_input_frames: int = 0
var auto_detect_enabled: bool = false
var auto_detect_timer: float = 0.0
var auto_detect_running: bool = false
var detection_history: Array = []
var mouse_sensitivity: float = 0.002
var grabbed_node: Node3D = null
var grab_distance: float = 0.0
var grab_offset: Vector3 = Vector3.ZERO
var grabbed_bar: MeshInstance3D = null
var grab_start_hand_pos: Vector3 = Vector3.ZERO
var grab_start_node_pos: Vector3 = Vector3.ZERO
var grab_forward: Vector3 = Vector3.FORWARD
var grab_start_hand_basis: Basis = Basis()
var grab_start_node_basis: Basis = Basis()
var grab_start_node_euler: Vector3 = Vector3.ZERO
var stats_timer: float = 0.0
var stats_fps: float = 0.0
var stats_frame_times: Array = []
var stats_network_events: int = 0
var passthrough_mode: int = 0
var passthrough_labels: Array = ["On", "Off", "Starfield", "Ash", "Snow", "Data"]
var bg_names: Array = ["Starfield", "Ash", "Snow", "Data"]
var bg_offsets: Array = [Vector3.ZERO, Vector3.ZERO, Vector3(0, 10, 0), Vector3(0, -3, 0)]
var ui_visible: bool = false
var bezel_enabled: bool = true
var bezel_mesh: MeshInstance3D
var curvature: int = 2
var curvature_labels: Array = ["Flat", "Slight Curve", "Curved"]
var smooth_mode: int = 0
var sharpen_mode: int = 0
var smooth_labels: Array = ["0%", "10%", "20%", "30%", "40%", "50%"]
var sharpen_labels: Array = ["0%", "10%", "20%", "30%", "40%", "50%"]
var _xr_base_render_scale: float = 1.0
var _xr_render_width: int = 1680
var _mesh_size: Vector2 = Vector2(3.2, 1.8)
var stream_fps: int = 60
var _cached_filter_mode: int = -1
var _cached_sharpen: float = -1.0
var _cached_blur_scale: float = -1.0
var host_resolution: Vector2i = Vector2i(1920, 1080)
var resolution_idx: int = 1
var resolutions: Array = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1600, 1200), Vector2i(3440, 1440)]
var resolution_labels: Array = ["720", "HD", "2K", "4K", "4:3", "21:9"]
var double_h: bool = false
var bitrate_idx: int = -1
var bitrates: Array = [5, 10, 15, 20, 30, 40, 50, 60, 80, 100, 120]
var bitrate_labels: Array = ["Auto", "5", "10", "15", "20", "30", "40", "50", "60", "80", "100", "120"]
var display_refresh_rate: float = 72.0

var cursor_mode: int = 1
var cursor_labels: Array = ["Circle", "Pointer"]
var pointer_steady: int = 1
var pointer_steady_labels: Array = ["Off", "Low", "High"]
var _steady_hit: Vector3 = Vector3.ZERO
var _steady_active: bool = false
var _steady_factor: float = 0.3
var _steady_dead_zone: float = 0.002
var codec_preference: int = 1
var codec_labels: Array = ["H.264", "HEVC", "AV1", "Raw"]
var _client_codec_support: Dictionary = {}
var _server_codec_support: Dictionary = {}
var corner_handles: Array = []
var grabbed_corner_idx: int = -1
var corner_anchor_world: Vector3 = Vector3.ZERO

var stream_manager: StreamManager
var xr_interaction: XRInteraction
var input_handler: InputHandler
var ui_controller: UIController
var auto_detect: AutoDetect
var depth_estimator: DepthEstimatorModule
var virtual_keyboard: VirtualKeyboard
var welcome_screen: WelcomeScreen
var screen_manager: ScreenManager
var settings_controller: SettingsController
var state_manager: StateManager
var host_discovery: HostDiscovery
var controller_mapper: ControllerMapper

var comp_cylinder: Node3D = null
var _comp_cyl_center := Vector3.ZERO
var _comp_cyl_radius := 0.0
var _comp_cyl_central_angle := 0.0
var comp_cursor: Node3D = null
var comp_ui: Node3D = null
var comp_kb: Node3D = null
var comp_cursor_viewport: SubViewport = null
var comp_layer: Node3D = null
var comp_viewport: SubViewport = null
var comp_yuv_rect: ColorRect = null
var comp_bezel_rect: ColorRect = null
var comp_shader_mat: ShaderMaterial = null
var comp_cylinder_left: Node3D = null
var comp_cylinder_right: Node3D = null
var comp_viewport_left: SubViewport = null
var comp_viewport_right: SubViewport = null
var comp_yuv_rect_left: ColorRect = null
var comp_yuv_rect_right: ColorRect = null
var comp_bezel_rect_left: ColorRect = null
var comp_bezel_rect_right: ColorRect = null
var comp_shader_mat_left: ShaderMaterial = null
var comp_shader_mat_right: ShaderMaterial = null
var use_comp_layer: bool = false
var comp_stream_cursor: TextureRect = null
var comp_stream_cursor_circle: ColorRect = null
var comp_stream_cursor_left: TextureRect = null
var comp_stream_cursor_circle_left: ColorRect = null
var comp_stream_cursor_right: TextureRect = null
var comp_stream_cursor_circle_right: ColorRect = null
var comp_layer_available: bool = false
var _screen_mesh_saved_mat: Material = null
var _screen_mesh_original_mat: Material = null
var _ui_saved_mat: Material = null
var _kb_saved_mat: Material = null

var _log_lines: PackedStringArray = []
var _ui_viewport_size := Vector2i(1920, 1216)
var _ui_viewport_override := Vector2i(600, 380)
var _ui_mesh_size := Vector2(1.20, 0.76)
var _ui_host_label: Label
var _ui_status_label: Label
var _ui_pt_btn: Button
var _ui_curve_btn: Button
var _ui_bezel_btn: Button
var _ui_sbs_btn: Button
var _ui_3d_btn: Button
var _ui_res_btn: Button
var _ui_fps_btn: Button
var _ui_bitrate_btn: Button
var _ui_ctrl_type_btn: Button
var _ui_btn_toggle_btn: Button
var _ui_render_btn: Button
var _ui_sharpen_btn: Button
var _ui_ctrl_mode_btn: Button
var _ui_cursor_btn: Button
var _ui_steady_btn: Button
var _ui_codec_btn: Button
var auto_reconnect_enabled: bool = true
var _reconnecting: bool = false
var idle_timeout_min: int = 0
var _last_activity_time: float = 0.0
var _ui_idle_btn: Button
var _ui_reconnect_btn: Button
var _ui_exit_btn: Button
var _ui_disconnect_btn: Button
var _ui_close_btn: Button
var _ui_center_btn: Button

var _btn_style: StyleBoxFlat
var _btn_hover: StyleBoxFlat

func _log(msg: String):
	_log_lines.append(msg)
	push_warning("NF: %s" % msg)

func _flush_log():
	var f = FileAccess.open("user://debug.log", FileAccess.WRITE)
	if f:
		for line in _log_lines:
			f.store_line(line)
		f.close()

func _setup_comp_layer():
	if not ClassDB.class_exists("OpenXRCompositionLayerCylinder"):
		_log("[COMP] OpenXRCompositionLayerCylinder not available")
		return

	comp_cylinder = OpenXRCompositionLayerCylinder.new()
	comp_cylinder.name = "CompCylinderLayer"
	comp_cylinder.set_sort_order(1)
	comp_cylinder.set_enable_hole_punch(false)
	comp_cylinder.set_alpha_blend(true)
	comp_cylinder.visible = false
	xr_origin.add_child(comp_cylinder)
	if comp_cylinder.is_natively_supported():
		_log("[COMP] Cylinder layer natively supported")
	else:
		_log("[COMP] Cylinder layer NOT natively supported")

	comp_viewport = SubViewport.new()
	comp_viewport.name = "CompViewport"
	comp_viewport.disable_3d = true
	comp_viewport.transparent_bg = true
	comp_viewport.size = Vector2i(1920, 1080)
	_comp_base_size = Vector2i(1920, 1080)
	comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(comp_viewport)

	comp_bezel_rect = ColorRect.new()
	comp_bezel_rect.name = "CompBezelRect"
	comp_bezel_rect.color = Color(0, 0, 0, 1)
	comp_bezel_rect.anchors_preset = 15
	comp_bezel_rect.anchor_right = 1.0
	comp_bezel_rect.anchor_bottom = 1.0
	comp_bezel_rect.grow_horizontal = 2
	comp_bezel_rect.grow_vertical = 2
	comp_viewport.add_child(comp_bezel_rect)

	comp_yuv_rect = ColorRect.new()
	comp_yuv_rect.name = "CompYuvRect"
	comp_yuv_rect.anchors_preset = 15
	comp_yuv_rect.anchor_right = 1.0
	comp_yuv_rect.anchor_bottom = 1.0
	comp_yuv_rect.grow_horizontal = 2
	comp_yuv_rect.grow_vertical = 2
	comp_shader_mat = ShaderMaterial.new()
	comp_shader_mat.shader = load("res://src/shaders/yuv_display.gdshader")
	comp_yuv_rect.material = comp_shader_mat
	comp_bezel_rect.add_child(comp_yuv_rect)

	comp_stream_cursor = TextureRect.new()
	comp_stream_cursor.name = "CompStreamCursor"
	comp_stream_cursor.texture = load("res://src/assets/mouse_pointer_01.png")
	comp_stream_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	comp_stream_cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	comp_stream_cursor.visible = false
	comp_stream_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	comp_bezel_rect.add_child(comp_stream_cursor)

	comp_stream_cursor_circle = ColorRect.new()
	comp_stream_cursor_circle.name = "CompStreamCursorCircle"
	comp_stream_cursor_circle.visible = false
	comp_stream_cursor_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle_mat_sq = ShaderMaterial.new()
	circle_mat_sq.shader = preload("res://src/shaders/circle_cursor.gdshader")
	comp_stream_cursor_circle.material = circle_mat_sq
	comp_bezel_rect.add_child(comp_stream_cursor_circle)

	comp_ui = OpenXRCompositionLayerQuad.new()
	comp_ui.name = "CompUILayer"
	comp_ui.set_sort_order(3)
	comp_ui.set_enable_hole_punch(false)
	comp_ui.set_alpha_blend(true)
	comp_ui.set_quad_size(_ui_mesh_size)
	comp_ui.visible = false
	xr_origin.add_child(comp_ui)
	comp_ui.set_layer_viewport(ui_viewport)
	_log("[COMP] UI composition layer created")

	comp_cursor = OpenXRCompositionLayerQuad.new()
	comp_cursor.name = "CompCursorLayer"
	comp_cursor.set_sort_order(4)
	comp_cursor.set_enable_hole_punch(false)
	comp_cursor.set_alpha_blend(true)
	comp_cursor.set_quad_size(Vector2(0.04, 0.04))
	comp_cursor.visible = false
	xr_origin.add_child(comp_cursor)

	comp_cursor_viewport = SubViewport.new()
	comp_cursor_viewport.name = "CompCursorViewport"
	comp_cursor_viewport.disable_3d = true
	comp_cursor_viewport.transparent_bg = true
	comp_cursor_viewport.size = Vector2i(40, 64)
	comp_cursor_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(comp_cursor_viewport)

	var pointer_tex = TextureRect.new()
	pointer_tex.name = "PointerTexture"
	pointer_tex.anchors_preset = 15
	pointer_tex.anchor_right = 1.0
	pointer_tex.anchor_bottom = 1.0
	pointer_tex.expand_mode = 1
	pointer_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pointer_tex.texture = load("res://src/assets/mouse_pointer_01.png")
	comp_cursor_viewport.add_child(pointer_tex)

	var circle = ColorRect.new()
	circle.name = "CircleTexture"
	circle.anchors_preset = 15
	circle.anchor_right = 1.0
	circle.anchor_bottom = 1.0
	var circle_mat = ShaderMaterial.new()
	circle_mat.shader = preload("res://src/shaders/circle_cursor.gdshader")
	circle.material = circle_mat
	circle.visible = false
	comp_cursor_viewport.add_child(circle)

	comp_cursor.set_layer_viewport(comp_cursor_viewport)
	_log("[COMP] Cursor composition layer created")

	comp_kb = OpenXRCompositionLayerQuad.new()
	comp_kb.name = "CompKBLayer"
	comp_kb.set_sort_order(2)
	comp_kb.set_enable_hole_punch(false)
	comp_kb.set_alpha_blend(true)
	comp_kb.set_quad_size(virtual_keyboard.mesh_size)
	comp_kb.visible = false
	xr_origin.add_child(comp_kb)
	comp_kb.set_layer_viewport(virtual_keyboard.viewport)
	_log("[COMP] Keyboard composition layer created")

	comp_cylinder_left = OpenXRCompositionLayerCylinder.new()
	comp_cylinder_left.name = "CompCylinderLeft"
	comp_cylinder_left.set_sort_order(1)
	comp_cylinder_left.set_enable_hole_punch(false)
	comp_cylinder_left.set_alpha_blend(true)
	comp_cylinder_left.set_eye_visibility(OpenXRCompositionLayer.EYE_VISIBILITY_LEFT)
	comp_cylinder_left.visible = false
	xr_origin.add_child(comp_cylinder_left)

	comp_cylinder_right = OpenXRCompositionLayerCylinder.new()
	comp_cylinder_right.name = "CompCylinderRight"
	comp_cylinder_right.set_sort_order(1)
	comp_cylinder_right.set_enable_hole_punch(false)
	comp_cylinder_right.set_alpha_blend(true)
	comp_cylinder_right.set_eye_visibility(OpenXRCompositionLayer.EYE_VISIBILITY_RIGHT)
	comp_cylinder_right.visible = false
	xr_origin.add_child(comp_cylinder_right)

	comp_viewport_left = SubViewport.new()
	comp_viewport_left.name = "CompViewportLeft"
	comp_viewport_left.disable_3d = true
	comp_viewport_left.transparent_bg = true
	comp_viewport_left.size = Vector2i(1920, 1080)
	comp_viewport_left.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(comp_viewport_left)

	comp_bezel_rect_left = ColorRect.new()
	comp_bezel_rect_left.name = "CompBezelRectLeft"
	comp_bezel_rect_left.color = Color(0, 0, 0, 1)
	comp_bezel_rect_left.anchors_preset = 15
	comp_bezel_rect_left.anchor_right = 1.0
	comp_bezel_rect_left.anchor_bottom = 1.0
	comp_bezel_rect_left.grow_horizontal = 2
	comp_bezel_rect_left.grow_vertical = 2
	comp_viewport_left.add_child(comp_bezel_rect_left)

	comp_yuv_rect_left = ColorRect.new()
	comp_yuv_rect_left.name = "CompYuvRectLeft"
	comp_yuv_rect_left.anchors_preset = 15
	comp_yuv_rect_left.anchor_right = 1.0
	comp_yuv_rect_left.anchor_bottom = 1.0
	comp_yuv_rect_left.grow_horizontal = 2
	comp_yuv_rect_left.grow_vertical = 2
	comp_shader_mat_left = ShaderMaterial.new()
	comp_shader_mat_left.shader = load("res://src/shaders/yuv_display.gdshader")
	comp_shader_mat_left.set_shader_parameter("eye_index", 1)
	comp_yuv_rect_left.material = comp_shader_mat_left
	comp_bezel_rect_left.add_child(comp_yuv_rect_left)

	comp_stream_cursor_left = TextureRect.new()
	comp_stream_cursor_left.name = "CompStreamCursorLeft"
	comp_stream_cursor_left.texture = load("res://src/assets/mouse_pointer_01.png")
	comp_stream_cursor_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	comp_stream_cursor_left.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	comp_stream_cursor_left.visible = false
	comp_stream_cursor_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	comp_bezel_rect_left.add_child(comp_stream_cursor_left)

	comp_stream_cursor_circle_left = ColorRect.new()
	comp_stream_cursor_circle_left.name = "CompStreamCursorCircleLeft"
	comp_stream_cursor_circle_left.visible = false
	comp_stream_cursor_circle_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle_mat_left = ShaderMaterial.new()
	circle_mat_left.shader = preload("res://src/shaders/circle_cursor.gdshader")
	comp_stream_cursor_circle_left.material = circle_mat_left
	comp_bezel_rect_left.add_child(comp_stream_cursor_circle_left)

	comp_viewport_right = SubViewport.new()
	comp_viewport_right.name = "CompViewportRight"
	comp_viewport_right.disable_3d = true
	comp_viewport_right.transparent_bg = true
	comp_viewport_right.size = Vector2i(1920, 1080)
	comp_viewport_right.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(comp_viewport_right)

	comp_bezel_rect_right = ColorRect.new()
	comp_bezel_rect_right.name = "CompBezelRectRight"
	comp_bezel_rect_right.color = Color(0, 0, 0, 1)
	comp_bezel_rect_right.anchors_preset = 15
	comp_bezel_rect_right.anchor_right = 1.0
	comp_bezel_rect_right.anchor_bottom = 1.0
	comp_bezel_rect_right.grow_horizontal = 2
	comp_bezel_rect_right.grow_vertical = 2
	comp_viewport_right.add_child(comp_bezel_rect_right)

	comp_yuv_rect_right = ColorRect.new()
	comp_yuv_rect_right.name = "CompYuvRectRight"
	comp_yuv_rect_right.anchors_preset = 15
	comp_yuv_rect_right.anchor_right = 1.0
	comp_yuv_rect_right.anchor_bottom = 1.0
	comp_yuv_rect_right.grow_horizontal = 2
	comp_yuv_rect_right.grow_vertical = 2
	comp_shader_mat_right = ShaderMaterial.new()
	comp_shader_mat_right.shader = load("res://src/shaders/yuv_display.gdshader")
	comp_shader_mat_right.set_shader_parameter("eye_index", 2)
	comp_yuv_rect_right.material = comp_shader_mat_right
	comp_bezel_rect_right.add_child(comp_yuv_rect_right)

	comp_stream_cursor_right = TextureRect.new()
	comp_stream_cursor_right.name = "CompStreamCursorRight"
	comp_stream_cursor_right.texture = load("res://src/assets/mouse_pointer_01.png")
	comp_stream_cursor_right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	comp_stream_cursor_right.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	comp_stream_cursor_right.visible = false
	comp_stream_cursor_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	comp_bezel_rect_right.add_child(comp_stream_cursor_right)

	comp_stream_cursor_circle_right = ColorRect.new()
	comp_stream_cursor_circle_right.name = "CompStreamCursorCircleRight"
	comp_stream_cursor_circle_right.visible = false
	comp_stream_cursor_circle_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle_mat_right = ShaderMaterial.new()
	circle_mat_right.shader = preload("res://src/shaders/circle_cursor.gdshader")
	comp_stream_cursor_circle_right.material = circle_mat_right
	comp_bezel_rect_right.add_child(comp_stream_cursor_circle_right)

	comp_cylinder_left.set_layer_viewport(comp_viewport_left)
	comp_cylinder_right.set_layer_viewport(comp_viewport_right)
	_log("[COMP] Stereo composition layers created")

	comp_layer = comp_cylinder
	comp_layer.set_layer_viewport(comp_viewport)
	comp_layer_available = true
	if comp_cylinder.is_natively_supported():
		_log("[COMP] Composition layer cylinder natively supported")
	else:
		_log("[COMP] Composition layer cylinder NOT natively supported (using fallback mesh)")

var _comp_base_size := Vector2i(1920, 1080)

func _update_comp_bezel():
	if not comp_yuv_rect or not comp_bezel_rect:
		return
	var base_w = _comp_base_size.x
	var base_h = _comp_base_size.y
	if bezel_enabled and use_comp_layer:
		var px = 8
		comp_bezel_rect.color = Color(0, 0, 0, 1)
		comp_bezel_rect.anchors_preset = 15
		comp_bezel_rect.offset_left = 0
		comp_bezel_rect.offset_top = 0
		comp_bezel_rect.offset_right = 0
		comp_bezel_rect.offset_bottom = 0
		comp_yuv_rect.offset_left = px
		comp_yuv_rect.offset_top = px
		comp_yuv_rect.offset_right = -px
		comp_yuv_rect.offset_bottom = -px
		comp_yuv_rect.anchor_left = 0.0
		comp_yuv_rect.anchor_top = 0.0
		comp_yuv_rect.anchor_right = 1.0
		comp_yuv_rect.anchor_bottom = 1.0
		comp_yuv_rect.anchors_preset = 0
		comp_viewport.size = Vector2i(base_w + px * 2, base_h + px * 2)
		var bezel_x = _mesh_size.x * (1.0 + float(px * 2) / float(base_w))
		var bezel_y = _mesh_size.y * (1.0 + float(px * 2) / float(base_h))
		if comp_cylinder and comp_cylinder.visible:
			comp_cylinder.set_aspect_ratio(bezel_x / bezel_y)
		if comp_bezel_rect_left:
			comp_bezel_rect_left.color = Color(0, 0, 0, 1)
			comp_bezel_rect_left.anchors_preset = 15
			comp_bezel_rect_left.offset_left = 0
			comp_bezel_rect_left.offset_top = 0
			comp_bezel_rect_left.offset_right = 0
			comp_bezel_rect_left.offset_bottom = 0
			comp_yuv_rect_left.offset_left = px
			comp_yuv_rect_left.offset_top = px
			comp_yuv_rect_left.offset_right = -px
			comp_yuv_rect_left.offset_bottom = -px
			comp_yuv_rect_left.anchor_left = 0.0
			comp_yuv_rect_left.anchor_top = 0.0
			comp_yuv_rect_left.anchor_right = 1.0
			comp_yuv_rect_left.anchor_bottom = 1.0
			comp_yuv_rect_left.anchors_preset = 0
			comp_viewport_left.size = Vector2i(base_w + px * 2, base_h + px * 2)
		if comp_bezel_rect_right:
			comp_bezel_rect_right.color = Color(0, 0, 0, 1)
			comp_bezel_rect_right.anchors_preset = 15
			comp_bezel_rect_right.offset_left = 0
			comp_bezel_rect_right.offset_top = 0
			comp_bezel_rect_right.offset_right = 0
			comp_bezel_rect_right.offset_bottom = 0
			comp_yuv_rect_right.offset_left = px
			comp_yuv_rect_right.offset_top = px
			comp_yuv_rect_right.offset_right = -px
			comp_yuv_rect_right.offset_bottom = -px
			comp_yuv_rect_right.anchor_left = 0.0
			comp_yuv_rect_right.anchor_top = 0.0
			comp_yuv_rect_right.anchor_right = 1.0
			comp_yuv_rect_right.anchor_bottom = 1.0
			comp_yuv_rect_right.anchors_preset = 0
			comp_viewport_right.size = Vector2i(base_w + px * 2, base_h + px * 2)
		if comp_cylinder_left and comp_cylinder_left.visible:
			comp_cylinder_left.set_aspect_ratio(bezel_x / bezel_y)
		if comp_cylinder_right and comp_cylinder_right.visible:
			comp_cylinder_right.set_aspect_ratio(bezel_x / bezel_y)
	else:
		comp_bezel_rect.color = Color(0, 0, 0, 0)
		comp_bezel_rect.anchors_preset = 15
		comp_bezel_rect.offset_left = 0
		comp_bezel_rect.offset_top = 0
		comp_bezel_rect.offset_right = 0
		comp_bezel_rect.offset_bottom = 0
		comp_yuv_rect.offset_left = 0
		comp_yuv_rect.offset_top = 0
		comp_yuv_rect.offset_right = 0
		comp_yuv_rect.offset_bottom = 0
		comp_yuv_rect.anchors_preset = 15
		comp_viewport.size = Vector2i(base_w, base_h)
		if comp_cylinder and comp_cylinder.visible:
			comp_cylinder.set_aspect_ratio(_mesh_size.x / _mesh_size.y)
		if comp_bezel_rect_left:
			comp_bezel_rect_left.color = Color(0, 0, 0, 0)
			comp_bezel_rect_left.anchors_preset = 15
			comp_bezel_rect_left.offset_left = 0
			comp_bezel_rect_left.offset_top = 0
			comp_bezel_rect_left.offset_right = 0
			comp_bezel_rect_left.offset_bottom = 0
			comp_yuv_rect_left.offset_left = 0
			comp_yuv_rect_left.offset_top = 0
			comp_yuv_rect_left.offset_right = 0
			comp_yuv_rect_left.offset_bottom = 0
			comp_yuv_rect_left.anchors_preset = 15
			comp_viewport_left.size = Vector2i(base_w, base_h)
		if comp_bezel_rect_right:
			comp_bezel_rect_right.color = Color(0, 0, 0, 0)
			comp_bezel_rect_right.anchors_preset = 15
			comp_bezel_rect_right.offset_left = 0
			comp_bezel_rect_right.offset_top = 0
			comp_bezel_rect_right.offset_right = 0
			comp_bezel_rect_right.offset_bottom = 0
			comp_yuv_rect_right.offset_left = 0
			comp_yuv_rect_right.offset_top = 0
			comp_yuv_rect_right.offset_right = 0
			comp_yuv_rect_right.offset_bottom = 0
			comp_yuv_rect_right.anchors_preset = 15
			comp_viewport_right.size = Vector2i(base_w, base_h)
		if comp_cylinder_left and comp_cylinder_left.visible:
			comp_cylinder_left.set_aspect_ratio(_mesh_size.x / _mesh_size.y)
		if comp_cylinder_right and comp_cylinder_right.visible:
			comp_cylinder_right.set_aspect_ratio(_mesh_size.x / _mesh_size.y)

func _update_cylinder_params():
	if not comp_cylinder and not comp_cylinder_left:
		return
	var cam_to_screen = screen_mesh.global_position - xr_camera.global_position
	var view_dist = cam_to_screen.length()
	if view_dist < 0.5:
		view_dist = 3.0
	var radius = view_dist * 100.0
	if curvature == 1:
		radius = view_dist * 3.0
	elif curvature == 2:
		radius = view_dist * 2.0
	var screen_forward = -screen_mesh.global_transform.basis.z
	var central_angle = _mesh_size.x / radius
	var aspect = _mesh_size.x / _mesh_size.y
	_comp_cyl_radius = radius
	_comp_cyl_central_angle = central_angle
	_comp_cyl_center = screen_mesh.global_position - screen_forward * radius
	if comp_cylinder and comp_cylinder.visible:
		comp_cylinder.set_radius(radius)
		comp_cylinder.set_central_angle(central_angle)
		comp_cylinder.set_aspect_ratio(aspect)
		comp_cylinder.global_position = screen_mesh.global_position - screen_forward * radius
		comp_cylinder.global_rotation = screen_mesh.global_rotation
	if comp_cylinder_left and comp_cylinder_left.visible:
		comp_cylinder_left.set_radius(radius)
		comp_cylinder_left.set_central_angle(central_angle)
		comp_cylinder_left.set_aspect_ratio(aspect)
		comp_cylinder_left.global_position = screen_mesh.global_position - screen_forward * radius
		comp_cylinder_left.global_rotation = screen_mesh.global_rotation
	if comp_cylinder_right and comp_cylinder_right.visible:
		comp_cylinder_right.set_radius(radius)
		comp_cylinder_right.set_central_angle(central_angle)
		comp_cylinder_right.set_aspect_ratio(aspect)
		comp_cylinder_right.global_position = screen_mesh.global_position - screen_forward * radius
		comp_cylinder_right.global_rotation = screen_mesh.global_rotation

func _make_screen_transparent():
	_screen_mesh_saved_mat = screen_mesh.material_override
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mesh.material_override = mat

func _make_ui_transparent():
	_ui_saved_mat = ui_panel_3d.material_override
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ui_panel_3d.material_override = mat

func _make_kb_transparent():
	if not virtual_keyboard:
		return
	_kb_saved_mat = virtual_keyboard.mesh_instance.material_override
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	virtual_keyboard.mesh_instance.material_override = mat

func _restore_screen_material():
	if _screen_mesh_saved_mat:
		screen_mesh.material_override = _screen_mesh_saved_mat
		_screen_mesh_saved_mat = null
	elif _screen_mesh_original_mat:
		screen_mesh.material_override = _screen_mesh_original_mat
	var screen_bar = get_node_or_null("%ScreenGrabBar")
	if screen_bar:
		screen_bar.visible = true

func _restore_ui_material():
	if _ui_saved_mat:
		ui_panel_3d.material_override = _ui_saved_mat
		_ui_saved_mat = null

func _restore_kb_material():
	if _kb_saved_mat and virtual_keyboard:
		virtual_keyboard.mesh_instance.material_override = _kb_saved_mat
		_kb_saved_mat = null

func _get_steady_hit(raw: Vector3) -> Vector3:
	if pointer_steady == 0 or not is_xr_active:
		_steady_active = false
		return raw
	if not _steady_active:
		_steady_hit = raw
		_steady_active = true
		return raw
	var factor := 0.3 if pointer_steady == 1 else 0.1
	var dead_zone := 0.002 if pointer_steady == 1 else 0.005
	var delta = raw - _steady_hit
	if delta.length() < dead_zone:
		return _steady_hit
	_steady_hit = _steady_hit.lerp(raw, factor)
	return _steady_hit

func _get_cylinder_normal_at(hit_point: Vector3) -> Vector3:
	if curvature == 0 or not comp_layer:
		return -screen_mesh.global_transform.basis.z
	var screen_forward = -screen_mesh.global_transform.basis.z
	if _comp_cyl_radius < 0.01:
		return screen_forward
	var cyl_center = screen_mesh.global_position - screen_forward * _comp_cyl_radius
	var to_hit = hit_point - cyl_center
	to_hit.y = 0.0
	if to_hit.length() < 0.001:
		return screen_forward
	return to_hit.normalized()

func _hit_point_to_uv(hit_point: Vector3) -> Vector2:
	var ms = _mesh_size
	var local_pos = screen_mesh.to_local(hit_point)
	var uv_x = 0.0
	var uv_y = clampf((ms.y * 0.5 - local_pos.y) / ms.y, 0.0, 1.0)
	if curvature == 0:
		uv_x = clampf((local_pos.x + ms.x * 0.5) / ms.x, 0.0, 1.0)
	elif use_comp_layer and _comp_cyl_radius > 0.01 and _comp_cyl_central_angle > 0.001:
		var cam_pos = xr_camera.global_position
		var ray_dir = (hit_point - cam_pos).normalized()
		var screen_right = screen_mesh.global_transform.basis.x
		var screen_forward = -screen_mesh.global_transform.basis.z
		var screen_up = screen_mesh.global_transform.basis.y
		var oc = cam_pos - _comp_cyl_center
		var oc_right = oc.dot(screen_right)
		var oc_fwd = oc.dot(screen_forward)
		var d_right = ray_dir.dot(screen_right)
		var d_fwd = ray_dir.dot(screen_forward)
		var a = d_right * d_right + d_fwd * d_fwd
		var b = 2.0 * (oc_right * d_right + oc_fwd * d_fwd)
		var c = oc_right * oc_right + oc_fwd * oc_fwd - _comp_cyl_radius * _comp_cyl_radius
		var disc = b * b - 4.0 * a * c
		if disc < 0.0:
			uv_x = 0.5
		else:
			var sqrt_disc = sqrt(disc)
			var t1 = (-b - sqrt_disc) / (2.0 * a)
			var t2 = (-b + sqrt_disc) / (2.0 * a)
			var t = t1 if t1 > 0.001 else t2
			if t > 0.0:
				var hit_world = cam_pos + ray_dir * t
				var hit_local = screen_mesh.to_local(hit_world)
				uv_y = clampf((ms.y * 0.5 - hit_local.y) / ms.y, 0.0, 1.0)
				var hit_cyl = hit_world - _comp_cyl_center
				var hit_right = hit_cyl.dot(screen_right)
				var hit_fwd = hit_cyl.dot(screen_forward)
				var hit_angle = atan2(hit_right, hit_fwd)
				uv_x = clampf((hit_angle + _comp_cyl_central_angle * 0.5) / _comp_cyl_central_angle, 0.0, 1.0)
			else:
				uv_x = 0.5
	else:
		var radius = 10.0 if curvature == 1 else 4.0
		var total_angle = ms.x / radius
		var chord = clampf(local_pos.x / radius, -1.0, 1.0)
		uv_x = clampf((asin(chord) + total_angle * 0.5) / total_angle, 0.0, 1.0)
	return Vector2(uv_x, uv_y)

func _show_stream_cursor(cursor: TextureRect, circle: ColorRect, cx: float, cy: float, cursor_px: int):
	if cursor_mode == 0:
		if cursor: cursor.visible = false
		if circle:
			circle.visible = true
			circle.position = Vector2(cx - cursor_px * 0.5, cy - cursor_px * 0.5)
			circle.size = Vector2(cursor_px, cursor_px)
	else:
		if circle: circle.visible = false
		if cursor:
			cursor.visible = true
			cursor.position = Vector2(cx, cy)
			cursor.size = Vector2(cursor_px, cursor_px * 1.6)

func _hide_stream_cursor(cursor: TextureRect, circle: ColorRect):
	if cursor: cursor.visible = false
	if circle: circle.visible = false

func _hide_all_stream_cursors():
	_hide_stream_cursor(comp_stream_cursor, comp_stream_cursor_circle)
	_hide_stream_cursor(comp_stream_cursor_left, comp_stream_cursor_circle_left)
	_hide_stream_cursor(comp_stream_cursor_right, comp_stream_cursor_circle_right)

func _update_cursor_layer():
	if not comp_cursor or not use_comp_layer:
		if comp_cursor:
			comp_cursor.visible = false
		_hide_all_stream_cursors()
		return
	var active_raycast = hand_raycast if is_xr_active else mouse_raycast
	var on_screen = false
	var pad_on_screen = controller_mapper and controller_mapper.is_active() and controller_mapper.ctrl_type == ControllerMapper.CtrlType.GAMEPAD
	var tp_capturing = virtual_keyboard and virtual_keyboard.visible and virtual_keyboard.trackpad_active
	var stereo = settings_controller.get_stereo_mode() if settings_controller else 0
	var use_in_stream = is_streaming and on_screen and not pad_on_screen and not tp_capturing
	if active_raycast.is_colliding():
		var hit_point = _get_steady_hit(active_raycast.get_collision_point())
		var col = active_raycast.get_collider()
		var par = col.get_parent() if col else null
		on_screen = (par == screen_mesh)
		use_in_stream = is_streaming and on_screen and not pad_on_screen and not tp_capturing
		if on_screen and (pad_on_screen or tp_capturing):
			comp_cursor.visible = false
			_hide_all_stream_cursors()
		elif use_in_stream and on_screen:
			var uv = _hit_point_to_uv(hit_point)
			var bezel_px = 8 if bezel_enabled else 0
			var base_w = _comp_base_size.x
			var base_h = _comp_base_size.y
			var cursor_px = 48
			var cx = bezel_px + uv.x * base_w
			var cy = bezel_px + uv.y * base_h
			comp_cursor.visible = false
			_show_stream_cursor(comp_stream_cursor, comp_stream_cursor_circle, cx, cy, cursor_px)
			if stereo > 0:
				var left_cx = cx
				if stereo >= 3:
					left_cx += 0.015 * base_w
				_show_stream_cursor(comp_stream_cursor_left, comp_stream_cursor_circle_left, left_cx, cy, cursor_px)
				_show_stream_cursor(comp_stream_cursor_right, comp_stream_cursor_circle_right, cx, cy, cursor_px)
			else:
				_hide_stream_cursor(comp_stream_cursor_left, comp_stream_cursor_circle_left)
				_hide_stream_cursor(comp_stream_cursor_right, comp_stream_cursor_circle_right)
		else:
			_hide_all_stream_cursors()
			var surf_normal = _get_cylinder_normal_at(hit_point) if on_screen else (xr_camera.global_position - hit_point).normalized()
			var to_cam = (xr_camera.global_position - hit_point).normalized()
			var pointer = comp_cursor_viewport.get_node_or_null("PointerTexture")
			var circle = comp_cursor_viewport.get_node_or_null("CircleTexture")
			if cursor_mode == 0:
				if pointer: pointer.visible = false
				if circle: circle.visible = true
				comp_cursor_viewport.size = Vector2i(256, 256)
				comp_cursor.set_quad_size(Vector2(0.035, 0.035))
				comp_cursor.global_position = hit_point + surf_normal * 0.002
				comp_cursor.look_at(comp_cursor.global_position + to_cam, Vector3.UP)
				comp_cursor.rotate_object_local(Vector3.UP, PI)
			elif on_screen:
				if pointer: pointer.visible = true
				if circle: circle.visible = false
				comp_cursor_viewport.size = Vector2i(40, 64)
				comp_cursor.set_quad_size(Vector2(0.04, 0.064))
				comp_cursor.global_position = hit_point + surf_normal * 0.002
				comp_cursor.look_at(comp_cursor.global_position + to_cam, Vector3.UP)
				comp_cursor.rotate_object_local(Vector3.UP, PI)
				var right = comp_cursor.global_transform.basis.x
				var up = comp_cursor.global_transform.basis.y
				comp_cursor.global_position += right * 0.02 - up * 0.032
			else:
				if pointer: pointer.visible = false
				if circle: circle.visible = true
				comp_cursor_viewport.size = Vector2i(256, 256)
				comp_cursor.set_quad_size(Vector2(0.035, 0.035))
				comp_cursor.global_position = hit_point + surf_normal * 0.002
				comp_cursor.look_at(comp_cursor.global_position + to_cam, Vector3.UP)
				comp_cursor.rotate_object_local(Vector3.UP, PI)
			comp_cursor.visible = true
	else:
		comp_cursor.visible = false
		_hide_all_stream_cursors()
	if pointer_cursor:
		pointer_cursor.visible = false
	if contact_dot:
		contact_dot.visible = false
	if comp_ui and comp_ui.visible:
		comp_ui.global_position = ui_panel_3d.global_position
		comp_ui.global_rotation = ui_panel_3d.global_rotation
	if comp_kb and virtual_keyboard and virtual_keyboard.visible:
		comp_kb.global_position = virtual_keyboard.global_position
		comp_kb.global_rotation = virtual_keyboard.global_rotation
		comp_kb.visible = true
		if not _kb_saved_mat:
			_make_kb_transparent()
	else:
		if comp_kb:
			comp_kb.visible = false
		if virtual_keyboard and _kb_saved_mat:
			virtual_keyboard.mesh_instance.material_override = _kb_saved_mat
			_kb_saved_mat = null

func set_comp_grab_bar_color(viewport: SubViewport, color: Color):
	if not viewport:
		return
	var bar = viewport.find_child("CompGrabBar", true, false)
	if bar and bar is PanelContainer:
		var style = bar.get_theme_stylebox("panel")
		if style and style is StyleBoxFlat:
			style = style.duplicate()
			style.bg_color = Color(1, 1, 1, color.a)
			bar.add_theme_stylebox_override("panel", style)

func exit_app():
	get_tree().quit()

func disconnect_stream():
	if current_host_id >= 0:
		stream_backend.cancel_host_stream(current_host_id)
	stream_backend.stop_play_stream()

func start_connect_timeout():
	_connect_timeout_pending = true
	get_tree().create_timer(10.0).timeout.connect(_on_connect_timeout)

func _on_connect_timeout():
	if not _connect_timeout_pending:
		return
	_connect_timeout_pending = false
	_log("[CONNECT] Connection timed out")
	_ui_status_label.text = "Failed to connect (timeout)"
	welcome_screen.reset_connect_button()
	stream_backend.stop_play_stream()

func _bind_yuv_textures():
	var mat = stream_backend.get_shader_material()
	if not mat:
		_log("[YUV] No shader material from stream backend, using SubViewport path")
		var stream_tex = stream_viewport.get_texture()
		if not use_comp_layer and screen_mesh.material_override is ShaderMaterial:
			screen_mesh.material_override.set_shader_parameter("main_texture", stream_tex)
			screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
		_bind_comp_fallback_texture(stream_tex)
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
		if not use_comp_layer and screen_mesh.material_override is ShaderMaterial:
			screen_mesh.material_override.set_shader_parameter("tex_y", tex_y)
			screen_mesh.material_override.set_shader_parameter("tex_u", tex_u)
			screen_mesh.material_override.set_shader_parameter("tex_v", tex_v)
			screen_mesh.material_override.set_shader_parameter("color_matrix_type", cmt)
			screen_mesh.material_override.set_shader_parameter("color_range", cr)
			screen_mesh.material_override.set_shader_parameter("yuv_mode", yuv_mode_val)
		_log("[YUV] Direct YUV binding: mode=%d nv12_rd=%s semi_planar=%s" % [yuv_mode_val, str(is_nv12_rd), str(is_semi_planar)])
		_bind_comp_yuv_textures(tex_y, tex_u, tex_v, yuv_mode_val, cmt, cr)
	else:
		var stream_tex = stream_viewport.get_texture()
		if not use_comp_layer and screen_mesh.material_override is ShaderMaterial:
			screen_mesh.material_override.set_shader_parameter("main_texture", stream_tex)
			screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
		_log("[YUV] No Y textures, falling back to SubViewport path")
		_bind_comp_fallback_texture(stream_tex)

func _bind_comp_yuv_textures(tex_y, tex_u, tex_v, yuv_mode: int, cmt, cr):
	var mats = [comp_shader_mat, comp_shader_mat_left, comp_shader_mat_right]
	for mat in mats:
		if not mat:
			continue
		mat.set_shader_parameter("tex_y", tex_y)
		mat.set_shader_parameter("tex_u", tex_u)
		mat.set_shader_parameter("tex_v", tex_v)
		mat.set_shader_parameter("yuv_mode", yuv_mode)
		mat.set_shader_parameter("color_matrix_type", cmt)
		mat.set_shader_parameter("color_range", cr)
	_log("[COMP] YUV textures bound to composition layer shader (mode=%d)" % yuv_mode)

func _bind_comp_fallback_texture(stream_tex):
	var mats = [comp_shader_mat, comp_shader_mat_left, comp_shader_mat_right]
	for mat in mats:
		if not mat:
			continue
		mat.set_shader_parameter("main_texture", stream_tex)
		mat.set_shader_parameter("yuv_mode", 0)

func _on_stream_started():
	var was_restarting = _restarting_stream
	is_streaming = true
	_restarting_stream = false
	_connect_timeout_pending = false
	_reconnecting = false
	_last_activity_time = Time.get_ticks_msec() / 1000.0
	_ui_status_label.text = "Connecting..."
	ui_controller.update_host_label()
	welcome_screen.reset_connect_button()
	if _ui_disconnect_btn: _ui_disconnect_btn.visible = true
	_log("[STREAM] Connection started!")
	if not use_comp_layer:
		stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	welcome_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stream_manager.bind_texture()
	_bind_yuv_textures()
	_switch_to_comp_layer()
	if not was_restarting:
		ui_visible = false
		_set_ui_visible(false)
		if comp_ui:
			comp_ui.visible = false
	if passthrough_mode < 2:
		_hide_all_backgrounds()
	var all_btn_flags = 0x1000|0x2000|0x4000|0x8000|0x0001|0x0002|0x0004|0x0008|0x0100|0x0200|0x0010|0x0020|0x0040|0x0080|0x0400
	stream_backend.send_controller_arrival(0, 1, 1, all_btn_flags, 0x01|0x02)

func _switch_to_comp_layer():
	if not comp_layer_available:
		use_comp_layer = false
		_log("[COMP] Not available, using mesh rendering")
		return
	var stereo = settings_controller.get_stereo_mode() if settings_controller else 0
	_log("[SBS-DEBUG] _switch_to_comp_layer: stereo=%d" % stereo)
	if stereo > 0:
		_switch_to_stereo_comp_layer()
		return
	use_comp_layer = true
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if comp_cylinder_left: comp_cylinder_left.visible = false
	if comp_cylinder_right: comp_cylinder_right.visible = false
	if comp_viewport_left: comp_viewport_left.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if comp_viewport_right: comp_viewport_right.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if comp_cylinder:
		comp_layer = comp_cylinder
		comp_layer.set_layer_viewport(comp_viewport)
		comp_layer.visible = true
		_update_cylinder_params()
		_log("[COMP] Switched to composition layer (cylinder, curv=%d)" % curvature)
	else:
		comp_layer.set_layer_viewport(comp_viewport)
		comp_layer.visible = true
		_log("[COMP] Switched to composition layer (quad fallback)")
	comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	comp_shader_mat.set_shader_parameter("stereo_mode", 0)
	settings_controller.apply_filter()
	_make_screen_transparent()
	bezel_mesh.visible = false
	_update_comp_bezel()

func _switch_to_stereo_comp_layer():
	_log("[SBS-DEBUG] _switch_to_stereo_comp_layer called, comp_layer_available=%s" % str(comp_layer_available))
	if not comp_layer_available:
		use_comp_layer = false
		_log("[COMP] Not available, cannot use stereo comp layer")
		return
	use_comp_layer = true
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if comp_cylinder: comp_cylinder.visible = false
	comp_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var stereo = settings_controller.get_stereo_mode()
	_log("[SBS-DEBUG] stereo=%d comp_cylinder_left=%s comp_cylinder_right=%s comp_viewport_left=%s comp_viewport_right=%s" % [stereo, str(comp_cylinder_left), str(comp_cylinder_right), str(comp_viewport_left), str(comp_viewport_right)])
	_log("[SBS-DEBUG] comp_shader_mat_left=%s comp_shader_mat_right=%s" % [str(comp_shader_mat_left), str(comp_shader_mat_right)])
	comp_cylinder_left.visible = true
	comp_cylinder_right.visible = true
	comp_cylinder_left.set_layer_viewport(comp_viewport_left)
	comp_cylinder_right.set_layer_viewport(comp_viewport_right)
	comp_shader_mat_left.set_shader_parameter("stereo_mode", stereo)
	comp_shader_mat_left.set_shader_parameter("eye_index", 1)
	comp_shader_mat_right.set_shader_parameter("stereo_mode", stereo)
	comp_shader_mat_right.set_shader_parameter("eye_index", 2)
	comp_viewport_left.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	comp_viewport_right.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_make_screen_transparent()
	bezel_mesh.visible = false
	_update_cylinder_params()
	_update_comp_bezel()
	if is_streaming:
		_bind_yuv_textures()
	_log("[COMP] Switched to stereo composition layer (mode=%d)" % stereo)

func _switch_to_mesh_rendering():
	use_comp_layer = false
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_streaming else SubViewport.UPDATE_DISABLED
	if comp_cylinder: comp_cylinder.visible = false
	if comp_cylinder_left: comp_cylinder_left.visible = false
	if comp_cylinder_right: comp_cylinder_right.visible = false
	if comp_ui: comp_ui.visible = false
	if comp_kb: comp_kb.visible = false
	if comp_cursor: comp_cursor.visible = false
	if comp_viewport:
		comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if comp_viewport_left:
		comp_viewport_left.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if comp_viewport_right:
		comp_viewport_right.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_restore_screen_material()
	_restore_ui_material()
	_restore_kb_material()
	bezel_mesh.visible = bezel_enabled
	if is_streaming:
		stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var mat = screen_mesh.material_override
		_log("[MESH] material type=%s" % str(mat.get_class()) if mat else "[MESH] material is null")
		mat.set_shader_parameter("main_texture", stream_viewport.get_texture())
		mat.set_shader_parameter("yuv_mode", 0)
		_bind_yuv_textures()
		var mode = settings_controller.get_stereo_mode()
		mat.set_shader_parameter("stereo_mode", mode)
		mat.set_shader_parameter("filter_mode", smooth_mode)
		mat.set_shader_parameter("sharpen", float(sharpen_mode) * 0.016)
		_log("[MESH] stereo=%d yuv_mode=%d filter=%d sharpen=%.3f" % [mode, mat.get_shader_parameter("yuv_mode"), smooth_mode, float(sharpen_mode) * 0.016])

func _update_comp_layer_size():
	_update_cylinder_params()

func _on_stream_terminated(msg: String, err_code: int = 0):
	_log("[NF] _on_stream_terminated: auto=" + str(_auto_connect) + " restarting=" + str(_restarting_stream) + " reconnecting=" + str(_reconnecting) + " msg=" + str(msg) + " err=" + str(err_code))
	if _auto_connect:
		_auto_connect = false
		return
	if _restarting_stream:
		is_streaming = false
		_server_codec_support = {}
		ui_controller.update_codec_btn()
		stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_clear_comp_yuv_textures()
		if not use_comp_layer and screen_mesh.material_override is ShaderMaterial:
			screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
			screen_mesh.material_override.set_shader_parameter("tex_y", null)
			screen_mesh.material_override.set_shader_parameter("tex_u", null)
			screen_mesh.material_override.set_shader_parameter("tex_v", null)
		return
	if auto_reconnect_enabled and err_code != 0:
		_log("[RECONNECT] Keeping stream alive for auto-reconnect")
		is_streaming = false
		_ui_status_label.text = "Connection lost, reconnecting..."
		return
	_reconnecting = false
	is_streaming = false
	_full_disconnect_cleanup("Disconnected: " + str(msg))

func _full_disconnect_cleanup(status_msg: String):
	_connect_timeout_pending = false
	_server_codec_support = {}
	ui_controller.update_codec_btn()
	_ui_status_label.text = status_msg
	if _ui_disconnect_btn: _ui_disconnect_btn.visible = false
	_log("[STREAM] Full disconnect: %s" % status_msg)
	welcome_screen.show_welcome_screen("welcome")
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_clear_comp_yuv_textures()
	comp_shader_mat.set_shader_parameter("main_texture", welcome_viewport.get_texture())
	comp_shader_mat.set_shader_parameter("yuv_mode", 0)
	if comp_shader_mat_left:
		comp_shader_mat_left.set_shader_parameter("main_texture", welcome_viewport.get_texture())
		comp_shader_mat_left.set_shader_parameter("yuv_mode", 0)
	if comp_shader_mat_right:
		comp_shader_mat_right.set_shader_parameter("main_texture", welcome_viewport.get_texture())
		comp_shader_mat_right.set_shader_parameter("yuv_mode", 0)
	if not use_comp_layer and screen_mesh.material_override is ShaderMaterial:
		screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
		screen_mesh.material_override.set_shader_parameter("tex_y", null)
		screen_mesh.material_override.set_shader_parameter("tex_u", null)
		screen_mesh.material_override.set_shader_parameter("tex_v", null)
	stream_manager.teardown_v2_yuv_rect()
	welcome_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if comp_layer_available:
		_switch_to_comp_layer()
		comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		if not use_comp_layer:
			screen_mesh.material_override.set_shader_parameter("main_texture", welcome_viewport.get_texture())
		_switch_to_mesh_rendering()
	if mouse_captured_by_stream:
		input_handler.release_stream_mouse()
	audio_player.stop()
	ui_visible = false
	_set_ui_visible(false)
	if comp_ui:
		comp_ui.visible = false
	welcome_screen.reset_connect_button()
	if passthrough_mode >= 2:
		var bg_idx = passthrough_mode - 2
		if bg_idx >= 0 and bg_idx < bg_names.size():
			var bg = get_node_or_null(bg_names[bg_idx])
			if bg:
				bg.visible = true
				bg.emitting = true
	welcome_screen.update_welcome_info()
	stream_manager.resize_stream_viewport(1920, 1080)

func _clear_comp_yuv_textures():
	var mats = [comp_shader_mat, comp_shader_mat_left, comp_shader_mat_right]
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

func _ready():
	if OS.get_name() == "Android":
		OS.set_environment("CURL_CA_BUNDLE", "/system/etc/security/cacerts/")
		OS.set_environment("SSL_CERT_FILE", "/system/etc/security/cacerts/")
	else:
		OS.set_environment("CURL_CA_BUNDLE", "/etc/ssl/certs/ca-certificates.crt")
		OS.set_environment("SSL_CERT_FILE", "/etc/ssl/certs/")
	_log("=== Nightfall started ===")
	Engine.max_fps = 0

	stream_manager = StreamManager.new(self)
	xr_interaction = XRInteraction.new(self)
	input_handler = InputHandler.new(self)
	ui_controller = UIController.new(self)
	auto_detect = AutoDetect.new(self)
	depth_estimator = DepthEstimatorModule.new(self)
	welcome_screen = WelcomeScreen.new(self)
	screen_manager = ScreenManager.new(self)
	settings_controller = SettingsController.new(self)
	state_manager = StateManager.new(self)
	host_discovery = HostDiscovery.new(self)
	controller_mapper = ControllerMapper.new(self)
	add_child(controller_mapper)

	if OS.get_name() == "Android":
		depth_estimator.setup()
	sbs_mode = clampi(sbs_mode, 0, 2)
	ai_3d_mode = clampi(ai_3d_mode, 0, 1)

	virtual_keyboard = VirtualKeyboard.new(self)
	add_child(virtual_keyboard)
	virtual_keyboard.build()

	%ScreenGrabBar.material_override = %ScreenGrabBar.material_override.duplicate()
	_mesh_size = screen_mesh.mesh.size
	screen_manager.create_corner_handles()
	screen_manager.create_bezel()
	_create_contact_dot()

	if OS.get_name() == "Android":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if OS.get_name() == "Android":
		_load_controller_models()

	ui_controller.build_ui()
	welcome_screen.build_welcome_ui()

	%IPInput.gui_input.connect(func(e): ui_controller.on_ipinput_gui_input(e))
	ui_controller.setup_numpad()

	if config_mgr and comp_mgr:
		comp_mgr.set_config_manager(config_mgr)
	if not ClassDB.class_exists("NightfallStream"):
		_log("[FATAL] NightfallStream GDExtension failed to load - missing .so or incompatible glibc")
		if not Engine.is_editor_hint():
			get_tree().quit()
		return
	var v2_node = ClassDB.instantiate("NightfallStream")
	add_child(v2_node)
	v2_node.set_auto_reconnect(auto_reconnect_enabled)
	v2_node.set_max_reconnect_attempts(5)
	v2_node.set_reconnect_delay_ms(2000)
	stream_backend = StreamBackend.new(v2_node)
	stream_backend.set_config_manager(config_mgr)
	stream_backend.set_computer_manager(comp_mgr)
	_client_codec_support = stream_backend.probe_all_video_formats()
	_log("[CODEC] Client support: h264=%s hevc=%s av1=%s raw=%s" % [
		str(_client_codec_support.get("h264", false)),
		str(_client_codec_support.get("hevc", false)),
		str(_client_codec_support.get("av1", false)),
		str(_client_codec_support.get("raw", true))])
	v2_node.pair_completed.connect(func(s, m): stream_manager.on_pair_completed(s, m))
	v2_node.stream_started.connect(func():
		_on_stream_started()
	)
	v2_node.stream_terminated.connect(func(err_code, err_msg):
		_on_stream_terminated(err_msg, err_code)
	)
	if v2_node.has_signal("reconnect_scheduled"):
		v2_node.reconnect_scheduled.connect(func(attempt, max_attempts, delay_ms):
			_reconnecting = true
			_ui_status_label.text = "Reconnecting %d/%d in %ds..." % [attempt, max_attempts, delay_ms / 1000]
			_log("[RECONNECT] Attempt %d/%d in %dms" % [attempt, max_attempts, delay_ms])
		)
	if v2_node.has_signal("reconnect_failed"):
		v2_node.reconnect_failed.connect(func():
			_reconnecting = false
			_log("[RECONNECT] All attempts failed")
			_full_disconnect_cleanup("Reconnect failed")
		)
	if v2_node.has_signal("h264_hw_upgraded"):
		v2_node.h264_hw_upgraded.connect(func():
			_bind_yuv_textures()
			_log("[H264] HW upgrade: re-bound YUV textures for NV12")
		)
	if v2_node.has_signal("controller_rumble"):
		v2_node.controller_rumble.connect(func(controller, low_freq, high_freq):
			_trigger_haptic(controller, low_freq, high_freq)
		)
	if v2_node.has_signal("controller_trigger_rumble"):
		v2_node.controller_trigger_rumble.connect(func(controller, left_motor, right_motor):
			_trigger_haptic(controller, left_motor, right_motor)
		)
	v2_node.log_message.connect(func(msg):
		if "dropped" in msg or "Unrecoverable" in msg or "Waiting for IDR" in msg:
			stats_network_events += 1
	)

	var interface = XRServer.find_interface("OpenXR")
	if not interface or not interface.is_initialized():
		_log("[XR] OpenXR not available - cannot run without VR runtime")
		if not Engine.is_editor_hint():
			get_tree().quit()
		return

	var render_size = interface.get_render_target_size()
	_xr_render_width = int(render_size.x)
	_log("[XR] OpenXR render target: %dx%d" % [render_size.x, render_size.y])
	_log("[XR] Blend modes: %s" % str(interface.get_supported_environment_blend_modes()))

	var blend_modes = interface.get_supported_environment_blend_modes()
	var has_alpha_blend = false
	for bm in blend_modes:
		if bm == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
			has_alpha_blend = true
			break

	if has_alpha_blend:
		get_viewport().transparent_bg = true
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color(0, 0, 0, 0)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		passthrough_labels = ["On", "Off", "Starfield", "Ash", "Snow", "Data"]
	else:
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color(0, 0, 0, 1)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		passthrough_mode = 1
		passthrough_labels = ["Off", "Starfield", "Ash", "Snow", "Data"]

	get_viewport().size = render_size
	get_viewport().use_xr = true
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	_xr_base_render_scale = get_viewport().scaling_3d_scale
	is_xr_active = true
	sbs_mode = 0
	ai_3d_mode = 0
	passthrough_mode = 0

	settings_controller.apply_display_refresh_rate()

	_create_backgrounds()

	_screen_mesh_original_mat = screen_mesh.material_override
	_setup_comp_layer()
	if comp_layer_available:
		comp_shader_mat.set_shader_parameter("main_texture", welcome_viewport.get_texture())
		comp_shader_mat.set_shader_parameter("yuv_mode", 0)
		if comp_shader_mat_left:
			comp_shader_mat_left.set_shader_parameter("main_texture", welcome_viewport.get_texture())
			comp_shader_mat_left.set_shader_parameter("yuv_mode", 0)
		if comp_shader_mat_right:
			comp_shader_mat_right.set_shader_parameter("main_texture", welcome_viewport.get_texture())
			comp_shader_mat_right.set_shader_parameter("yuv_mode", 0)
	comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	await get_tree().create_timer(0.5).timeout
	_reposition_screen_and_ui()

	screen_mesh.extra_cull_margin = 10.0
	ui_panel_3d.extra_cull_margin = 10.0

	state_manager.load_state()

	if comp_layer_available:
		_switch_to_comp_layer()

	if passthrough_mode > 0:
		var saved_pt = passthrough_mode
		passthrough_mode = 0
		for i in range(saved_pt):
			settings_controller.toggle_passthrough()

	ui_visible = false
	_set_ui_visible(false)

	var saved_ip = ""
	if config_mgr:
		config_mgr.load_config()
		var save = ConfigFile.new()
		if save.load("user://last_connection.cfg") == OK:
			saved_ip = save.get_value("connection", "ip", "")
			if saved_ip != "":
				%IPInput.text = saved_ip
				state_manager.load_host_state(saved_ip)
				for h in config_mgr.get_hosts():
					if h.has("localaddress") and h.localaddress == saved_ip:
						current_host_id = h.id
						break
				ui_controller.update_host_label()
				welcome_screen.update_welcome_info()

	stream_manager.bind_texture()
	if screen_mesh.material_override is ShaderMaterial:
		screen_mesh.material_override.set_shader_parameter("main_texture", welcome_viewport.get_texture())
	comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var _wt = welcome_viewport.get_texture()

	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ui_controller.update_ui()
	ui_controller.update_stereo_shader()

	if _auto_connect:
		var v2_cm = stream_backend.get_config_manager()
		if v2_cm:
			var v2_hosts = v2_cm.get_hosts()
			if v2_hosts.size() > 0:
				var h = v2_hosts[0]
				var host_ip = h.get("localaddress", "") if h.has("localaddress") else saved_ip
				var host_id = h.get("id", -1) if h.has("id") else -1
				if host_id != -1 and host_ip != "":
					current_host_id = host_id
					%IPInput.text = host_ip
					_log("[AUTO-CONNECT] Auto-connecting to host_id=%d ip=%s" % [host_id, host_ip])
					_auto_connect = false
					await get_tree().create_timer(1.0).timeout
					stream_manager.start_stream(host_id, _selected_app_id)

	Input.joy_connection_changed.connect(func(device, connected):
		_on_joy_changed(device, connected)
	)

	_post_ready_check.call_deferred()

func _post_ready_check():
	await get_tree().create_timer(0.5).timeout



func _on_joy_changed(device: int, connected: bool):
	pass

func _process(delta):
	if Engine.get_frames_drawn() % 120 == 0:
		_flush_log()

	if is_xr_active:
		if not controller_mapper or not controller_mapper.is_active():
			var b_pressed = right_hand.is_button_pressed("by_button")
			if b_pressed and not _was_b_pressed:
				_toggle_ui()
			_was_b_pressed = b_pressed
			var a_pressed = right_hand.is_button_pressed("ax_button")
			if a_pressed and not _was_a_pressed:
				virtual_keyboard.toggle()
			_was_a_pressed = a_pressed
			var r_stick_click = right_hand.is_button_pressed("primary_click")
			var l_stick_click = left_hand.is_button_pressed("primary_click") if left_hand else false
			if r_stick_click and not _was_r_stick_click and not l_stick_click:
				var tp_exited = virtual_keyboard and virtual_keyboard.thumbstick_exit_flag
				if not virtual_keyboard or (not virtual_keyboard.trackpad_active and not tp_exited):
					settings_controller.cycle_sbs_mode()
			if not r_stick_click:
				if virtual_keyboard:
					virtual_keyboard.thumbstick_exit_flag = false
			_was_r_stick_click = r_stick_click
		if _startup_reposition:
			if xr_camera.global_position.length_squared() > 0.01:
				_reposition_screen_and_ui()
				_startup_reposition = false

	if right_click_cooldown > 0.0:
		right_click_cooldown -= delta

	if Input.is_action_just_pressed("ui_focus_next"):
		if mouse_captured_by_stream:
			input_handler.release_stream_mouse()

	if Input.is_key_pressed(KEY_CTRL) and Input.is_key_pressed(KEY_ALT) and Input.is_key_pressed(KEY_SHIFT):
		if mouse_captured_by_stream:
			input_handler.release_stream_mouse()

	if not mouse_captured_by_stream:
		xr_interaction.handle_pointer_interaction()
	xr_interaction.handle_scroll()
	_update_cursor_layer()

	if is_streaming and idle_timeout_min > 0:
		if right_hand:
			var trigger = right_hand.get_float("trigger")
			var grip = right_hand.get_float("grip")
			if trigger > 0.1 or grip > 0.1:
				_last_activity_time = Time.get_ticks_msec() / 1000.0
		if left_hand:
			var l_trigger = left_hand.get_float("trigger")
			var l_grip = left_hand.get_float("grip")
			if l_trigger > 0.1 or l_grip > 0.1:
				_last_activity_time = Time.get_ticks_msec() / 1000.0

	if is_xr_active:
		for i in range(bg_names.size()):
			var bg = get_node_or_null(bg_names[i])
			if bg and bg.visible:
				bg.global_position = xr_camera.global_position + bg_offsets[i]
				break

	auto_detect.process(delta)

	if depth_estimator:
		depth_estimator.process(delta)
		if depth_estimator.depth_texture and ai_3d_mode > 0 and use_comp_layer:
			var dt = depth_estimator.depth_texture
			if comp_shader_mat_left and not comp_shader_mat_left.get_shader_parameter("depth_texture"):
				comp_shader_mat_left.set_shader_parameter("depth_texture", dt)
			if comp_shader_mat_right and not comp_shader_mat_right.get_shader_parameter("depth_texture"):
				comp_shader_mat_right.set_shader_parameter("depth_texture", dt)

	if is_streaming:
		if use_comp_layer:
			var need_bind = false
			if comp_shader_mat and comp_shader_mat.get_shader_parameter("yuv_mode") == 0:
				need_bind = true
			if comp_shader_mat_left and comp_shader_mat_left.get_shader_parameter("yuv_mode") == 0:
				need_bind = true
			if comp_shader_mat_right and comp_shader_mat_right.get_shader_parameter("yuv_mode") == 0:
				need_bind = true
			if need_bind:
				_bind_yuv_textures()
			var cur_filter = smooth_mode
			var cur_sharpen = float(sharpen_mode) * 0.5
			var cur_blur_scale = float(host_resolution.x) / float(_xr_render_width) if _xr_render_width > 0 else 1.0
			if cur_filter != _cached_filter_mode or cur_sharpen != _cached_sharpen or cur_blur_scale != _cached_blur_scale:
				_cached_filter_mode = cur_filter
				_cached_sharpen = cur_sharpen
				_cached_blur_scale = cur_blur_scale
				settings_controller.apply_filter()
		stats_frame_times.append(delta)
		stats_timer += delta
		if stats_timer >= 0.5:
			var avg = 0.0
			for t in stats_frame_times:
				avg += t
			if stats_frame_times.size() > 0:
				avg /= stats_frame_times.size()
			stats_fps = 1.0 / avg if avg > 0 else 0.0
			stream_manager.update_stats()
			stats_timer = 0.0
			stats_frame_times.clear()

	if is_streaming and idle_timeout_min > 0:
		var now = Time.get_ticks_msec() / 1000.0
		if now - _last_activity_time > idle_timeout_min * 60.0:
			_log("[IDLE] Idle timeout (%d min), disconnecting" % idle_timeout_min)
			disconnect_stream()
			_full_disconnect_cleanup("Idle timeout")

	if grabbed_node:
		xr_interaction.handle_grab()

	if grabbed_corner_idx >= 0:
		xr_interaction.handle_corner_resize()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		state_manager.save_state()

func _input(event):
	input_handler.handle_input(event)
	if is_streaming and (event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		_last_activity_time = Time.get_ticks_msec() / 1000.0

func _toggle_ui():
	ui_visible = not ui_visible
	_set_ui_visible(ui_visible)
	if ui_visible:
		if comp_ui:
			comp_ui.visible = true
			comp_ui.global_position = ui_panel_3d.global_position
			comp_ui.global_rotation = ui_panel_3d.global_rotation
		if use_comp_layer:
			_make_ui_transparent()
		else:
			var ui_tex = ui_viewport.get_texture()
			ui_panel_3d.material_override.albedo_texture = ui_tex
	else:
		if comp_ui:
			comp_ui.visible = false
		_restore_ui_material()
	if _ui_disconnect_btn:
		_ui_disconnect_btn.visible = is_streaming

var _ui_saved_offset: Vector3 = Vector3.ZERO
var _ui_saved_rot_y: float = 0.0
var _ui_saved_rot_x: float = 0.0
var _ui_has_saved_offset: bool = false

func _set_ui_visible(vis: bool):
	ui_panel_3d.visible = vis
	var area = ui_panel_3d.get_node_or_null("Area3D")
	if area:
		area.process_mode = Node.PROCESS_MODE_INHERIT if vis else Node.PROCESS_MODE_DISABLED
	if is_xr_active and vis:
		var cam_pos = xr_camera.global_position
		if _ui_has_saved_offset:
			ui_panel_3d.global_position = screen_mesh.global_position + screen_mesh.global_transform.basis * _ui_saved_offset
			ui_panel_3d.rotation.y = screen_mesh.global_rotation.y + _ui_saved_rot_y
			ui_panel_3d.rotation.x = _ui_saved_rot_x
		else:
			var cam_fwd = -xr_camera.global_transform.basis.z
			var cam_right = xr_camera.global_transform.basis.x
			var cam_up = xr_camera.global_transform.basis.y
			ui_panel_3d.global_position = cam_pos + cam_fwd * 0.8 - cam_right * 0.8 - cam_up * 0.2
			var to_cam = (cam_pos - ui_panel_3d.global_position).normalized()
			ui_panel_3d.rotation.y = atan2(to_cam.x, to_cam.z)
			ui_panel_3d.rotation.x = -0.26
			_ui_has_saved_offset = true
	elif is_xr_active:
		var scr_basis = screen_mesh.global_transform.basis.inverse()
		_ui_saved_offset = scr_basis * (ui_panel_3d.global_position - screen_mesh.global_position)
		_ui_saved_rot_y = ui_panel_3d.rotation.y - screen_mesh.global_rotation.y
		_ui_saved_rot_x = ui_panel_3d.rotation.x
		_ui_has_saved_offset = true

func _trigger_haptic(_controller: int, low_freq: int, high_freq: int):
	var strength = clampf((low_freq + high_freq) / 510.0, 0.0, 1.0)
	if strength < 0.01:
		return
	if right_hand:
		right_hand.trigger_haptic_pulse("haptic", strength, 0.05)
	if left_hand:
		left_hand.trigger_haptic_pulse("haptic", strength, 0.05)

func _reposition_screen_and_ui():
	if not is_xr_active:
		return
	var cam_pos = xr_camera.global_position
	var cam_fwd = -xr_camera.global_transform.basis.z
	var cam_right = xr_camera.global_transform.basis.x
	var cam_yaw = atan2(-cam_fwd.x, -cam_fwd.z)
	screen_mesh.global_position = cam_pos + cam_fwd * 1.8
	screen_mesh.rotation = Vector3.ZERO
	screen_mesh.rotation.y = cam_yaw
	if (comp_cylinder and comp_cylinder.visible) or (comp_cylinder_left and comp_cylinder_left.visible):
		_update_cylinder_params()
	_log("[POS] Screen at %s, Cam at %s" % [str(screen_mesh.global_position), str(cam_pos)])

func _reset_positions():
	if ui_visible:
		_toggle_ui()
	if virtual_keyboard and virtual_keyboard.visible:
		virtual_keyboard.toggle()
	_ui_has_saved_offset = false
	if virtual_keyboard:
		virtual_keyboard.reset_position()
	_reposition_screen_and_ui()
	state_manager.save_state()

func _load_controller_models():
	var left_scene = load("res://models/controllers/MetaQuestTouchPlus_Left.fbx")
	var right_scene = load("res://models/controllers/MetaQuestTouchPlus_Right.fbx")
	if left_scene:
		var left_model = left_scene.instantiate()
		left_hand.add_child(left_model)
		left_model.scale = Vector3(1.0, 1.0, 1.0)
		left_model.rotation = Vector3(0, PI, 0)
		_apply_controller_textures(left_model, true)
	if right_scene:
		var right_model = right_scene.instantiate()
		right_hand.add_child(right_model)
		right_model.scale = Vector3(1.0, 1.0, 1.0)
		right_model.rotation = Vector3(0, PI, 0)
		_apply_controller_textures(right_model, false)

func _apply_controller_textures(node: Node, is_left: bool):
	var base_color_path = "res://models/controllers/textures/MetaQuestTouchPlus_Left_BaseColor.png" if is_left else "res://models/controllers/textures/MetaQuestTouchPlus_right_BaseColor.png"
	var base_tex = load(base_color_path)
	if not base_tex:
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			for i in range(child.get_surface_override_material_count()):
				var mat = child.get_surface_override_material(i)
				if not mat:
					mat = child.mesh.surface_get_material(i) if child.mesh else null
				if mat is StandardMaterial3D:
					mat = mat.duplicate()
					mat.albedo_texture = base_tex
					child.set_surface_override_material(i, mat)
				elif mat is BaseMaterial3D:
					mat = mat.duplicate()
					mat.albedo_texture = base_tex
					child.set_surface_override_material(i, mat)
		_apply_controller_textures(child, is_left)

var contact_dot: MeshInstance3D
var pointer_cursor: MeshInstance3D

func _create_contact_dot():
	contact_dot = MeshInstance3D.new()
	contact_dot.name = "ContactDot"
	var dot_mesh = SphereMesh.new()
	dot_mesh.radius = 0.01
	dot_mesh.height = 0.02
	contact_dot.mesh = dot_mesh
	var dot_mat = StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(1, 1, 1, 0.1)
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.render_priority = 127
	dot_mat.no_depth_test = true
	contact_dot.material_override = dot_mat
	contact_dot.visible = false
	add_child(contact_dot)

	pointer_cursor = MeshInstance3D.new()
	pointer_cursor.name = "PointerCursor"
	var ptr_mesh = QuadMesh.new()
	ptr_mesh.size = Vector2(0.06, 0.08)
	pointer_cursor.mesh = ptr_mesh
	var ptr_mat = StandardMaterial3D.new()
	ptr_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ptr_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ptr_mat.render_priority = 127
	ptr_mat.no_depth_test = true
	ptr_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ptr_mat.albedo_texture = load("res://src/assets/mouse_pointer_01.png")
	ptr_mat.albedo_color = Color(1, 1, 1, 1.0)
	pointer_cursor.material_override = ptr_mat
	pointer_cursor.visible = false
	pointer_cursor.extra_cull_margin = 10.0
	add_child(pointer_cursor)

func _hide_all_backgrounds():
	for name in bg_names:
		var bg = get_node_or_null(name)
		if bg:
			bg.visible = false
			bg.emitting = false

func _create_backgrounds():
	_create_starfield()
	_create_ash()
	_create_snow()
	_create_data()
	var active_bg = passthrough_mode - 2
	for i in range(bg_names.size()):
		var bg = get_node_or_null(bg_names[i])
		if bg:
			bg.visible = (i == active_bg)

func _create_starfield():
	var particles = GPUParticles3D.new()
	particles.name = "Starfield"
	particles.emitting = true
	particles.amount = 80
	particles.lifetime = 30.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0
	particles.fixed_fps = 30
	particles.local_coords = true
	particles.visible = false
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(50, 50, 50)
	mat.particle_flag_disable_z = false
	mat.gravity = Vector3.ZERO
	var vel = mat.direction
	vel = Vector3(0, 0, 0)
	mat.direction = vel
	mat.spread = 0.0
	particles.process_material = mat
	var star_mesh = SphereMesh.new()
	star_mesh.radius = 0.05
	star_mesh.height = 0.1
	var star_shader = load("res://src/shaders/star.gdshader")
	var star_mat = ShaderMaterial.new()
	star_mat.shader = star_shader
	star_mat.render_priority = -128
	star_mesh.material = star_mat
	particles.draw_pass_1 = star_mesh
	particles.sorting_offset = -100.0
	particles.position = xr_camera.global_position
	add_child(particles)

func _create_ash():
	var particles = GPUParticles3D.new()
	particles.name = "Ash"
	particles.emitting = true
	particles.amount = 200
	particles.lifetime = 4.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0
	particles.fixed_fps = 30
	particles.local_coords = true
	particles.visible = false
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(30, 30, 30)
	mat.particle_flag_disable_z = false
	mat.gravity = Vector3.ZERO
	mat.direction = Vector3(0, 0, 1)
	mat.spread = 30.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 35.0
	particles.process_material = mat
	var dot = SphereMesh.new()
	dot.radius = 0.04
	dot.height = 0.08
	var sh = load("res://src/shaders/warp.gdshader")
	var sm = ShaderMaterial.new()
	sm.shader = sh
	sm.render_priority = -128
	dot.material = sm
	particles.draw_pass_1 = dot
	particles.sorting_offset = -100.0
	particles.position = xr_camera.global_position
	add_child(particles)

func _create_snow():
	var particles = GPUParticles3D.new()
	particles.name = "Snow"
	particles.emitting = true
	particles.amount = 150
	particles.lifetime = 15.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0
	particles.fixed_fps = 30
	particles.local_coords = true
	particles.visible = false
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(20, 2, 20)
	mat.particle_flag_disable_z = false
	mat.gravity = Vector3(0, -1.0, 0)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 15.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 1.0
	particles.process_material = mat
	var flake = QuadMesh.new()
	flake.size = Vector2(0.075, 0.075)
	var sh = load("res://src/shaders/snow.gdshader")
	var sm = ShaderMaterial.new()
	sm.shader = sh
	sm.render_priority = -128
	flake.material = sm
	particles.draw_pass_1 = flake
	particles.sorting_offset = -100.0
	particles.position = xr_camera.global_position + Vector3(0, 10, 0)
	add_child(particles)

func _create_data():
	var particles = GPUParticles3D.new()
	particles.name = "Data"
	particles.emitting = true
	particles.amount = 250
	particles.lifetime = 6.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0
	particles.fixed_fps = 30
	particles.local_coords = true
	particles.visible = false
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(50, 2, 50)
	mat.particle_flag_disable_z = false
	mat.gravity = Vector3(0, 3.0, 0)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 5.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0
	particles.process_material = mat
	var quad = QuadMesh.new()
	quad.size = Vector2(0.3, 1.0)
	var sh = load("res://src/shaders/datastream.gdshader")
	var sm = ShaderMaterial.new()
	sm.shader = sh
	sm.render_priority = -128
	quad.material = sm
	particles.draw_pass_1 = quad
	particles.sorting_offset = -100.0
	particles.position = xr_camera.global_position + Vector3(0, -3, 0)
	add_child(particles)
