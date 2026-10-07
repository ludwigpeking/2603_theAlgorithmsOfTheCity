class_name MallView
extends Node2D
## Draws the layout, tenants, revenue bars, pedestrian heat and shoppers.

const INK := Color(0.1, 0.1, 0.1)
const GRAY := Color(0.5, 0.5, 0.5)
const WALK_COLOR := Color(0.94, 0.94, 0.94)
const BLUE := Color("#1a5faa")
const RED := Color("#c0392b")

var layout: MallLayout
var catalog: Catalog
var sim: CustomerSim
var assignment := PackedInt32Array()
var unit_revenue := PackedFloat32Array()
var show_heat := true
var show_agents := true
var cell_px := 24.0
var selected_unit := -1


func _draw() -> void:
	if layout == null or catalog == null:
		return
	var font := ThemeDB.fallback_font
	var cs := cell_px

	# --- public realm + footfall heat
	var max_heat := 1
	if show_heat and sim != null:
		for v in sim.heat:
			max_heat = maxi(max_heat, v)
	for i in layout.cells.size():
		var c := layout.cells[i]
		if c == MallLayout.VOID or c == MallLayout.UNIT:
			continue
		var col := WALK_COLOR
		if show_heat and sim != null and sim.heat[i] > 0:
			var k := sqrt(float(sim.heat[i]) / float(max_heat))
			col = WALK_COLOR.lerp(BLUE, k * 0.7)
		draw_rect(Rect2(_cell_pos(i), Vector2(cs, cs)), col)

	# --- units
	var max_rev := 1.0
	for v in unit_revenue:
		max_rev = maxf(max_rev, v)
	for u in layout.units.size():
		var r: Rect2i = layout.units[u]["rect"]
		var rect := Rect2(Vector2(r.position) * cs, Vector2(r.size) * cs)
		var cat: int = assignment[u] if u < assignment.size() else 0
		var cdef: Dictionary = catalog.categories[cat]
		var fill: Color = cdef["color"]
		draw_rect(rect, fill.lerp(Color.WHITE, 0.55))
		draw_rect(rect, INK, false, 1.0)
		var font_size := int(clampf(cs * 0.45, 9.0, 14.0))
		draw_string(font, rect.position + Vector2(4, font_size + 2), cdef["short"],
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, font_size, INK)
		var rev := unit_revenue[u] if u < unit_revenue.size() else 0.0
		if rev > 0.0:
			draw_string(font, rect.position + Vector2(4, font_size * 2 + 5), str(int(rev)),
					HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, font_size - 1, GRAY)
			var bar_w := (rect.size.x - 8.0) * rev / max_rev
			draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 7), Vector2(bar_w, 3)), INK)
		if u == selected_unit:
			draw_rect(rect.grow(-2.0), RED, false, 2.0)
		var door: int = layout.units[u]["door"]
		if door >= 0:
			draw_circle(_cell_pos(door) + Vector2(cs, cs) * 0.5, maxf(1.5, cs * 0.07), GRAY)

	# --- entrances
	for e in layout.entrances:
		var p := _cell_pos(e["cell"]) + Vector2(cs, cs) * 0.5
		draw_circle(p, cs * 0.36, RED)
		draw_string(font, p + Vector2(-cs * 0.18, cs * 0.16), "E",
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.45), Color.WHITE)

	# --- shoppers (those inside shops are hidden)
	if show_agents and sim != null:
		var rad := maxf(2.0, cs * 0.13)
		for a in sim.agents:
			if a.state == CustomerSim.DONE or a.state == CustomerSim.IN_SHOP:
				continue
			var pos := _cell_pos(a.cell) + Vector2(cs, cs) * 0.5 + a.offset * cs
			draw_circle(pos, rad, catalog.profiles[a.profile]["color"])

	# --- caption
	draw_string(font, Vector2(0, layout.h * cs + 18),
			"%s   ·   %d units · %d entrances · grid %d × %d" % [layout.title, layout.units.size(),
			layout.entrances.size(), layout.w, layout.h],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GRAY)


@warning_ignore("integer_division")
func _cell_pos(i: int) -> Vector2:
	return Vector2(i % layout.w, i / layout.w) * cell_px


func cell_at(p: Vector2) -> int:
	if layout == null:
		return -1
	var x := int(floor(p.x / cell_px))
	var y := int(floor(p.y / cell_px))
	if x < 0 or y < 0 or x >= layout.w or y >= layout.h:
		return -1
	return layout.idx(x, y)
