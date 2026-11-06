#!/data/data/com.termux/files/usr/bin/bash
# Long Night - Step 5: main menu + pause menu + controller (move, jump, push/pull, crouch)
set -e
cd ~/long-night

# 1) The game now starts on the menu
sed -i 's#^run/main_scene=.*#run/main_scene="res://menu.tscn"#' project.godot

# 2) Menu scene
cat > menu.tscn << 'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://menu.gd" id="1"]

[node name="Menu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
EOF

cat > menu.gd << 'EOF'
extends Control


func _ready() -> void:
	get_tree().set_quit_on_go_back(true)
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	center.add_child(box)

	var title := Label.new()
	title.text = "LONG NIGHT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 110)
	title.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	box.add_child(title)

	var sub := Label.new()
	sub.text = "KASSERINE"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 34)
	sub.add_theme_color_override("font_color", Color(0.55, 0.15, 0.12))
	box.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)

	_button(box, "PLAY", _on_play)
	_button(box, "QUIT", _on_quit)

	# Slow flicker on the title
	var tw := create_tween().set_loops()
	tw.tween_property(title, "modulate:a", 0.6, 1.6)
	tw.tween_property(title, "modulate:a", 1.0, 1.1)


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 90)
	b.add_theme_font_size_override("font_size", 38)
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_play() -> void:
	get_tree().change_scene_to_file("res://main.tscn")


func _on_quit() -> void:
	get_tree().quit()
EOF

# 3) HUD: touch controller + pause menu
cat > hud.gd << 'EOF'
extends CanvasLayer

var player
var touches := {}
var pause_panel: Control

# [label, from, to] zones as fractions of the screen width
var zones := [
	["<", 0.0, 0.15],
	[">", 0.15, 0.30],
	["DOWN", 0.56, 0.70],
	["PUSH", 0.70, 0.85],
	["JUMP", 0.85, 1.0],
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	get_tree().set_quit_on_go_back(false)
	for z in zones:
		_hint(z[0], z[1], z[2])
	_build_pause_button()
	_build_pause_panel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if get_tree().paused:
			_resume()
		else:
			_pause()


func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
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
	if player == null:
		return
	var size := get_viewport().get_visible_rect().size
	var l := false
	var r := false
	var d := false
	var pu := false
	var j := false
	for p in touches.values():
		if p.y < size.y * 0.16:
			continue  # top strip is for the pause button
		var fx: float = p.x / size.x
		if fx < 0.15:
			l = true
		elif fx < 0.30:
			r = true
		elif fx >= 0.85:
			j = true
		elif fx >= 0.70:
			pu = true
		elif fx >= 0.56:
			d = true
	player.touch_left = l
	player.touch_right = r
	player.touch_down = d
	player.touch_push = pu
	player.touch_jump = j


func _hint(text: String, a_left: float, a_right: float) -> void:
	var lb := Label.new()
	lb.text = text
	lb.anchor_left = a_left
	lb.anchor_right = a_right
	lb.anchor_top = 0.6
	lb.anchor_bottom = 1.0
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 40)
	lb.modulate = Color(1, 1, 1, 0.3)
	add_child(lb)


func _build_pause_button() -> void:
	var b := Button.new()
	b.text = "II"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 40)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	b.offset_left = -120.0
	b.offset_top = 20.0
	b.offset_right = -20.0
	b.offset_bottom = 100.0
	b.pressed.connect(_pause)
	add_child(b)


func _build_pause_panel() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	add_child(pause_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)

	_menu_button(box, "RESUME", _resume)
	_menu_button(box, "RESTART", _restart)
	_menu_button(box, "MAIN MENU", _to_menu)


func _menu_button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 90)
	b.add_theme_font_size_override("font_size", 38)
	b.pressed.connect(cb)
	parent.add_child(b)


func _pause() -> void:
	get_tree().paused = true
	pause_panel.visible = true
	touches.clear()
	_update_touch()


func _resume() -> void:
	get_tree().paused = false
	pause_panel.visible = false


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu.tscn")
EOF

# 4) Player: move, jump, crouch (DOWN), grab/push/pull crates (PUSH)
cat > player.gd << 'EOF'
extends CharacterBody3D

const SPEED := 4.0
const CROUCH_SPEED := 1.6
const GRAB_SPEED := 1.8
const JUMP := 7.0
const GRAVITY := 18.0
const STAND_H := 1.5
const CROUCH_H := 0.9
const GRAB_REACH := 1.05

const SKIN := Color(0.86, 0.7, 0.6)
const SHIRT := Color(0.75, 0.12, 0.1)
const PANTS := Color(0.12, 0.12, 0.16)

var touch_left := false
var touch_right := false
var touch_jump := false
var touch_down := false
var touch_push := false

var visual: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var col: CollisionShape3D
var shape: CapsuleShape3D
var phase := 0.0
var crouching := false
var facing := 1.0
var grabbed: RigidBody3D = null


func _ready() -> void:
	col = CollisionShape3D.new()
	shape = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = STAND_H
	col.shape = shape
	col.position.y = STAND_H / 2.0
	add_child(col)
	_build_body()


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _limb(pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	visual.add_child(pivot)
	_box(pivot, size, color, Vector3(0, -size.y / 2.0, 0))
	return pivot


func _build_body() -> void:
	visual = Node3D.new()
	visual.rotation.y = deg_to_rad(90.0)
	add_child(visual)

	_box(visual, Vector3(0.4, 0.5, 0.22), SHIRT, Vector3(0, 0.9, 0))

	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	head.mesh = sm
	head.material_override = _mat(SKIN)
	head.position = Vector3(0, 1.32, 0)
	visual.add_child(head)

	arm_l = _limb(Vector3(-0.27, 1.12, 0), Vector3(0.12, 0.5, 0.12), SHIRT)
	arm_r = _limb(Vector3(0.27, 1.12, 0), Vector3(0.12, 0.5, 0.12), SHIRT)
	_box(arm_l, Vector3(0.13, 0.13, 0.13), SKIN, Vector3(0, -0.52, 0))
	_box(arm_r, Vector3(0.13, 0.13, 0.13), SKIN, Vector3(0, -0.52, 0))

	leg_l = _limb(Vector3(-0.1, 0.65, 0), Vector3(0.17, 0.65, 0.17), PANTS)
	leg_r = _limb(Vector3(0.1, 0.65, 0), Vector3(0.17, 0.65, 0.17), PANTS)


func _set_crouch(v: bool) -> void:
	crouching = v
	shape.height = CROUCH_H if v else STAND_H
	col.position.y = shape.height / 2.0


func _find_crate() -> RigidBody3D:
	for n in get_tree().get_nodes_in_group("crate"):
		var c := n as RigidBody3D
		if c == null:
			continue
		var dx := c.global_position.x - global_position.x
		var dy := c.global_position.y - global_position.y
		if absf(dx) < GRAB_REACH and absf(dy - 0.5) < 0.6 and signf(dx) == facing:
			return c
	return null


func _physics_process(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or touch_left:
		dir -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D) or touch_right:
		dir += 1.0
	var down_held := Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) or touch_down
	var push_held := Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SHIFT) or touch_push
	var want_jump := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or touch_jump

	# Crouch (stay crouched if something is above)
	if down_held and is_on_floor():
		_set_crouch(true)
	elif crouching and not down_held:
		if not test_move(global_transform, Vector3(0.0, STAND_H - CROUCH_H + 0.05, 0.0)):
			_set_crouch(false)

	# Grab a crate: hold PUSH while facing it
	if push_held and is_on_floor() and not crouching:
		if grabbed == null:
			grabbed = _find_crate()
		elif absf(grabbed.global_position.x - global_position.x) > 1.6:
			grabbed = null
	else:
		grabbed = null

	if dir != 0.0 and grabbed == null:
		facing = signf(dir)

	var spd := SPEED
	if crouching:
		spd = CROUCH_SPEED
	elif grabbed != null:
		spd = GRAB_SPEED

	velocity.x = dir * spd
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif want_jump and not crouching and grabbed == null:
		velocity.y = JUMP

	move_and_slide()
	position.z = 0.0

	if grabbed != null:
		grabbed.sleeping = false
		grabbed.linear_velocity.x = dir * spd

	_animate(delta, dir)


func _animate(delta: float, dir: float) -> void:
	var target_yaw := deg_to_rad(90.0 * facing)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(delta * 12.0, 0.0, 1.0))
	var sy := 0.62 if crouching else 1.0
	visual.scale.y = lerpf(visual.scale.y, sy, clampf(delta * 14.0, 0.0, 1.0))

	var ll := 0.0
	var lr := 0.0
	var al := 0.0
	var ar := 0.0
	if not is_on_floor():
		ll = -0.7
		lr = 0.5
		al = -2.4
		ar = -2.4
	elif grabbed != null:
		al = -1.5
		ar = -1.5
		if dir != 0.0:
			phase += delta * 6.0
			var sg := sin(phase)
			ll = sg * 0.5
			lr = -sg * 0.5
	elif dir != 0.0:
		var rate := 6.0 if crouching else 10.0
		var amp := 0.5 if crouching else 0.8
		phase += delta * rate
		var sw := sin(phase)
		ll = sw * amp
		lr = -sw * amp
		al = -sw * amp * 0.9
		ar = sw * amp * 0.9
	else:
		phase = 0.0

	var t := clampf(delta * 18.0, 0.0, 1.0)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, ll, t)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, lr, t)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, al, t)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, ar, t)
EOF

# 5) Level: uses the HUD, crate is in group "crate", adds a low vent to crawl under
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

	var hud = CanvasLayer.new()
	hud.set_script(load("res://hud.gd"))
	hud.player = player
	add_child(hud)


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
EOF

git add project.godot menu.tscn menu.gd hud.gd player.gd level.gd
git commit -m "Step 5: menu, pause, controller (push/pull, crouch)"
git push
echo "OK: pushed, build is starting"
