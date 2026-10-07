class_name TrafficSim
extends RefCounted
## Layer 1 — pedestrian traffic on our side (sidewalk ring + passages through the block).
##
## Walkers appear at the block corners according to the corner-pair matrix (Poisson,
## persons / min, 1 step = 1 s). Through walkers go corner → corner. Shop visitors go
## corner → a generic shop → back to their corner (shop chosen by distance only, logit).
##
## The only cost is time. Walking speed falls with crowd density in the cell:
##     v(ρ) = 1                            ρ ≤ 1 person / cell
##     v(ρ) = 1 − (ρ − 1) / (ρ_jam − 1)    otherwise, floored at v_min
## A walker accumulates v each step and moves when it has covered the step length
## (1 orthogonal, √2 diagonal).
## Route choice: descend a cost-to-go field toward the destination.
##   congestion-aware: Dijkstra on cell cost 1 / v(ρ̄) (ρ̄ = smoothed density), refreshed
##                     round-robin, plus the fresh local cost of the next cell.
##   naive:            free-flow shortest paths; among equal options, the emptier cell.
## Efficiency = Σ free-flow time ÷ Σ actual travel time (1.0 = nobody is slowed down).

const WALKING := 0
const IN_SHOP := 1
const DONE := 2
const MAX_TRIP := 3600


class Walker:
	var cell := 0
	var origin := 0
	var dest_zone := 0
	var shopper := false
	var shop := -1
	var to_shop := false
	var state := 0
	var progress := 0.0
	var t := 0
	var free_time := 0.0
	var dwell := 0
	var used_interior := false
	var offset := Vector2.ZERO


var grid: StreetGrid
var od: ODMatrix
var rng := RandomNumberGenerator.new()

# --- parameters
var demand_scale := 1.0
var jam_density := 8.0         # persons per cell at which walking stops (≈ 5 / m²)
var min_speed := 0.08
var crowd_level := 3           # persons per cell counted as "crowded" (≈ 1.8 / m²)
var congestion_routing := true
var shop_theta := 20.0         # logit distance scale for choosing a shop (cells)
var dwell_min := 40
var dwell_max := 160

# --- state
var walkers: Array[Walker] = []
var count := PackedInt32Array()      # persons per cell, this step
var density := PackedFloat32Array()  # smoothed persons per cell
var cost := PackedFloat32Array()     # seconds per unit length through a cell
var gate_field: Array[PackedFloat32Array] = []
var unit_field: Array[PackedFloat32Array] = []
var step_count := 0
var population := 0
var _gate_cursor := 0
var _unit_cursor := 0

# --- accumulated since (re)start: shop exposure
var unit_passers := PackedInt32Array()
var unit_visits := PackedInt32Array()

# --- efficiency metrics (since measure_from)
var measure_from := 0
var through_trips := 0
var through_time := 0
var through_free := 0.0
var through_interior := 0
var shop_trips := 0
var shop_time := 0
var shop_free := 0.0
var person_steps := 0
var crowded_steps := 0
var peak_density := 0.0
var series_eff := PackedFloat32Array()
var series_pop := PackedFloat32Array()
var _win_time := 0
var _win_free := 0.0


func _init(p_grid: StreetGrid, p_od: ODMatrix) -> void:
	grid = p_grid
	od = p_od


func reset(p_seed: int) -> void:
	rng.seed = p_seed
	walkers.clear()
	step_count = 0
	population = 0
	var n := grid.w * grid.h
	count = PackedInt32Array()
	count.resize(n)
	density = PackedFloat32Array()
	density.resize(n)
	cost = PackedFloat32Array()
	cost.resize(n)
	cost.fill(1.0)
	gate_field.clear()
	for z in grid.gates.size():
		gate_field.append(grid.gate_dist[z].duplicate())
	unit_field.clear()
	for u in grid.units.size():
		unit_field.append(grid.unit_dist[u].duplicate())
	unit_passers = PackedInt32Array()
	unit_passers.resize(grid.units.size())
	unit_visits = PackedInt32Array()
	unit_visits.resize(grid.units.size())
	series_eff = PackedFloat32Array()
	series_pop = PackedFloat32Array()
	_gate_cursor = 0
	_unit_cursor = 0
	measure_from = 0
	_clear_metrics()


func _clear_metrics() -> void:
	through_trips = 0
	through_time = 0
	through_free = 0.0
	through_interior = 0
	shop_trips = 0
	shop_time = 0
	shop_free = 0.0
	person_steps = 0
	crowded_steps = 0
	peak_density = 0.0
	_win_time = 0
	_win_free = 0.0


func step() -> void:
	_spawn_all()

	count.fill(0)
	population = 0
	for a in walkers:
		if a.state == WALKING:
			count[a.cell] += 1
			population += 1
	var measuring := step_count >= measure_from
	for i in grid.walk_cells:
		var d := density[i] * 0.92 + float(count[i]) * 0.08
		density[i] = d
		cost[i] = 1.0 / speed(d)
		if measuring and d > peak_density:
			peak_density = d

	if congestion_routing and not grid.gates.is_empty():
		gate_field[_gate_cursor] = grid.dijkstra(grid.gates[_gate_cursor], cost)
		_gate_cursor = (_gate_cursor + 1) % grid.gates.size()
		if not grid.units.is_empty():
			var door: int = grid.units[_unit_cursor]["door"]
			unit_field[_unit_cursor] = grid.dijkstra(PackedInt32Array([door]), cost)
			_unit_cursor = (_unit_cursor + 1) % grid.units.size()

	for a in walkers:
		if a.state == WALKING:
			_walk(a, measuring)
		elif a.state == IN_SHOP:
			a.dwell -= 1
			if a.dwell <= 0:
				a.state = WALKING

	step_count += 1
	if step_count % 60 == 0:
		series_eff.append(_win_free / float(_win_time) if _win_time > 0 else 1.0)
		series_pop.append(float(population))
		_win_time = 0
		_win_free = 0.0
		var alive: Array[Walker] = []
		for a in walkers:
			if a.state != DONE:
				alive.append(a)
		walkers = alive


func speed(rho: float) -> float:
	if rho <= 1.0:
		return 1.0
	return clampf(1.0 - (rho - 1.0) / (jam_density - 1.0), min_speed, 1.0)


# ---------------------------------------------------------------- walking

func _walk(a: Walker, measuring: bool) -> void:
	a.t += 1
	if a.t > MAX_TRIP:
		a.state = DONE           # safety valve: drop walkers that got stuck
		return
	if measuring:
		person_steps += 1
		if count[a.cell] >= crowd_level:
			crowded_steps += 1
	a.progress = minf(a.progress + speed(float(count[a.cell])), 2.0)
	var k := _next_index(a)
	if k < 0:
		return
	var ln: float = grid.nlen[a.cell][k]
	if a.progress < ln:
		return
	a.progress -= ln
	var nxt: int = grid.neighbors[a.cell][k]
	a.cell = nxt
	if grid.interior[nxt] == 1:
		a.used_interior = true
	for u in grid.frontage[nxt]:
		unit_passers[u] += 1
	if _free_field(a)[nxt] <= 0.0:
		_arrive(a)


func _free_field(a: Walker) -> PackedFloat32Array:
	return grid.unit_dist[a.shop] if a.to_shop else grid.gate_dist[a.dest_zone]


## Index into grid.neighbors[a.cell] of the next step, or -1.
func _next_index(a: Walker) -> int:
	var nbs: PackedInt32Array = grid.neighbors[a.cell]
	var lens: PackedFloat32Array = grid.nlen[a.cell]
	var best := -1
	if congestion_routing:
		var f: PackedFloat32Array = unit_field[a.shop] if a.to_shop else gate_field[a.dest_zone]
		var here := f[a.cell]
		var best_v := INF
		for k in nbs.size():
			var nb := nbs[k]
			if f[nb] >= here:
				continue
			var v := f[nb] + lens[k] / speed(float(count[nb]) + 1.0)
			if v < best_v - 1e-4 or (absf(v - best_v) <= 1e-4 and rng.randf() < 0.5):
				best_v = v
				best = k
		if best >= 0:
			return best
	var free := _free_field(a)
	var here_f := free[a.cell]
	var best_c := 1 << 30
	for k in nbs.size():
		var nb := nbs[k]
		if absf(free[nb] + lens[k] - here_f) > 1e-3:
			continue                  # not on a shortest path
		var c := count[nb]
		if c < best_c or (c == best_c and rng.randf() < 0.5):
			best_c = c
			best = k
	return best


func _arrive(a: Walker) -> void:
	if a.to_shop:
		a.to_shop = false
		a.state = IN_SHOP
		a.dwell = rng.randi_range(dwell_min, dwell_max)
		unit_visits[a.shop] += 1
		return
	a.state = DONE
	_win_time += a.t
	_win_free += a.free_time
	if step_count < measure_from:
		return
	if a.shopper:
		shop_trips += 1
		shop_time += a.t
		shop_free += a.free_time
	else:
		through_trips += 1
		through_time += a.t
		through_free += a.free_time
		if a.used_interior:
			through_interior += 1


# ---------------------------------------------------------------- demand

func _spawn_all() -> void:
	var nz := mini(od.zones, grid.gates.size())
	for o in nz:
		for d in nz + 1:
			if d == o:
				continue
			var is_shop := d == nz
			var rate := od.get_rate(o, od.shop_col() if is_shop else d)
			# corner pairs are two-way totals: each direction gets half
			var lam := rate * (1.0 if is_shop else 0.5) * demand_scale / 60.0
			if lam <= 0.0:
				continue
			var n := int(lam)
			if rng.randf() < lam - float(n):
				n += 1
			for _i in n:
				_spawn(o, -1 if is_shop else d)


## d = destination corner, or -1 for a shop visit.
func _spawn(o: int, d: int) -> void:
	var gate: PackedInt32Array = grid.gates[o]
	if gate.is_empty():
		return
	var a := Walker.new()
	a.cell = gate[rng.randi() % gate.size()]
	a.origin = o
	a.offset = Vector2(rng.randf_range(-0.28, 0.28), rng.randf_range(-0.28, 0.28))
	if d < 0:
		if grid.units.is_empty():
			return
		a.shop = _choose_shop(a.cell)
		if a.shop < 0:
			return
		a.shopper = true
		a.to_shop = true
		a.dest_zone = o
		var door: int = grid.units[a.shop]["door"]
		a.free_time = grid.unit_dist[a.shop][a.cell] + grid.gate_dist[o][door]
	else:
		a.dest_zone = d
		a.free_time = grid.gate_dist[d][a.cell]
		if a.free_time <= 0.0 or a.free_time == INF:
			return
	if a.free_time == INF:
		return
	walkers.append(a)


## Generic shops are identical, so only distance matters.
func _choose_shop(from_cell: int) -> int:
	var nu := grid.units.size()
	var weights := PackedFloat32Array()
	weights.resize(nu)
	var total := 0.0
	for u in nu:
		var dd: float = grid.unit_dist[u][from_cell]
		var wgt := exp(-dd / shop_theta) if dd < INF else 0.0
		weights[u] = wgt
		total += wgt
	if total <= 0.0:
		return -1
	var r := rng.randf() * total
	for u in nu:
		r -= weights[u]
		if r <= 0.0:
			return u
	return nu - 1


# ---------------------------------------------------------------- summary

func efficiency() -> float:
	var t := through_time + shop_time
	return (through_free + shop_free) / float(t) if t > 0 else 1.0


func through_efficiency() -> float:
	return through_free / float(through_time) if through_time > 0 else 1.0


func shop_efficiency() -> float:
	return shop_free / float(shop_time) if shop_time > 0 else 1.0


func mean_delay() -> float:
	var n := through_trips + shop_trips
	return (float(through_time + shop_time) - through_free - shop_free) / float(n) if n > 0 else 0.0


func crowded_share() -> float:
	return float(crowded_steps) / float(person_steps) if person_steps > 0 else 0.0


func interior_share() -> float:
	return float(through_interior) / float(through_trips) if through_trips > 0 else 0.0


func minutes_measured() -> float:
	return float(step_count - measure_from) / 60.0
