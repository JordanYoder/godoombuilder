@tool
class_name DMGeo
extends RefCounted
## 2D polygon helpers for sector maps. Points are map-local (x, z) in meters.


## Coordinates are snapped to this so edges shared by two sectors match exactly.
const SNAP := 0.0001
## Areas below this (m²) are treated as empty slivers.
const MIN_AREA := 0.0001
## Distance under which two edges count as lying on the same line (m).
const LINE_EPS := 0.001
## Height difference under which two heights count as equal (m).
const HEIGHT_EPS := 0.0001


## Shoelace area: positive for counter-clockwise loops in (x, z).
static func signed_area(p: PackedVector2Array) -> float:
	var a := 0.0
	var n := p.size()
	for i in n:
		var u := p[i]
		var v := p[(i + 1) % n]
		a += u.x * v.y - v.x * u.y
	return a * 0.5


## Snaps points, drops duplicates, collinear points and spikes.
## Returns an empty array when fewer than three points remain.
static func clean(p: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for q in p:
		var s := Vector2(snappedf(q.x, SNAP), snappedf(q.y, SNAP))
		if pts.is_empty() or pts[pts.size() - 1].distance_to(s) > SNAP * 0.5:
			pts.append(s)
	while pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) <= SNAP * 0.5:
		pts.remove_at(pts.size() - 1)
	var changed := true
	while changed and pts.size() >= 3:
		changed = false
		var n := pts.size()
		for i in n:
			var a := pts[(i - 1 + n) % n]
			var b := pts[i]
			var c := pts[(i + 1) % n]
			var ab := b - a
			var bc := c - b
			if absf(ab.cross(bc)) <= 1e-7 * maxf(ab.length() * bc.length(), 1e-12):
				pts.remove_at(i)
				changed = true
				break
	if pts.size() < 3:
		return PackedVector2Array()
	return pts


## Cleans `p` and orients it counter-clockwise (or clockwise when `ccw` is false).
static func normalized(p: PackedVector2Array, ccw := true) -> PackedVector2Array:
	var c := clean(p)
	if c.is_empty():
		return c
	if (signed_area(c) > 0.0) != ccw:
		c.reverse()
	return c


## True when `pt` is inside the polygon (even-odd rule). Used instead of
## Geometry2D.is_point_in_polygon, which can report points far outside a
## polygon as inside when it has nearly parallel edges.
static func point_in_polygon(pt: Vector2, p: PackedVector2Array) -> bool:
	var inside := false
	var n := p.size()
	var j := n - 1
	for i in n:
		var a := p[i]
		var b := p[j]
		if (a.y > pt.y) != (b.y > pt.y):
			var x := a.x + (pt.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if pt.x < x:
				inside = not inside
		j = i
	return inside


## A point strictly inside the polygon (centroid of its largest triangle).
static func interior_point(p: PackedVector2Array) -> Vector2:
	var tri := Geometry2D.triangulate_polygon(p)
	var best := -1.0
	var out := Vector2.ZERO
	for i in range(0, tri.size(), 3):
		var a := p[tri[i]]
		var b := p[tri[i + 1]]
		var c := p[tri[i + 2]]
		var area := absf((b - a).cross(c - a))
		if area > best:
			best = area
			out = (a + b + c) / 3.0
	if best < 0.0:
		for q in p:
			out += q
		out /= maxf(1.0, float(p.size()))
	return out


## True when no two non-adjacent edges of the loop touch.
static func is_simple(p: PackedVector2Array) -> bool:
	var n := p.size()
	if n < 3:
		return false
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		for j in range(i + 1, n):
			if j == i or (j + 1) % n == i or (i + 1) % n == j:
				continue
			var c := p[j]
			var d := p[(j + 1) % n]
			if segments_touch(a, b, c, d):
				return false
	return true


## True when segments a-b and c-d meet. Geometry2D.segment_intersects_segment
## alone reports false crossings for nearly parallel segments (a point on
## neither), so its answer is checked against both segments.
static func segments_touch(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var x: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
	if x == null:
		return false
	var p: Vector2 = x
	const EPS := 1e-6
	return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= EPS 		and Geometry2D.get_closest_point_to_segment(p, c, d).distance_to(p) <= EPS


## A clipper result split into outer boundaries and holes.
class Parts:
	var outers: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []


## Splits a clipper result into outer boundaries and holes.
static func classify(results: Array[PackedVector2Array]) -> Parts:
	var outers: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	var big := 0.0
	var sign := 1.0
	for r in results:
		var a := signed_area(r)
		if absf(a) > big:
			big = absf(a)
			sign = signf(a)
	for r in results:
		var a := signed_area(r)
		if absf(a) < MIN_AREA:
			continue
		if signf(a) == sign:
			outers.append(r)
		else:
			holes.append(r)
	var parts := Parts.new()
	parts.outers = outers
	parts.holes = holes
	return parts


static func _normalize_all(polys: Array[PackedVector2Array], depth := 0) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for p in polys:
		var c := clean(p)
		if c.is_empty():
			continue
		var lobes := split_pinches(c)
		if lobes.size() == 1:
			c = normalized(c)
			if c.is_empty() or absf(signed_area(c)) < MIN_AREA:
				continue
			out.append(c)
			continue
		# Pinched (the loop touches itself at a point): lobes running the same
		# way as the loop are pieces of it; lobes running the other way are
		# holes touching its boundary at that point, cut out of the pieces.
		var sign := signf(signed_area(c))
		var pieces: Array[PackedVector2Array] = []
		var holes: Array[PackedVector2Array] = []
		for lobe in lobes:
			var a := signed_area(lobe)
			if absf(a) < MIN_AREA:
				continue
			var n := normalized(lobe)
			if n.is_empty():
				continue
			if signf(a) == sign:
				pieces.append(n)
			else:
				holes.append(n)
		for h in holes:
			if depth >= 6:
				push_warning("GoDoomBuilder: couldn't cut a hole out of a pinched polygon")
				break
			# Cut each piece in two through the hole first (as subtract() does
			# for holes), so the hole opens onto the cut instead of touching
			# the boundary at a single point again.
			var x := interior_point(h).x
			var next: Array[PackedVector2Array] = []
			for piece in pieces:
				if overlap_area(piece, h) < MIN_AREA:
					next.append(piece)
					continue
				for half in halves(piece, x):
					next.append_array(_normalize_all(classify(Geometry2D.clip_polygons(half, h)).outers, depth + 1))
			pieces = next
		out.append_array(pieces)
	return out


## Splits a loop that touches itself (visits the same point twice, or has a
## corner lying on one of its other edges) into loops that don't, e.g. a
## figure eight into its two halves.
static func split_pinches(p: PackedVector2Array) -> Array[PackedVector2Array]:
	p = _insert_touching_corners(p)
	return _split_repeats(p)


## A corner lying on a non-adjacent edge of the same loop is added to that
## edge too, so the touch becomes a repeated point that _split_repeats finds.
static func _insert_touching_corners(p: PackedVector2Array) -> PackedVector2Array:
	var guard := p.size() * 2
	var inserted := true
	while inserted and guard > 0:
		inserted = false
		guard -= 1
		var n := p.size()
		for i in n:
			var v := p[i]
			for j in n:
				var j2 := (j + 1) % n
				if j == i or j2 == i:
					continue
				var a := p[j]
				var b := p[j2]
				if v.distance_to(a) <= SNAP * 0.5 or v.distance_to(b) <= SNAP * 0.5:
					continue
				if Geometry2D.get_closest_point_to_segment(v, a, b).distance_to(v) <= SNAP:
					p.insert(j + 1, v)
					inserted = true
					break
			if inserted:
				break
	return p


static func _split_repeats(p: PackedVector2Array) -> Array[PackedVector2Array]:
	var seen := {}
	for i in p.size():
		var k := Vector2i(roundi(p[i].x / SNAP), roundi(p[i].y / SNAP))
		if seen.has(k):
			var j: int = seen[k]
			var out: Array[PackedVector2Array] = []
			out.append_array(_split_repeats(p.slice(j, i)))
			out.append_array(_split_repeats(p.slice(0, j) + p.slice(i)))
			return out
		seen[k] = i
	var one: Array[PackedVector2Array] = [p]
	return one


## `p` minus `n`, as hole-free counter-clockwise polygons.
## When `n` sits strictly inside `p` (which would leave a hole), `p` is first cut
## in two by a vertical line through `n`, so each half gets a notch instead.
static func subtract(p: PackedVector2Array, n: PackedVector2Array, depth := 0) -> Array[PackedVector2Array]:
	var parts := classify(Geometry2D.clip_polygons(p, n))
	if parts.holes.is_empty() or depth >= 6:
		return _normalize_all(parts.outers, depth)
	var x := interior_point(n).x
	var out: Array[PackedVector2Array] = []
	for half in halves(p, x):
		out.append_array(subtract(half, n, depth + 1))
	return out


## `p` cut by the vertical line at `x`, as hole-free polygons.
static func halves(p: PackedVector2Array, x: float) -> Array[PackedVector2Array]:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for q in p:
		lo = lo.min(q)
		hi = hi.max(q)
	lo -= Vector2.ONE
	hi += Vector2.ONE
	var left := PackedVector2Array([Vector2(lo.x, lo.y), Vector2(x, lo.y), Vector2(x, hi.y), Vector2(lo.x, hi.y)])
	var right := PackedVector2Array([Vector2(x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(x, hi.y)])
	var out: Array[PackedVector2Array] = []
	out.append_array(_normalize_all(classify(Geometry2D.intersect_polygons(p, left)).outers))
	out.append_array(_normalize_all(classify(Geometry2D.intersect_polygons(p, right)).outers))
	return out


## Area of the overlap between two simple polygons.
static func overlap_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var parts := classify(Geometry2D.intersect_polygons(a, b))
	var total := 0.0
	for o in parts.outers:
		total += absf(signed_area(o))
	for h in parts.holes:
		total -= absf(signed_area(h))
	return maxf(total, 0.0)
