class_name CustomerSim
extends RefCounted
## Agent-based shopper simulation on a MallLayout with a given tenant assignment.
##
## Each shopper arrives at an entrance with a shopping list (categories) and a
## time budget. They walk to the nearest shop that sells the next item on the list.
## While walking they are exposed to every shopfront they pass, and may walk in
## on impulse. Comparison goods (fashion, electronics, department) make shoppers
## visit rival shops before buying; tired shoppers are drawn to cafés, which
## let them stay longer. When the list is done or time runs out, they leave
## by the nearest entrance.
##
## Runs identically with or without rendering, so the optimiser uses it headless.

const TO_TARGET := 0
const IN_SHOP := 1
const LEAVING := 2
const DONE := 3


class Agent:
	var cell := 0
	var profile := 0
	var wants: Array[int] = []
	var visited := {}
	var attempts := {}
	var target := -1
	var impulse := false
	var state := 0
	var dwell := 0
	var t := 0
	var budget := 100.0
	var offset := Vector2.ZERO


var layout: MallLayout
var catalog: Catalog
var assignment := PackedInt32Array()
var rng := RandomNumberGenerator.new()

# parameters
var total_customers := 300
var spawn_steps := 200
var max_steps := 2500

# state
var agents: Array[Agent] = []
var step_count := 0
var spawned := 0
var active := 0
var _spawn_acc := 0.0
var _cat_units: Array[PackedInt32Array] = []
var _entrance_cdf := PackedFloat32Array()
var _profile_cdf := PackedFloat32Array()

# metrics
var unit_visits := PackedInt32Array()
var unit_sales := PackedInt32Array()
var unit_revenue := PackedFloat32Array()
var unit_passers := PackedInt32Array()
var heat := PackedInt32Array()
var revenue := 0.0
var sales := 0
var unmet := 0
var finished := 0
var total_time := 0


func _init(p_layout: MallLayout, p_catalog: Catalog) -> void:
	layout = p_layout
	catalog = p_catalog
	var acc := 0.0
	for e in layout.entrances:
		acc += float(e["weight"])
		_entrance_cdf.append(acc)
	acc = 0.0
	for p in catalog.profiles:
		acc += float(p["share"])
		_profile_cdf.append(acc)


func reset(p_assignment: PackedInt32Array, p_seed: int) -> void:
	assignment = p_assignment.duplicate()
	rng.seed = p_seed
	agents.clear()
	step_count = 0
	spawned = 0
	active = 0
	_spawn_acc = 0.0
	revenue = 0.0
	sales = 0
	unmet = 0
	finished = 0
	total_time = 0
	var nu := layout.units.size()
	unit_visits = PackedInt32Array()
	unit_visits.resize(nu)
	unit_sales = PackedInt32Array()
	unit_sales.resize(nu)
	unit_passers = PackedInt32Array()
	unit_passers.resize(nu)
	unit_revenue = PackedFloat32Array()
	unit_revenue.resize(nu)
	heat = PackedInt32Array()
	heat.resize(layout.w * layout.h)   # packed arrays resize to zeros

	var lists := []
	for c in catalog.categories.size():
		lists.append([])
	for u in nu:
		lists[assignment[u]].append(u)
	_cat_units.clear()
	for c in catalog.categories.size():
		_cat_units.append(PackedInt32Array(lists[c]))


func is_finished() -> bool:
	return (spawned >= total_customers and active == 0) or step_count >= max_steps


func run_to_end() -> void:
	while not is_finished():
		step()


func avg_time() -> float:
	return float(total_time) / float(maxi(finished, 1))


func step() -> void:
	if spawned < total_customers:
		_spawn_acc += float(total_customers) / float(spawn_steps)
		while _spawn_acc >= 1.0 and spawned < total_customers:
			_spawn_acc -= 1.0
			_spawn()
	for a in agents:
		if a.state != DONE:
			_update(a)
	step_count += 1


# ---------------------------------------------------------------- agents

func _spawn() -> void:
	var a := Agent.new()
	a.profile = _pick_cdf(_profile_cdf)
	var e := _pick_cdf(_entrance_cdf)
	a.cell = layout.entrances[e]["cell"]
	var prof: Dictionary = catalog.profiles[a.profile]
	a.budget = float(prof["budget"]) * rng.randf_range(0.8, 1.2)
	a.wants = _sample_wants(prof)
	a.offset = Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
	agents.append(a)
	spawned += 1
	active += 1
	_choose_next(a)


func _update(a: Agent) -> void:
	a.t += 1
	match a.state:
		IN_SHOP:
			a.dwell -= 1
			if a.dwell <= 0:
				_finish_visit(a)
		TO_TARGET:
			var field: PackedInt32Array = layout.unit_dist[a.target]
			if field[a.cell] <= 0:
				_enter(a)
			else:
				_move(a, field)
				_look_around(a)
		LEAVING:
			if layout.exit_dist[a.cell] <= 0:
				_done(a)
			else:
				_move(a, layout.exit_dist)
				_look_around(a)


## Step downhill on a distance field; ties broken randomly (spreads crowds).
func _move(a: Agent, field: PackedInt32Array) -> void:
	var here := field[a.cell]
	var options := PackedInt32Array()
	for nb in layout.neighbors[a.cell]:
		if field[nb] >= 0 and field[nb] < here:
			options.append(nb)
	if options.is_empty():
		return
	a.cell = options[rng.randi() % options.size()]
	heat[a.cell] += 1


## Shopfront exposure and impulse visits.
func _look_around(a: Agent) -> void:
	var fronting: PackedInt32Array = layout.frontage[a.cell]
	for u in fronting:
		unit_passers[u] += 1
	if a.impulse:
		return
	for u in fronting:
		if u == a.target or a.visited.has(u):
			continue
		var cat := assignment[u]
		if cat == Catalog.VACANT:
			continue
		var p := _impulse_prob(a, cat)
		if a.state == LEAVING:
			p *= 0.5
		if rng.randf() < p:
			a.target = u
			a.impulse = true
			a.state = TO_TARGET
			return


func _impulse_prob(a: Agent, cat: int) -> float:
	var c: Dictionary = catalog.categories[cat]
	var prof: Dictionary = catalog.profiles[a.profile]
	var fatigue := clampf(float(a.t) / a.budget, 0.0, 1.0)
	var p: float = float(c["impulse"]) * float(prof["browse"]) * catalog.interest(a.profile, cat)
	if cat == Catalog.CAFE:
		p *= 0.3 + 2.5 * fatigue          # tired shoppers sit down
	else:
		p *= 1.0 - fatigue
	if bool(c["comparison"]) and a.wants.has(cat):
		p += 0.4 * (1.0 - fatigue)        # "let's also look in this one"
	return clampf(p, 0.0, 0.95)


func _enter(a: Agent) -> void:
	var u := a.target
	var cat := assignment[u]
	a.state = IN_SHOP
	a.dwell = int(catalog.categories[cat]["dwell"])
	a.visited[u] = true
	unit_visits[u] += 1


func _finish_visit(a: Agent) -> void:
	var u := a.target
	var cat := assignment[u]
	var c: Dictionary = catalog.categories[cat]
	var wanted := a.wants.has(cat)
	var conv: float = float(c["conversion"]) if wanted else float(c["conversion"]) * 0.4
	if rng.randf() < conv:
		var amount: float = float(c["spend"]) * rng.randf_range(0.6, 1.4)
		revenue += amount
		sales += 1
		unit_sales[u] += 1
		unit_revenue[u] += amount
		if wanted:
			a.wants.erase(cat)
	elif wanted:
		var n: int = a.attempts.get(cat, 0) + 1
		a.attempts[cat] = n
		var limit := 3 if bool(c["comparison"]) else 1
		if n >= limit:
			a.wants.erase(cat)
			unmet += 1
	if cat == Catalog.CAFE:
		a.budget += 60.0                  # a rest extends the visit
	_choose_next(a)


## Greedy: go to the nearest unvisited shop selling anything still on the list.
func _choose_next(a: Agent) -> void:
	a.impulse = false
	a.target = -1
	if float(a.t) >= a.budget:
		unmet += a.wants.size()
		a.wants.clear()
	var best := -1
	var best_d := 1 << 30
	for cat in a.wants.duplicate():
		var found := false
		for u in _cat_units[cat]:
			if a.visited.has(u):
				continue
			var d: int = layout.unit_dist[u][a.cell]
			if d < 0:
				continue
			found = true
			if d < best_d:
				best_d = d
				best = u
		if not found:
			a.wants.erase(cat)
			unmet += 1
	if best == -1:
		a.state = LEAVING
	else:
		a.target = best
		a.state = TO_TARGET


func _done(a: Agent) -> void:
	a.state = DONE
	active -= 1
	finished += 1
	total_time += a.t


# ---------------------------------------------------------------- helpers

func _pick_cdf(cdf: PackedFloat32Array) -> int:
	var r := rng.randf() * cdf[cdf.size() - 1]
	for i in cdf.size():
		if r <= cdf[i]:
			return i
	return cdf.size() - 1


func _sample_wants(prof: Dictionary) -> Array[int]:
	var weights: Dictionary = prof["wants"]
	var pool: Array = weights.keys()
	var k := rng.randi_range(int(prof["min"]), int(prof["max"]))
	var out: Array[int] = []
	while out.size() < k and pool.size() > 0:
		var total := 0.0
		for c in pool:
			total += float(weights[c])
		var r := rng.randf() * total
		var pick = pool[pool.size() - 1]
		for c in pool:
			r -= float(weights[c])
			if r <= 0.0:
				pick = c
				break
		out.append(int(pick))
		pool.erase(pick)
	return out
