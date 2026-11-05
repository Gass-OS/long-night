extends Node3D

var player: CharacterBody3D
var cam: Camera3D
var touches := {}


func _ready() -> void:
	_setup_environment()
	_build_level()

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
	# Platforms and obstacles
	_add_box(Vector3(6, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(9, 1.2, 0), Vector3(2, 0.4, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(14, 0.75, 0), Vector3(1.5, 1.5, 1.5), Color(0.45, 0.3, 0.2))
	_add_box(Vector3(20, 1.0, 0), Vector3(1, 2, 2), Color(0.35, 0.3, 0.3))
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


func _process(delta: float) -> void:
	if player == null or cam == null:
		return
	var target := Vector3(player.position.x, player.position.y + 2.5, 9.0)
	cam.position = cam.position.lerp(target, clamp(delta * 4.0, 0.0, 1.0))


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
