class_name SettingsController
extends RefCounted

var main: Node3D
var _restart_pending: bool = false
var _restart_seq: int = 0

var sbs_labels: Array = ["Off", "Stretch", "Crop"]
var ai_3d_labels: Array = ["2D", "MiDaS"]
var idle_labels: Array = ["Off", "5m", "15m", "30m", "60m"]
var idle_values: Array = [0, 5, 15, 30, 60]

func _init(owner: Node3D):
	main = owner

func get_stereo_mode() -> int:
	if main.sbs_mode > 0:
		return main.sbs_mode
	if main.ai_3d_mode == 0:
		return 0
	elif main.ai_3d_mode == 1:
		return 3
	else:
		return 4

func cycle_sbs_mode():
	main.sbs_mode = (main.sbs_mode + 1) % 3
	main.ui_controller.update_option_btn(main._ui_sbs_btn, sbs_labels[main.sbs_mode])
	main.ui_controller.update_3d_btn_state()
	apply_stereo()
	main.state_manager.save_state()

func cycle_ai_3d_mode():
	if OS.get_name() != "Android":
		return
	if main.sbs_mode > 0:
		return
	main.ai_3d_mode = (main.ai_3d_mode + 1) % 2
	main.ui_controller.update_option_btn(main._ui_3d_btn, ai_3d_labels[main.ai_3d_mode])
	apply_stereo()
	main.state_manager.save_state()

func apply_stereo():
	var mode = get_stereo_mode()
	if main.comp_layer_available:
		if mode > 0:
			main._switch_to_stereo_comp_layer()
		else:
			main._switch_to_comp_layer()
	else:
		if mode > 0 and main.use_comp_layer:
			main._switch_to_mesh_rendering()
		elif mode == 0 and not main.use_comp_layer and main.is_streaming:
			main._switch_to_comp_layer()
	if main.screen_mesh.material_override is ShaderMaterial:
		main.screen_mesh.material_override.set_shader_parameter("stereo_mode", mode)
	if main.depth_estimator:
		main.depth_estimator.set_enabled(mode >= 3)
		if mode >= 3 and main.depth_estimator.depth_texture:
			if main.comp_shader_mat_left:
				main.comp_shader_mat_left.set_shader_parameter("depth_texture", main.depth_estimator.depth_texture)
			if main.comp_shader_mat_right:
				main.comp_shader_mat_right.set_shader_parameter("depth_texture", main.depth_estimator.depth_texture)
	main.stream_backend.set_depth_model(1 if mode == 4 else 0)

func toggle_passthrough():
	if not main.is_xr_active:
		return
	var interface = XRServer.find_interface("OpenXR")
	if not interface:
		return
	main.passthrough_mode = (main.passthrough_mode + 1) % main.passthrough_labels.size()
	main._log("[PT] mode=%d labels=%s" % [main.passthrough_mode, str(main.passthrough_labels.size())])
	main._flush_log()
	var has_alpha_blend = main.passthrough_labels.has("On")
	_hide_all_backgrounds()
	if has_alpha_blend and main.passthrough_mode == 0:
		main.get_viewport().transparent_bg = true
		main.world_env.environment.background_mode = Environment.BG_COLOR
		main.world_env.environment.background_color = Color(0, 0, 0, 0)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	elif (has_alpha_blend and main.passthrough_mode == 1) or (not has_alpha_blend and main.passthrough_mode == 0):
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		main.world_env.environment.background_color = Color(0, 0, 0, 1)
		main.get_viewport().transparent_bg = false
	else:
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		main.world_env.environment.background_color = Color(0, 0, 0, 0)
		main.get_viewport().transparent_bg = false
		var bg_idx = main.passthrough_mode - 2
		if bg_idx >= 0 and bg_idx < main.bg_names.size():
			var bg = main.get_node_or_null(main.bg_names[bg_idx])
			if bg:
				bg.visible = true
				bg.emitting = true
	main.ui_controller.update_option_btn(main._ui_pt_btn, main.passthrough_labels[main.passthrough_mode])
	main.state_manager.save_state()

func _hide_all_backgrounds():
	for name in main.bg_names:
		var bg = main.get_node_or_null(name)
		if bg:
			bg.visible = false
			bg.emitting = false

func cycle_smooth_mode():
	main.smooth_mode = (main.smooth_mode + 1) % main.smooth_labels.size()
	main.ui_controller.update_option_btn(main._ui_render_btn, main.smooth_labels[main.smooth_mode])
	apply_filter()
	main.state_manager.save_state()

func cycle_cursor_mode():
	main.cursor_mode = (main.cursor_mode + 1) % main.cursor_labels.size()
	main.ui_controller.update_option_btn(main._ui_cursor_btn, main.cursor_labels[main.cursor_mode])
	main.state_manager.save_state()

func cycle_steady():
	main.pointer_steady = (main.pointer_steady + 1) % main.pointer_steady_labels.size()
	main._steady_active = false
	main.ui_controller.update_option_btn(main._ui_steady_btn, main.pointer_steady_labels[main.pointer_steady])
	main.state_manager.save_state()

func is_codec_available(idx: int) -> bool:
	var client_ok = false
	var server_ok = false
	match idx:
		0:
			client_ok = main._client_codec_support.get("h264", true)
			server_ok = main._server_codec_support.get("h264", true)
		1:
			client_ok = main._client_codec_support.get("hevc", true)
			server_ok = main._server_codec_support.get("hevc", true)
		2:
			client_ok = main._client_codec_support.get("av1", true)
			server_ok = main._server_codec_support.get("av1", true)
		3:
			client_ok = main._client_codec_support.get("raw", true)
			server_ok = main._server_codec_support.get("raw", true)
	if main._server_codec_support.is_empty():
		return client_ok
	return client_ok and server_ok

func _get_available_codecs() -> PackedInt32Array:
	var result = PackedInt32Array()
	for i in range(main.codec_labels.size()):
		if is_codec_available(i):
			result.append(i)
	return result

func cycle_codec():
	var available = _get_available_codecs()
	if available.is_empty():
		return
	var cur_pos = available.find(main.codec_preference)
	if cur_pos >= 0:
		main.codec_preference = available[(cur_pos + 1) % available.size()]
	else:
		main.codec_preference = available[0]
	main.ui_controller.update_codec_btn()
	main.state_manager.save_state()
	if main.is_streaming:
		_schedule_stream_restart()

func fallback_codec():
	if is_codec_available(1):
		main.codec_preference = 1
	else:
		var available = _get_available_codecs()
		main.codec_preference = available[0] if not available.is_empty() else 0

func cycle_sharpen_mode():
	main.sharpen_mode = (main.sharpen_mode + 1) % main.sharpen_labels.size()
	main.ui_controller.update_option_btn(main._ui_sharpen_btn, main.sharpen_labels[main.sharpen_mode])
	apply_filter()
	main.state_manager.save_state()

func cycle_auto_reconnect():
	main.auto_reconnect_enabled = not main.auto_reconnect_enabled
	if main.stream_backend and main.stream_backend._v2:
		main.stream_backend._v2.set_auto_reconnect(main.auto_reconnect_enabled)
	main.ui_controller.update_option_btn(main._ui_reconnect_btn, "On" if main.auto_reconnect_enabled else "Off")
	main.state_manager.save_state()

func cycle_idle_timeout():
	var idx = idle_values.find(main.idle_timeout_min)
	idx = (idx + 1) % idle_values.size()
	main.idle_timeout_min = idle_values[idx]
	main.ui_controller.update_option_btn(main._ui_idle_btn, idle_labels[idx])
	main.state_manager.save_state()

func apply_filter():
	if not main.is_xr_active:
		return
	var filter_val = main.smooth_mode
	var sharp_val = float(main.sharpen_mode) * 0.5
	var blur_scale_val = float(main.host_resolution.x) / float(main._xr_render_width) if main._xr_render_width > 0 else 1.0
	var mat = main.screen_mesh.material_override
	if mat and mat is ShaderMaterial:
		mat.set_shader_parameter("filter_mode", filter_val)
		mat.set_shader_parameter("sharpen", sharp_val)
		mat.set_shader_parameter("blur_scale", blur_scale_val)
	var comp_mats = [main.comp_shader_mat, main.comp_shader_mat_left, main.comp_shader_mat_right]
	for cm in comp_mats:
		if cm:
			cm.set_shader_parameter("filter_mode", filter_val)
			cm.set_shader_parameter("sharpen", sharp_val)
			cm.set_shader_parameter("blur_scale", blur_scale_val)

func apply_display_refresh_rate():
	if not main.is_xr_active:
		return
	var interface = XRServer.find_interface("OpenXR")
	if not interface:
		return
	var target_hz: float = 90.0
	match main.stream_fps:
		30: target_hz = 90.0
		60: target_hz = 72.0
		72: target_hz = 72.0
		90: target_hz = 90.0
		120: target_hz = 120.0
	var available = interface.get_available_display_refresh_rates()
	if available.is_empty():
		main._log("[REFRESH] No available refresh rates reported")
		main.display_refresh_rate = target_hz
		return
	var best: float = 0.0
	for rate in available:
		if rate >= target_hz and (best == 0.0 or rate < best):
			best = rate
	if best == 0.0:
		available.sort()
		best = available[available.size() - 1]
	interface.set_display_refresh_rate(best)
	main.display_refresh_rate = best
	Engine.max_fps = 0
	main._log("[REFRESH] Set headset to %.0fHz (target %.0fHz for %dfps)" % [best, target_hz, main.stream_fps])

func cycle_fps():
	var rates = [30, 60, 72, 90, 120]
	var idx = rates.find(main.stream_fps)
	main.stream_fps = rates[(idx + 1) % rates.size()]
	main.ui_controller.update_option_btn(main._ui_fps_btn, "%d" % main.stream_fps)
	main.state_manager.save_state()
	_schedule_stream_restart()

func cycle_resolution():
	main.resolution_idx += 1
	if main.resolution_idx >= main.resolutions.size():
		main.resolution_idx = -1
	if main.resolution_idx == -1:
		main.host_resolution = Vector2i(1920, 1080)
		main.ui_controller.update_option_btn(main._ui_res_btn, "Auto")
	else:
		main.host_resolution = main.resolutions[main.resolution_idx]
		main.ui_controller.update_option_btn(main._ui_res_btn, main.resolution_labels[main.resolution_idx])
	main.state_manager.save_state()
	_schedule_stream_restart()

func cycle_bitrate():
	main.bitrate_idx += 1
	if main.bitrate_idx >= main.bitrate_labels.size():
		main.bitrate_idx = -1
	var label = main.bitrate_labels[main.bitrate_idx + 1] if main.bitrate_idx >= 0 else "Auto"
	main.ui_controller.update_option_btn(main._ui_bitrate_btn, label)
	main.state_manager.save_state()
	_schedule_stream_restart()

func cycle_double_h():
	main.double_h = not main.double_h
	main.state_manager.save_state()
	_schedule_stream_restart()

func _schedule_stream_restart():
	if not main.is_streaming or main.current_host_id < 0:
		return
	_restart_pending = true
	_restart_seq += 1
	var my_seq = _restart_seq
	await main.get_tree().create_timer(0.8).timeout
	if _restart_seq != my_seq:
		return
	_restart_pending = false
	main._log("[RESTART] Restarting stream")
	apply_display_refresh_rate()
	main._restarting_stream = true
	main._dim_screen()  # Dark grey while reconfiguring
	main.stream_backend.stop_play_stream()
	await main.get_tree().create_timer(0.5).timeout
	main.stream_manager.start_stream(main.current_host_id, main._selected_app_id)

func toggle_hand_tracking():
	main.tracking_mode = (main.tracking_mode + 1) % 2
	main.state_manager.save_state()
	main.state_manager.sync_ui_to_settings()
