class_name StreetGrid
extends RefCounted
## Rasterised spatial model for Layer 1.
##   WALK — public realm on OUR side only: the sidewalk ring around the block polygon,
##          plus arcades / plazas inside it
##   UNIT — generic shop units (arbitrary cell sets, so they can follow diagonal edges)
##   VOID — carriageway, far side of the street, back-of-house
## Movement is 8-connected (diagonal step = √2, no cutting past a blocked corner).
## Gates are the block's corners (polygon vertices).
##
## Scale: 1 cell ≈ 1.3 m, 1 step ≈ 1 s → free walking speed = 1 cell / step.

const VOID := 0
const WALK := 1
const UNIT := 2
const SQRT2 := 1.41421356

var title := ""
var w := 0
var h := 0
var cells := PackedInt32Array()
var unit_of := PackedInt32Array()              # cell -> unit index, or -1
var interior := PackedByteArray()              # 1 = inside the block polygon
var polygon := PackedVector2Array()
var units: Array[Dictionary] = []              # {cells, area, door, center}
var gates: Array[PackedInt32Array] = []        # corner -> its cells
var gate_points := PackedVector2Array()
var gate_names: Array[String] = []
var walk_cells := PackedInt32Array()
var neighbors: Array[PackedInt32Array] = []    # walk cell -> walkable neighbours (8-conn.)
var nlen: Array[PackedFloat32Array] = []       # matching step lengths (1 or √2)
var frontage: Array[PackedInt32Array] = []     # walk cell -> units it faces
var gate_dist: Array[PackedFloat32Array] = []  # free-flow distance to each corner
var unit_dist: Array[PackedFloat32Array] = []  # free-flow distance to each shop door


func _init(p_title: String, p_w: int, p_h: int) -> void:
	title = p_title
	w = p_w
	h = p_h
	cells.resize(w * h)
	cells.fill(VOID)
	unit_of.resize(w * h)
	unit_of.fill(-1)
	interior.resize(w * h)


func idx(x: int, y: int) -> int:
	return y * w + x


@warning_ignore("integer_division")
func cell_xy(i: int) -> Vector2i:
	return Vector2i(i % w, i / w)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func is_walk(i: int) -> bool:
	return cells[i] == WALK


func is_walk_xy(x: int, y: int) -> bool:
	return in_bounds(x, y) and cells[idx(x, y)] == WALK


func add_unit_cells(list: PackedInt32Array) -> void:
	var id := units.size()
	var c := Vector2.ZERO
	for i in list:
		cells[i] = UNIT
		unit_of[i] = id
		c += Vector2(cell_xy(i)) + Vector2(0.5, 0.5)
	units.append({"cells": list, "area": list.size(), "door": -1, "center": c / float(list.size())})


func add_gate(point: Vector2, list: PackedInt32Array, p_name: String) -> void:
	gate_points.append(point)
	gates.append(list)
	gate_names.append(p_name)


func finalize() -> void:
	var n := w * h
	neighbors.resize(n)
	nlen.resize(n)
	frontage.resize(n)
	walk_cells = PackedInt32Array()
	for y in h:
		for x in w:
			var i := idx(x, y)
			var nb := PackedInt32Array()
			var ln := PackedFloat32Array()
			var fr := PackedInt32Array()
			if is_walk(i):
				walk_cells.append(i)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dy == 0:
							continue
						var nx: int = x + dx
						var ny: int = y + dy
						if not in_bounds(nx, ny):
							continue
						var j := idx(nx, ny)
						if cells[j] == UNIT and not fr.has(unit_of[j]):
							fr.append(unit_of[j])
						if not is_walk(j):
							continue
						var diagonal: bool = dx != 0 and dy != 0
						if diagonal and not (is_walk_xy(x + dx, y) and is_walk_xy(x, y + dy)):
							continue
						nb.append(j)
						ln.append(SQRT2 if diagonal else 1.0)
			neighbors[i] = nb
			nlen[i] = ln
			frontage[i] = fr

	# Door = walk cell orthogonally next to the unit, closest to its centre.
	var dirs4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for u in units.size():
		var center: Vector2 = units[u]["center"]
		var best := -1
		var best_d := INF
		for i in units[u]["cells"]:
			var p := cell_xy(i)
			for d in dirs4:
				var q := p + d
				if not is_walk_xy(q.x, q.y):
					continue
				var dd := (Vector2(q) + Vector2(0.5, 0.5)).distance_squared_to(center)
				if dd < best_d:
					best_d = dd
					best = idx(q.x, q.y)
		units[u]["door"] = best

	var ones := PackedFloat32Array()
	ones.resize(n)
	ones.fill(1.0)
	gate_dist.clear()
	for z in gates.size():
		gate_dist.append(dijkstra(gates[z], ones))
	unit_dist.clear()
	for u in units.size():
		unit_dist.append(dijkstra(PackedInt32Array([units[u]["door"]]), ones))


## Cost-to-go field: f(u) = min over neighbours v of f(v) + cost[v] · len(u, v),
## i.e. the time to reach the sources, paying each cell's cost when stepping into it.
func dijkstra(sources: PackedInt32Array, cost: PackedFloat32Array) -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	dist.fill(INF)
	var heap := MinHeap.new()
	for s in sources:
		if s >= 0:
			dist[s] = 0.0
			heap.push(0.0, s)
	while heap.size() > 0:
		var v := heap.pop()
		var dv := heap.last_key
		if dv > dist[v]:
			continue
		var cv := cost[v]
		var nb: PackedInt32Array = neighbors[v]
		var ln: PackedFloat32Array = nlen[v]
		for k in nb.size():
			var u := nb[k]
			var cand := dv + cv * ln[k]
			if cand < dist[u]:
				dist[u] = cand
				heap.push(cand, u)
	return dist


class MinHeap:
	var keys := PackedFloat32Array()
	var vals := PackedInt32Array()
	var last_key := 0.0

	func size() -> int:
		return vals.size()

	func push(k: float, v: int) -> void:
		keys.append(k)
		vals.append(v)
		var i := vals.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> int:
		var top := vals[0]
		last_key = keys[0]
		var last := vals.size() - 1
		keys[0] = keys[last]
		vals[0] = vals[last]
		keys.resize(last)
		vals.resize(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < last and keys[l] < keys[m]:
				m = l
			if r < last and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tk := keys[a]
		keys[a] = keys[b]
		keys[b] = tk
		var tv := vals[a]
		vals[a] = vals[b]
		vals[b] = tv
