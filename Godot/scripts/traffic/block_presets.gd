class_name BlockPresets
extends RefCounted
## Starting shapes in metres, inside a 100 × 64 m frame. All are freely editable afterwards
## (drag corners and passage ends). Passages are lines; their ends may lie outside the block —
## only the part inside counts, and it connects where it meets the block's sides.


static func specs() -> Array[LayoutSpec]:
	var rect := [Vector2(10, 10), Vector2(90, 10), Vector2(90, 54), Vector2(10, 54)]
	var diag1 := [Vector2(6, 7.8), Vector2(94, 56.2)]      # through NW and SE corners
	var diag2 := [Vector2(94, 7.8), Vector2(6, 56.2)]      # through NE and SW corners
	var ew := [Vector2(5, 32), Vector2(95, 32)]
	var ns := [Vector2(50, 5), Vector2(50, 59)]
	var out: Array[LayoutSpec] = []
	out.append(LayoutSpec.make("A · Closed block", rect))
	out.append(LayoutSpec.make("B · Orthogonal cross", rect, [ew, ns]))
	out.append(LayoutSpec.make("C · One diagonal", rect, [diag1]))
	out.append(LayoutSpec.make("D · Diagonal X", rect, [diag1, diag2]))
	out.append(LayoutSpec.make("E · Star (X + cross)", rect, [diag1, diag2, ew, ns]))
	out.append(LayoutSpec.make("F · Pentagon, two passages",
			[Vector2(14, 20), Vector2(56, 8), Vector2(90, 26), Vector2(78, 58), Vector2(16, 54)],
			[[Vector2(10, 18), Vector2(82, 62)], [Vector2(54, 4), Vector2(46, 62)]]))
	out.append(LayoutSpec.make("G · Wedge, one passage",
			[Vector2(10, 56), Vector2(30, 8), Vector2(90, 56)],
			[[Vector2(17, 32), Vector2(94, 60)]]))
	return out
