## ARCHIVED v0.1 main script (tenant mix + shopper profiles + simulated annealing).
## Kept for the later layers. Its dependencies are in scripts/core and scripts/view (ignored by Godot).
## To revive: move this file and those folders back together and remove the .gdignore files.

extends Node2D

const PANEL_W := 330.0
const TOP := 72.0
const INK := Color(0.12, 0.12, 0.12)
const MUTED := Color(0.45, 0.45, 0.45)
const BLUE := Color("#1a5faa")

var catalog := Catalog.new()
var layouts: Array[MallLayout] = []
var layout: MallLayout
var assignment := PackedInt32Array()
var live: CustomerSim
var optimizer: TenantOptimizer
var rng := RandomNumberGenerator.new()
var view: MallView
var chart: HistoryChart
var running := true
var optimizing := false
var live_seed := 1
var customers := 300
var speed := 3
var last_run := "—"
var selected_unit := -1


func _ready() -> void:
	rng.seed = 2026
	layouts.append(LayoutPresets.high_street())
	layouts.append(LayoutPresets.dumbbell())
	view = MallView.new()
	view.position = Vector2(28, TOP)
	add_child(view)
	layout = layouts[0]
	assignment = catalog.random_assignment(layout, rng)
	live = CustomerSim.new(layout, catalog)
	optimizer = TenantOptimizer.new(layout, catalog)
	view.layout = layout
	view.catalog = catalog
	view.sim = live
	live.total_customers = customers
	live.reset(assignment, live_seed)
	view.assignment = assignment


func _process(_delta: float) -> void:
	if optimizing:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 14:
			optimizer.step()
		assignment = optimizer.best
		view.assignment = assignment
		view.unit_revenue = optimizer.best_unit_revenue
	elif running:
		for _i in speed:
			if live.is_finished():
				live_seed += 1
				live.reset(assignment, live_seed)
				break
			live.step()
		view.unit_revenue = live.unit_revenue
	view.queue_redraw()

# (The full v0.1 control panel is omitted here; the traffic layer's UIKit supersedes it.)
