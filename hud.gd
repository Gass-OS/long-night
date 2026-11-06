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
