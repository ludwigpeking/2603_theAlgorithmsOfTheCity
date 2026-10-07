class_name Catalog
extends RefCounted
## Merchandise categories (what a shop sells and how it behaves)
## and customer profiles (who comes, what they want, how they browse).
##
## Time unit: one simulation step = one walked cell.

const VACANT := 0
const SUPERMARKET := 1
const DEPARTMENT := 2
const FASHION := 3
const ELECTRONICS := 4
const CAFE := 5
const CONVENIENCE := 6
const SERVICES := 7

## Units with at least this many cells count as "large" and may host anchors.
const LARGE_AREA := 18

var categories: Array[Dictionary] = []
var profiles: Array[Dictionary] = []
var _interest: Array[PackedFloat32Array] = []


func _init() -> void:
	#        name            short     colour     impulse conv  spend dwell comparison anchor
	_add_cat("Vacant",        "vacant", "#ffffff", 0.00, 0.00,   0.0,  0, false, false)
	_add_cat("Supermarket",   "SUPER",  "#4a86c5", 0.03, 0.90,  55.0, 14, false, true)
	_add_cat("Department",    "DEPT",   "#2f4f8a", 0.12, 0.45,  70.0, 18, true,  true)
	_add_cat("Fashion",       "fashion","#d9534f", 0.18, 0.30,  45.0, 10, true,  false)
	_add_cat("Electronics",   "electr.","#8e6bbf", 0.08, 0.25, 110.0, 10, true,  false)
	_add_cat("Café / F&B",    "café",   "#e8a23a", 0.10, 0.85,   9.0, 12, false, false)
	_add_cat("Convenience",   "conv.",  "#5aa469", 0.10, 0.70,  11.0,  4, false, false)
	_add_cat("Services",      "serv.",  "#8c8c8c", 0.02, 0.85,  30.0, 12, false, false)

	profiles.append({
		"name": "Errand", "desc": "short, goal-directed trips",
		"color": Color("#1a5faa"), "share": 0.40,
		"wants": {SUPERMARKET: 5, CONVENIENCE: 3, SERVICES: 3, ELECTRONICS: 1},
		"min": 1, "max": 2, "browse": 0.5, "budget": 140.0,
	})
	profiles.append({
		"name": "Leisure", "desc": "browsing, comparison shopping",
		"color": Color("#c0392b"), "share": 0.40,
		"wants": {FASHION: 5, DEPARTMENT: 3, ELECTRONICS: 2, CAFE: 2},
		"min": 1, "max": 3, "browse": 1.3, "budget": 260.0,
	})
	profiles.append({
		"name": "Family", "desc": "mixed list, needs rests",
		"color": Color("#222222"), "share": 0.20,
		"wants": {SUPERMARKET: 3, DEPARTMENT: 3, FASHION: 2, CAFE: 2, CONVENIENCE: 1},
		"min": 2, "max": 3, "browse": 0.9, "budget": 220.0,
	})
	_build_interest()


func _add_cat(p_name: String, short: String, hex: String, impulse: float, conversion: float,
		spend: float, dwell: int, comparison: bool, anchor: bool) -> void:
	categories.append({
		"name": p_name, "short": short, "color": Color(hex),
		"impulse": impulse,        # base chance to walk in when passing the shopfront
		"conversion": conversion,  # chance a purposeful visit ends in a purchase
		"spend": spend,            # mean basket value
		"dwell": dwell,            # steps spent inside
		"comparison": comparison,  # comparison goods: shoppers visit several rivals
		"anchor": anchor,          # needs a large unit
	})


func _build_interest() -> void:
	for p in profiles:
		var wants: Dictionary = p["wants"]
		var max_w := 1.0
		for k in wants:
			max_w = maxf(max_w, float(wants[k]))
		var arr := PackedFloat32Array()
		arr.resize(categories.size())
		for c in categories.size():
			arr[c] = 0.35 + 0.65 * float(wants.get(c, 0)) / max_w
		_interest.append(arr)


## How interested a profile is in a category when passing by (0.35 … 1.0).
func interest(profile: int, cat: int) -> float:
	return _interest[profile][cat]


func fits(cat: int, area: int) -> bool:
	if categories[cat]["anchor"]:
		return area >= LARGE_AREA
	return true


## Tenant mix for a layout: anchors for the large units, the rest by shares.
func default_mix(layout: MallLayout) -> Array[int]:
	var n := layout.units.size()
	var n_large := 0
	for u in layout.units:
		if int(u["area"]) >= LARGE_AREA:
			n_large += 1
	var mix: Array[int] = []
	if n_large >= 1:
		mix.append(SUPERMARKET)
	if n_large >= 2:
		mix.append(DEPARTMENT)
	var rest := n - mix.size()
	var shares := {FASHION: 0.35, CAFE: 0.20, ELECTRONICS: 0.12, CONVENIENCE: 0.12, SERVICES: 0.12, VACANT: 0.09}
	var count := 0
	for c in shares:
		var k := int(floor(rest * float(shares[c])))
		for _i in k:
			mix.append(c)
		count += k
	var order := [FASHION, CAFE, ELECTRONICS, CONVENIENCE, SERVICES]
	var j := 0
	while count < rest:
		mix.append(order[j % order.size()])
		j += 1
		count += 1
	return mix


## Random placement of the default mix that respects unit sizes.
func random_assignment(layout: MallLayout, rng: RandomNumberGenerator) -> PackedInt32Array:
	var n := layout.units.size()
	var result := PackedInt32Array()
	result.resize(n)
	result.fill(-1)
	var anchors: Array[int] = []
	var others: Array[int] = []
	for c in default_mix(layout):
		if categories[c]["anchor"]:
			anchors.append(c)
		else:
			others.append(c)
	var large_units: Array[int] = []
	for u in n:
		if int(layout.units[u]["area"]) >= LARGE_AREA:
			large_units.append(u)
	_shuffle(large_units, rng)
	for i in anchors.size():
		result[large_units[i]] = anchors[i]
	var free_units: Array[int] = []
	for u in n:
		if result[u] == -1:
			free_units.append(u)
	_shuffle(others, rng)
	for i in free_units.size():
		result[free_units[i]] = others[i]
	return result


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
