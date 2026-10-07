class_name MallLayout
extends RefCounted
## Spatial model: a grid of cells. Walkable cells form the public realm,
## unit cells belong to shop units, entrances are where shoppers arrive and leave.
## finalize() precomputes shopfront exposure and walking-distance fields.

const VOID := 0
const WALK := 1
const UNIT := 2
const ENTRANCE := 3

var title := ""
var w := 0
var h := 0
var cells := PackedInt32Array()
var unit_of := PackedInt32Array()              # cell -> unit index, or -1
var units: Array[Dictionary] = []              # {rect: Rect2i, area: int, door: int}
var entrances: Array[Dictionary] = []          # {cell: int, weight: float}
var neighbors: Array[PackedInt32Array] = []    # walkable cell -> walkable neighbours
var frontage: Array[PackedInt32Array] = []     # walkable cell -> units whose front it passes
var unit_dist: Array[PackedInt32Array] = []    # unit -> walking distance field to its door
var exit_dist := PackedInt32Array()            # distance to the nearest entrance


func _init(p_title: String, p_w: int, p_h: int) -> void:
	title = p_title
	w = p_w
	h = p_h
	cells.resize(w * h)
	cells.fill(VOID)
	unit_of.resize(w * h)
	unit_of.fill(-1)


func idx(x: int, y: int) -> int:
	return y * w + x


@warning_ignore("integer_division")
func cell_xy(i: int) -> Vector2i:
	return Vector2i(i % w, i / w)


func is_walkable(i: int) -> bool:
	var c := cells[i]
	return c == WALK or c == ENTRANCE


func add_walk(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			cells[idx(x, y)] = WALK


func add_unit(r: Rect2i) -> void:
	var id := units.size()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			cells[idx(x, y)] = UNIT
			unit_of[idx(x, y)] = id
	units.append({"rect": r, "area": r.get_area(), "door": -1})


func add_entrance(x: int, y: int, weight: float) -> void:
	var i := idx(x, y)
	cells[i] = ENTRANCE
	entrances.append({"cell": i, "weight": weight})


func finalize() -> void:
	var n := w * h
	neighbors.resize(n)
	frontage.resize(n)
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in h:
		for x in w:
			var i := idx(x, y)
			var nb := PackedInt32Array()
			var fr := PackedInt32Array()
			if is_walkable(i):
				for d in dirs:
					var nx := x + d.x
					var ny := y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var j := idx(nx, ny)
					if is_walkable(j):
						nb.append(j)
					elif cells[j] == UNIT:
						var u := unit_of[j]
						if not fr.has(u):
							fr.append(u)
			neighbors[i] = nb
			frontage[i] = fr

	# Door = the frontage cell closest to the unit's centre.
	for u in units.size():
		var r: Rect2i = units[u]["rect"]
		var center := Vector2(r.position) + Vector2(r.size) * 0.5
		var best := -1
		var best_d := INF
		for i in n:
			if frontage[i].has(u):
				var d := (Vector2(cell_xy(i)) + Vector2(0.5, 0.5)).distance_squared_to(center)
				if d < best_d:
					best_d = d
					best = i
		units[u]["door"] = best

	unit_dist.clear()
	for u in units.size():
		unit_dist.append(bfs(PackedInt32Array([units[u]["door"]])))
	var exits := PackedInt32Array()
	for e in entrances:
		exits.append(e["cell"])
	exit_dist = bfs(exits)


## Multi-source breadth-first search over walkable cells (Manhattan steps).
func bfs(sources: PackedInt32Array) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue := PackedInt32Array()
	for s in sources:
		if s >= 0:
			dist[s] = 0
			queue.append(s)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for nb in neighbors[c]:
			if dist[nb] == -1:
				dist[nb] = dist[c] + 1
				queue.append(nb)
	return dist
