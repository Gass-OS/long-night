		if p.x < w * 0.2:
			player.touch_left = true
		elif p.x < w * 0.4:
			player.touch_right = true
		elif p.x > w * 0.7:
			player.touch_jump = true


func _build_touch_hints() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	_hint(ui, "<", 0.0, 0.2)
	_hint(ui, ">", 0.2, 0.4)
	_hint(ui, "JUMP", 0.7, 1.0)


func _hint(ui: CanvasLayer, text: String, a_left: float, a_right: float) -> void:
	var l := Label.new()
	l.text = text
	l.anchor_left = a_left
	l.anchor_right = a_right
	l.anchor_top = 0.6
	l.anchor_bottom = 1.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 56)
	l.modulate = Color(1, 1, 1, 0.3)
	ui.add_child(l)
EOF

echo "OK: project created in ~/long-night"

