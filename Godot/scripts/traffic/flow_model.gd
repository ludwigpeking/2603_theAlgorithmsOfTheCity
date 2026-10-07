class_name FlowModel
extends RefCounted
## Deterministic flow assignment on the StreetNetwork. No congestion: everyone takes a
## shortest path; when several are equally short, the flow is split over them in
## proportion to the number of shortest paths through each edge (as in betweenness).
##
##   corner pairs: q persons / min (two-way total) between corners a and b
##   shop visits:  r persons / min arrive at corner c, choose a generic shop s with
##                 p ∝ exp(−distance / θ), walk there and back the same way (counts twice)
##
## A shop's traffic = everyone who walks past its frontage: the whole flow on its edge,
## plus shop visitors who walk along part of the edge to reach another shop on it.
## Reported per hour.

var net: StreetNetwork
var od: ODMatrix
var theta := 60.0          # m — how far shop visitors are willing to go (logit scale)

var edge_flow := PackedFloat64Array()      # persons / min, everyone
var edge_through := PackedFloat64Array()   # persons / min, corner-pair flows only
var shop_pass := PackedFloat64Array()      # persons / min past each shop front
var shop_pass_through := PackedFloat64Array()
var shop_visits := PackedFloat64Array()    # visits / min

# summary
var through_rate := 0.0
var through_person_m := 0.0     # person·m / min
var shopper_rate := 0.0
var shopper_person_m := 0.0
var passage_share := 0.0
var unreachable := 0.0


func _init(p_net: StreetNetwork, p_od: ODMatrix) -> void:
	net = p_net
	od = p_od


func compute() -> void:
	var ne := net.edges.size()
	var ns := net.shops.size()
	edge_flow = _zeros(ne)
	edge_through = _zeros(ne)
	shop_pass = _zeros(ns)
	shop_pass_through = _zeros(ns)
	shop_visits = _zeros(ns)
	through_rate = 0.0
	through_person_m = 0.0
	shopper_rate = 0.0
	shopper_person_m = 0.0
	unreachable = 0.0
	var nz := mini(od.zones, net.corner_nodes.size())

	# corner-pair (through) flows
	for a in nz:
		for b in range(a + 1, nz):
			var q := od.get_rate(a, b)
			if q <= 0.0:
				continue
			var ca := net.corner_nodes[a]
			var cb := net.corner_nodes[b]
			var d: float = net.dist[ca][cb]
			if d == INF:
				unreachable += q
				continue
			_add_flow(ca, cb, q)
			through_rate += q
			through_person_m += q * d
	edge_through = edge_flow.duplicate()

	# shop visitors
	var extra := _zeros(ns)
	if ns > 0:
		for c in nz:
			var r := od.get_rate(c, od.shop_col())
			if r <= 0.0:
				continue
			var cn := net.corner_nodes[c]
			var du := PackedFloat64Array()
			var dv := PackedFloat64Array()
			var wts := PackedFloat64Array()
			du.resize(ns)
			dv.resize(ns)
			wts.resize(ns)
			var total := 0.0
			for s in ns:
				var e: Dictionary = net.edges[net.shops[s]["edge"]]
				var x: float = net.shops[s]["x"]
				du[s] = net.dist[cn][e["a"]] + x
				dv[s] = net.dist[cn][e["b"]] + (float(e["len"]) - x)
				var dd := minf(du[s], dv[s])
				wts[s] = exp(-dd / theta) if dd < INF else 0.0
				total += wts[s]
			if total <= 0.0:
				unreachable += r
				continue
			shopper_rate += r
			for s in ns:
				var q := r * wts[s] / total
				if q <= 0.0:
					continue
				shop_visits[s] += q
				var ei: int = net.shops[s]["edge"]
				var e: Dictionary = net.edges[ei]
				var x: float = net.shops[s]["x"]
				var wu := 0.5
				if du[s] < dv[s] - StreetNetwork.TIE:
					wu = 1.0
				elif dv[s] < du[s] - StreetNetwork.TIE:
					wu = 0.0
				shopper_person_m += 2.0 * q * minf(du[s], dv[s])
				# there and back = two passes
				if wu > 0.0:
					_add_flow(cn, e["a"], 2.0 * q * wu)
					for s2 in net.edge_shops[ei]:
						if float(net.shops[s2]["x"]) < x - 1e-6:
							extra[s2] += 2.0 * q * wu
				if wu < 1.0:
					_add_flow(cn, e["b"], 2.0 * q * (1.0 - wu))
					for s2 in net.edge_shops[ei]:
						if float(net.shops[s2]["x"]) > x + 1e-6:
							extra[s2] += 2.0 * q * (1.0 - wu)

	for s in ns:
		var ei: int = net.shops[s]["edge"]
		shop_pass[s] = edge_flow[ei] + extra[s]
		shop_pass_through[s] = edge_through[ei]

	var on_passages := 0.0
	var on_all := 0.0
	for ei in ne:
		var pm: float = edge_flow[ei] * float(net.edges[ei]["len"])
		on_all += pm
		if net.edges[ei]["kind"] == StreetNetwork.KIND_PASSAGE:
			on_passages += pm
	passage_share = on_passages / on_all if on_all > 0.0 else 0.0


## Spread q over all shortest s–t paths (both directions are the same set of edges).
func _add_flow(s: int, t: int, q: float) -> void:
	if s == t or q <= 0.0:
		return
	var ds: PackedFloat64Array = net.dist[s]
	var dt: PackedFloat64Array = net.dist[t]
	var total: float = ds[t]
	if total == INF:
		return
	var n_paths: float = net.sigma[s][t]
	for ei in net.edges.size():
		var e: Dictionary = net.edges[ei]
		var u: int = e["a"]
		var v: int = e["b"]
		var l: float = e["len"]
		if absf(ds[u] + l + dt[v] - total) <= StreetNetwork.TIE * 4.0:
			edge_flow[ei] += q * net.sigma[s][u] * net.sigma[t][v] / n_paths
		elif absf(ds[v] + l + dt[u] - total) <= StreetNetwork.TIE * 4.0:
			edge_flow[ei] += q * net.sigma[s][v] * net.sigma[t][u] / n_paths


static func _zeros(n: int) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(n)
	return a


# ---------------------------------------------------------------- summary

func mean_through_trip() -> float:
	return through_person_m / through_rate if through_rate > 0.0 else 0.0


func person_km_per_hour() -> float:
	return (through_person_m + shopper_person_m) * 60.0 / 1000.0


func shop_hourly() -> PackedFloat64Array:
	var h := PackedFloat64Array()
	for v in shop_pass:
		h.append(v * 60.0)
	return h


func shop_stats() -> Dictionary:
	var h := shop_hourly()
	var n := h.size()
	if n == 0:
		return {"n": 0, "mean": 0.0, "min": 0.0, "max": 0.0, "gini": 0.0, "weak": 0.0, "total": 0.0}
	var sorted := h.duplicate()
	sorted.sort()
	var total := 0.0
	var weighted := 0.0
	for i in n:
		total += sorted[i]
		weighted += float(i + 1) * sorted[i]
	var mean := total / float(n)
	var gini := (2.0 * weighted) / (float(n) * total) - (float(n) + 1.0) / float(n) if total > 0.0 else 0.0
	var weak := 0
	for v in h:
		if v < 0.25 * mean:
			weak += 1
	return {"n": n, "mean": mean, "min": sorted[0], "max": sorted[n - 1],
			"gini": gini, "weak": float(weak) / float(n), "total": total}
