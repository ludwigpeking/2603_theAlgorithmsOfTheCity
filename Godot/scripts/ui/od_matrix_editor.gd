class_name ODMatrixEditor
extends VBoxContainer
## Corner-pair demand as typed numbers (persons / min, two-way totals).
## Upper triangle = editable pair; lower triangle mirrors it (gray). Last column = shop visits.
## A value is committed on Enter or when the field loses focus; `changed` is emitted only
## if the number actually changed.

signal changed

var od: ODMatrix
var names: Array[String] = []
var _edits := {}      # Vector2i(o, d) -> LineEdit
var _mirrors := {}    # Vector2i(o, d) -> Label
var _total: Label


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)


func bind(p_od: ODMatrix, p_names: Array[String]) -> void:
	od = p_od
	names = p_names
	_rebuild()


func _rebuild() -> void:
	_edits.clear()
	_mirrors.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if od == null:
		return
	var n := od.zones
	var g := GridContainer.new()
	g.columns = n + 2
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 3)
	g.add_theme_constant_override("v_separation", 3)
	add_child(g)

	g.add_child(_cell_label("", UIKit.MUTED))
	for d in n:
		g.add_child(_cell_label(_name(d), UIKit.INK))
	g.add_child(_cell_label("Shop", UIKit.BLUE))
	for o in n:
		g.add_child(_cell_label(_name(o), UIKit.INK))
		for d in n + 1:
			var key := Vector2i(o, d)
			if d == o:
				g.add_child(_cell_label("—", UIKit.LINE))
			elif d < n and d < o:
				var m := _cell_label("", UIKit.LINE)
				_mirrors[key] = m
				g.add_child(m)
			else:
				var le := LineEdit.new()
				le.alignment = HORIZONTAL_ALIGNMENT_CENTER
				le.custom_minimum_size = Vector2(28, 22)
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				le.select_all_on_focus = true
				le.tooltip_text = "%s ↔ %s" % [_name(o), _name(d)] if d < n else "shop visits from %s" % _name(o)
				le.text_submitted.connect(func(_t: String) -> void: _commit(o, d, le))
				le.focus_exited.connect(func() -> void: _commit(o, d, le))
				_edits[key] = le
				g.add_child(le)
	_total = UIKit.label("", 10)
	_total.add_theme_color_override("font_color", UIKit.MUTED)
	add_child(_total)
	refresh()


func refresh() -> void:
	if od == null:
		return
	for key in _edits:
		(_edits[key] as LineEdit).text = _fmt(od.get_rate(key.x, key.y))
	for key in _mirrors:
		(_mirrors[key] as Label).text = _fmt(od.get_rate(key.x, key.y))
	_total.text = "Total %.0f persons / min. Pairs are two-way totals; type a number and press Enter." % od.total()


func _commit(o: int, d: int, le: LineEdit) -> void:
	if od == null or _edits.get(Vector2i(o, d)) != le:
		return        # stale field from a previous layout
	var old := od.get_rate(o, d)
	var txt := le.text.strip_edges()
	if not txt.is_valid_float():
		le.text = _fmt(old)
		return
	var v := clampf(txt.to_float(), 0.0, 999.0)
	if absf(v - old) < 1e-6:
		le.text = _fmt(old)
		return
	od.set_rate(o, d, v)
	refresh()
	changed.emit()


func _name(z: int) -> String:
	return names[z] if z < names.size() else str(z)


static func _fmt(v: float) -> String:
	return str(int(round(v))) if absf(v - round(v)) < 1e-6 else "%.1f" % v


static func _cell_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.custom_minimum_size = Vector2(22, 22)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", color)
	return l
