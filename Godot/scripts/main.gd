extends Node2D
## Layer 1 — Traffic, network version. No congestion, no path widths:
## demand is assigned to shortest paths on a line network, and every shop along a path
## counts the people passing its frontage. Everything recomputes instantly on any change
## (also live while dragging geometry).

const PANEL_W := 370.0
const TOP := 64.0
const HANDLE_R := 1.6           # m

var presets: Array[LayoutSpec] = []
var spec: LayoutSpec
var last_good: LayoutSpec
var net: StreetNetwork
var flow: FlowModel
var od := ODMatrix.new(4)
var view: NetworkView
var od_editor: ODMatrixEditor

var frontage := 6.0
var setback := 2.0
var side_setback := 0.0
var theta := 60.0
var selected_shop := -1
var edit_mode := false
var drag := {}                  # {"type": "v"|"a", "i": int, "j": int}
var message := ""

var stats_label: Label
var shop_label: Label
var bench_label: Label
var msg_label: Label
var frontage_label: Label
var setback_label: Label
var side_setback_label: Label
var theta_label: Label


func _ready() -> void:
	presets = BlockPresets.specs()
	view = NetworkView.new()
	view.position = Vector2(24, TOP)
	add_child(view)
	_build_ui()
	get_viewport().size_changed.connect(_on_resize)
	_select_preset(0)


# ---------------------------------------------------------------- model

func _select_preset(i: int) -> void:
	spec = presets[i].copy()
	selected_shop = -1
	_rebuild()


## Rebuild network + flows from spec (instant). Invalid shapes keep the last good one.
func _rebuild() -> void:
	if spec.is_valid():
		message = ""
		last_good = spec.copy()
	else:
		message = "Edges cross — showing the last valid shape."
	net = StreetNetwork.build(last_good, frontage, setback, side_setback)
	if od.zones != net.corner_nodes.size():
		od.resize(net.corner_nodes.size())
		od_editor.bind(od, net.corner_names)
	elif od_editor.names != net.corner_names:
		od_editor.bind(od, net.corner_names)
	_recompute_flows()


func _recompute_flows() -> void:
	flow = FlowModel.new(net, od)
	flow.theta = theta
	flow.compute()
	if selected_shop >= net.shops.size():
		selected_shop = -1
	view.net = net
	view.flow = flow
	view.spec = spec
	view.selected_shop = selected_shop
	_update_text()
	view.queue_redraw()


func _set_od_preset(which: String) -> void:
	match which:
		"balanced":
			od.preset_balanced()
		"across":
			od.preset_across()
		"side":
			od.preset_busy_side()
		"clear":
			od.clear()
	od_editor.refresh()
	_recompute_flows()


# ---------------------------------------------------------------- input / editing

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouse) or net == null:
		return
	var p := view.to_local((event as InputEventMouse).position) / view.ppm    # metres
	if edit_mode:
		_edit_input(event, p)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_shop = net.shop_at(p)
		view.selected_shop = selected_shop
		_update_text()
		view.queue_redraw()


func _edit_input(event: InputEvent, p: Vector2) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var h := _hit_handle(p)
				if not h.is_empty():
					drag = h
				elif mb.double_click:
					_insert_vertex(p)
			else:
				drag = {}
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var h := _hit_handle(p)
			if h.is_empty():
				return
			if h["type"] == "v":
				if spec.polygon.size() > 3:
					var poly := spec.polygon
					poly.remove_at(h["i"])
					spec.polygon = poly
			else:
				spec.arcades.remove_at(h["i"])
			_rebuild()
	elif event is InputEventMouseMotion and not drag.is_empty():
		var q := _clamp(p)
		if drag["type"] == "v":
			var poly := spec.polygon
			poly[drag["i"]] = q
			spec.polygon = poly
		else:
			var seg: PackedVector2Array = spec.arcades[drag["i"]]
			seg[drag["j"]] = q
			spec.arcades[drag["i"]] = seg
		_rebuild()                  # instant: live update while dragging


func _hit_handle(p: Vector2) -> Dictionary:
	for k in spec.polygon.size():
		if p.distance_to(spec.polygon[k]) <= HANDLE_R:
			return {"type": "v", "i": k, "j": 0}
	for k in spec.arcades.size():
		for j in 2:
			if p.distance_to(spec.arcades[k][j]) <= HANDLE_R:
				return {"type": "a", "i": k, "j": j}
	return {}


func _insert_vertex(p: Vector2) -> void:
	var poly := spec.polygon
	var n := poly.size()
	var best_k := -1
	var best_d := 2.5
	for k in n:
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % n]))
		if d < best_d:
			best_d = d
			best_k = k
	if best_k < 0:
		return
	poly.insert(best_k + 1, _clamp(p))
	spec.polygon = poly
	_rebuild()


func _add_passage(diagonal: bool) -> void:
	var c := spec.centroid()
	var dir := Vector2(1, 0.55).normalized() if diagonal else Vector2(1, 0)
	var a := _clamp(c - dir * 60.0)
	var b := _clamp(c + dir * 60.0)
	spec.arcades.append(PackedVector2Array([a, b]))
	_rebuild()


func _clamp(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 1.0, NetworkView.FRAME.x - 1.0), clampf(p.y, 1.0, NetworkView.FRAME.y - 1.0))


# ---------------------------------------------------------------- comparison

func _compare() -> void:
	var lines: Array[String] = []
	var list: Array[LayoutSpec] = []
	var skipped := 0
	for s in presets:
		if s.polygon.size() == od.zones:
			list.append(s)
		else:
			skipped += 1
	var cur := last_good.copy()
	cur.title = "Current (%s)" % last_good.title
	list.append(cur)
	for s in list:
		var n := StreetNetwork.build(s, frontage, setback, side_setback)
		var f := FlowModel.new(n, od)
		f.theta = theta
		f.compute()
		var st := f.shop_stats()
		lines.append("%s\n   %d shops · mean %s/h · min %s/h · Gini %.2f · weak %.0f%% · trip %.0f m · passages %.0f%%" % [
				s.title, st["n"], NetworkView.fmt(st["mean"]), NetworkView.fmt(st["min"]), st["gini"],
				100.0 * st["weak"], f.mean_through_trip(), 100.0 * f.passage_share])
	if skipped > 0:
		lines.append("(%d preset(s) skipped: different number of corners)" % skipped)
	bench_label.text = "\n".join(lines)


# ---------------------------------------------------------------- display

func _on_resize() -> void:
	var vp := get_viewport_rect().size
	var aw := vp.x - PANEL_W - 48.0
	var ah := vp.y - TOP - 60.0
	view.ppm = maxf(3.0, minf(aw / NetworkView.FRAME.x, ah / NetworkView.FRAME.y))
	view.queue_redraw()


func _update_text() -> void:
	var st := flow.shop_stats()
	var t := "Through flow %.0f /min · mean trip %.0f m\n" % [flow.through_rate, flow.mean_through_trip()]
	t += "Shop visitors %.0f /min · walking %.1f person-km / h\n" % [flow.shopper_rate, flow.person_km_per_hour()]
	t += "Person-distance on passages %.0f%%\n" % [100.0 * flow.passage_share]
	t += "%d shops · traffic per shop: mean %s/h, min %s/h, max %s/h\n" % [
			st["n"], NetworkView.fmt(st["mean"]), NetworkView.fmt(st["min"]), NetworkView.fmt(st["max"])]
	t += "Inequality (Gini) %.2f · weak shops (< 25%% of mean) %.0f%%\n" % [st["gini"], 100.0 * st["weak"]]
	t += "Floor: shops %.0f m² (%.0f%%) + public setback %.0f m² of %.0f m² block · mean shop %.0f m²" % [
			net.shop_area, 100.0 * net.shop_area / maxf(net.block_area, 1.0),
			maxf(0.0, net.block_area - net.shop_area), net.block_area,
			net.shop_area / float(maxi(net.shops.size(), 1))]
	if flow.unreachable > 0.0:
		t += "\n%.0f /min cannot reach their destination" % flow.unreachable
	stats_label.text = t

	var s := selected_shop
	if s >= 0 and s < net.shops.size():
		var e: Dictionary = net.edges[net.shops[s]["edge"]]
		var kind := "passage" if e["kind"] == StreetNetwork.KIND_PASSAGE else "block side"
		shop_label.text = "Shop %d on a %s · %.1f m frontage · %.0f m²\npassers-by %.0f / h  (through %.0f, shop visitors %.0f)\nvisits %.0f / h" % [
				s, kind, float(net.shops[s]["frontage"]), float(net.shops[s]["area"]),
				flow.shop_pass[s] * 60.0, flow.shop_pass_through[s] * 60.0,
				(flow.shop_pass[s] - flow.shop_pass_through[s]) * 60.0, flow.shop_visits[s] * 60.0]
	else:
		shop_label.text = "Click a shop to see its traffic."
	msg_label.text = message
	msg_label.visible = message != ""


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var ui_theme := UIKit.make_theme()
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := UIKit.label("Algorithms of the City · Shopping street — Layer 1: Traffic (network)\n"
			+ "No congestion, no widths: every corner-to-corner flow takes its shortest path along our sidewalk and the passages; every shop on the path counts the passers-by.", 13)
	title.theme = ui_theme
	title.position = Vector2(24, 10)
	title.size = Vector2(900, 48)
	layer.add_child(title)

	var panel := PanelContainer.new()
	panel.theme = ui_theme
	layer.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_W
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	# geometry
	box.add_child(UIKit.header("BLOCK SHAPE & PASSAGES"))
	var names: Array = []
	for s in presets:
		names.append(s.title)
	box.add_child(UIKit.option(names, _select_preset))
	box.add_child(UIKit.toggle("Edit geometry", false, _on_edit_toggled))
	box.add_child(UIKit.row([
		UIKit.button("+ Straight passage", func() -> void: _add_passage(false)),
		UIKit.button("+ Diagonal passage", func() -> void: _add_passage(true)),
	]))
	box.add_child(UIKit.label("Edit mode: drag red corners or blue passage ends (updates live) · double-click a side to add a corner · right-click a corner or passage end to delete it.", 10))
	msg_label = UIKit.label("", 11)
	msg_label.add_theme_color_override("font_color", UIKit.RED)
	box.add_child(msg_label)

	# demand
	box.add_child(UIKit.header("CORNER-TO-CORNER FLOWS  (persons / min, two-way)"))
	od_editor = ODMatrixEditor.new()
	od_editor.changed.connect(_recompute_flows)
	box.add_child(od_editor)
	od_editor.bind(od, StreetNetwork.compass_names(presets[0].polygon))
	box.add_child(UIKit.row([
		UIKit.button("Balanced", func() -> void: _set_od_preset("balanced")),
		UIKit.button("Across", func() -> void: _set_od_preset("across")),
		UIKit.button("Busy side", func() -> void: _set_od_preset("side")),
		UIKit.button("Clear", func() -> void: _set_od_preset("clear")),
	]))

	# shops
	box.add_child(UIKit.header("SHOPS"))
	frontage_label = UIKit.label("")
	box.add_child(frontage_label)
	box.add_child(UIKit.slider(3, 15, 0.5, frontage, _on_frontage))
	setback_label = UIKit.label("")
	box.add_child(setback_label)
	box.add_child(UIKit.slider(0, 8, 0.5, setback, _on_setback))
	side_setback_label = UIKit.label("")
	box.add_child(side_setback_label)
	box.add_child(UIKit.slider(0, 6, 0.5, side_setback, _on_side_setback))
	theta_label = UIKit.label("")
	box.add_child(theta_label)
	box.add_child(UIKit.slider(10, 300, 10, theta, _on_theta))
	_on_frontage(frontage, false)
	_on_setback(setback, false)
	_on_side_setback(side_setback, false)
	_on_theta(theta, false)
	box.add_child(UIKit.label("Seeds (black dots) sit on the path axis, spaced equally along every frontage; each shop is the Voronoi cell of its seed, then set back from the axis. The gray link is the shop's conceptual entrance, still counted on the path.", 10))

	# display
	box.add_child(UIKit.header("DISPLAY"))
	box.add_child(UIKit.row([
		UIKit.toggle("Flow lines", true, _on_show_flows),
		UIKit.toggle("Shop numbers", true, _on_show_numbers),
	]))

	# results
	box.add_child(UIKit.header("RESULTS"))
	stats_label = UIKit.label("")
	box.add_child(stats_label)
	box.add_child(UIKit.header("SELECTED SHOP"))
	shop_label = UIKit.label("")
	box.add_child(shop_label)

	box.add_child(UIKit.header("COMPARE"))
	box.add_child(UIKit.button("Compare presets + current shape", _compare))
	bench_label = UIKit.label("Same flows and shop settings; only shapes with the same number of corners.", 11)
	box.add_child(bench_label)

	box.add_child(UIKit.header("LEGEND"))
	box.add_child(UIKit.swatch(UIKit.BLUE, "path line, width = flow (sides drawn on our sidewalk)"))
	box.add_child(UIKit.swatch(NetworkView.traffic_color(0.85), "shop fill & number = passers-by per hour"))
	box.add_child(UIKit.swatch(UIKit.RED, "corner (where people join / leave our side)", true))


func _on_show_flows(on: bool) -> void:
	view.show_flows = on
	view.queue_redraw()


func _on_show_numbers(on: bool) -> void:
	view.show_numbers = on
	view.queue_redraw()


func _on_edit_toggled(on: bool) -> void:
	edit_mode = on
	view.edit_mode = on
	drag = {}
	view.queue_redraw()


func _on_frontage(v: float, apply := true) -> void:
	frontage = v
	frontage_label.text = "Target shop frontage: %.1f m" % v
	if apply:
		_rebuild()


func _on_setback(v: float, apply := true) -> void:
	setback = v
	setback_label.text = "Half passage width: %.1f m (passages %.1f m wide; the sidewalk axis runs %.1f m outside the building line)" % [v, 2.0 * v, v]
	if apply:
		_rebuild()


func _on_side_setback(v: float, apply := true) -> void:
	side_setback = v
	side_setback_label.text = "Extra setback inside the building line: %.1f m" % v
	if apply:
		_rebuild()


func _on_theta(v: float, apply := true) -> void:
	theta = v
	theta_label.text = "Shop visitors' distance scale θ: %d m  (larger = go further)" % int(v)
	if apply:
		_recompute_flows()
