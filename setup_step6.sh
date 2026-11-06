#!/data/data/com.termux/files/usr/bin/bash
# Long Night - Step 6: dogs (patrol / chase / stealth), death + checkpoints, exit
set -e
cd ~/long-night

# 1) Player: respawn function (added once)
if ! grep -q "func respawn" player.gd; then
	cat >> player.gd << 'EOF'


func respawn(pos: Vector3) -> void:
	position = pos
	velocity = Vector3.ZERO
	grabbed = null
	if crouching:
		_set_crouch(false)
EOF
fi

# 2) Dog
cat > dog.gd << 'EOF'
extends CharacterBody3D

signal caught

const PATROL_SPEED := 1.4
const CHASE_SPEED := 5.0
const GRAVITY := 18.0

var target
var left_x := 0.0
var right_x := 0.0
var start_x := 0.0
var facing := 1.0
var chasing := false
var ignore_timer := 0.0
var wait_timer := 0.0
var above_timer := 0.0
var phase := 0.0
var visual: Node3D
var legs: Array = []


func _ready() -> void:
	# Dogs live on layer 2: they never block the player, but they bite on contact
	collision_layer = 2
	collision_mask = 1
	start_x = position.x
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 0.65, 0.35)
	col.shape = shape
	col.position.y = 0.325
	add_child(col)
	_build_body()


func _mat(color: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, glow)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _leg(x: float, z: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 0.4, z)
	visual.add_child(pivot)
	_box(pivot, Vector3(0.09, 0.4, 0.09), color, Vector3(0, -0.2, 0))
	return pivot


func _build_body() -> void:
	visual = Node3D.new()
	add_child(visual)
	var fur := Color(0.1, 0.1, 0.11)
	_box(visual, Vector3(0.85, 0.32, 0.3), fur, Vector3(0, 0.5, 0))
	_box(visual, Vector3(0.28, 0.26, 0.26), fur, Vector3(0.55, 0.62, 0))
	_box(visual, Vector3(0.2, 0.12, 0.16), fur, Vector3(0.74, 0.57, 0))
	_box(visual, Vector3(0.07, 0.14, 0.06), fur, Vector3(0.5, 0.82, 0.09))
	_box(visual, Vector3(0.07, 0.14, 0.06), fur, Vector3(0.5, 0.82, -0.09))
	var tail := _box(visual, Vector3(0.3, 0.07, 0.07), fur, Vector3(-0.55, 0.62, 0))
	tail.rotation.z = 0.5
	# Glowing eyes
	_box(visual, Vector3(0.05, 0.05, 0.05), Color(1.0, 0.1, 0.05), Vector3(0.69, 0.68, 0.09), true)
	_box(visual, Vector3(0.05, 0.05, 0.05), Color(1.0, 0.1, 0.05), Vector3(0.69, 0.68, -0.09), true)
	legs = [_leg(0.3, 0.1, fur), _leg(0.3, -0.1, fur), _leg(-0.3, 0.1, fur), _leg(-0.3, -0.1, fur)]


func reset_state() -> void:
	position = Vector3(start_x, 0.05, 0.0)
	velocity = Vector3.ZERO
	chasing = false
	ignore_timer = 1.0
	wait_timer = 0.0
	above_timer = 0.0


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var dx: float = target.global_position.x - global_position.x
	var dy: float = target.global_position.y - global_position.y
	var crouched: bool = target.crouching
	ignore_timer = maxf(0.0, ignore_timer - delta)

	# Senses: sight in front, hearing all around. Crouching halves both.
	var sight := 4.0 if crouched else 8.0
	var hear := 1.0 if crouched else 2.2
	var sees := absf(dy) < 2.0 and ((signf(dx) == facing and absf(dx) < sight) or absf(dx) < hear)
	if ignore_timer <= 0.0 and sees:
		chasing = true
	if chasing and absf(dx) > 14.0:
		chasing = false

	var move := 0.0
	var speed := PATROL_SPEED
	if chasing:
		if absf(dx) > 0.05:
			facing = signf(dx)
		if dy > 0.9 and absf(dx) < 1.3:
			# Player is out of reach above: wait under him, then give up
			above_timer += delta
			if above_timer > 4.0:
				chasing = false
				ignore_timer = 4.0
				above_timer = 0.0
		else:
			above_timer = 0.0
			speed = CHASE_SPEED
			if absf(dx) > 0.05:
				move = facing
	else:
		above_timer = 0.0
		if wait_timer > 0.0:
			wait_timer -= delta
		else:
			move = facing
			if (facing > 0.0 and position.x >= right_x) or (facing < 0.0 and position.x <= left_x):
				facing = -facing
				wait_timer = 1.2
				move = 0.0

	velocity.x = move * speed
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	position.z = 0.0

	# Bite: close on the ground = dead. Jump over him or stand on something high.
	if absf(dx) < 0.8 and dy < 0.75 and dy > -1.0:
		caught.emit()

	_animate(delta)


func _animate(delta: float) -> void:
	var target_yaw := 0.0 if facing > 0.0 else PI
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(delta * 10.0, 0.0, 1.0))

	var a := 0.0
	var b := 0.0
	if absf(velocity.x) > 0.1:
		phase += delta * (16.0 if chasing else 8.0)
		var amp := 0.9 if chasing else 0.45
		var s := sin(phase)
		a = s * amp
		b = -s * amp
	var t := clampf(delta * 18.0, 0.0, 1.0)
	legs[0].rotation.z = lerpf(legs[0].rotation.z, a, t)
	legs[3].rotation.z = lerpf(legs[3].rotation.z, a, t)
	legs[1].rotation.z = lerpf(legs[1].rotation.z, b, t)
	legs[2].rotation.z = lerpf(legs[2].rotation.z, b, t)
EOF

# 3) Level: dogs, death screen, checkpoints, exit
cat > level.gd << 'EOF'
extends Node3D

const DOOR_CLOSED_Y := 1.5
const DOOR_OPEN_Y := 4.7

var player: CharacterBody3D
var cam: Camera3D

var plate: Area3D
var plate_mat: StandardMaterial3D
var plate_light: OmniLight3D
var door: AnimatableBody3D

var dogs: Array = []
var checkpoint := Vector3(0.0, 0.1, 0.0)
var checkpoint_xs: Array[float] = [28.5, 38.5]
var dead := false
var finished := false
var fade: ColorRect
var msg_label: Label


func _ready() -> void:
	_setup_environment()
	_build_level()
	_build_puzzle()

	player = CharacterBody3D.new()
	player.set_script(load("res://player.gd"))
	player.position = checkpoint
	add_child(player)

	cam = Camera3D.new()
	cam.position = Vector3(0, 2.5, 9)
	add_child(cam)
	cam.make_current()

	_add_dog(45.0, 43.0, 48.0)
	_add_dog(55.0, 52.5, 56.5)
	_build_exit()

	var hud = CanvasLayer.new()
	hud.set_script(load("res://hud.gd"))
	hud.player = player
	add_child(hud)

	_build_overlay()


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
	# Low vent after the door: crouch (DOWN) to crawl under it
	_add_box(Vector3(34, 1.5, 0), Vector3(6, 1.0, 4), Color(0.2, 0.2, 0.24))
	# Safe platforms in the dog zone (dogs cannot reach you up there)
	_add_box(Vector3(40.5, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(50.5, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))
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
	rb.add_to_group("crate")
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
	_add_crate(Vector3(16.0, 0.52, 0.0))

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

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(30.0, 2.5, 1.5)
	lamp.omni_range = 8.0
	lamp.light_energy = 1.2
	lamp.light_color = Color(1.0, 0.75, 0.4)
	add_child(lamp)


func _add_dog(x: float, left_x: float, right_x: float) -> void:
	var d = CharacterBody3D.new()
	d.set_script(load("res://dog.gd"))
	d.target = player
	d.left_x = left_x
	d.right_x = right_x
	d.position = Vector3(x, 0.05, 0.0)
	d.caught.connect(_on_caught)
	add_child(d)
	dogs.append(d)


func _build_exit() -> void:
	var a := Area3D.new()
	a.position = Vector3(58.8, 0.0, 0.0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 3.0, 3.0)
	col.shape = shape
	col.position.y = 1.5
	a.add_child(col)
	add_child(a)
	a.body_entered.connect(_on_exit)

	var light := OmniLight3D.new()
	light.position = Vector3(58.0, 2.2, 1.0)
	light.omni_range = 9.0
	light.light_energy = 2.0
	light.light_color = Color(0.95, 0.85, 0.6)
	add_child(light)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	fade = ColorRect.new()
	fade.color = Color(0.02, 0.0, 0.0, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.modulate.a = 0.0
	layer.add_child(fade)

	msg_label = Label.new()
	msg_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 90)
	msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_label.modulate.a = 0.0
	layer.add_child(msg_label)


func _on_caught() -> void:
	if dead or finished:
		return
	dead = true
	player.set_physics_process(false)
	msg_label.text = "YOU DIED"
	msg_label.add_theme_color_override("font_color", Color(0.7, 0.1, 0.1))
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(msg_label, "modulate:a", 1.0, 0.8)
	await tw.finished
	await get_tree().create_timer(0.8).timeout

	player.respawn(checkpoint)
	for d in dogs:
		d.reset_state()
	player.set_physics_process(true)
	dead = false

	var tw2 := create_tween()
	tw2.tween_property(fade, "modulate:a", 0.0, 0.6)
	tw2.parallel().tween_property(msg_label, "modulate:a", 0.0, 0.4)


func _on_exit(body: Node3D) -> void:
	if body != player or finished or dead:
		return
	finished = true
	player.set_physics_process(false)
	msg_label.text = "TO BE CONTINUED"
	msg_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 1.0)
	tw.parallel().tween_property(msg_label, "modulate:a", 1.0, 1.4)
	await tw.finished
	await get_tree().create_timer(2.5).timeout
	get_tree().change_scene_to_file("res://menu.tscn")


func _physics_process(delta: float) -> void:
	if plate != null and door != null:
		var pressed := false
		for b in plate.get_overlapping_bodies():
			if b is CharacterBody3D or b is RigidBody3D:
				if b is CharacterBody3D and b != player:
					continue
				pressed = true
				break
		var c := Color(0.1, 0.8, 0.3) if pressed else Color(0.7, 0.1, 0.1)
		plate_mat.albedo_color = c
		plate_mat.emission = c
		plate_light.light_color = c
		var target := DOOR_OPEN_Y if pressed else DOOR_CLOSED_Y
		door.position.y = move_toward(door.position.y, target, 4.0 * delta)

	if player != null and not dead and not finished:
		for cx in checkpoint_xs:
			if player.position.x >= cx and cx > checkpoint.x:
				checkpoint = Vector3(cx, 0.1, 0.0)
		if player.position.y < -8.0:
			_on_caught()


func _process(delta: float) -> void:
	if player == null or cam == null:
		return
	var target := Vector3(player.position.x, player.position.y + 2.5, 9.0)
	cam.position = cam.position.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
EOF

git add dog.gd player.gd level.gd
git commit -m "Step 6: dogs, death, checkpoints, exit"
git push
echo "OK: pushed, build is starting"
