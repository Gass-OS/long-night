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
