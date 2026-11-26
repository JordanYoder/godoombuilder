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


## Restores this map from a snapshot. `emit` false skips the changed signal
## (for callers that rebuild themselves, e.g. on every mouse move of a drag).
func copy_from(other: DMMapData, emit := true) -> void:
	sectors.clear()
	for s in other.sectors:
		sectors.append(s.duplicate_sector())
	if emit:
		emit_changed()


func notify_changed() -> void:
	emit_changed()


## Problems with the stored data (e.g. a hand-edited or damaged scene file),
## as readable messages; empty when it's fine. Cheap enough to run on load.
func check() -> Array[String]:
	var out: Array[String] = []
	for si in sectors.size():
		var s := sectors[si]
		if s == null:
			out.append("sector %d is empty (null)" % si)
			continue
		if not (is_finite(s.floor_height) and is_finite(s.ceiling_height)):
			out.append("sector %d has an invalid height" % si)
		elif s.ceiling_height < s.floor_height - DMGeo.HEIGHT_EPS:
			out.append("sector %d has its ceiling below its floor" % si)
		if not is_finite(s.wall_thickness) or s.wall_thickness < 0.0:
			out.append("sector %d has an invalid wall thickness" % si)
		if s.polygons.is_empty():
			out.append("sector %d has no area" % si)
		for pi in s.polygons.size():
			var poly := s.polygons[pi]
			var bad := false
			for q in poly:
				if not (is_finite(q.x) and is_finite(q.y)):
					bad = true
			if bad:
				out.append("sector %d, piece %d has an invalid point" % [si, pi])
			elif poly.size() < 3:
				out.append("sector %d, piece %d has fewer than 3 points" % [si, pi])
			elif DMGeo.signed_area(poly) < DMGeo.MIN_AREA:
				out.append("sector %d, piece %d is inside out or has no area" % [si, pi])
			elif Geometry2D.triangulate_polygon(poly).is_empty():
				out.append("sector %d, piece %d can't be triangulated (its floor won't show)" % [si, pi])
		for o in s.wall_overrides:
			if not (o.get("a") is Vector2 and o.get("b") is Vector2):
				out.append("sector %d has a wall setting without its edge" % si)
	return out


## True (and an error is reported) unless every index names a sector.
func _check_indices(indices: Array[int], what: String) -> bool:
	for i in indices:
		if i < 0 or i >= sectors.size():
			push_error("GoDoomBuilder: %s: no sector %d (the map has %d)" % [what, i, sectors.size()])
			return false
	return true


## Index of the sector whose floor area contains `pt`, or -1. For many
## lookups on an unchanging map, locator() is much faster.
func sector_at(pt: Vector2) -> int:
	for i in sectors.size():
		if sectors[i].contains_point(pt):
			return i
	return -1


## A snapshot for fast sector_at() lookups. It doesn't follow later edits:
## make a new one after the map changes.
func locator() -> SectorLocator:
	return SectorLocator.new(self)


## Finds the sector at a point via a grid of polygon bounding boxes.
class SectorLocator:
	var _polys: Array[PackedVector2Array] = []
	var _owner := PackedInt32Array()
	var _boxes: Array[Rect2] = []
	var _cells := {}
	var _cell := 1.0

	func _init(data: DMMapData) -> void:
		var total := 0.0
		for si in data.sectors.size():
			for poly in data.sectors[si].polygons:
				if poly.is_empty():
					continue
				var box := Rect2(poly[0], Vector2.ZERO)
				for q in poly:
					box = box.expand(q)
				_polys.append(poly)
				_owner.append(si)
				_boxes.append(box.grow(1e-6))
				total += maxf(box.size.x, box.size.y)
		_cell = maxf(total / maxf(float(_polys.size()), 1.0), 0.05)
		for i in _polys.size():
			var lo := _cell_of(_boxes[i].position)
			var hi := _cell_of(_boxes[i].end)
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					var c := Vector2i(x, y)
					if not _cells.has(c):
						_cells[c] = PackedInt32Array()
					var list: PackedInt32Array = _cells[c]
					list.append(i)
					_cells[c] = list

	func _cell_of(p: Vector2) -> Vector2i:
		return Vector2i(floori(p.x / _cell), floori(p.y / _cell))

	## Same answer as DMMapData.sector_at() on the map it was made from.
	func sector_at(pt: Vector2) -> int:
		var c := _cell_of(pt)
		if not _cells.has(c):
			return -1
		var list: PackedInt32Array = _cells[c]
		# Lowest sector index wins, as in DMMapData.sector_at().
		var best := -1
		for i in list:
			if (best < 0 or _owner[i] < best) and _boxes[i].has_point(pt) and DMGeo.point_in_polygon(pt, _polys[i]):
				best = _owner[i]
		return best


## Draws a new sector from a closed loop of map points.
##
## Works like drawing in a Doom map editor: the new area is cut out of any
## sector it overlaps, and sectors it completely surrounds are kept and cut out
## of the new one. Heights and materials come from the sector the loop was
## drawn inside, or from `defaults` when drawn in empty space.
## Returns the new sector's index, or why it couldn't be drawn.
func add_loop(points: PackedVector2Array, defaults: DMSector) -> DMResult:
	var loop := DMGeo.normalized(points)
	if loop.size() < 3 or absf(DMGeo.signed_area(loop)) < DMGeo.MIN_AREA:
		return DMResult.failure("The shape is too small or flat.", -1)
	if not DMGeo.is_simple(loop):
		return DMResult.failure("The lines cross each other. Draw a shape whose sides don't cross.", -1)

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
		return DMResult.failure("That area is already covered by sectors.", -1)
	fresh.polygons = pieces
	sectors.append(fresh)
	emit_changed()
	return DMResult.success(sectors.size() - 1)


## Removes the given sectors; their area becomes empty space (solid wall).
func delete_sectors(indices: Array[int]) -> void:
	var drop := {}
	for i in indices:
		drop[i] = true
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
func move_vertices(from: PackedVector2Array, to: PackedVector2Array, emit := true) -> void:
	if from.size() != to.size():
		push_error("GoDoomBuilder: move_vertices: %d points to move but %d targets" % [from.size(), to.size()])
		return
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
			for k: Vector2i in s.outer_corners:
				var nk := k
				if moves.has(k):
					var moved_to: Vector2 = moves[k]
					nk = key_of(moved_to)
				moved[nk] = s.outer_corners[k]
			s.outer_corners = moved
	for s in sectors:
		for o in s.wall_overrides:
			for end: String in ["a", "b"]:
				var at: Vector2 = o[end]
				var k := key_of(at)
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
	if emit:
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
func bounds_of(indices: Array[int]) -> Rect2:
	var box := Rect2()
	if not _check_indices(indices, "bounds_of"):
		return box
	var first := true
	for i in indices:
		for poly in sectors[i].polygons:
			for q in poly:
				if first:
					box = Rect2(q, Vector2.ZERO)
					first = false
				else:
					box = box.expand(q)
	return box


## Scales the given sectors about `anchor` (factor per axis); shared corners
## of neighbouring sectors move with them.
func scale_sectors(indices: Array[int], anchor: Vector2, factor: Vector2) -> void:
	if not _check_indices(indices, "scale_sectors"):
		return
	var seen := {}
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	for i in indices:
		for poly in sectors[i].polygons:
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
				for k: Vector2i in others:
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
func join_sectors(indices: Array[int]) -> int:
	if indices.is_empty() or not _check_indices(indices, "join_sectors"):
		return -1
	var keep := sectors[indices[0]]
	var polys: Array[PackedVector2Array] = []
	for i in indices:
		polys.append_array(sectors[i].polygons)
		if sectors[i] != keep:
			keep.wall_overrides.append_array(sectors[i].wall_overrides)
	keep.polygons = merge_pieces(polys)
	var drop: Array[int] = []
	for i in range(1, indices.size()):
		drop.append(indices[i])
	var target := sectors[indices[0]]
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

## Walls to thicken: a boundary (a loop, or an open polyline when `open`),
## which of its segments to thicken (`chosen`), which face solid space, and
## optionally where the outward band starts (`outside_points`, else `points`).
class Run:
	var points: PackedVector2Array
	var chosen: Array[bool] = []
	var faces_void: Array[bool] = []
	var open := false
	var outside_points := PackedVector2Array()

	func copy() -> Run:
		var r := Run.new()
		r.points = points
		r.chosen = chosen.duplicate()
		r.faces_void = faces_void.duplicate()
		r.open = open
		r.outside_points = outside_points
		return r

## Gives a sector's walls a thickness of `thickness` meters. `side`: 1 outward
## (the room keeps its size), -1 inward (the room gets smaller), 0 half each.
## Only the sector's outer boundary counts (not the edges around sectors
## inside it). Where it has walls facing solid space, only those get thick:
## outward, they become solid blocks (the sector's wall_thickness), and
## openings into neighbouring sectors stay open. A room with no such walls
## (standing inside another room) gets thick walls all round, taking the
## outward part from the rooms around it. 
func thicken_walls(index: int, thickness: float, side: int) -> DMResult:
	if not _check_indices([index], "thicken_walls"):
		return DMResult.failure("That sector doesn't exist.", index)
	if thickness <= DMGeo.SNAP:
		return DMResult.failure("Set a wall thickness first.", index)
	var runs: Array[Run] = []
	var void_walls := false
	for loop in boundary_loops(index):
		if DMGeo.signed_area(loop.points) <= 0.0:
			continue # Around something inside this sector, not its outer wall.
		var run := Run.new()
		run.points = loop.points
		run.faces_void = loop.faces_void
		run.chosen = loop.faces_void.duplicate()
		if run.chosen.has(true):
			void_walls = true
		else:
			run.chosen.fill(true)
		runs.append(run)
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
func thicken_edge(index: int, a: Vector2, b: Vector2, thickness: float, side: int) -> DMResult:
	if not _check_indices([index], "thicken_edge"):
		return DMResult.failure("That sector doesn't exist.", index)
	if thickness <= DMGeo.SNAP:
		return DMResult.failure("Set a wall thickness first.", index)
	if a.distance_to(b) < DMGeo.LINE_EPS:
		return DMResult.failure("That wall is too short.", index)
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
	var run := Run.new()
	run.points = PackedVector2Array([a, b])
	run.chosen = [true, false]
	run.open = true
	run.faces_void = [faces_void, false]
	run.outside_points = PackedVector2Array([a2, b2])
	var runs: Array[Run] = [run]
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
func _apply_bands(index: int, runs: Array[Run], thickness: float, side: int, set_void_thickness: Callable) -> DMResult:
	var outside := _outside_part(thickness, side)
	var inside := thickness - outside
	var target := sectors[index]
	# Only these of the target's settings are compared afterwards.
	var thickness_before := target.wall_thickness
	var overrides_before: Array[Dictionary] = []
	for o in target.wall_overrides:
		overrides_before.append(o.duplicate())
	var corners_before := target.outer_corners.duplicate()
	var total_before := 0.0
	for s in sectors:
		total_before += s.area()
	if inside > 0.0:
		target.polygons = _subtract_all(target.polygons, _wall_bands(runs, inside, 1.0))
	if outside > 0.0:
		var out_runs: Array[Run] = []
		for run in runs:
			var r := run.copy()
			for i in r.chosen.size():
				r.chosen[i] = run.chosen[i] and not run.faces_void[i]
			if not r.outside_points.is_empty():
				r.points = r.outside_points
			out_runs.append(r)
		var bands := _wall_bands(out_runs, outside, -1.0)
		for s in sectors:
			if s != target:
				s.polygons = _subtract_all(s.polygons, bands)
		set_void_thickness.call()
	var total_after := 0.0
	var empty: Array[int] = []
	for i in sectors.size():
		total_after += sectors[i].area()
		if sectors[i].polygons.is_empty():
			empty.append(i)
	if empty.has(index):
		return DMResult.failure("The room is too small for walls that thick.", index)
	var props_changed: bool = not is_equal_approx(target.wall_thickness, thickness_before) or target.wall_overrides != overrides_before or target.outer_corners != corners_before
	if absf(total_after - total_before) < DMGeo.MIN_AREA and not props_changed:
		return DMResult.failure("Nothing changed: the walls are already that thick.", index)
	delete_sectors(empty)
	return DMResult.success(sectors.find(target))


func boundary_loops(index: int) -> Array[DMBuilder.Loop]:
	if not _check_indices([index], "boundary_loops"):
		return []
	return DMBuilder.chain_loops(DMBuilder.build(self).outlines[index], self)


## Quads covering the chosen segments of each run, `width` meters toward the
## sector (dir 1) or away from it (dir -1). Neighbouring chosen segments meet
## at mitered corners; a run's ends (next to unchosen segments) are square.
## Runs marked "open" are polylines, not loops.
static func _wall_bands(runs: Array[Run], width: float, dir: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for run in runs:
		var loop := run.points
		var chosen := run.chosen
		var open := run.open
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
	if p.is_empty():
		return Rect2()
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
	if not _check_indices([index], "simplify_sector"):
		return 0
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
				for k in DMSector.OVERRIDE_KEYS:
					if o1.has(k):
						props[k] = o1[k]
				s.set_wall_override(a, c, props)
			pts.remove_at(i)
			changed = true
			break
	return pts


static func _same_wall_settings(o1: Dictionary, o2: Dictionary) -> bool:
	for k in DMSector.OVERRIDE_KEYS:
		if o1.has(k) != o2.has(k):
			return false
		if not o1.has(k):
			continue
		var x: Variant = o1[k]
		var y: Variant = o2[k]
		if typeof(x) == TYPE_FLOAT or typeof(y) == TYPE_FLOAT:
			var fx: float = x
			var fy: float = y
			if not is_equal_approx(fx, fy):
				return false
		elif x is Vector2 and y is Vector2:
			var vx: Vector2 = x
			var vy: Vector2 = y
			if not vx.is_equal_approx(vy):
				return false
		elif x != y:
			return false
	return true


# --- Copy, paste and transforms ------------------------------------------------

## Copies of the given sectors moved by `xf` (a 2D transform of map points:
## move, rotate, mirror). Their wall settings and hand-placed outer corners
## move with them; a mirror flips the polygons back to counter-clockwise.
static func transformed_sectors(list: Array[DMSector], xf: Transform2D) -> Array[DMSector]:
	var out: Array[DMSector] = []
	var mirrored := xf.determinant() < 0.0
	for src in list:
		var s := src.duplicate_sector()
		var polys: Array[PackedVector2Array] = []
		for p in s.polygons:
			var q := PackedVector2Array()
			for v in p:
				q.append(_snap(xf * v))
			if mirrored:
				q.reverse()
			polys.append(q)
		s.polygons = polys
		for o in s.wall_overrides:
			var edge := DMSector.setting_edge(o)
			var a := _snap(xf * edge[0])
			var b := _snap(xf * edge[1])
			# Edges run with the sector on their left; a mirror swaps their ends.
			o.a = b if mirrored else a
			o.b = a if mirrored else b
		var corners := {}
		for k: Vector2i in s.outer_corners:
			var inner := Vector2(k) * DMGeo.SNAP
			var offset: Vector2 = s.outer_corners[k]
			corners[key_of(_snap(xf * inner))] = xf.basis_xform(offset)
		s.outer_corners = corners
		out.append(s)
	return out


static func _snap(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, DMGeo.SNAP), snappedf(p.y, DMGeo.SNAP))


## Moves, rotates or mirrors the given sectors in place (their neighbours stay
## put). Call validate() afterwards: they may now overlap their neighbours.
func transform_sectors(indices: Array[int], xf: Transform2D) -> void:
	if not _check_indices(indices, "transform_sectors"):
		return
	var list: Array[DMSector] = []
	for i in indices:
		list.append(sectors[i])
	var moved := transformed_sectors(list, xf)
	for k in indices.size():
		var target := sectors[indices[k]]
		target.polygons = moved[k].polygons
		target.wall_overrides = moved[k].wall_overrides
		target.outer_corners = moved[k].outer_corners
	emit_changed()


## Pastes copies of `list` moved by `xf`. Like drawing, the pasted area is
## cut out of the sectors already there. Returns {ok, indices, message}.
func paste_sectors(list: Array[DMSector], xf: Transform2D) -> DMResult:
	var pasted := transformed_sectors(list, xf)
	var cutters: Array[PackedVector2Array] = []
	for s in pasted:
		cutters.append_array(s.polygons)
	if cutters.is_empty():
		return DMResult.failure("Nothing to paste.")
	var keep: Array[DMSector] = []
	for s in sectors:
		s.polygons = _subtract_all(s.polygons, cutters)
		if not s.polygons.is_empty():
			keep.append(s)
	sectors = keep
	var indices: Array[int] = []
	for s in pasted:
		sectors.append(s)
		indices.append(sectors.size() - 1)
	emit_changed()
	return DMResult.success(-1, indices)


# --- Corners -------------------------------------------------------------------

## Adds a corner at `p` to every wall passing through it (so neighbouring
## sectors sharing the wall get it too). Returns false when no wall passes
## through `p` or there's already a corner there.
func insert_vertex(p: Vector2) -> bool:
	p = _snap(p)
	var before := all_vertices().size()
	split_edges_at(p)
	if all_vertices().size() == before:
		return false
	emit_changed()
	return true


## Removes the corner at `p` from every sector that has it (its two walls
## become one). Pieces left with fewer than three corners go, and so do
## sectors left with no pieces. Returns false when there's no corner at `p`.
## Call validate() afterwards: the straightened wall may cross another.
func remove_vertex(p: Vector2) -> bool:
	var k := key_of(p)
	var found := false
	var keep: Array[DMSector] = []
	for s in sectors:
		var polys: Array[PackedVector2Array] = []
		for poly in s.polygons:
			var q := PackedVector2Array()
			for v in poly:
				if key_of(v) == k:
					found = true
				else:
					q.append(v)
			if q.size() != poly.size():
				q = DMGeo.clean(q)
			if q.size() >= 3:
				polys.append(q)
		s.polygons = polys
		s.outer_corners.erase(k)
		if not polys.is_empty():
			keep.append(s)
	if not found:
		return false
	sectors = keep
	emit_changed()
	return true


# --- Curves --------------------------------------------------------------------

## Bends the wall a -> b (an edge of sector `index`, the sector on its left)
## into an arc of `segments` straight pieces whose middle is `bulge` meters
## from the straight line: positive bulges away from the sector (the room
## grows), negative into it. Sectors sharing the wall bend with it, and
## corners on the wall move onto the arc. Call validate()
## afterwards.
func curve_edge(index: int, a: Vector2, b: Vector2, segments: int, bulge: float) -> DMResult:
	if not _check_indices([index], "curve_edge"):
		return DMResult.failure("That sector doesn't exist.")
	var chord := b - a
	var length := chord.length()
	if length < DMGeo.LINE_EPS:
		return DMResult.failure("That wall is too short.")
	if segments < 2:
		return DMResult.failure("Use at least 2 segments.")
	if absf(bulge) < DMGeo.SNAP:
		return DMResult.failure("Set a bulge first (how far the middle of the wall moves).")
	if absf(bulge) > length * 0.5 + DMGeo.SNAP:
		return DMResult.failure("The bulge can be at most half the wall's length (a half circle).")
	var u := chord / length
	var out := Vector2(u.y, -u.x) # Away from the sector (it's on the left).
	# Circle through a, b and the bulged middle.
	var h := bulge
	var r := (length * length / 4.0 + h * h) / (2.0 * absf(h))
	var center := (a + b) * 0.5 + out * signf(h) * (absf(h) - r)
	var a0 := (a - center).angle()
	var sweep := 2.0 * asin(clampf(length * 0.5 / r, -1.0, 1.0))
	# Turn toward b through the bulged side.
	var mid_dir := (a + b) * 0.5 + out * h - center
	var test := Vector2.from_angle(a0 + sweep * 0.5)
	if test.dot(mid_dir.normalized()) < 0.0:
		sweep = -sweep
	var arc := func(t: float) -> Vector2:
		return _snap(center + Vector2.from_angle(a0 + sweep * t) * r)
	var ts: Array[float] = []
	for i in range(1, segments):
		ts.append(float(i) / segments)
	# Parameter (0..1) along a -> b of a point on the wall, or -1.
	var param := func(p: Vector2) -> float:
		if absf(u.cross(p - a)) > DMGeo.LINE_EPS:
			return -1.0
		var t := u.dot(p - a) / length
		return t if t > -1e-6 and t < 1.0 + 1e-6 else -1.0
	var changed := false
	for s in sectors:
		var polys: Array[PackedVector2Array] = []
		for poly in s.polygons:
			var n := poly.size()
			var q := PackedVector2Array()
			for i in n:
				var p := poly[i]
				var nx := poly[(i + 1) % n]
				var tp: float = param.call(p)
				var tn: float = param.call(nx)
				var here: Vector2 = arc.call(tp) if tp > 1e-6 and tp < 1.0 - 1e-6 else p
				q.append(here)
				if tp < 0.0 or tn < 0.0 or absf(tp - tn) < 1e-9:
					continue
				# This edge lies on the wall: follow the arc from p to nx.
				changed = true
				if tp < tn:
					for t in ts:
						if t > tp + 1e-6 and t < tn - 1e-6:
							var on: Vector2 = arc.call(t)
							q.append(on)
				else:
					for j in range(ts.size() - 1, -1, -1):
						if ts[j] < tp - 1e-6 and ts[j] > tn + 1e-6:
							var on: Vector2 = arc.call(ts[j])
							q.append(on)
			polys.append(DMGeo.clean(q))
		s.polygons = polys
	if not changed:
		return DMResult.failure("That wall isn't part of the sector.")
	# Settings on the straight wall no longer match its pieces.
	var target := sectors[index]
	target.set_wall_override(a, b, DMSector.cleared_settings())
	emit_changed()
	return DMResult.success()


# --- Stairs --------------------------------------------------------------------

## Makes stairs from the given sectors, in order: each floor is `step`
## meters above the one before (negative goes down), starting from the
## first one's floor. With `move_ceilings` each ceiling moves by as much as
## its floor; otherwise ceilings only move up where a floor would pass them.
func make_stairs(indices: Array[int], step: float, move_ceilings: bool) -> void:
	if indices.is_empty() or not _check_indices(indices, "make_stairs"):
		return
	var base := sectors[indices[0]].floor_height
	for k in indices.size():
		var s := sectors[indices[k]]
		var target := base + step * k
		var delta := target - s.floor_height
		s.floor_height = target
		if move_ceilings:
			s.ceiling_height += delta
		else:
			s.ceiling_height = maxf(s.ceiling_height, target)
	emit_changed()


## Cuts sector `index` into `count` strips across `direction` (a unit axis:
## Vector2.RIGHT is +X, Vector2.DOWN is +Z, ...), then makes them stairs that
## rise `step` meters per strip in that direction (see make_stairs). Returns the
## strips' indices (first strip first) in `indices`.
func split_into_steps(index: int, count: int, direction: Vector2, step: float, move_ceilings: bool) -> DMResult:
	if not _check_indices([index], "split_into_steps"):
		return DMResult.failure("That sector doesn't exist.")
	if count < 2:
		return DMResult.failure("Use at least 2 steps.")
	var src := sectors[index]
	var dir := direction.normalized()
	var side := Vector2(-dir.y, dir.x)
	# Extent of the sector along the direction and across it.
	var lo := INF
	var hi := -INF
	var lo2 := INF
	var hi2 := -INF
	for p in src.polygons:
		for v in p:
			lo = minf(lo, v.dot(dir))
			hi = maxf(hi, v.dot(dir))
			lo2 = minf(lo2, v.dot(side))
			hi2 = maxf(hi2, v.dot(side))
	var depth := (hi - lo) / count
	if depth < DMGeo.LINE_EPS * 10.0:
		return DMResult.failure("The sector is too short for that many steps.")
	lo2 -= 1.0
	hi2 += 1.0
	var strips: Array[DMSector] = []
	for k in count:
		var d0 := lo + depth * k
		var d1 := hi + 1.0 if k == count - 1 else lo + depth * (k + 1)
		if k == 0:
			d0 = lo - 1.0
		var band := PackedVector2Array([dir * d0 + side * lo2, dir * d1 + side * lo2, dir * d1 + side * hi2, dir * d0 + side * hi2])
		band = DMGeo.normalized(band)
		var pieces: Array[PackedVector2Array] = []
		for p in src.polygons:
			pieces.append_array(_normalize_pieces(Geometry2D.intersect_polygons(p, band)))
		if pieces.is_empty():
			continue
		var s := src.duplicate_sector()
		s.polygons = pieces
		strips.append(s)
	if strips.size() < 2:
		return DMResult.failure("The sector couldn't be split into steps that way.")
	sectors.remove_at(index)
	var indices: Array[int] = []
	for s in strips:
		sectors.append(s)
		indices.append(sectors.size() - 1)
	make_stairs(indices, step, move_ceilings)
	return DMResult.success(-1, indices)


static func _normalize_pieces(results: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for r in DMGeo.classify(results).outers:
		var c := DMGeo.normalized(r)
		if c.size() >= 3 and absf(DMGeo.signed_area(c)) >= DMGeo.MIN_AREA:
			out.append(c)
	return out
