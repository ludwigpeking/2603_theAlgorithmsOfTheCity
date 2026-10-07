class_name UIKit
extends RefCounted
## Shared light theme and widget helpers.
## Overflow rules: every Label wraps; every Button / OptionButton clips with an ellipsis,
## so nothing can push the panel wider than PANEL_W.

const INK := Color(0.12, 0.12, 0.12)
const MUTED := Color(0.45, 0.45, 0.45)
const LINE := Color(0.78, 0.78, 0.78)
const BLUE := Color("#1a5faa")
const RED := Color("#c0392b")


static func make_theme() -> Theme:
	var t := Theme.new()
	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", 12)
	for type_name in ["Button", "OptionButton"]:
		t.set_color("font_color", type_name, INK)
		t.set_color("font_hover_color", type_name, INK)
		t.set_color("font_focus_color", type_name, INK)
		t.set_color("font_pressed_color", type_name, Color.WHITE)
		t.set_color("font_hover_pressed_color", type_name, Color.WHITE)
		t.set_stylebox("normal", type_name, _box(Color(0.97, 0.97, 0.97), LINE))
		t.set_stylebox("hover", type_name, _box(Color(0.92, 0.95, 0.99), BLUE))
		t.set_stylebox("pressed", type_name, _box(BLUE, BLUE))
		t.set_stylebox("hover_pressed", type_name, _box(BLUE.lightened(0.1), BLUE))
		t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		t.set_font_size("font_size", type_name, 12)
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(0.985, 0.985, 0.985)
	panel_box.border_color = Color(0.82, 0.82, 0.82)
	panel_box.border_width_left = 1
	panel_box.content_margin_left = 14
	panel_box.content_margin_right = 10
	panel_box.content_margin_top = 12
	panel_box.content_margin_bottom = 12
	t.set_stylebox("panel", "PanelContainer", panel_box)

	# typed number fields
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_uneditable_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(BLUE, 0.25))
	t.set_font_size("font_size", "LineEdit", 11)
	t.set_constant("minimum_character_width", "LineEdit", 2)
	var le_box := _box(Color.WHITE, LINE)
	le_box.content_margin_left = 3
	le_box.content_margin_right = 3
	le_box.content_margin_top = 2
	le_box.content_margin_bottom = 2
	t.set_stylebox("normal", "LineEdit", le_box)
	var le_focus := StyleBoxFlat.new()
	le_focus.draw_center = false
	le_focus.border_color = BLUE
	le_focus.set_border_width_all(2)
	le_focus.set_corner_radius_all(3)
	t.set_stylebox("focus", "LineEdit", le_focus)
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func label(text: String, font_size := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(40, 0)
	l.add_theme_font_size_override("font_size", font_size)
	return l


static func header(text: String) -> Label:
	var l := label(text, 11)
	l.add_theme_color_override("font_color", MUTED)
	return l


static func _clip(b: Button) -> void:
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(40, 0)


static func button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	_clip(b)
	b.pressed.connect(callback)
	return b


static func toggle(text: String, pressed: bool, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = pressed
	_clip(b)
	b.toggled.connect(callback)
	return b


static func option(items: Array, callback: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	_clip(o)
	o.fit_to_longest_item = false
	o.item_selected.connect(callback)
	return o


static func slider(lo: float, hi: float, step_size: float, value: float, callback: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step_size
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(40, 18)
	s.value_changed.connect(callback)
	return s


static func row(children: Array) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	for c in children:
		r.add_child(c)
	return r


static func swatch(color: Color, text: String, dot := false) -> HBoxContainer:
	var sq := ColorRect.new()
	sq.color = color
	sq.custom_minimum_size = Vector2(8, 8) if dot else Vector2(14, 14)
	sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row([sq, label(text)])
