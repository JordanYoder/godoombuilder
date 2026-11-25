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
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return false
	return true


## Splits a clipper result into outer boundaries and holes.
static func classify(results: Array) -> Dictionary:
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
	return {"outers": outers, "holes": holes}


static func _normalize_all(polys: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for p in polys:
		var c := normalized(p)
		if not c.is_empty() and absf(signed_area(c)) >= MIN_AREA:
			out.append(c)
	return out


## `p` minus `n`, as hole-free counter-clockwise polygons.
## When `n` sits strictly inside `p` (which would leave a hole), `p` is first cut
## in two by a vertical line through `n`, so each half gets a notch instead.
static func subtract(p: PackedVector2Array, n: PackedVector2Array, depth := 0) -> Array[PackedVector2Array]:
	var parts := classify(Geometry2D.clip_polygons(p, n))
	if (parts.holes as Array).is_empty() or depth >= 6:
		return _normalize_all(parts.outers)
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
