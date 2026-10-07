class_name SeriesChart
extends Control
## Per-minute series: efficiency (red, fixed 0–1 scale) and people in network (gray, own scale).

var eff := PackedFloat32Array()
var pop := PackedFloat32Array()


func _init() -> void:
	custom_minimum_size = Vector2(200, 96)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), UIKit.LINE, false, 1.0)
	draw_string(font, Vector2(6, 13), "efficiency", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.RED)
	draw_string(font, Vector2(70, 13), "people in network", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.MUTED)
	draw_string(font, Vector2(size.x - 60, 13), "per minute", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.MUTED)
	if eff.size() < 2:
		return
	var max_pop := 1.0
	for v in pop:
		max_pop = maxf(max_pop, v)
	_plot(pop, 0.0, max_pop * 1.1, UIKit.MUTED)
	_plot(eff, 0.0, 1.0, UIKit.RED)


func _plot(data: PackedFloat32Array, lo: float, hi: float, col: Color) -> void:
	var n := data.size()
	var start := maxi(0, n - 120)          # last two hours
	var m := n - start
	if m < 2:
		return
	var pts := PackedVector2Array()
	for i in m:
		var x := 4.0 + float(i) / float(m - 1) * (size.x - 8.0)
		var y := size.y - 4.0 - (data[start + i] - lo) / (hi - lo) * (size.y - 22.0)
		pts.append(Vector2(x, y))
	draw_polyline(pts, col, 1.5)
