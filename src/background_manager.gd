class_name BackgroundManager
extends RefCounted

var main

func _init(p_main):
	main = p_main

func create_backgrounds():
	_create_starfield()
	_create_ash()
	_create_snow()
	_create_data()
	var active_bg = main.background_mode - 1
	for i in range(main.bg_names.size()):
		var bg = main.get_node_or_null(main.bg_names[i])
		if bg:
			bg.visible = (i == active_bg)

func hide_all():
	for name in main.bg_names:
		var bg = main.get_node_or_null(name)
		if bg:
			bg.visible = false
			bg.emitting = false

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
	mat.direction = Vector3(0, 0, 0)
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
	particles.position = main.xr_camera.global_position
	main.add_child(particles)

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
	particles.position = main.xr_camera.global_position
	main.add_child(particles)

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
	particles.position = main.xr_camera.global_position + Vector3(0, 10, 0)
	main.add_child(particles)

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
	particles.position = main.xr_camera.global_position + Vector3(0, -3, 0)
	main.add_child(particles)
