class_name ControllerMapper
extends Node

enum CtrlType { GAMEPAD, KEYBOARD, KBMOUSE }
enum BtnToggle { HEAD, TILT, NONE }
enum PrimaryHand { RIGHT, LEFT, AUTO }

var btn_toggle: int = BtnToggle.TILT
var btn_toggle_labels: Array = ["Head", "Tilt", "None"]

var primary_hand: int = PrimaryHand.RIGHT
var primary_labels: Array = ["Right", "Left", "Auto"]

var main: Node3D
var active: bool = false
var ctrl_type: int = CtrlType.GAMEPAD
var type_labels: Array = ["PAD", "PAD", "KBM"]

var _active_key_dirs: Dictionary = {}
var _prev_button_flags: int = 0
var _prev_lt: int = 0
var _prev_rt: int = 0
var _prev_lx: int = 0
var _prev_ly: int = 0
var _prev_rx: int = 0
var _prev_ry: int = 0
var _was_both_sticks: bool = false
var _close_to_head: bool = false
var _close_dist: float = 0.25
var _poll_timer: float = 0.0

var _KBD_DEFAULT = {
	"left_up": KEY_W,
	"left_down": KEY_S,
	"left_left": KEY_A,
	"left_right": KEY_D,
	"right_up": KEY_UP,
	"right_down": KEY_DOWN,
	"right_left": KEY_LEFT,
	"right_right": KEY_RIGHT,
	"right_a": KEY_1,
	"right_b": KEY_2,
	"left_x": KEY_3,
	"left_y": KEY_4,
	"left_trigger": KEY_SHIFT,
	"right_trigger": KEY_SPACE,
	"left_grip": KEY_CTRL,
	"right_grip": KEY_TAB,
	"left_menu": KEY_ESCAPE,
	"right_menu": KEY_ENTER,
}

var _KBM_DEFAULT = {
	"left_up": KEY_W,
	"left_down": KEY_S,
	"left_left": KEY_A,
	"left_right": KEY_D,
	"right_a": KEY_SPACE,
	"right_b": KEY_R,
	"left_x": KEY_E,
	"left_y": KEY_F,
	"left_trigger": KEY_SHIFT,
	"left_grip": KEY_CTRL,
	"left_menu": KEY_ESCAPE,
	"right_menu": KEY_TAB,
}

var _kbd_profile: Dictionary = {}
var _kbm_profile: Dictionary = {}
var _kb_held: Dictionary = {}

func _init(owner: Node3D):
	main = owner
	_kbd_profile = _KBD_DEFAULT.duplicate()
	_kbm_profile = _KBM_DEFAULT.duplicate()

func _process(_delta):
	if not main.is_streaming or not main.is_xr_active or not active:
		if _kb_held.size() > 0:
			for kc in _kb_held.keys():
				main.stream_backend.send_keyboard_event(kc, 4, 0)
			_kb_held.clear()
		return

	_poll_timer += _delta

	if ctrl_type == CtrlType.GAMEPAD:
		_send_controller_mode()
	elif ctrl_type == CtrlType.KEYBOARD:
		_send_keyboard_mode()
	elif ctrl_type == CtrlType.KBMOUSE:
		_send_kbm_mode()

func check_toggle():
	if not main.is_xr_active:
		return
	var l_click = false
	var r_click = false
	if main.left_hand:
		l_click = main.left_hand.is_button_pressed("primary_click")
	if main.right_hand:
		r_click = main.right_hand.is_button_pressed("primary_click")
	var both = l_click and r_click
	if both and not _was_both_sticks:
		if active:
			_deactivate()
		else:
			_activate()
		main.state_manager.save_state()
		if main.ui_controller:
			main.ui_controller.update_ctrl_mode_btn()
	_was_both_sticks = both

func check_toggle_ui():
	if active:
		_deactivate()
	else:
		_activate()
	main.state_manager.save_state()
	if main.ui_controller:
		main.ui_controller.update_ctrl_mode_btn()

func _activate():
	active = true
	if ctrl_type == CtrlType.GAMEPAD:
		_prev_button_flags = -1
		_prev_lt = -1
		_prev_rt = -1
		_prev_lx = -1
		_prev_ly = -1
		_prev_rx = -1
		_prev_ry = -1
		_poll_timer = 1.0
	_log("[CTRL] Activated: " + type_labels[ctrl_type])
	if main.ui_controller:
		main.ui_controller.update_ctrl_mode_btn()
		main.ui_controller.update_ctrl_type_btn()

func _deactivate():
	for kc in _kb_held.keys():
		main.stream_backend.send_keyboard_event(kc, 4, 0)
	_kb_held.clear()
	_active_key_dirs.clear()
	_prev_button_flags = 0
	_prev_lt = 0
	_prev_rt = 0
	_prev_lx = 0
	_prev_ly = 0
	_prev_rx = 0
	_prev_ry = 0
	if main.is_streaming:
		main.stream_backend.send_multi_controller_event(0, 1, 0, 0, 0, 0, 0, 0, 0)
	active = false
	_log("[CTRL] Deactivated")
	if main.ui_controller:
		main.ui_controller.update_ctrl_mode_btn()

func cycle_type():
	ctrl_type = (ctrl_type + 1) % 3
	if ctrl_type == CtrlType.KEYBOARD:
		ctrl_type = CtrlType.KBMOUSE
	if active:
		_deactivate_silent()
		if ctrl_type == CtrlType.GAMEPAD:
			_prev_button_flags = -1
			_prev_lt = -1
			_prev_rt = -1
			_prev_lx = -1
			_prev_ly = -1
			_prev_rx = -1
			_prev_ry = -1
			_poll_timer = 1.0
	main.state_manager.save_state()
	if main.ui_controller:
		main.ui_controller.update_ctrl_mode_btn()
		main.ui_controller.update_ctrl_type_btn()
	_log("[CTRL] Type: " + type_labels[ctrl_type])

func _deactivate_silent():
	for kc in _kb_held.keys():
		main.stream_backend.send_keyboard_event(kc, 4, 0)
	_kb_held.clear()
	_active_key_dirs.clear()
	_prev_button_flags = 0
	_prev_lt = 0
	_prev_rt = 0
	_prev_lx = 0
	_prev_ly = 0
	_prev_rx = 0
	_prev_ry = 0
	if main.is_streaming:
		main.stream_backend.send_multi_controller_event(0, 1, 0, 0, 0, 0, 0, 0, 0)

func _log(msg: String):
	if main and main.has_method("_log"):
		main._log(msg)

func _send_controller_mode():
	var head_pos = main.xr_camera.global_position
	var left_pos = main.left_hand.global_position if main.left_hand else Vector3.ZERO
	var right_pos = main.right_hand.global_position if main.right_hand else Vector3.ZERO

	var left_alt = false
	var right_alt = false
	if btn_toggle == BtnToggle.HEAD:
		_close_to_head = left_pos.distance_to(head_pos) < _close_dist or right_pos.distance_to(head_pos) < _close_dist
		left_alt = left_pos.distance_to(head_pos) < _close_dist
		right_alt = right_pos.distance_to(head_pos) < _close_dist
	elif btn_toggle == BtnToggle.TILT:
		if main.left_hand:
			var left_roll = atan2(-main.left_hand.global_basis.x.y, main.left_hand.global_basis.x.x)
			left_alt = left_roll > 0.5
		if main.right_hand:
			var right_roll = atan2(-main.right_hand.global_basis.x.y, main.right_hand.global_basis.x.x)
			right_alt = right_roll < -0.5
		_close_to_head = left_alt or right_alt

	var button_flags: int = 0

	var lv = main.left_hand.get_vector2("primary") if main.left_hand else Vector2.ZERO
	var rv = main.right_hand.get_vector2("primary") if main.right_hand else Vector2.ZERO

	var lt_val = main.left_hand.get_float("trigger") if main.left_hand else 0.0
	var rt_val = main.right_hand.get_float("trigger") if main.right_hand else 0.0
	var lg_val = main.left_hand.get_float("grip") if main.left_hand else 0.0
	var rg_val = main.right_hand.get_float("grip") if main.right_hand else 0.0

	var left_a = main.left_hand.is_button_pressed("ax_button") if main.left_hand else false
	var left_b = main.left_hand.is_button_pressed("by_button") if main.left_hand else false
	var right_a = main.right_hand.is_button_pressed("ax_button") if main.right_hand else false
	var right_b = main.right_hand.is_button_pressed("by_button") if main.right_hand else false
	var left_menu = main.left_hand.is_button_pressed("menu_button") if main.left_hand else false
	var right_menu = main.right_hand.is_button_pressed("menu_button") if main.right_hand else false
	var l_click = main.left_hand.is_button_pressed("primary_click") if main.left_hand else false
	var r_click = main.right_hand.is_button_pressed("primary_click") if main.right_hand else false

	if left_alt:
		if left_a: button_flags |= 0x0002
		if left_b: button_flags |= 0x0001
	else:
		if left_a: button_flags |= 0x0004
		if left_b: button_flags |= 0x0008

	if right_alt:
		if right_a: button_flags |= 0x4000
		if right_b: button_flags |= 0x8000
	else:
		if right_a: button_flags |= 0x1000
		if right_b: button_flags |= 0x2000

	if lg_val > 0.5: button_flags |= 0x0100
	if rg_val > 0.5: button_flags |= 0x0200
	if left_menu: button_flags |= 0x0020
	if right_menu: button_flags |= 0x0010
	if l_click: button_flags |= 0x0040
	if r_click: button_flags |= 0x0080

	var lt = int(clampf(lt_val, 0.0, 1.0) * 255.0)
	var rt = int(clampf(rt_val, 0.0, 1.0) * 255.0)
	if main.xr_interaction and main.xr_interaction.pointer_on_ui:
		rt = 0
	var lx = int(clampf(lv.x, -1.0, 1.0) * 32767.0)
	var ly = int(clampf(lv.y, -1.0, 1.0) * 32767.0)
	var rx = int(clampf(rv.x, -1.0, 1.0) * 32767.0)
	var ry = int(clampf(rv.y, -1.0, 1.0) * 32767.0)

	var changed = button_flags != _prev_button_flags or lt != _prev_lt or rt != _prev_rt \
		or lx != _prev_lx or ly != _prev_ly or rx != _prev_rx or ry != _prev_ry
	if changed or _poll_timer >= 0.1:
		main.stream_backend.send_multi_controller_event(0, 1, button_flags, lt, rt, lx, ly, rx, ry)
		_prev_button_flags = button_flags
		_prev_lt = lt
		_prev_rt = rt
		_prev_lx = lx
		_prev_ly = ly
		_prev_rx = rx
		_prev_ry = ry
		_poll_timer = 0.0

func _send_keyboard_mode():
	var lv = main.left_hand.get_vector2("primary") if main.left_hand else Vector2.ZERO
	var rv = main.right_hand.get_vector2("primary") if main.right_hand else Vector2.ZERO
	var stick_threshold = 0.5

	_handle_thumbstick_key(lv.y < -stick_threshold, "left_up", _kbd_profile.get("left_up", KEY_W))
	_handle_thumbstick_key(lv.y > stick_threshold, "left_down", _kbd_profile.get("left_down", KEY_S))
	_handle_thumbstick_key(lv.x < -stick_threshold, "left_left", _kbd_profile.get("left_left", KEY_A))
	_handle_thumbstick_key(lv.x > stick_threshold, "left_right", _kbd_profile.get("left_right", KEY_D))
	_handle_thumbstick_key(rv.y < -stick_threshold, "right_up", _kbd_profile.get("right_up", KEY_UP))
	_handle_thumbstick_key(rv.y > stick_threshold, "right_down", _kbd_profile.get("right_down", KEY_DOWN))
	_handle_thumbstick_key(rv.x < -stick_threshold, "right_left", _kbd_profile.get("right_left", KEY_LEFT))
	_handle_thumbstick_key(rv.x > stick_threshold, "right_right", _kbd_profile.get("right_right", KEY_RIGHT))

	var trigger_threshold = 0.5
	var lt = main.left_hand.get_float("trigger") if main.left_hand else 0.0
	var rt = main.right_hand.get_float("trigger") if main.right_hand else 0.0
	_handle_analog_key(lt > trigger_threshold, "left_trigger", _kbd_profile.get("left_trigger", KEY_SHIFT))
	_handle_analog_key(rt > trigger_threshold, "right_trigger", _kbd_profile.get("right_trigger", KEY_SPACE))

	var grip_threshold = 0.5
	var lg = main.left_hand.get_float("grip") if main.left_hand else 0.0
	var rg = main.right_hand.get_float("grip") if main.right_hand else 0.0
	_handle_analog_key(lg > grip_threshold, "left_grip", _kbd_profile.get("left_grip", KEY_CTRL))
	_handle_analog_key(rg > grip_threshold, "right_grip", _kbd_profile.get("right_grip", KEY_TAB))

	_handle_button_key(main.right_hand.is_button_pressed("ax_button") if main.right_hand else false, "right_a", _kbd_profile.get("right_a", KEY_1))
	_handle_button_key(main.right_hand.is_button_pressed("by_button") if main.right_hand else false, "right_b", _kbd_profile.get("right_b", KEY_2))
	_handle_button_key(main.left_hand.is_button_pressed("ax_button") if main.left_hand else false, "left_x", _kbd_profile.get("left_x", KEY_3))
	_handle_button_key(main.left_hand.is_button_pressed("by_button") if main.left_hand else false, "left_y", _kbd_profile.get("left_y", KEY_4))
	_handle_button_key(main.left_hand.is_button_pressed("menu_button") if main.left_hand else false, "left_menu", _kbd_profile.get("left_menu", KEY_ESCAPE))
	_handle_button_key(main.right_hand.is_button_pressed("menu_button") if main.right_hand else false, "right_menu", _kbd_profile.get("right_menu", KEY_ENTER))

func _send_kbm_mode():
	var lv = main.left_hand.get_vector2("primary") if main.left_hand else Vector2.ZERO
	var stick_threshold = 0.5
	var profile = _kbm_profile

	_handle_thumbstick_key(lv.y < -stick_threshold, "left_up", profile.get("left_up", KEY_W))
	_handle_thumbstick_key(lv.y > stick_threshold, "left_down", profile.get("left_down", KEY_S))
	_handle_thumbstick_key(lv.x < -stick_threshold, "left_left", profile.get("left_left", KEY_A))
	_handle_thumbstick_key(lv.x > stick_threshold, "left_right", profile.get("left_right", KEY_D))

	var trigger_threshold = 0.5
	var lt = main.left_hand.get_float("trigger") if main.left_hand else 0.0
	_handle_analog_key(lt > trigger_threshold, "left_trigger", profile.get("left_trigger", KEY_SHIFT))

	var grip_threshold = 0.5
	var lg = main.left_hand.get_float("grip") if main.left_hand else 0.0
	_handle_analog_key(lg > grip_threshold, "left_grip", profile.get("left_grip", KEY_CTRL))

	_handle_button_key(main.right_hand.is_button_pressed("ax_button") if main.right_hand else false, "right_a", profile.get("right_a", KEY_SPACE))
	_handle_button_key(main.right_hand.is_button_pressed("by_button") if main.right_hand else false, "right_b", profile.get("right_b", KEY_R))
	_handle_button_key(main.left_hand.is_button_pressed("ax_button") if main.left_hand else false, "left_x", profile.get("left_x", KEY_E))
	_handle_button_key(main.left_hand.is_button_pressed("by_button") if main.left_hand else false, "left_y", profile.get("left_y", KEY_F))
	_handle_button_key(main.left_hand.is_button_pressed("menu_button") if main.left_hand else false, "left_menu", profile.get("left_menu", KEY_ESCAPE))
	_handle_button_key(main.right_hand.is_button_pressed("menu_button") if main.right_hand else false, "right_menu", profile.get("right_menu", KEY_TAB))

func _handle_thumbstick_key(active: bool, dir_id: String, keycode: int):
	if active and not _active_key_dirs.get(dir_id, false):
		main.stream_backend.send_keyboard_event(keycode, 3, 0)
		_active_key_dirs[dir_id] = true
		_kb_held[keycode] = true
	elif not active and _active_key_dirs.get(dir_id, false):
		main.stream_backend.send_keyboard_event(keycode, 4, 0)
		_active_key_dirs[dir_id] = false
		_kb_held.erase(keycode)

func _handle_analog_key(active: bool, id: String, keycode: int):
	if active and not _kb_held.has(keycode):
		main.stream_backend.send_keyboard_event(keycode, 3, 0)
		_kb_held[keycode] = true
	elif not active and _kb_held.has(keycode):
		main.stream_backend.send_keyboard_event(keycode, 4, 0)
		_kb_held.erase(keycode)

func _handle_button_key(pressed: bool, id: String, keycode: int):
	var held = _kb_held.has(keycode)
	if pressed and not held:
		main.stream_backend.send_keyboard_event(keycode, 3, 0)
		_kb_held[keycode] = true
	elif not pressed and held:
		main.stream_backend.send_keyboard_event(keycode, 4, 0)
		_kb_held.erase(keycode)

func is_active() -> bool:
	return active

func get_mode_label() -> String:
	if not active:
		return "Off"
	return type_labels[ctrl_type]

func get_close_to_head() -> bool:
	return _close_to_head

func cycle_btn_toggle():
	btn_toggle = (btn_toggle + 1) % 3
	main.state_manager.save_state()
	if main.ui_controller:
		main.ui_controller.update_btn_toggle_btn()
	_log("[CTRL] Button toggle: " + btn_toggle_labels[btn_toggle])

func cycle_primary_hand():
	primary_hand = (primary_hand + 1) % 3
	main.state_manager.save_state()
	if main.ui_controller:
		main.ui_controller.update_primary_btn()
	_log("[CTRL] Primary hand: " + primary_labels[primary_hand])
