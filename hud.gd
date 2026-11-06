extends CanvasLayer


class Pad extends Control:
	var pressed := {}

	func layout() -> Array:
		var sz := get_viewport_rect().size
		var lc := Vector2(200.0, sz.y - 135.0)
		var rc := Vector2(sz.x - 200.0, sz.y - 205.0)
		return [
			{"id": "left", "pos": lc + Vector2(-84, 0), "r": 74.0, "label": "<", "cap": "", "col": Color(1, 1, 1)},
			{"id": "right", "pos": lc + Vector2(84, 0), "r": 74.0, "label": ">", "cap": "", "col": Color(1, 1, 1)},
			{"id": "jump", "pos": rc + Vector2(0, 104), "r": 78.0, "label": "A", "cap": "JUMP", "col": Color(0.3, 0.85, 0.4)},
			{"id": "push", "pos": rc + Vector2(-108, -8), "r": 70.0, "label": "X", "cap": "PUSH", "col": Color(0.3, 0.55, 1.0)},
			{"id": "down", "pos": rc + Vector2(108, -8), "r": 70.0, "label": "B", "cap": "DOWN", "col": Color(0.95, 0.3, 0.3)},
		]

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for b in layout():
			var p: Vector2 = b["pos"]
			var r: float = b["r"]
			var col: Color = b["col"]
			var down: bool = pressed.get(b["id"], false)
			draw_circle(p, r, Color(col.r, col.g, col.b, 0.5 if down else 0.16))
			draw_arc(p, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.9 if down else 0.5), 4.0, true)
			var label: String = b["label"]
			var cap: String = b["cap"]
			var txt := Color(1, 1, 1, 0.95 if down else 0.6)
			if cap == "":
				draw_string(font, p + Vector2(-r, 22), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 64, txt)
			else:
				draw_string(font, p + Vector2(-r, 10), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 52, txt)
				draw_string(font, p + Vector2(-r, 46), cap, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 22, txt)


var player
var touches := {}
var pad: Pad
var pause_panel: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	get_tree().set_quit_on_go_back(false)
	pad = Pad.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)
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
	var specs: Array = pad.layout()
	var down := {}
	for p in touches.values():
		if p.y < size.y * 0.16:
			continue  # top strip is for the pause button
		var best := ""
		var best_d := 1000000.0
		for b in specs:
			var d: float = (b["pos"] as Vector2).distance_to(p) / float(b["r"])
			if d < 1.35 and d < best_d:
				best = b["id"]
				best_d = d
		if best != "":
			down[best] = true
	player.touch_left = down.get("left", false)
	player.touch_right = down.get("right", false)
	player.touch_jump = down.get("jump", false)
	player.touch_push = down.get("push", false)
	player.touch_down = down.get("down", false)
	pad.pressed = down
	pad.queue_redraw()


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
