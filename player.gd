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
var model_animation: AnimationPlayer
var model_instance: Node3D
var using_procedural := false


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


func _find_model_animation(node: Node) -> AnimationPlayer:
        if node is AnimationPlayer:
                return node as AnimationPlayer
        for child in node.get_children():
                var found := _find_model_animation(child)
                if found != null:
                        return found
        return null


func _play_model_animation(wanted: String, speed: float = 1.0) -> void:
        if model_animation == null:
                return

        var chosen := ""
        for candidate in model_animation.get_animation_list():
                var lower := candidate.to_lower()
                if lower == wanted.to_lower() or lower.ends_with("/" + wanted.to_lower()):
                        chosen = candidate
                        break

        if chosen == "":
                return

        model_animation.speed_scale = speed
        if String(model_animation.current_animation) != chosen:
                model_animation.play(chosen, 0.18)


func _build_body() -> void:
        visual = Node3D.new()
        add_child(visual)

        var packed := load("res://assets/models/Student.glb") as PackedScene
        if packed != null:
                model_instance = packed.instantiate() as Node3D
                if model_instance != null:
                        visual.add_child(model_instance)
                        model_animation = _find_model_animation(model_instance)
                        if model_animation != null:
                                _play_model_animation("Idle")
                                return
                        model_instance.queue_free()
                        model_instance = null

        # Safe original procedural fallback.
        using_procedural = true
        visual.rotation.y = deg_to_rad(90.0)
        push_warning("Student.glb unavailable or has no AnimationPlayer; using procedural player")

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
        if using_procedural:
                visual.rotation.y = deg_to_rad(90.0 * facing)
                phase += delta * (9.0 if dir != 0.0 else 2.0)
                if arm_l != null and arm_r != null and leg_l != null and leg_r != null:
                        var swing := sin(phase) * 0.65 if dir != 0.0 else 0.0
                        arm_l.rotation.x = swing
                        arm_r.rotation.x = -swing
                        leg_l.rotation.x = -swing
                        leg_r.rotation.x = swing
                return

        var target_yaw := deg_to_rad(-90.0 * facing)
        visual.rotation.y = lerp_angle(
                visual.rotation.y, target_yaw,
                clampf(delta * 12.0, 0.0, 1.0)
        )

        var target_scale_y := 0.76 if crouching else 1.0
        visual.scale.y = lerpf(
                visual.scale.y, target_scale_y,
                clampf(delta * 10.0, 0.0, 1.0)
        )

        if not is_on_floor():
                _play_model_animation("Special")
        elif grabbed != null:
                _play_model_animation("Walk", 0.55 if dir != 0.0 else 1.0)
        elif dir != 0.0:
                if crouching:
                        _play_model_animation("Walk", 0.55)
                else:
                        _play_model_animation("Run")
        else:
                _play_model_animation("Idle")

func respawn(pos: Vector3) -> void:
	position = pos
	velocity = Vector3.ZERO
	grabbed = null
	if crouching:
		_set_crouch(false)
