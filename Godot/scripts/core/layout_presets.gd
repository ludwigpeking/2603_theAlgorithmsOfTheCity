class_name LayoutPresets
extends RefCounted
## Built-in spatial scenarios. Coordinates are grid cells (1 cell ≈ one shopfront module).


## A linear high street, open at both ends, with a side alley to a car park.
static func high_street() -> MallLayout:
	var m := MallLayout.new("High street — open ends + side alley", 34, 9)
	m.add_walk(Rect2i(0, 3, 34, 3))     # the street
	m.add_walk(Rect2i(13, 6, 2, 3))     # side alley
	for s in [[1, 4], [5, 4], [9, 4], [13, 8], [21, 4], [25, 4], [29, 4]]:
		m.add_unit(Rect2i(s[0], 0, s[1], 3))           # north side
	for s in [[1, 4], [5, 4], [9, 4], [15, 4], [19, 4], [23, 4], [27, 6]]:
		m.add_unit(Rect2i(s[0], 6, s[1], 3))           # south side
	m.add_entrance(0, 4, 1.0)
	m.add_entrance(33, 4, 1.0)
	m.add_entrance(13, 8, 0.7)
	m.finalize()
	return m


## The classic "dumbbell" mall: two anchor boxes at the ends,
## one central entrance, small units lining the mall between them.
static func dumbbell() -> MallLayout:
	var m := MallLayout.new("Dumbbell mall — anchors at both ends, central entrance", 40, 11)
	m.add_walk(Rect2i(8, 4, 24, 3))     # mall corridor
	m.add_walk(Rect2i(19, 7, 2, 4))     # entrance passage
	m.add_unit(Rect2i(0, 1, 8, 9))      # west anchor box
	m.add_unit(Rect2i(32, 1, 8, 9))     # east anchor box
	for s in [[8, 4], [12, 4], [16, 8], [24, 4], [28, 4]]:
		m.add_unit(Rect2i(s[0], 1, s[1], 3))
	for s in [[8, 4], [12, 4], [16, 3], [21, 3], [24, 4], [28, 4]]:
		m.add_unit(Rect2i(s[0], 7, s[1], 3))
	m.add_entrance(19, 10, 1.0)
	m.finalize()
	return m
