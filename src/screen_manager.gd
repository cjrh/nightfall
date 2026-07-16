class_name ScreenManager
extends RefCounted

var main: Node3D

func _init(owner: Node3D):
	main = owner

func _get_cylinder_radius() -> float:
	if main.comp.in_use:
		var cam_to_screen = main.screen_mesh.global_position - main.xr_camera.global_position
		var view_dist = cam_to_screen.length()
		if view_dist < 0.5:
			view_dist = 3.0
		if main.curvature == 1:
			return view_dist * 3.0
		elif main.curvature == 2:
			return view_dist * 2.0
		else:
			return view_dist * 100.0
	else:
		return 1000.0 if main.curvature == 0 else (10.0 if main.curvature == 1 else 4.0)

func create_corner_handles():
	var offsets = [
		Vector2(-0.5, 0.5),
		Vector2(0.5, 0.5),
		Vector2(-0.5, -0.5),
		Vector2(0.5, -0.5),
	]
	var corner_ids = ["top-left", "top-right", "bottom-left", "bottom-right"]
	var mesh_size = main._mesh_size
	var corner_size = mesh_size.x * 0.027
	var col_size = mesh_size.x * 0.067
	for i in range(4):
		var handle = MeshInstance3D.new()
		handle.name = "Corner%d" % i
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 1, 1, 0)
		mat.albedo_texture = _make_corner_texture(corner_ids[i])
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.render_priority = 127
		var corner_quad = QuadMesh.new()
		corner_quad.size = Vector2(corner_size, corner_size)
		corner_quad.orientation = PlaneMesh.FACE_Z
		handle.mesh = corner_quad
		handle.material_override = mat
		var area = Area3D.new()
		area.collision_layer = 2
		var shape = CollisionShape3D.new()
		var col = BoxShape3D.new()
		col.size = Vector3(col_size, col_size, 0.1)
		shape.shape = col
		shape.position = Vector3(offsets[i].x * col_size, offsets[i].y * col_size, 0)
		area.add_child(shape)
		handle.add_child(area)
		handle.position = Vector3(offsets[i].x * (mesh_size.x + corner_size), offsets[i].y * (mesh_size.y + corner_size), 0)
		main.screen_mesh.add_child(handle)
		main.corner_handles.append(handle)

func update_corner_positions():
	var mesh_size = main._mesh_size
	var radius = _get_cylinder_radius()
	var half_angle = mesh_size.x / radius * 0.5
	var edge_x = sin(half_angle) * radius
	var edge_z = -(cos(half_angle) * radius - radius)
	var offsets = [
		Vector2(-0.5, 0.5),
		Vector2(0.5, 0.5),
		Vector2(-0.5, -0.5),
		Vector2(0.5, -0.5),
	]
	var corner_size = mesh_size.x * 0.027
	var col_size = mesh_size.x * 0.067
	var grab_bar_off = mesh_size.y * 0.119
	for i in range(4):
		var handle = main.corner_handles[i]
		if handle.mesh is QuadMesh:
			handle.mesh.size = Vector2(corner_size, corner_size)
		for child in handle.get_children():
			if child is Area3D:
				for c in child.get_children():
					if c is CollisionShape3D and c.shape is BoxShape3D:
						c.shape.size = Vector3(col_size, col_size, 0.1)
						c.position = Vector3(offsets[i].x * col_size, offsets[i].y * col_size, 0)
		var cy = offsets[i].y * (mesh_size.y + corner_size)
		var a = half_angle if offsets[i].x > 0 else -half_angle
		var cx = edge_x if offsets[i].x > 0 else -edge_x
		if offsets[i].x > 0:
			cx += corner_size * 0.5
		else:
			cx -= corner_size * 0.5
		handle.position = Vector3(cx, cy, edge_z)
		handle.rotation.y = -a
	var grab_bar = main.get_node("%ScreenGrabBar")
	grab_bar.position.y = -mesh_size.y / 2.0 - grab_bar_off
	if grab_bar.mesh is CylinderMesh:
		var grab_r = mesh_size.x * 0.0045
		var grab_h = mesh_size.x * 0.134
		grab_bar.mesh.top_radius = grab_r
		grab_bar.mesh.bottom_radius = grab_r
		grab_bar.mesh.height = grab_h
	var grab_area = grab_bar.get_node_or_null("Area3D")
	if grab_area:
		var grab_shape = grab_area.get_node_or_null("CollisionShape3D")
		if grab_shape and grab_shape.shape is BoxShape3D:
			grab_shape.shape.size = Vector3(mesh_size.x * 0.134, mesh_size.y * 0.079, 0.1)

func create_bezel():
	main.bezel_mesh = MeshInstance3D.new()
	main.bezel_mesh.name = "Bezel"
	var bezel_quad = QuadMesh.new()
	main.bezel_mesh.mesh = bezel_quad
	var bezel_mat = StandardMaterial3D.new()
	bezel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bezel_mat.albedo_color = Color(0, 0, 0, 1)
	main.bezel_mesh.material_override = bezel_mat
	main.bezel_mesh.position = Vector3(0, 0, -0.005)
	main.screen_mesh.add_child(main.bezel_mesh)
	update_bezel_size()

func update_bezel_size():
	if not main.bezel_mesh:
		return
	var mesh_size = main._mesh_size
	var bezel_pad = 0.04
	var bezel_size = mesh_size + Vector2(bezel_pad, bezel_pad)
	if main.curvature == 0:
		var bezel_quad = QuadMesh.new()
		bezel_quad.size = bezel_size
		main.bezel_mesh.mesh = bezel_quad
		main.bezel_mesh.position = Vector3(0, 0, -0.005)
	else:
		var radius = _get_cylinder_radius()
		var subdivide = 32
		var v_subdivide = 16
		var angle = bezel_size.x / radius
		var verts = PackedVector3Array()
		var uvs = PackedVector2Array()
		var indices = PackedInt32Array()
		for j in range(subdivide + 1):
			for i in range(v_subdivide + 1):
				var t = float(j) / subdivide
				var u = float(i) / v_subdivide
				var a = -angle * 0.5 + angle * t
				var x = sin(a) * radius
				var z = -(cos(a) * radius - radius) - 0.005
				var y = (u - 0.5) * bezel_size.y
				verts.append(Vector3(x, y, z))
				uvs.append(Vector2(t, 1.0 - u))
		var cols = v_subdivide + 1
		for j in range(subdivide):
			for i in range(v_subdivide):
				var idx = j * cols + i
				indices.append(idx)
				indices.append(idx + 1)
				indices.append(idx + cols)
				indices.append(idx + 1)
				indices.append(idx + cols + 1)
				indices.append(idx + cols)
		var arr = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = indices
		var arr_mesh = ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		main.bezel_mesh.mesh = arr_mesh
		main.bezel_mesh.position = Vector3.ZERO

func toggle_bezel():
	main.bezel_enabled = not main.bezel_enabled
	if main.bezel_mesh:
		main.bezel_mesh.visible = main.bezel_enabled if not main.comp.in_use else false
	main.ui_controller.update_option_btn(main._ui_bezel_btn, "On" if main.bezel_enabled else "Off")
	main.comp.update_bezel()
	main.state_manager.save_state()

func resize_screen_to_aspect(stream_w: int, stream_h: int):
	var aspect = float(stream_w) / float(stream_h)
	var new_w = main._mesh_size.x
	var new_h = new_w / aspect
	if new_h < 0.4:
		new_h = 0.4
		new_w = new_h * aspect
	main._mesh_size = Vector2(new_w, new_h)
	if main.curvature == 0:
		main.screen_mesh.mesh.size = main._mesh_size
		set_screen_collision_flat(main._mesh_size)
	else:
		apply_curvature()
	update_corner_positions()
	if main.bezel_mesh:
		update_bezel_size()
	if main.comp_layer and main.comp_layer is OpenXRCompositionLayerQuad:
		main.comp_layer.set_quad_size(main._mesh_size)

func cycle_curvature():
	main.curvature = (main.curvature + 1) % 3
	apply_curvature()
	if main.comp.in_use:
		main.comp.switch_to_comp_layer()
	main.ui_controller.update_option_btn(main._ui_curve_btn, main.curvature_labels[main.curvature])
	main.state_manager.save_state()

func apply_curvature():
	var mesh_size = main._mesh_size
	if main.curvature == 0:
		var quad = QuadMesh.new()
		quad.size = mesh_size
		main.screen_mesh.mesh = quad
		update_shader_for_mesh(mesh_size)
		set_screen_collision_flat(mesh_size)
		return
	var subdivide = 32
	var v_subdivide = 16
	var radius = _get_cylinder_radius()
	var angle = mesh_size.x / radius
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	for j in range(subdivide + 1):
		for i in range(v_subdivide + 1):
			var t = float(j) / subdivide
			var u = float(i) / v_subdivide
			var a = -angle * 0.5 + angle * t
			var x = sin(a) * radius
			var z = -(cos(a) * radius - radius)
			var y = (u - 0.5) * mesh_size.y
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(t, 1.0 - u))
	var cols = v_subdivide + 1
	for j in range(subdivide):
		for i in range(v_subdivide):
			var idx = j * cols + i
			indices.append(idx)
			indices.append(idx + 1)
			indices.append(idx + cols)
			indices.append(idx + 1)
			indices.append(idx + cols + 1)
			indices.append(idx + cols)
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var arr_mesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	main.screen_mesh.mesh = arr_mesh
	update_shader_for_mesh(mesh_size)
	set_screen_collision_curved(verts, indices)

func update_shader_for_mesh(mesh_size: Vector2):
	set_screen_collision_flat(mesh_size)
	update_corner_positions()
	if main.bezel_mesh:
		update_bezel_size()

func set_screen_collision_flat(mesh_size: Vector2):
	var col_shape = main.screen_mesh.get_node_or_null("Area3D/CollisionShape3D")
	if not col_shape:
		return
	var box = BoxShape3D.new()
	box.size = Vector3(mesh_size.x, mesh_size.y, 0.01)
	col_shape.shape = box

func set_screen_collision_curved(verts: PackedVector3Array, indices: PackedInt32Array):
	var col_shape = main.screen_mesh.get_node_or_null("Area3D/CollisionShape3D")
	if not col_shape:
		return
	var faces = PackedVector3Array()
	for i in range(0, indices.size(), 3):
		faces.append(verts[indices[i]])
		faces.append(verts[indices[i + 1]])
		faces.append(verts[indices[i + 2]])
	var concave = ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	col_shape.shape = concave

func _make_corner_texture(corner: String, size: int = 128, thickness: int = 20, opacity: float = 0.08) -> ImageTexture:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var color = Color(1, 1, 1, opacity)
	var s = size
	var t = thickness
	var pad = 16
	match corner:
		"top-left":
			img.fill_rect(Rect2i(pad, pad, s - 2 * pad, t), color)
			img.fill_rect(Rect2i(pad, pad + t, t, s - 2 * pad - t), color)
		"top-right":
			img.fill_rect(Rect2i(pad, pad, s - 2 * pad, t), color)
			img.fill_rect(Rect2i(s - pad - t, pad + t, t, s - 2 * pad - t), color)
		"bottom-left":
			img.fill_rect(Rect2i(pad, s - pad - t, s - 2 * pad, t), color)
			img.fill_rect(Rect2i(pad, pad, t, s - 2 * pad - t), color)
		"bottom-right":
			img.fill_rect(Rect2i(pad, s - pad - t, s - 2 * pad, t), color)
			img.fill_rect(Rect2i(s - pad - t, pad, t, s - 2 * pad - t), color)
	return ImageTexture.create_from_image(img)
