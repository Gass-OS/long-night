extends Node
# Squad: puts two police officers in stage 1 (next to the police cars) and resets them on respawn.

var lv: Node = null
var age := 0
var officers: Array = []
var wired := false


func _process(_delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	var stage1 := cs.get("player") != null and cs.get("env") != null and cs.get("cam") != null and cs.get("weather") != null and cs.get("dogs") != null and cs.get("stage") == null
	if not stage1:
		lv = null
		return
	if lv != cs:
		lv = cs
		age = 0
		officers.clear()
		wired = false
	age += 1
	if age == 6:
		_spawn(60.0, 57.5, 62.5)
		_spawn(105.0, 102.0, 107.0)
	if age > 6 and not wired:
		var player = lv.get("player")
		if player != null and player.has_signal("respawned"):
			player.respawned.connect(_reset)
			wired = true


func _spawn(x: float, left_x: float, right_x: float) -> void:
	var p := CharacterBody3D.new()
	p.set_script(load("res://police.gd"))
	p.set("target", lv.get("player"))
	p.set("left_x", left_x)
	p.set("right_x", right_x)
	p.position = Vector3(x, 0.05, 0.0)
	if lv.has_method("_on_caught"):
		p.connect("caught", Callable(lv, "_on_caught"))
	lv.add_child(p)
	officers.append(p)


func _reset() -> void:
	for o in officers:
		if is_instance_valid(o):
			o.reset_state()
