extends CharacterBody3D

const SPEED := 4.0
const JUMP := 7.0
const GRAVITY := 18.0

var touch_left := false
var touch_right := false
var touch_jump := false


func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.4
	col.shape = shape
	col.position.y = 0.7
	add_child(col)

	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.4
	mesh.mesh = cap
	mesh.position.y = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.15, 0.1)
	mesh.material_override = mat
	add_child(mesh)


func _physics_process(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or touch_left:
		dir -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D) or touch_right:
		dir += 1.0

	var want_jump := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or touch_jump

	velocity.x = dir * SPEED
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif want_jump:
		velocity.y = JUMP

	move_and_slide()
	position.z = 0.0
