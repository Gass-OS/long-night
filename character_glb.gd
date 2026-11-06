extends Node3D
# Real skinned character (Mixamo / any FBX or GLB). Same interface as the procedural rig.

signal footstep(strength: float)

const DIR := "res://assets/character/"
const BASE_NAMES := ["boy.fbx", "boy.glb", "boy.gltf"]
const ANIMS := ["idle", "walk", "run", "jump", "fall", "crouch_idle", "crouch_walk", "push", "die"]
const LOOPED := ["idle", "walk", "run", "fall", "crouch_idle", "crouch_walk", "push"]
const EXTS := [".fbx", ".glb", ".gltf"]
const FALLBACK := {
	"crouch_walk": ["crouch_idle", "walk"],
	"crouch_idle": ["idle"],
	"push": ["walk", "idle"],
	"run": ["walk", "idle"],
	"walk": ["run", "idle"],
	"jump": ["fall", "idle"],
	"fall": ["jump", "idle"],
	"idle": [],
	"die": [],
}

var model: Node3D
var ap: AnimationPlayer
var ok := false
var dying := false
var current := ""
var step_timer := 0.0


static func available() -> bool:
	for n in BASE_NAMES:
		if ResourceLoader.exists(DIR + n):
			return true
	return false


func _ready() -> void:
	var packed: PackedScene = null
	for n in BASE_NAMES:
		if ResourceLoader.exists(DIR + n):
			packed = load(DIR + n) as PackedScene
			break
	if packed == null:
		return
	model = packed.instantiate() as Node3D
	if model == null:
		return
	add_child(model)
	_fit_model()
	ap = _find_ap(model)
	if ap == null:
		ap = AnimationPlayer.new()
		model.add_child(ap)
	_load_animations()
	ok = true
	_play("idle")


func _meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_meshes(c, out)


func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null


func _fit_model() -> void:
	var list: Array = []
	_meshes(model, list)
	var result := AABB()
	var first := true
	var inv := model.global_transform.affine_inverse()
	for n in list:
		var b: AABB = (inv * n.global_transform) * n.get_aabb()
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	if not first and result.size.y > 0.01:
		var s := 1.5 / result.size.y
		model.scale = Vector3.ONE * s
		model.position.y = -result.position.y * s


func _load_animations() -> void:
	var lib: AnimationLibrary
	if ap.has_animation_library(""):
		lib = ap.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		ap.add_animation_library("", lib)
	for key in ANIMS:
		for e in EXTS:
			var path: String = DIR + key + e
			if not ResourceLoader.exists(path):
				continue
			var ps := load(path) as PackedScene
			if ps == null:
				continue
			var inst := ps.instantiate()
			var ap2 := _find_ap(inst)
			if ap2 != null:
				var picked := ""
				for nm in ap2.get_animation_list():
					if nm != "RESET":
						picked = nm
						break
				if picked != "":
					var anim: Animation = ap2.get_animation(picked).duplicate()
					anim.loop_mode = Animation.LOOP_LINEAR if key in LOOPED else Animation.LOOP_NONE
					if lib.has_animation(key):
						lib.remove_animation(key)
					lib.add_animation(key, anim)
			inst.queue_free()
			break


func _resolve(anim_name: String) -> String:
	if ap.has_animation(anim_name):
		return anim_name
	for alt in FALLBACK.get(anim_name, []):
		if ap.has_animation(alt):
			return alt
	return ""


func _play(anim_name: String) -> void:
	var n := _resolve(anim_name)
	if n == "" or n == current:
		return
	ap.play(n, 0.2)
	current = n


func animate(delta: float, vx: float, vy: float, on_floor: bool, crouching: bool, grabbing: bool, facing: float, input_dir: float) -> void:
	if not ok:
		return
	if dying:
		dying = false
		model.rotation = Vector3.ZERO
		visible = true
	rotation.y = lerp_angle(rotation.y, deg_to_rad(90.0 * facing), clampf(delta * 12.0, 0.0, 1.0))

	var speed := absf(vx)
	var moving := absf(input_dir) > 0.0 and speed > 0.2 and on_floor
	var want := "idle"
	if not on_floor:
		want = "jump" if vy > 0.5 else "fall"
	elif grabbing:
		want = "push"
	elif crouching:
		want = "crouch_walk" if moving else "crouch_idle"
	elif moving:
		want = "run" if speed > 3.0 else "walk"
	_play(want)
	ap.speed_scale = 0.0 if (want == "push" and not moving) else 1.0

	if moving and not crouching and not grabbing:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = 0.34
			footstep.emit(clampf(speed / 4.0, 0.0, 1.0))


func spawn_ragdoll(world_parent: Node, _vel: Vector3, _push: float) -> Node3D:
	var root := Node3D.new()
	world_parent.add_child(root)
	dying = true
	visible = true
	if ok:
		var n := _resolve("die")
		if n != "":
			ap.speed_scale = 1.0
			ap.play(n, 0.1)
			current = n
		else:
			var tw := create_tween()
			tw.tween_property(model, "rotation:x", -1.5, 0.45)
	return root
