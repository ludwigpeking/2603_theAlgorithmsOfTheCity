class_name HistoryChart
extends Control
## Optimiser progress: current score (gray) and best score (red) per iteration.

var best := PackedFloat32Array()
var current := PackedFloat32Array()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.75, 0.75), false, 1.0)
	if best.size() < 2:
		draw_string(font, Vector2(6, 16), "optimiser history — press Optimise",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.5))
		return
	var lo := INF
	var hi := -INF
	for v in current:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	for v in best:
		hi = maxf(hi, v)
	if hi - lo < 1e-6:
		hi = lo + 1.0
	_plot(current, lo, hi, Color(0.6, 0.6, 0.6))
	_plot(best, lo, hi, Color("#c0392b"))
	draw_string(font, Vector2(6, 14), "best %.0f" % best[best.size() - 1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c0392b"))
	draw_string(font, Vector2(size.x - 70, 14), "iter %d" % (best.size() - 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.4, 0.4))


func _plot(data: PackedFloat32Array, lo: float, hi: float, col: Color) -> void:
	var n := data.size()
	var pts := PackedVector2Array()
	for i in n:
		var x := 4.0 + float(i) / float(n - 1) * (size.x - 8.0)
		var y := size.y - 4.0 - (data[i] - lo) / (hi - lo) * (size.y - 24.0)
		pts.append(Vector2(x, y))
	draw_polyline(pts, col, 1.5)
