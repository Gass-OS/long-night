extends Node

var menu_done: Node = null

func _process(_delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return

	if cs.get("main_box") != null and cs.get("settings_box") != null:
		if menu_done != cs:
			menu_done = cs
			_inject_menu(cs)

func _inject_menu(menu: Node) -> void:
	var box = menu.get("main_box")
	if box == null:
		return

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(520, 84)
	btn.add_theme_font_size_override("font_size", 36)
	btn.text = "STAGE 2  -  MEDINA"
	btn.pressed.connect(
		func(): get_tree().change_scene_to_file("res://stage2.tscn")
	)

	box.add_child(btn)

	var idx := 0
	for i in box.get_child_count():
		var c = box.get_child(i)
		if c is Button and c.text == "PLAY":
			idx = i + 1
			break

	box.move_child(btn, idx)
