@tool
class_name DMMapData
extends Resource
## All sectors of one sector map, plus the edit operations on them.


@export var sectors: Array[DMSector] = []


## A deep copy for undo snapshots.
func duplicate_data() -> DMMapData:
	var d := DMMapData.new()
	for s in sectors:
		d.sectors.append(s.duplicate_sector())
	return d


## Restores this map from a snapshot.
func copy_from(other: DMMapData) -> void:
	sectors.clear()
	for s in other.sectors:
		sectors.append(s.duplicate_sector())
	emit_changed()


func notify_changed() -> void:
	emit_changed()


## Index of the sector whose floor area contains `pt`, or -1.
func sector_at(pt: Vector2) -> int:
	for i in sectors.size():
		if sectors[i].contains_point(pt):
			return i
	return -1


## Draws a new sector from a closed loop of map points.
##
## Works like drawing in a Doom map editor: the new area is cut out of any
## sector it overlaps, and sectors it completely surrounds are kept and cut out
## of the new one. Heights and materials come from the sector the loop was
## drawn inside, or from `defaults` when drawn in empty space.
## Returns {ok: bool, index: int, message: String}.
func add_loop(points: PackedVector2Array, defaults: DMSector) -> Dictionary:
	var loop := DMGeo.normalized(points)
	if loop.size() < 3 or absf(DMGeo.signed_area(loop)) < DMGeo.MIN_AREA:
		return {"ok": false, "index": -1, "message": "The shape is too small or flat."}
	if not DMGeo.is_simple(loop):
		return {"ok": false, "index": -1, "message": "The lines cross each other. Draw a shape whose sides don't cross."}

	var source := sector_at(DMGeo.interior_point(loop))
	var fresh := DMSector.new()
	fresh.copy_props_from(sectors[source] if source >= 0 else defaults)

	var enclosed: Array[DMSector] = []
	var keep: Array[DMSector] = []
	for s in sectors:
		var total := s.area()
		var overlap := 0.0
		for p in s.polygons:
			overlap += DMGeo.overlap_area(p, loop)
		if overlap < DMGeo.MIN_AREA:
			keep.append(s)
			continue
		if absf(overlap - total) < maxf(DMGeo.MIN_AREA, total * 1e-6):
			# Completely inside the new loop: keep it and cut it out of the new sector.
			enclosed.append(s)
			keep.append(s)
			continue
		var rest: Array[PackedVector2Array] = []
		for p in s.polygons:
			rest.append_array(DMGeo.subtract(p, loop))
		if not rest.is_empty():
			s.polygons = rest
			keep.append(s)

	var pieces: Array[PackedVector2Array] = [loop]
	for s in enclosed:
		for hole in s.polygons:
			var next: Array[PackedVector2Array] = []
			for p in pieces:
				next.append_array(DMGeo.subtract(p, hole))
			pieces = next
	sectors = keep
	if pieces.is_empty():
		emit_changed()
		return {"ok": false, "index": -1, "message": "That area is already covered by sectors."}
	fresh.polygons = pieces
	sectors.append(fresh)
	emit_changed()
	return {"ok": true, "index": sectors.size() - 1, "message": ""}


## Removes the given sectors; their area becomes empty space (solid wall).
func delete_sectors(indices: Array) -> void:
	var drop := {}
	for i in indices:
		drop[int(i)] = true
	var keep: Array[DMSector] = []
	for i in sectors.size():
		if not drop.has(i):
			keep.append(sectors[i])
	sectors = keep
	emit_changed()


## Every polygon vertex in the map (for snapping while drawing).
func all_vertices() -> PackedVector2Array:
	var out := PackedVector2Array()
	for s in sectors:
		for p in s.polygons:
			out.append_array(p)
	return out


# --- Moving vertices (dragging corners and walls, resizing) --------------------

## Dictionary key for a map point (positions are snapped, so equal points match).
static func key_of(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / DMGeo.SNAP), roundi(p.y / DMGeo.SNAP))


## Adds `p` as a vertex to every edge that passes through it, so every sector
## touching `p` follows when it moves.
func split_edges_at(p: Vector2) -> void:
	for s in sectors:
		for pi in s.polygons.size():
			var poly := s.polygons[pi]
			var i := 0
			var changed := false
			while i < poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				if a.distance_to(p) > DMGeo.LINE_EPS and b.distance_to(p) > DMGeo.LINE_EPS:
					var c := Geometry2D.get_closest_point_to_segment(p, a, b)
					if c.distance_to(p) < DMGeo.LINE_EPS:
						poly.insert(i + 1, p)
						changed = true
						i += 1
				i += 1
			if changed:
				s.polygons[pi] = poly


## Moves every vertex at from[i] to to[i], in all sectors (shared corners move
## together, so neighbours stretch instead of coming apart). Call validate()
## afterwards: the result may be invalid (crossing or overlapping).
func move_vertices(from: PackedVector2Array, to: PackedVector2Array) -> void:
	for p in from:
		split_edges_at(p)
	var moves := {}
	for i in from.size():
		moves[key_of(from[i])] = Vector2(snappedf(to[i].x, DMGeo.SNAP), snappedf(to[i].y, DMGeo.SNAP))
	_carry_points_on_moving_edges(moves)
	# Wall settings and hand-placed outer corners follow their corners.
	for s in sectors:
		if not s.outer_corners.is_empty():
			var moved := {}
			for k in s.outer_corners:
				var nk = key_of(moves[k]) if moves.has(k) else k
				moved[nk] = s.outer_corners[k]
			s.outer_corners = moved
	for s in sectors:
		for o in s.wall_overrides:
			for end in ["a", "b"]:
				var k := key_of(o[end])
				if moves.has(k):
					o[end] = moves[k]
	for s in sectors:
		for pi in s.polygons.size():
			var poly := s.polygons[pi]
			var changed := false
			for vi in poly.size():
				var k := key_of(poly[vi])
				if moves.has(k):
					poly[vi] = moves[k]
					changed = true
			if changed:
				s.polygons[pi] = DMGeo.clean(poly)
	emit_changed()


## Why the map is invalid ("" when it's fine): collapsed, inside-out, crossing
## or overlapping sectors.
func validate() -> String:
	var polys: Array[PackedVector2Array] = []
	var boxes: Array[Rect2] = []
	for s in sectors:
		for poly in s.polygons:
			if poly.size() < 3:
				return "a sector would collapse"
			if DMGeo.signed_area(poly) < DMGeo.MIN_AREA:
				return "a sector would be turned inside out"
			if not DMGeo.is_simple(poly):
				return "a sector's sides would cross"
			var box := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				box = box.expand(q)
			polys.append(poly)
			boxes.append(box.grow(-DMGeo.LINE_EPS))
	for i in polys.size():
		for j in range(i + 1, polys.size()):
			if not boxes[i].intersects(boxes[j]):
				continue
			if DMGeo.overlap_area(polys[i], polys[j]) > 0.001:
				return "sectors would overlap"
	return ""


## Bounding box of the given sectors' floor areas.
func bounds_of(indices: Array) -> Rect2:
	var box := Rect2()
	var first := true
	for i in indices:
		for poly in sectors[int(i)].polygons:
			for q in poly:
				if first:
					box = Rect2(q, Vector2.ZERO)
					first = false
				else:
					box = box.expand(q)
	return box


## Scales the given sectors about `anchor` (factor per axis); shared corners
## of neighbouring sectors move with them.
func scale_sectors(indices: Array, anchor: Vector2, factor: Vector2) -> void:
	var seen := {}
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	for i in indices:
		for poly in sectors[int(i)].polygons:
			for q in poly:
				var k := key_of(q)
				if seen.has(k):
					continue
				seen[k] = true
				from.append(q)
				to.append(anchor + (q - anchor) * factor)
	move_vertices(from, to)


## Corners that sit in the middle of a moving edge (where another sector or a
## seam meets it) slide along with that edge, so nothing tears or overlaps.
func _carry_points_on_moving_edges(moves: Dictionary) -> void:
	var others := {}
	for v in all_vertices():
		var k := key_of(v)
		if not moves.has(k):
			others[k] = v
	var extra := {}
	for s in sectors:
		for poly in s.polygons:
			var n := poly.size()
			for i in n:
				var p := poly[i]
				var q := poly[(i + 1) % n]
				var kp := key_of(p)
				var kq := key_of(q)
				if not (moves.has(kp) or moves.has(kq)):
					continue
				var length_sq := p.distance_squared_to(q)
				if length_sq < 1e-12:
					continue
				var p2: Vector2 = moves.get(kp, p)
				var q2: Vector2 = moves.get(kq, q)
				for k in others:
					if extra.has(k):
						continue
					var v: Vector2 = others[k]
					if v.distance_to(p) < DMGeo.LINE_EPS or v.distance_to(q) < DMGeo.LINE_EPS:
						continue
					if Geometry2D.get_closest_point_to_segment(v, p, q).distance_to(v) >= DMGeo.LINE_EPS:
						continue
					var t := (v - p).dot(q - p) / length_sq
					var w := p2.lerp(q2, t)
					extra[k] = Vector2(snappedf(w.x, DMGeo.SNAP), snappedf(w.y, DMGeo.SNAP))
	moves.merge(extra)


# --- Joining sectors -----------------------------------------------------------

## Joins the given sectors into one, keeping the first one's heights and
## materials. Pieces that touch are merged so no seams are left. Returns the
## joined sector's new index.
func join_sectors(indices: Array) -> int:
	var keep := sectors[int(indices[0])]
	var polys: Array[PackedVector2Array] = []
	for i in indices:
		polys.append_array(sectors[int(i)].polygons)
		if sectors[int(i)] != keep:
			keep.wall_overrides.append_array(sectors[int(i)].wall_overrides)
	keep.polygons = merge_pieces(polys)
	var drop := []
	for i in range(1, indices.size()):
		drop.append(int(indices[i]))
	var target := sectors[int(indices[0])]
	delete_sectors(drop)
	return sectors.find(target)


## Merges touching hole-free pieces into fewer pieces, as long as the result
## stays hole-free (pieces that would enclose a hole are left separate).
static func merge_pieces(polys: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = polys.duplicate()
	var merged := true
	while merged:
		merged = false
		for i in out.size():
			for j in range(i + 1, out.size()):
				var r := Geometry2D.merge_polygons(out[i], out[j])
				if r.size() != 1 or Geometry2D.is_polygon_clockwise(r[0]):
					continue
				var p := DMGeo.normalized(r[0])
				if p.size() < 3 or not DMGeo.is_simple(p):
					continue
				# Same area as both pieces: they touched along an edge, not overlapped oddly.
				var total := absf(DMGeo.signed_area(out[i])) + absf(DMGeo.signed_area(out[j]))
				if absf(DMGeo.signed_area(p) - total) > maxf(DMGeo.MIN_AREA, total * 1e-5):
					continue
				out[i] = p
				out.remove_at(j)
				merged = true
				break
			if merged:
				break
	return out


# --- Thick walls -----------------------------------------------------------------

## Gives a sector's walls a thickness of `thickness` meters. `side`: 1 outward
## (the room keeps its size), -1 inward (the room gets smaller), 0 half each.
## Only the sector's outer boundary counts (not the edges around sectors
## inside it). Where it has walls facing solid space, only those get thick:
## outward, they become solid blocks (the sector's wall_thickness), and
## openings into neighbouring sectors stay open. A room with no such walls
## (standing inside another room) gets thick walls all round, taking the
## outward part from the rooms around it. Returns {ok, index, message}.
func thicken_walls(index: int, thickness: float, side: int) -> Dictionary:
	if thickness <= DMGeo.SNAP:
		return {"ok": false, "index": index, "message": "Set a wall thickness first."}
	var runs: Array = []
	var void_walls := false
	for loop in boundary_loops(index):
		if DMGeo.signed_area(loop.points) <= 0.0:
			continue # Around something inside this sector, not its outer wall.
		var chosen: Array = loop.faces_void.duplicate()
		if chosen.has(true):
			void_walls = true
		else:
			chosen.fill(true)
		runs.append({"points": loop.points, "chosen": chosen, "faces_void": loop.faces_void})
	var target := sectors[index]
	var outside := _outside_part(thickness, side)
	var setter := func() -> void:
		if void_walls:
			target.wall_thickness = outside
			target.clear_outer_corners()
	return _apply_bands(index, runs, thickness, side, setter)


## Thickens one wall only (the sector edge a -> b), like thicken_walls: facing
## solid space, outward thickness makes it a solid block; facing another
## room, it takes the space from that room. Ends are square; where the wall
## next to it is already thick the same way, the corner joins up.
func thicken_edge(index: int, a: Vector2, b: Vector2, thickness: float, side: int) -> Dictionary:
	if thickness <= DMGeo.SNAP:
		return {"ok": false, "index": index, "message": "Set a wall thickness first."}
	if a.distance_to(b) < DMGeo.LINE_EPS:
		return {"ok": false, "index": index, "message": "That wall is too short."}
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var faces_void := sector_at((a + b) * 0.5 - n * 0.01) < 0
	var outside := _outside_part(thickness, side)
	var a2 := a
	var b2 := b
	if outside > 0.0 and not faces_void:
		var w := outside
		if sector_at(a - d * w * 0.5 + n * w * 0.5) < 0 and sector_at(a - d * w * 0.5 - n * w * 0.5) >= 0:
			a2 = a - d * w
		if sector_at(b + d * w * 0.5 + n * w * 0.5) < 0 and sector_at(b + d * w * 0.5 - n * w * 0.5) >= 0:
			b2 = b + d * w
	var runs := [{"points": PackedVector2Array([a, b]), "chosen": [true, false], "open": true,
		"faces_void": [faces_void, false], "outside_points": PackedVector2Array([a2, b2])}]
	var target := sectors[index]
	var setter := func() -> void:
		if faces_void:
			target.set_wall_override(a, b, {"thickness": outside})
			target.clear_outer_corners([a, b])
	return _apply_bands(index, runs, thickness, side, setter)


static func _outside_part(thickness: float, side: int) -> float:
	return 0.0 if side < 0 else (thickness * 0.5 if side == 0 else thickness)


## Applies a thickening: the inward part is cut out of this sector; the
## outward part is cut out of neighbouring sectors where the walls face them,
## and `set_void_thickness` records it for walls facing solid space.
func _apply_bands(index: int, runs: Array, thickness: float, side: int, set_void_thickness: Callable) -> Dictionary:
	var outside := _outside_part(thickness, side)
	var inside := thickness - outside
	var target := sectors[index]
	var before := duplicate_data()
	var total_before := 0.0
	for s in sectors:
		total_before += s.area()
	if inside > 0.0:
		target.polygons = _subtract_all(target.polygons, _wall_bands(runs, inside, 1.0))
	if outside > 0.0:
		var out_runs: Array = []
		for run in runs:
			var r: Dictionary = run.duplicate()
			var c: Array = []
			for i in (run.chosen as Array).size():
				c.append(run.chosen[i] and not run.faces_void[i])
			r.chosen = c
			out_runs.append(r)
		var bands := _wall_bands(out_runs, outside, -1.0, "outside_points")
		for s in sectors:
			if s != target:
				s.polygons = _subtract_all(s.polygons, bands)
		set_void_thickness.call()
	var total_after := 0.0
	var empty := []
	for i in sectors.size():
		total_after += sectors[i].area()
		if sectors[i].polygons.is_empty():
			empty.append(i)
	if empty.has(index):
		return {"ok": false, "index": index, "message": "The room is too small for walls that thick."}
	var props_changed: bool = not is_equal_approx(target.wall_thickness, before.sectors[index].wall_thickness) or target.wall_overrides != before.sectors[index].wall_overrides or target.outer_corners != before.sectors[index].outer_corners
	if absf(total_after - total_before) < DMGeo.MIN_AREA and not props_changed:
		return {"ok": false, "index": index, "message": "Nothing changed: the walls are already that thick."}
	delete_sectors(empty)
	return {"ok": true, "index": sectors.find(target), "message": ""}


func boundary_loops(index: int) -> Array:
	return DMBuilder.chain_loops(DMBuilder.build(self).outlines[index], self)


## Quads covering the chosen segments of each run, `width` meters toward the
## sector (dir 1) or away from it (dir -1). Neighbouring chosen segments meet
## at mitered corners; a run's ends (next to unchosen segments) are square.
## Runs marked "open" are polylines, not loops.
static func _wall_bands(runs: Array, width: float, dir: float, points_key := "points") -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for run in runs:
		var loop: PackedVector2Array = run.get(points_key, run.points)
		var chosen: Array = run.chosen
		var open: bool = run.get("open", false)
		var n := loop.size()
		var segs := n - 1 if open else n
		var normals := PackedVector2Array()
		for i in segs:
			var d := (loop[(i + 1) % n] - loop[i]).normalized()
			normals.append(Vector2(-d.y, d.x) * dir)
		for i in segs:
			if not chosen[i]:
				continue
			var j := (i + 1) % n
			var prev := (i - 1 + segs) % segs
			var nxt := (i + 1) % segs
			var start_off := normals[i] * width
			var end_off := normals[i] * width
			if not open or i > 0:
				if chosen[prev] and prev != i:
					start_off = _miter(normals[prev], normals[i]) * width
			if not open or i < segs - 1:
				if chosen[nxt] and nxt != i:
					end_off = _miter(normals[i], normals[nxt]) * width
			var quad := DMGeo.normalized(PackedVector2Array([loop[i], loop[j], loop[j] + end_off, loop[i] + start_off]))
			if quad.size() < 3 or not DMGeo.is_simple(quad):
				quad = DMGeo.normalized(PackedVector2Array([loop[i], loop[j], loop[j] + normals[i] * width, loop[i] + normals[i] * width]))
			if quad.size() >= 3:
				out.append(quad)
	return out


static func _miter(n1: Vector2, n2: Vector2) -> Vector2:
	var m := (n1 + n2) / maxf(1.0 + n1.dot(n2), 0.1)
	return m.normalized() * 4.0 if m.length() > 4.0 else m


static func _subtract_all(polys: Array[PackedVector2Array], cutters: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var cur := polys
	for c in cutters:
		var box := _box(c)
		var next: Array[PackedVector2Array] = []
		for p in cur:
			if not _box(p).intersects(box):
				next.append(p)
				continue
			for piece in DMGeo.subtract(p, c):
				if absf(DMGeo.signed_area(piece)) >= DMGeo.MIN_AREA:
					next.append(piece)
		cur = next
	return cur


static func _box(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


# --- Simplifying -----------------------------------------------------------------

## Removes points that don't change a sector's shape: seams between its own
## pieces (pieces are fused where possible) and points lying on a straight
## wall (within `tolerance` meters). A point is kept where the walls on either
## side have different single-wall settings. Returns how many points went.
func simplify_sector(index: int, tolerance := DMGeo.LINE_EPS) -> int:
	var s := sectors[index]
	var before := 0
	for p in s.polygons:
		before += p.size()
	var pieces := merge_pieces(s.polygons)
	var out: Array[PackedVector2Array] = []
	for p in pieces:
		out.append(_drop_straight_points(s, p, tolerance))
	s.polygons = out
	var after := 0
	for p in out:
		after += p.size()
	if after != before:
		emit_changed()
	return before - after


static func _drop_straight_points(s: DMSector, poly: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var pts := poly.duplicate()
	var changed := true
	while changed and pts.size() > 3:
		changed = false
		var n := pts.size()
		for i in n:
			var a := pts[(i - 1 + n) % n]
			var b := pts[i]
			var c := pts[(i + 1) % n]
			var ac := c - a
			if ac.length() < DMGeo.LINE_EPS:
				continue
			# On the line from a to c, and between them (not a spike).
			var t := (b - a).dot(ac) / ac.length_squared()
			if t <= 0.0 or t >= 1.0:
				continue
			if Geometry2D.get_closest_point_to_segment(b, a, c).distance_to(b) > tolerance:
				continue
			var o1 := s.wall_override(a, b)
			var o2 := s.wall_override(b, c)
			if not _same_wall_settings(o1, o2):
				continue
			if not o1.is_empty():
				var props := {}
				for k in ["hidden", "top", "bottom", "thickness"]:
					if o1.has(k):
						props[k] = o1[k]
				s.set_wall_override(a, c, props)
			pts.remove_at(i)
			changed = true
			break
	return pts


static func _same_wall_settings(o1: Dictionary, o2: Dictionary) -> bool:
	for k in ["hidden", "top", "bottom", "thickness"]:
		if o1.has(k) != o2.has(k):
			return false
		if o1.has(k) and not is_equal_approx(float(o1[k]), float(o2[k])):
			return false
	return true
