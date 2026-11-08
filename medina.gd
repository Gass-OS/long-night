extends Node

var menu_done: Node = null
var chain_done: Node = null


func _process(_delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	if cs.get("main_box") != null and cs.get("settings_box") != null:
		if menu_done != cs:
			menu_done = cs
			_inject_menu(cs)
		return
	if chain_done == cs:
		return
	# Stage 1 finished: continue straight to stage 2
	if cs.get("finished") == true and cs.get("weather") != null and cs.get("dogs") != null:
		chain_done = cs
		_continue(cs, 2.6, "res://stage2.tscn")
	# Stage 2 finished: continue straight to stage 3
	elif cs.get("stage") == 2 and cs.get("finished") == true:
		chain_done = cs
		_continue(cs, 9.5, "res://stage3.tscn")


func _continue(cs: Node, delay: float, path: String) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(cs) and get_tree().current_scene == cs:
		get_tree().change_scene_to_file(path)


func _add_button(box: Node, text: String, path: String) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(520, 84)
	btn.add_theme_font_size_override("font_size", 36)
	btn.text = text
	btn.pressed.connect(func(): get_tree().change_scene_to_file(path))
	box.add_child(btn)
	var idx := 0
	for i in box.get_child_count():
		var c = box.get_child(i)
		if c is Button and (c.text == "PLAY" or c.text == "STAGE 2  -  MEDINA"):
			idx = i + 1
	box.move_child(btn, idx)


func _inject_menu(menu: Node) -> void:
	var box = menu.get("main_box")
	_add_button(box, "STAGE 2  -  MEDINA", "res://stage2.tscn")
	_add_button(box, "STAGE 3  -  CHAAMBI", "res://stage3.tscn")
