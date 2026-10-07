class_name StreetView
extends Node2D
## Draws our sidewalk + passages (crowd density), generic shops coloured and labelled by
## accumulated passers-by, the corners, walkers, and the geometry-editing overlay.

const WALK_COLOR := Color(0.93, 0.93, 0.93)
## Warm ramp for accumulated shop traffic (kept apart from the blue→red walkway density).
const RAMP := [Color("#fbf6ec"), Color("#f7dca6"), Color("#f0a257"), Color("#d4602f"), Color("#9e2a1f")]

var grid: StreetGrid
var sim: TrafficSim
var spec: LayoutSpec          # for the edit overlay (may differ from grid while dragging)
var cell_px := 16.0
var show_density := true
var show_numbers := true
var edit_mode := false
var selected_unit := -1


static func traffic_color(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	var s := t * float(RAMP.size() - 1)
	var i := mini(int(s), RAMP.size() - 2)
	return (RAMP[i] as Color).lerp(RAMP[i + 1], s - float(i))


static func fmt_count(n: int) -> String:
	if n >= 100000:
		return "%.0fk" % (n / 1000.0)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


func _draw() -> void:
	if grid == null or sim == null:
		return
	var font := ThemeDB.fallback_font
	var cs := cell_px

	# --- walkway, coloured by smoothed density
	var crowd := float(sim.crowd_level)
	for i in grid.walk_cells:
		var col := WALK_COLOR
		if show_density:
			var d := sim.density[i]
			if d > 0.02:
				if d < crowd:
					col = WALK_COLOR.lerp(UIKit.BLUE, 0.15 + 0.55 * d / crowd)
				else:
					col = UIKit.BLUE.lerp(UIKit.RED, clampf((d - crowd) / (sim.jam_density - crowd), 0.0, 1.0))
		draw_rect(Rect2(_cell_pos(i), Vector2(cs, cs)), col)

	# --- shops: fill by accumulated passers-by (sqrt scale), outline, number
	var max_pass := 1
	for v in sim.unit_passers:
		max_pass = maxi(max_pass, v)
	for u in grid.units.size():
		var pass_n: int = sim.unit_passers[u] if u < sim.unit_passers.size() else 0
		var col := traffic_color(sqrt(float(pass_n) / float(max_pass)))
		for i in grid.units[u]["cells"]:
			draw_rect(Rect2(_cell_pos(i), Vector2(cs, cs)), col)
	_draw_unit_edges()
	for u in grid.units.size():
		var door: int = grid.units[u]["door"]
		if door >= 0:
			draw_circle(_cell_pos(door) + Vector2(cs, cs) * 0.5, maxf(1.2, cs * 0.08), UIKit.MUTED)
	if show_numbers:
		var fs := int(clampf(cs * 0.62, 8.0, 13.0))
		for u in grid.units.size():
			var pass_n: int = sim.unit_passers[u] if u < sim.unit_passers.size() else 0
			var t := sqrt(float(pass_n) / float(max_pass))
			var c: Vector2 = grid.units[u]["center"]
			var txt := fmt_count(pass_n)
			draw_string(font, c * cs + Vector2(-cs * 2.0, fs * 0.35), txt,
					HORIZONTAL_ALIGNMENT_CENTER, cs * 4.0, fs, Color.WHITE if t > 0.72 else UIKit.INK)

	# --- block outline
	_draw_polygon(grid.polygon, UIKit.MUTED, 1.0, false)

	# --- corners
	var centroid := Vector2.ZERO
	for v in grid.gate_points:
		centroid += v
	centroid /= float(maxi(grid.gate_points.size(), 1))
	for z in grid.gates.size():
		for i in grid.gates[z]:
			draw_rect(Rect2(_cell_pos(i), Vector2(cs, cs)), Color(UIKit.RED, 0.22))
		var v := grid.gate_points[z]
		var out := (v - centroid).normalized()
		var p := (v + out * (LayoutBuilder.SIDEWALK + 1.6)) * cs
		draw_string(font, p + Vector2(-cs * 1.5, 5), grid.gate_names[z],
				HORIZONTAL_ALIGNMENT_CENTER, cs * 3.0, 13, UIKit.RED)

	# --- walkers (inside shops hidden)
	var rad := maxf(1.6, cs * 0.14)
	var through_col := Color(0.2, 0.2, 0.2)
	for a in sim.walkers:
		if a.state != TrafficSim.WALKING:
			continue
		var pos := _cell_pos(a.cell) + Vector2(cs, cs) * 0.5 + a.offset * cs
		draw_circle(pos, rad, UIKit.BLUE if a.shopper else through_col)

	# --- selection
	if selected_unit >= 0 and selected_unit < grid.units.size():
		for i in grid.units[selected_unit]["cells"]:
			draw_rect(Rect2(_cell_pos(i), Vector2(cs, cs)), UIKit.RED, false, 1.0)

	if edit_mode and spec != null:
		_draw_edit_overlay()

	# --- caption + colour bar
	var y0 := grid.h * cs + 8.0
	draw_string(font, Vector2(0, y0 + 12),
			"%s  ·  %d corners · %d generic shops  ·  1 cell ≈ 1.3 m, 1 step ≈ 1 s" % [
			grid.title, grid.gates.size(), grid.units.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)
	var bx := grid.w * cs - 260.0
	draw_string(font, Vector2(bx - 150, y0 + 12), "shop traffic (passers-by)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.MUTED)
	for k in 50:
		draw_rect(Rect2(bx + k * 3.0, y0 + 2, 3.0, 12), traffic_color(sqrt(float(k) / 49.0)))
	draw_rect(Rect2(bx, y0 + 2, 150, 12), UIKit.LINE, false, 1.0)
	draw_string(font, Vector2(bx + 156, y0 + 12), "0 – %s" % fmt_count(max_pass), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.MUTED)


## Thin lines between different units / between a unit and anything else.
func _draw_unit_edges() -> void:
	var cs := cell_px
	var line := Color(0.55, 0.55, 0.55)
	for u in grid.units.size():
		for i in grid.units[u]["cells"]:
			var p := grid.cell_xy(i)
			var o := Vector2(p) * cs
			if not _same_unit(p.x + 1, p.y, u):
				draw_line(o + Vector2(cs, 0), o + Vector2(cs, cs), line, 1.0)
			if not _same_unit(p.x - 1, p.y, u):
				draw_line(o, o + Vector2(0, cs), line, 1.0)
			if not _same_unit(p.x, p.y + 1, u):
				draw_line(o + Vector2(0, cs), o + Vector2(cs, cs), line, 1.0)
			if not _same_unit(p.x, p.y - 1, u):
				draw_line(o, o + Vector2(cs, 0), line, 1.0)


func _same_unit(x: int, y: int, u: int) -> bool:
	return grid.in_bounds(x, y) and grid.unit_of[grid.idx(x, y)] == u


func _draw_polygon(poly: PackedVector2Array, col: Color, width: float, dashed: bool) -> void:
	var n := poly.size()
	for k in n:
		var a := poly[k] * cell_px
		var b := poly[(k + 1) % n] * cell_px
		if dashed:
			draw_dashed_line(a, b, col, width, 6.0)
		else:
			draw_line(a, b, col, width)


func _draw_edit_overlay() -> void:
	var cs := cell_px
	_draw_polygon(spec.polygon, UIKit.RED, 2.0, true)
	for seg in spec.arcades:
		draw_dashed_line(seg[0] * cs, seg[1] * cs, UIKit.BLUE, 2.0, 6.0)
		for p in seg:
			draw_circle(p * cs, 6.0, Color.WHITE)
			draw_arc(p * cs, 6.0, 0.0, TAU, 20, UIKit.BLUE, 2.0)
	for pl in spec.plazas:
		draw_arc(Vector2(pl.x, pl.y) * cs, pl.z * cs, 0.0, TAU, 48, UIKit.BLUE, 1.5)
	for v in spec.polygon:
		var r := Rect2(v * cs - Vector2(5, 5), Vector2(10, 10))
		draw_rect(r, Color.WHITE)
		draw_rect(r, UIKit.RED, false, 2.0)


@warning_ignore("integer_division")
func _cell_pos(i: int) -> Vector2:
	return Vector2(i % grid.w, i / grid.w) * cell_px


func cell_at(p: Vector2) -> int:
	if grid == null:
		return -1
	var x := int(floor(p.x / cell_px))
	var y := int(floor(p.y / cell_px))
	if not grid.in_bounds(x, y):
		return -1
	return grid.idx(x, y)
