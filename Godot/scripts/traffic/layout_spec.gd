class_name LayoutSpec
extends RefCounted
## Editable description of a block.
##   polygon — the block boundary (any simple polygon). Every vertex is a street corner.
##   arcades — public passages through the block, as line segments at any angle.
## Units: metres in the network model (v0.5+). The dormant v0.4 grid engine
## (LayoutBuilder / StreetGrid / TrafficSim) read the same fields in cells.

var title := ""
var polygon := PackedVector2Array()
var arcades: Array[PackedVector2Array] = []
var plazas: Array[Vector3] = []     # used only by the dormant v0.4 grid engine


static func make(p_title: String, pts: Array, arcs: Array = [], plz: Array = []) -> LayoutSpec:
	var s := LayoutSpec.new()
	s.title = p_title
	s.polygon = PackedVector2Array(pts)
	for a in arcs:
		s.arcades.append(PackedVector2Array(a))
	for p in plz:
		s.plazas.append(p)
	return s


func copy() -> LayoutSpec:
	var s := LayoutSpec.new()
	s.title = title
	s.polygon = polygon.duplicate()
	for a in arcades:
		s.arcades.append(a.duplicate())
	for p in plazas:
		s.plazas.append(p)
	return s


func centroid() -> Vector2:
	var c := Vector2.ZERO
	for v in polygon:
		c += v
	return c / float(maxi(polygon.size(), 1))


func is_valid() -> bool:
	return polygon.size() >= 3 and not Geometry2D.triangulate_polygon(polygon).is_empty()
