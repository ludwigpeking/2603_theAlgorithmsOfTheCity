class_name StreetNetwork
extends RefCounted
## Layer 1 (no congestion, no widths): the public realm as a network of lines, in metres.
##   polygon       — the drawn block outline = building line (stable; never moves)
##   axis_polygon  — the sidewalk axis: the outline offset OUTWARD by half the passage width
##                   (mitred, so every corner stays one node). Side traffic runs here, so the
##                   sidewalk is as wide as a passage and the block keeps its full area.
##   side edges    — edges of axis_polygon; shops on the inner side only
##   passage edges — passages through the block (clipped to the axis polygon); shops both sides
## Nodes: corners (polygon vertices), points where passages meet the boundary,
## passage crossings, passage dead-ends.
##
## Shops fill the block completely (no spare space) — frontage-seeded Voronoi:
##   1. faces = the block cut along all through-passages (dead-end spurs don't cut)
##   2. seeds = on every frontage edge of a face, n = round(length / target frontage)
##              points spaced equally (at the middle of n equal segments)
##   3. shops = the Voronoi cell of each seed within its face: every point of the face
##              goes to the nearest seed. Cells tile the face; each touches its frontage.
##   4. setback = cells are clipped to the drawn outline, a band of half-width `setback`
##              around every passage axis is carved out (and optionally a band inside the
##              outline), articulating the passage.
##              The seed stays on the axis: it is the shop's conceptual entrance and the
##              point it is counted at; `door` is where that entrance meets the shop front.

const KIND_SIDE := 0
const KIND_PASSAGE := 1
const MERGE := 0.3          # m — points closer than this are the same node
const TIE := 1e-3           # m — path-length tolerance for equal shortest paths
const CUT_HALF := 0.02      # m — half-width of the cut along a passage (numerical only)
const FRONT_TOL := 0.15     # m — a part edge this close to a network edge is frontage
const MIN_FRONT := 0.5      # m — shorter frontage edges don't own a region
const BIG := 10000.0

var title := ""
var polygon := PackedVector2Array()         # drawn outline (building line)
var axis_polygon := PackedVector2Array()    # sidewalk axis (outline offset outward)
var nodes := PackedVector2Array()
var corner_nodes := PackedInt32Array()     # corner k -> node
var corner_names: Array[String] = []
var edges: Array[Dictionary] = []          # {a, b, len, kind, dir, normal}
var adj: Array = []                        # node -> [[neighbour, length, edge], ...]
var shops: Array[Dictionary] = []          # {edge, x, x0, x1, frontage, poly, center, area}
var edge_shops: Array[PackedInt32Array] = []
var dist: Array[PackedFloat64Array] = []   # all-pairs shortest distance
var sigma: Array[PackedFloat64Array] = []  # all-pairs number of shortest paths
var faces: Array[PackedVector2Array] = []
var bands: Array[PackedVector2Array] = []  # setback bands used for carving
var band_draw: Array[PackedVector2Array] = []  # the same, clipped to the block, for drawing
var block_area := 0.0
var shop_area := 0.0
var setback_passage := 2.0
var setback_side := 0.0


static func build(spec: LayoutSpec, frontage := 6.0, p_setback := 2.0, p_side_setback := 0.0) -> StreetNetwork:
	var net := StreetNetwork.new()
	net.setback_passage = p_setback
	net.setback_side = p_side_setback
	net.title = spec.title
	net.polygon = spec.polygon.duplicate()
	net.axis_polygon = offset_miter(spec.polygon, p_setback)
	var poly := net.axis_polygon
	var n := poly.size()

	# corners are nodes 0..n-1
	for v in poly:
		net.corner_nodes.append(net._node(v))
	net.corner_names = compass_names(spec.polygon)

	# 1. passage pieces inside the polygon
	var pieces: Array[PackedVector2Array] = []
	for seg in spec.arcades:
		var a := seg[0]
		var b := seg[1]
		if a.distance_to(b) < 0.5:
			continue
		# ends outside the drawn outline are through-ends: extend them so they always
		# reach the (outward-offset) sidewalk axis
		var ext := 4.0 * p_setback + 1.0
		var sdir := (b - a).normalized()
		if not Geometry2D.is_point_in_polygon(a, spec.polygon):
			a -= sdir * ext
		if not Geometry2D.is_point_in_polygon(b, spec.polygon):
			b += sdir * ext
		var ts: Array[float] = [0.0, 1.0]
		for k in n:
			var hit = Geometry2D.segment_intersects_segment(a, b, poly[k], poly[(k + 1) % n])
			if hit != null:
				ts.append(_param(a, b, hit))
		ts.sort()
		for i in ts.size() - 1:
			if ts[i + 1] - ts[i] < 1e-4:
				continue
			var mid := a.lerp(b, (ts[i] + ts[i + 1]) * 0.5)
			if Geometry2D.is_point_in_polygon(mid, poly):
				pieces.append(PackedVector2Array([a.lerp(b, ts[i]), a.lerp(b, ts[i + 1])]))

	# 2. split parameters on every side and piece
	var side_split: Array = []
	for k in n:
		side_split.append([0.0, 1.0])
	var piece_split: Array = []
	for p in pieces:
		piece_split.append([0.0, 1.0])
	for j in pieces.size():
		for end_p in pieces[j]:
			for k in n:
				var a := poly[k]
				var b := poly[(k + 1) % n]
				if end_p.distance_to(Geometry2D.get_closest_point_to_segment(end_p, a, b)) < MERGE:
					side_split[k].append(clampf(_param(a, b, end_p), 0.0, 1.0))
	for j1 in pieces.size():
		for j2 in range(j1 + 1, pieces.size()):
			var hit = Geometry2D.segment_intersects_segment(pieces[j1][0], pieces[j1][1], pieces[j2][0], pieces[j2][1])
			if hit != null:
				piece_split[j1].append(_param(pieces[j1][0], pieces[j1][1], hit))
				piece_split[j2].append(_param(pieces[j2][0], pieces[j2][1], hit))

	# 3. edges
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + nrm * 0.2, poly):
			nrm = -nrm
		net._add_chain(a, b, side_split[k], KIND_SIDE, nrm)
	for j in pieces.size():
		var a := pieces[j][0]
		var b := pieces[j][1]
		var d := (b - a).normalized()
		net._add_chain(a, b, piece_split[j], KIND_PASSAGE, Vector2(-d.y, d.x))

	net._all_pairs()
	net._partition_shops(frontage)
	return net


# ---------------------------------------------------------------- construction

func _node(p: Vector2) -> int:
	for i in nodes.size():
		if nodes[i].distance_to(p) < MERGE:
			return i
	nodes.append(p)
	adj.append([])
	return nodes.size() - 1


func _add_chain(a: Vector2, b: Vector2, params: Array, kind: int, nrm: Vector2) -> void:
	params.sort()
	var prev := _node(a.lerp(b, params[0]))
	for i in range(1, params.size()):
		var cur := _node(a.lerp(b, params[i]))
		if cur != prev:
			_add_edge(prev, cur, kind, nrm)
		prev = cur


func _add_edge(u: int, v: int, kind: int, nrm: Vector2) -> void:
	var l := nodes[u].distance_to(nodes[v])
	if l < MERGE:
		return
	for e in edges:
		if (e["a"] == u and e["b"] == v) or (e["a"] == v and e["b"] == u):
			return
	var id := edges.size()
	edges.append({"a": u, "b": v, "len": l, "kind": kind,
			"dir": (nodes[v] - nodes[u]) / l, "normal": nrm})
	adj[u].append([v, l, id])
	adj[v].append([u, l, id])


## Dijkstra from every node, counting equal-length shortest paths (σ).
func _all_pairs() -> void:
	var n := nodes.size()
	dist.clear()
	sigma.clear()
	for s in n:
		var d := PackedFloat64Array()
		d.resize(n)
		d.fill(INF)
		var sg := PackedFloat64Array()
		sg.resize(n)
		var done := PackedByteArray()
		done.resize(n)
		d[s] = 0.0
		sg[s] = 1.0
		for _it in n:
			var u := -1
			var bd := INF
			for i in n:
				if done[i] == 0 and d[i] < bd:
					bd = d[i]
					u = i
			if u < 0:
				break
			done[u] = 1
			for item in adj[u]:
				var v: int = item[0]
				var nd: float = d[u] + float(item[1])
				if nd < d[v] - TIE:
					d[v] = nd
					sg[v] = sg[u]
				elif absf(nd - d[v]) <= TIE and done[v] == 0:
					sg[v] += sg[u]
		dist.append(d)
		sigma.append(sg)


# ---------------------------------------------------------------- shop subdivision

func _partition_shops(frontage: float) -> void:
	shops.clear()
	edge_shops.clear()
	for e in edges.size():
		edge_shops.append(PackedInt32Array())
	block_area = absf(poly_area(polygon))
	shop_area = 0.0
	_make_bands()
	faces = _faces()
	for face in faces:
		_partition_face(face, frontage)


## Setback bands: rectangles of half-width `setback` around each passage axis (square caps
## so crossings and junctions close cleanly), and optional bands along the inside of the
## drawn outline. Side traffic needs no band: its axis is already outside the outline.
func _make_bands() -> void:
	bands.clear()
	band_draw.clear()
	if setback_passage > 0.01:
		for e in edges:
			if e["kind"] == KIND_PASSAGE:
				_add_band(nodes[e["a"]], nodes[e["b"]], setback_passage)
	if setback_side > 0.01:
		var n := polygon.size()
		for k in n:
			_add_band(polygon[k], polygon[(k + 1) % n], setback_side)


func _add_band(a: Vector2, b: Vector2, h: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * h
	var a2 := a - d * h
	var b2 := b + d * h
	var band := PackedVector2Array([a2 + n, b2 + n, b2 - n, a2 - n])
	bands.append(band)
	for piece in Geometry2D.intersect_polygons(band, polygon):
		band_draw.append(piece)


## Passage edges that really cut the block: prune dead-end spurs, then order the rest
## outward from the boundary so every cut starts on an already-cut line (no holes).
func _cut_edges() -> Array[int]:
	var alive := {}
	for ei in edges.size():
		alive[ei] = true
	var changed := true
	while changed:
		changed = false
		var deg := PackedInt32Array()
		deg.resize(nodes.size())
		for ei in alive:
			deg[edges[ei]["a"]] += 1
			deg[edges[ei]["b"]] += 1
		for ei in alive.keys():
			if deg[edges[ei]["a"]] <= 1 or deg[edges[ei]["b"]] <= 1:
				alive.erase(ei)
				changed = true
	var reached := {}
	var pending: Array[int] = []
	for ei in alive:
		if edges[ei]["kind"] == KIND_SIDE:
			reached[edges[ei]["a"]] = true
			reached[edges[ei]["b"]] = true
		else:
			pending.append(ei)
	var order: Array[int] = []
	var progress := true
	while progress:
		progress = false
		for ei in pending.duplicate():
			var a: int = edges[ei]["a"]
			var b: int = edges[ei]["b"]
			if reached.has(a) or reached.has(b):
				order.append(ei)
				reached[a] = true
				reached[b] = true
				pending.erase(ei)
				progress = true
	return order


## The block cut along the through-passages (each cut is a hair-thin strip).
func _faces() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = [_ccw(axis_polygon.duplicate())]
	for ei in _cut_edges():
		var a: Vector2 = nodes[edges[ei]["a"]]
		var b: Vector2 = nodes[edges[ei]["b"]]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * CUT_HALF
		var a2 := a - d * 0.1
		var b2 := b + d * 0.1
		var strip := PackedVector2Array([a2 + n, b2 + n, b2 - n, a2 - n])
		var cut_faces: Array[PackedVector2Array] = []
		for f in out:
			for r in Geometry2D.clip_polygons(f, strip):
				if absf(poly_area(r)) > 0.5:
					cut_faces.append(_ccw(r))
		out = cut_faces
	return out


## Equal seeds along each frontage edge, then the Voronoi cell of each seed in the face.
func _partition_face(face: PackedVector2Array, frontage: float) -> void:
	var m := face.size()
	if m < 3:
		return
	var seeds: Array[Dictionary] = []          # {p, test, edge, width}
	for k in m:
		var a := face[k]
		var b := face[(k + 1) % m]
		var l := a.distance_to(b)
		if l < MIN_FRONT:
			continue
		var mid := (a + b) * 0.5
		var ne := _nearest_edge(mid, FRONT_TOL)
		if ne < 0:
			continue
		var d := (b - a) / l
		var nin := Vector2(-d.y, d.x)
		if not Geometry2D.is_point_in_polygon(mid + nin * 0.05, face):
			nin = -nin
		var count := maxi(1, int(round(l / frontage)))
		var wdt := l / float(count)
		for s in count:
			var p := a + d * (wdt * (float(s) + 0.5))
			seeds.append({"p": p, "test": p + nin * 0.05, "edge": ne, "width": wdt})

	for i in seeds.size():
		var pi_: Vector2 = seeds[i]["p"]
		var keep: Vector2 = seeds[i]["test"]
		var cell := face
		for j in seeds.size():
			if j == i:
				continue
			var pj: Vector2 = seeds[j]["p"]
			# points closer to seed i than to seed j:  (pj − pi)·x ≤ (|pj|² − |pi|²) / 2
			cell = _clip_half(cell, pj - pi_, (pj.length_squared() - pi_.length_squared()) * 0.5, keep)
			if cell.size() < 3:
				break
		if cell.size() < 3:
			continue
		cell = _carve_setbacks(cell)
		var area := absf(poly_area(cell))
		if cell.size() < 3 or area < 0.05:
			continue
		_add_shop(cell, area, seeds[i]["edge"], pi_, seeds[i]["width"])


## Clip a Voronoi cell to the drawn outline, then remove the setback bands (keep main piece).
func _carve_setbacks(cell: PackedVector2Array) -> PackedVector2Array:
	cell = _largest(Geometry2D.intersect_polygons(cell, polygon))
	for band in bands:
		if cell.size() < 3:
			break
		var res := Geometry2D.clip_polygons(cell, band)
		if res.size() == 1:
			cell = res[0]
			continue
		# several pieces (or outer + hole): keep the largest — a hole is always smaller
		cell = _largest(res)
	return cell


static func _largest(polys: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_a := 0.0
	for r in polys:
		var ar := absf(poly_area(r))
		if ar > best_a:
			best_a = ar
			best = r
	return best


## Mitred outward offset that keeps one vertex per corner (very sharp spikes are capped).
static func offset_miter(poly: PackedVector2Array, h: float) -> PackedVector2Array:
	var n := poly.size()
	if h <= 0.0 or n < 3:
		return poly.duplicate()
	var normals: Array[Vector2] = []
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var d := (b - a).normalized()
		var nr := Vector2(-d.y, d.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + nr * 0.01, poly):
			nr = -nr
		normals.append(nr)
	var out := PackedVector2Array()
	for k in n:
		var prev := (k - 1 + n) % n
		var v := poly[k]
		var hit = Geometry2D.line_intersects_line(poly[prev] + normals[prev] * h, v - poly[prev],
				v + normals[k] * h, poly[(k + 1) % n] - v)
		var p: Vector2 = v + normals[k] * h if hit == null else hit
		if p.distance_to(v) > 4.0 * h:
			p = v + (p - v).normalized() * 4.0 * h
		out.append(p)
	return out


func _add_shop(poly: PackedVector2Array, area: float, ei: int, seed_p: Vector2, width: float) -> void:
	var ea: Vector2 = nodes[edges[ei]["a"]]
	var dir: Vector2 = edges[ei]["dir"]
	var l: float = edges[ei]["len"]
	var x := clampf((seed_p - ea).dot(dir), 0.0, l)
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= float(poly.size())
	var id := shops.size()
	shops.append({"edge": ei, "x": x, "x0": maxf(0.0, x - width * 0.5), "x1": minf(l, x + width * 0.5),
			"frontage": width, "seed": seed_p, "door": _closest_on_polygon(seed_p, poly),
			"poly": poly, "center": c, "area": area})
	var es := edge_shops[ei]
	es.append(id)
	edge_shops[ei] = es
	shop_area += area


## poly ∩ {p : m·p ≤ k}. If the result has several pieces (concave faces), keep the one
## containing `keep` (the seed), otherwise the largest.
func _clip_half(poly: PackedVector2Array, mv: Vector2, k: float, keep := Vector2(INF, INF)) -> PackedVector2Array:
	if poly.size() < 3:
		return PackedVector2Array()
	var ln := mv.length()
	if ln < 1e-9:
		return poly if k >= 0.0 else PackedVector2Array()
	var mh := mv / ln
	var p0 := mh * (k / ln)
	var t := Vector2(-mh.y, mh.x)
	var hp := PackedVector2Array([p0 + t * BIG, p0 + t * BIG - mh * BIG, p0 - t * BIG - mh * BIG, p0 - t * BIG])
	var res := Geometry2D.intersect_polygons(poly, hp)
	if res.size() == 1:
		return res[0]
	var best := PackedVector2Array()
	var best_a := 0.0
	for r in res:
		if keep.x != INF and Geometry2D.is_point_in_polygon(keep, r):
			return r
		var ar := absf(poly_area(r))
		if ar > best_a:
			best_a = ar
			best = r
	return best


func _nearest_edge(p: Vector2, tol: float) -> int:
	var best := -1
	var best_d := tol
	for ei in edges.size():
		var a: Vector2 = nodes[edges[ei]["a"]]
		var b: Vector2 = nodes[edges[ei]["b"]]
		var dd := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
		if dd < best_d:
			best_d = dd
			best = ei
	return best


static func poly_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	var n := poly.size()
	for i in n:
		s += poly[i].cross(poly[(i + 1) % n])
	return s * 0.5


static func _closest_on_polygon(p: Vector2, poly: PackedVector2Array) -> Vector2:
	var best := p
	var best_d := INF
	var n := poly.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


static func _ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	return poly


# ---------------------------------------------------------------- helpers

func point_on_edge(e: int, x: float) -> Vector2:
	return nodes[edges[e]["a"]] + (edges[e]["dir"] as Vector2) * x


func shop_at(p: Vector2) -> int:
	for s in shops.size():
		if Geometry2D.is_point_in_polygon(p, shops[s]["poly"]):
			return s
	return -1


static func _param(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9)


## Compass name of each corner seen from the centroid (duplicates get a number).
static func compass_names(poly: PackedVector2Array) -> Array[String]:
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
