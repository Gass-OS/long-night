extends Node3D

const DOOR_CLOSED_Y := 1.5
const DOOR_OPEN_Y := 4.7

var player: CharacterBody3D
var cam: Camera3D
var touches := {}

var plate: Area3D
var plate_mat: StandardMaterial3D
var plate_light: OmniLight3D
var door: AnimatableBody3D


func _ready() -> void:
	_setup_environment()
	_build_level()
	_build_puzzle()

	player = CharacterBody3D.new()
	player.set_script(load("res://player.gd"))
	player.position = Vector3(0, 0.1, 0)
	add_child(player)

	cam = Camera3D.new()
	cam.position = Vector3(0, 2.5, 9)
	add_child(cam)
	cam.make_current()

	_build_touch_hints()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.5)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.1, 0.14)
	env.fog_density = 0.03
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)


func _add_box(pos: Vector3, size: Vector3, color: Color, solid := true) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	if solid:
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		col.shape = bs
		body.add_child(col)
	add_child(body)


func _build_level() -> void:
	# Ground (top surface at y = 0)
	_add_box(Vector3(20, -0.5, 0), Vector3(80, 1, 4), Color(0.3, 0.26, 0.22))
	# Jump practice
	_add_box(Vector3(6, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(9, 1.2, 0), Vector3(2, 0.4, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(12.5, 0.4, 0), Vector3(1.5, 0.8, 1.5), Color(0.45, 0.3, 0.2))
	# Background buildings (no collision) for depth
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(14):
		var h := rng.randf_range(4.0, 9.0)
		var w := rng.randf_range(3.0, 5.0)
		_add_box(Vector3(i * 5.0 - 5.0, h / 2.0, -5.0 - rng.randf_range(0.0, 3.0)),
			Vector3(w, h, 2.0), Color(0.16, 0.15, 0.17), false)
	# Back wall
	_add_box(Vector3(20, 5, -12), Vector3(80, 12, 1), Color(0.1, 0.1, 0.13), false)


func _add_crate(pos: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.position = pos
	rb.mass = 4.0
	rb.linear_damp = 5.0
	rb.gravity_scale = 2.0
	rb.axis_lock_linear_z = true
	rb.axis_lock_angular_x = true
	rb.axis_lock_angular_y = true
	rb.axis_lock_angular_z = true
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.2)
	mesh.material_override = mat
	rb.add_child(mesh)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1, 1, 1)
	col.shape = bs
	rb.add_child(col)
	add_child(rb)


func _build_puzzle() -> void:
	# Pushable crate
	_add_crate(Vector3(16.0, 0.52, 0.0))

	# Pressure plate (detects player and crates)
	plate = Area3D.new()
	plate.position = Vector3(22.0, 0.0, 0.0)
	var pcol := CollisionShape3D.new()
	var pshape := BoxShape3D.new()
	pshape.size = Vector3(1.6, 0.4, 1.4)
	pcol.shape = pshape
	pcol.position.y = 0.2
	plate.add_child(pcol)
	var pm := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(1.6, 0.1, 2.0)
	pm.mesh = pbox
	plate_mat = StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.7, 0.1, 0.1)
	plate_mat.emission_enabled = true
	plate_mat.emission = Color(0.7, 0.1, 0.1)
	plate_mat.emission_energy_multiplier = 0.6
	pm.material_override = plate_mat
	pm.position.y = 0.05
	plate.add_child(pm)
	add_child(plate)

	plate_light = OmniLight3D.new()
	plate_light.position = Vector3(22.0, 1.6, 1.5)
	plate_light.omni_range = 5.0
	plate_light.light_energy = 0.8
	plate_light.light_color = Color(0.9, 0.15, 0.1)
	add_child(plate_light)

	# Door
	door = AnimatableBody3D.new()
	door.position = Vector3(26.0, DOOR_CLOSED_Y, 0.0)
	var dmesh := MeshInstance3D.new()
	var dbox := BoxMesh.new()
	dbox.size = Vector3(0.5, 3.0, 4.0)
	dmesh.mesh = dbox
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.25, 0.25, 0.3)
	dmesh.material_override = dmat
	door.add_child(dmesh)
	var dcol := CollisionShape3D.new()
	var dshape := BoxShape3D.new()
	dshape.size = Vector3(0.5, 3.0, 4.0)
	dcol.shape = dshape
	door.add_child(dcol)
	add_child(door)

	# Warm light beyond the door
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(32.0, 2.5, 1.5)
	lamp.omni_range = 8.0
	lamp.light_energy = 1.2
	lamp.light_color = Color(1.0, 0.75, 0.4)
	add_child(lamp)


func _physics_process(delta: float) -> void:
	if plate == null or door == null:
		return
	var pressed := false
	for b in plate.get_overlapping_bodies():
		if b is CharacterBody3D or b is RigidBody3D:
			pressed = true
			break
	var c := Color(0.1, 0.8, 0.3) if pressed else Color(0.7, 0.1, 0.1)
	plate_mat.albedo_color = c
	plate_mat.emission = c
	plate_light.light_color = c
	var target := DOOR_OPEN_Y if pressed else DOOR_CLOSED_Y
	door.position.y = move_toward(door.position.y, target, 4.0 * delta)


func _process(delta: float) -> void:
	if player == null or cam == null:
		return
	var target := Vector3(player.position.x, player.position.y + 2.5, 9.0)
	cam.position = cam.position.lerp(target, clampf(delta * 4.0, 0.0, 1.0))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)
		_update_touch()
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		_update_touch()


func _update_touch() -> void:
	var w := get_viewport().get_visible_rect().size.x
	player.touch_left = false
	player.touch_right = false
	player.touch_jump = false
	for p in touches.values():
		if p.x < w * 0.2:
			player.touch_left = true
		elif p.x < w * 0.4:
			player.touch_right = true
		elif p.x > w * 0.7:
			player.touch_jump = true


func _build_touch_hints() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	_hint(ui, "<", 0.0, 0.2)
	_hint(ui, ">", 0.2, 0.4)
	_hint(ui, "JUMP", 0.7, 1.0)


func _hint(ui: CanvasLayer, text: String, a_left: float, a_right: float) -> void:
	var l := Label.new()
	l.text = text
	l.anchor_left = a_left
	l.anchor_right = a_right
	l.anchor_top = 0.6
	l.anchor_bottom = 1.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 56)
	l.modulate = Color(1, 1, 1, 0.3)
	ui.add_child(l)
