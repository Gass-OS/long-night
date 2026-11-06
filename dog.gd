extends CharacterBody3D

signal caught
signal alerted

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
var model_animation: AnimationPlayer
var model_instance: Node3D
var using_procedural := false


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
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 5.0
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

        var packed := load("res://assets/models/Dog.glb") as PackedScene
        if packed != null:
                model_instance = packed.instantiate() as Node3D
                if model_instance != null:
                        visual.add_child(model_instance)
                        model_animation = _find_model_animation(model_instance)
                        if model_animation != null:
                                _play_model_animation("idle")
                                return
                        model_instance.queue_free()
                        model_instance = null

        # Safe original procedural fallback.
        using_procedural = true
        push_warning("Dog.glb unavailable or has no AnimationPlayer; using procedural dog")

        var fur := Color(0.1, 0.1, 0.11)
        _box(visual, Vector3(0.85, 0.32, 0.3), fur, Vector3(0, 0.5, 0))
        _box(visual, Vector3(0.28, 0.26, 0.26), fur, Vector3(0.55, 0.62, 0))
        _box(visual, Vector3(0.2, 0.12, 0.16), fur, Vector3(0.74, 0.57, 0))
        _box(visual, Vector3(0.07, 0.14, 0.06), fur, Vector3(0.5, 0.82, 0.09))
        _box(visual, Vector3(0.07, 0.14, 0.06), fur, Vector3(0.5, 0.82, -0.09))
        var tail := _box(visual, Vector3(0.3, 0.07, 0.07), fur, Vector3(-0.55, 0.62, 0))
        tail.rotation.z = 0.5
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
		if not chasing:
			alerted.emit()
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
        if using_procedural:
                visual.rotation.y = 0.0 if facing > 0.0 else PI
                phase += delta * (12.0 if chasing else 7.0)
                var swing := sin(phase) * 0.55 if absf(velocity.x) > 0.1 else 0.0
                for i in range(legs.size()):
                        legs[i].rotation.x = swing if i % 2 == 0 else -swing
                return

        var target_yaw := deg_to_rad(-90.0) if facing > 0.0 else deg_to_rad(90.0)
        visual.rotation.y = lerp_angle(
                visual.rotation.y, target_yaw,
                clampf(delta * 10.0, 0.0, 1.0)
        )

        var dx := 999.0
        var dy := 999.0
        if target != null:
                dx = absf(target.global_position.x - global_position.x)
                dy = absf(target.global_position.y - global_position.y)

        if dx < 1.15 and dy < 0.9:
                _play_model_animation("attack")
        elif absf(velocity.x) > 0.1:
                _play_model_animation("walk", 1.5 if chasing else 1.0)
        else:
                _play_model_animation("idle")
