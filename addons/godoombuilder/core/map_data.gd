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
