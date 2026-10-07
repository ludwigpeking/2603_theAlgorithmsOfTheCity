class_name TenantOptimizer
extends RefCounted
## Simulated annealing over tenant placement.
## A move swaps the tenants of two units (respecting unit-size constraints).
## Each candidate is scored by running the full shopper simulation headless.
## A fixed seed (common random numbers) keeps comparisons between candidates fair.

var layout: MallLayout
var catalog: Catalog
var sim: CustomerSim
var rng := RandomNumberGenerator.new()

var eval_seed := 12345
var start_temperature := 0.03   # relative: a 3 % worse move is accepted with p ≈ 1/e
var cooling := 0.992
var min_temperature := 0.0005

var current := PackedInt32Array()
var current_score := 0.0
var best := PackedInt32Array()
var best_score := 0.0
var best_unit_revenue := PackedFloat32Array()
var temperature := 0.03
var iteration := 0
var accepted := 0
var history_best := PackedFloat32Array()
var history_current := PackedFloat32Array()


func _init(p_layout: MallLayout, p_catalog: Catalog) -> void:
	layout = p_layout
	catalog = p_catalog
	sim = CustomerSim.new(layout, catalog)
	rng.seed = 777


func start(initial: PackedInt32Array) -> void:
	current = initial.duplicate()
	current_score = evaluate(current)
	best = current.duplicate()
	best_score = current_score
	best_unit_revenue = sim.unit_revenue.duplicate()
	temperature = start_temperature
	iteration = 0
	accepted = 0
	history_best = PackedFloat32Array([best_score])
	history_current = PackedFloat32Array([current_score])


## Objective: total sales revenue of the centre in one simulated run.
func evaluate(assign: PackedInt32Array) -> float:
	sim.reset(assign, eval_seed)
	sim.run_to_end()
	return sim.revenue


func step() -> void:
	var cand := _propose()
	if cand.is_empty():
		return
	var score := evaluate(cand)
	var delta := (score - current_score) / maxf(current_score, 1.0)
	if delta >= 0.0 or rng.randf() < exp(delta / temperature):
		current = cand
		current_score = score
		accepted += 1
		if score > best_score:
			best = cand.duplicate()
			best_score = score
			best_unit_revenue = sim.unit_revenue.duplicate()
	temperature = maxf(min_temperature, temperature * cooling)
	iteration += 1
	history_best.append(best_score)
	history_current.append(current_score)


func _propose() -> PackedInt32Array:
	var n := current.size()
	for _try in 50:
		var i := rng.randi_range(0, n - 1)
		var j := rng.randi_range(0, n - 1)
		if i == j or current[i] == current[j]:
			continue
		if not catalog.fits(current[j], layout.units[i]["area"]):
			continue
		if not catalog.fits(current[i], layout.units[j]["area"]):
			continue
		var cand := current.duplicate()
		cand[i] = current[j]
		cand[j] = current[i]
		return cand
	return PackedInt32Array()
