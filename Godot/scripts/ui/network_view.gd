class_name NetworkView
extends Node2D
## Draws the block, the pedestrian network (line width = flow), shops coloured and labelled
## by passers-by per hour, the corners, and the geometry-editing overlay. Units: metres.

const FRAME := Vector2(100, 64)
const RAMP := [Color("#fbf6ec"), Color("#f7dca6"), Color("#f0a257"), Color("#d4602f"), Color("#9e2a1f")]

var net: StreetNetwork
var flow: FlowModel
var spec: LayoutSpec
var ppm := 10.0               # pixels per metre
var show_flows := true
var show_numbers := true
var edit_mode := false
var selected_shop := -1


static func traffic_color(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	var s := t * float(RAMP.size() - 1)
	var i := mini(int(s), RAMP.size() - 2)
	return (RAMP[i] as Color).lerp(RAMP[i + 1], s - float(i))


static func fmt(v: float) -> String:
	if v >= 10000.0:
		return "%.0fk" % (v / 1000.0)
	if v >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return str(int(round(v)))


func px(p: Vector2) -> Vector2:
	return p * ppm


func _draw() -> void:
	if net == null or flow == null:
		return
	var font := ThemeDB.fallback_font

	draw_rect(Rect2(Vector2.ZERO, FRAME * ppm), Color(0.85, 0.85, 0.85), false, 1.0)
	var poly_px := PackedVector2Array()
	for v in net.polygon:
		poly_px.append(px(v))
	if poly_px.size() >= 3:
		draw_colored_polygon(poly_px, Color(0.93, 0.93, 0.93))
	# setback bands = public space of the passages (and sides, if set back)
	for band in net.band_draw:
		var bp := PackedVector2Array()
		for p in band:
			bp.append(px(p))
		if bp.size() >= 3:
			draw_colored_polygon(bp, Color(0.995, 0.995, 0.99))

	# --- shops
	var hourly := flow.shop_hourly()
	var max_h := 1.0
	for v in hourly:
		max_h = maxf(max_h, v)
	for s in net.shops.size():
		var q: PackedVector2Array = net.shops[s]["poly"]
		var qp := PackedVector2Array()
		for p in q:
			qp.append(px(p))
		draw_colored_polygon(qp, traffic_color(sqrt(hourly[s] / max_h)))
		qp.append(qp[0])
		draw_polyline(qp, Color(0.6, 0.6, 0.6), 1.0)
	# building line (the drawn outline — stable, independent of the setback)
	if poly_px.size() >= 3:
		var outline := poly_px.duplicate()
		outline.append(outline[0])
		draw_polyline(outline, Color(0.35, 0.35, 0.35), 1.5)
	if selected_shop >= 0 and selected_shop < net.shops.size():
		var qs: PackedVector2Array = net.shops[selected_shop]["poly"]
		var qsp := PackedVector2Array()
		for p in qs:
			qsp.append(px(p))
		qsp.append(qsp[0])
		draw_polyline(qsp, UIKit.RED, 2.5)

	# --- network (side edges lie on the sidewalk axis, outside the building line)
	var max_f := 1e-6
	for v in flow.edge_flow:
		max_f = maxf(max_f, v)
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		var a := px(net.nodes[e["a"]])
		var b := px(net.nodes[e["b"]])
		var f: float = flow.edge_flow[ei]
		if show_flows and f > 1e-6:
			draw_line(a, b, Color(UIKit.BLUE, 0.85), 1.5 + 10.0 * sqrt(f / max_f))
		else:
			draw_line(a, b, Color(0.6, 0.6, 0.6), 1.0)
	for i in net.nodes.size():
		draw_circle(px(net.nodes[i]), 2.0, Color(0.45, 0.45, 0.45))
	# conceptual entrances: seed on the path axis → the set-back shop front
	for s in net.shops.size():
		var sp := px(net.shops[s]["seed"])
		var dp := px(net.shops[s]["door"])
		if sp.distance_to(dp) > 1.0:
			draw_line(sp, dp, UIKit.MUTED, 1.0)
		draw_circle(dp, 1.6, UIKit.MUTED)
		draw_circle(sp, 1.8, UIKit.INK)

	# --- shop numbers (per hour)
	if show_numbers:
		var fs := int(clampf(ppm * 1.1, 8.0, 12.0))
		for s in net.shops.size():
			var c := px(net.shops[s]["center"])
			var t := sqrt(hourly[s] / max_h)
			draw_string(font, c + Vector2(-30, fs * 0.35), fmt(hourly[s]), HORIZONTAL_ALIGNMENT_CENTER, 60,
					fs, Color.WHITE if t > 0.72 else UIKit.INK)

	# --- corners
	var centroid := Vector2.ZERO
	for v in net.polygon:
		centroid += v
	centroid /= float(maxi(net.polygon.size(), 1))
	for k in net.corner_nodes.size():
		var v := net.nodes[net.corner_nodes[k]]
		draw_circle(px(v), 5.0, UIKit.RED)
		var p := px(v + (v - centroid).normalized() * 4.5)
		draw_string(font, p + Vector2(-20, 5), net.corner_names[k], HORIZONTAL_ALIGNMENT_CENTER, 40, 13, UIKit.RED)

	if edit_mode and spec != null:
		_draw_edit_overlay()

	# --- caption, colour bar, scale bar
	var y0 := FRAME.y * ppm + 8.0
	draw_string(font, Vector2(0, y0 + 12), "%s  ·  %d corners · %d shops · %d network nodes" % [
			net.title, net.corner_nodes.size(), net.shops.size(), net.nodes.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)
	var bx := FRAME.x * ppm - 170.0
	draw_string(font, Vector2(bx - 170, y0 + 12), "shop traffic (passers-by / h)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.MUTED)
	for k in 40:
		draw_rect(Rect2(bx + k * 2.5, y0 + 2, 2.5, 12), traffic_color(sqrt(float(k) / 39.0)))
	draw_rect(Rect2(bx, y0 + 2, 100, 12), UIKit.LINE, false, 1.0)
	draw_string(font, Vector2(bx + 106, y0 + 12), "0–%s" % fmt(max_h), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.MUTED)
	var sb := Vector2(0, y0 + 26)
	draw_line(sb, sb + Vector2(20.0 * ppm, 0), UIKit.INK, 2.0)
	draw_string(font, sb + Vector2(20.0 * ppm + 6, 5), "20 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.INK)


func _draw_edit_overlay() -> void:
	var n := spec.polygon.size()
	for k in n:
		draw_dashed_line(px(spec.polygon[k]), px(spec.polygon[(k + 1) % n]), UIKit.RED, 1.5, 6.0)
	for seg in spec.arcades:
		draw_dashed_line(px(seg[0]), px(seg[1]), UIKit.BLUE, 1.5, 6.0)
		for p in seg:
			draw_circle(px(p), 6.0, Color.WHITE)
			draw_arc(px(p), 6.0, 0.0, TAU, 20, UIKit.BLUE, 2.0)
	for v in spec.polygon:
		var r := Rect2(px(v) - Vector2(5, 5), Vector2(10, 10))
		draw_rect(r, Color.WHITE)
		draw_rect(r, UIKit.RED, false, 2.0)
