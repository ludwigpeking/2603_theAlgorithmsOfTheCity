class_name LayoutBuilder
extends RefCounted
## Rasterises a LayoutSpec onto the grid.
##   inside polygon & within ARCADE_HALF of an arcade (or inside a plaza) → WALK
##   outside polygon & within SIDEWALK of its boundary                    → WALK (our sidewalk)
##   other inside cells → split into 4 × 4 tiles; each connected piece of ≥ MIN_UNIT cells
##   that touches a walkway becomes a generic shop unit, the rest is back-of-house.
##   gates: sidewalk cells within SIDEWALK + 0.6 of each polygon vertex.

const MAP_W := 64
const MAP_H := 44
const SIDEWALK := 3.0
const ARCADE_HALF := 2.0
const TILE := 4
const TILES_X := 16
const TILES_Y := 11
const MIN_UNIT := 5
const MARGIN := 4.0          # keep vertices this far from the map edge


static func build(spec: LayoutSpec) -> StreetGrid:
	var g := StreetGrid.new(spec.title, MAP_W, MAP_H)
	var poly := spec.polygon
	g.polygon = poly.duplicate()
	var cand := PackedByteArray()
	cand.resize(MAP_W * MAP_H)

	for y in MAP_H:
		for x in MAP_W:
			var i := g.idx(x, y)
			var p := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(p, poly):
				g.interior[i] = 1
				if _in_passage(p, spec):
					g.cells[i] = StreetGrid.WALK
				else:
					cand[i] = 1
			elif _dist_to_boundary(p, poly) <= SIDEWALK:
				g.cells[i] = StreetGrid.WALK

	# shop units: connected pieces of each tile
	var dirs4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for ty in TILES_Y:
		for tx in TILES_X:
			var tile := Rect2i(tx * TILE, ty * TILE, TILE, TILE)
			var seen := {}
			for yy in range(tile.position.y, tile.end.y):
				for xx in range(tile.position.x, tile.end.x):
					var start := g.idx(xx, yy)
					if cand[start] == 0 or seen.has(start):
						continue
					var comp := PackedInt32Array()
					var stack: Array[int] = [start]
					seen[start] = true
					var touches := false
					while not stack.is_empty():
						var c: int = stack.pop_back()
						comp.append(c)
						var cp := g.cell_xy(c)
						for d in dirs4:
							var q := cp + d
							if g.is_walk_xy(q.x, q.y):
								touches = true
							if not tile.has_point(q):
								continue
							var j := g.idx(q.x, q.y)
							if cand[j] == 1 and not seen.has(j):
								seen[j] = true
								stack.append(j)
					if touches and comp.size() >= MIN_UNIT:
						g.add_unit_cells(comp)

	# corner gates
	var names := gate_names(poly)
	for k in poly.size():
		var v := poly[k]
		var list := PackedInt32Array()
		var r := int(ceil(SIDEWALK + 1.0))
		for y in range(int(v.y) - r, int(v.y) + r + 1):
			for x in range(int(v.x) - r, int(v.x) + r + 1):
				if not g.in_bounds(x, y):
					continue
				var i := g.idx(x, y)
				if g.is_walk(i) and g.interior[i] == 0 \
						and Vector2(x + 0.5, y + 0.5).distance_to(v) <= SIDEWALK + 0.6:
					list.append(i)
		g.add_gate(v, list, names[k])

	g.finalize()
	return g


static func _in_passage(p: Vector2, spec: LayoutSpec) -> bool:
	for seg in spec.arcades:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) <= ARCADE_HALF:
			return true
	for pl in spec.plazas:
		if p.distance_to(Vector2(pl.x, pl.y)) <= pl.z:
			return true
	return false


static func _dist_to_boundary(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	var n := poly.size()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Compass name of each corner seen from the centroid (duplicates get a number).
static func gate_names(poly: PackedVector2Array) -> Array[String]:
	var dirs := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]   # screen y points down
	var c := Vector2.ZERO
	for v in poly:
		c += v
	c /= float(maxi(poly.size(), 1))
	var names: Array[String] = []
	var counts := {}
	for v in poly:
		var k := posmod(int(round((v - c).angle() / (PI / 4.0))), 8)
		var nm: String = dirs[k]
		names.append(nm)
		counts[nm] = int(counts.get(nm, 0)) + 1
	var seen := {}
	for k in names.size():
		var nm := names[k]
		if counts[nm] > 1:
			seen[nm] = int(seen.get(nm, 0)) + 1
			names[k] = "%s%d" % [nm, seen[nm]]
	return names


static func is_valid(spec: LayoutSpec) -> bool:
	return spec.polygon.size() >= 3 and not Geometry2D.triangulate_polygon(spec.polygon).is_empty()


static func clamp_point(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, MARGIN, MAP_W - MARGIN), clampf(p.y, MARGIN, MAP_H - MARGIN))
