extends Node3D

var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var audio

var rain: GPUParticles3D
var timer := 7.0
var flash := 0.0
var base_sun := 0.7
var base_ambient := 0.55


func _ready() -> void:
	if sun != null:
		base_sun = sun.light_energy
	if env != null:
		base_ambient = env.ambient_light_energy
	_build_rain()


func _build_rain() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.008, 0.34, 0.008)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.72, 0.8, 0.95, 0.14)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8.0, 0.2, 1.2)
	pm.direction = Vector3(0.12, -1.0, 0.0)
	pm.spread = 1.5
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0.0, -10.0, 0.0)

	rain = GPUParticles3D.new()
	rain.amount = 320
	rain.lifetime = 0.7
	rain.preprocess = 0.2
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-20, -12, -10), Vector3(40, 24, 20))
	rain.process_material = pm
	rain.draw_pass_1 = mesh
	add_child(rain)


func _process(delta: float) -> void:
	if cam != null and rain != null:
		rain.global_position = Vector3(cam.global_position.x, cam.global_position.y + 4.0, 3.5)

	timer -= delta
	if timer <= 0.0:
		timer = randf_range(9.0, 24.0)
		_strike()

	flash = move_toward(flash, 0.0, delta * 3.0)
	if sun != null:
		sun.light_energy = base_sun + flash * 3.5
	if env != null:
		env.ambient_light_energy = base_ambient + flash * 1.2


func _strike() -> void:
	var tw := create_tween()
	tw.tween_property(self, "flash", 1.0, 0.04)
	tw.tween_property(self, "flash", 0.2, 0.08)
	tw.tween_property(self, "flash", 0.9, 0.04)
	await get_tree().create_timer(randf_range(0.4, 1.6)).timeout
	if audio != null:
		audio.thunder()
