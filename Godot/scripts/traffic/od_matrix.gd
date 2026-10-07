class_name ODMatrix
extends RefCounted
## Demand on our side, persons per minute, for a block with `zones` corners.
## Corner pairs are undirected: rate(a, b) = rate(b, a) = two-way total, spawned half each way.
## Column `zones` (the last one) = shop visits: arrive at that corner, visit a generic shop,
## return to the same corner.

var zones := 4
var rates: Array[PackedFloat32Array] = []


func _init(n := 4) -> void:
	resize(n)


## Changing the number of corners resets the matrix to the balanced preset.
func resize(n: int) -> void:
	zones = n
	rates.clear()
	for o in n:
		var r := PackedFloat32Array()
		r.resize(n + 1)
		rates.append(r)
	preset_balanced()


func shop_col() -> int:
	return zones


func get_rate(o: int, d: int) -> float:
	return rates[o][d]


## Sets a corner pair (both directions) or a corner's shop rate (d == shop_col()).
func set_rate(o: int, d: int, v: float) -> void:
	if o == d:
		return
	v = clampf(v, 0.0, 999.0)
	_put(o, d, v)
	if d < zones:
		_put(d, o, v)


func _put(o: int, d: int, v: float) -> void:
	var r := rates[o]
	r[d] = v
	rates[o] = r


## Two corners joined by one side of the block.
func adjacent(a: int, b: int) -> bool:
	return (a + 1) % zones == b or (b + 1) % zones == a


func total() -> float:
	var s := 0.0
	for o in zones:
		for d in range(o + 1, zones):
			s += rates[o][d]
		s += rates[o][zones]
	return s


func copy() -> ODMatrix:
	var m := ODMatrix.new(zones)
	for o in zones:
		m.rates[o] = rates[o].duplicate()
	return m


func _fill(side_pair: float, across_pair: float, shoppers: float) -> void:
	for o in zones:
		for d in zones:
			if o != d:
				_put(o, d, side_pair if adjacent(o, d) else across_pair)
		_put(o, zones, shoppers)


## Every pair busy.
func preset_balanced() -> void:
	_fill(30.0, 20.0, 8.0)


## Pairs that are NOT on the same side dominate: the block is on the desire line.
func preset_across() -> void:
	_fill(6.0, 60.0, 6.0)


## One side (first two corners) carries most of the flow.
func preset_busy_side() -> void:
	_fill(6.0, 6.0, 6.0)
	set_rate(0, 1, 90.0)


func clear() -> void:
	_fill(0.0, 0.0, 0.0)
