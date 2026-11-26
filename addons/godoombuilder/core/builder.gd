@tool
class_name DMBuilder
extends RefCounted
## Turns sector data into a mesh: floors, ceilings and the walls between
## sectors, the way a Doom map is built from its sectors.


enum Part { FLOOR, CEILING, WALL }


## Texture size in meters: one texture repeat per meter by default.
const UV_SCALE := 1.0


## A sector boundary loop (see chain_loops): segment i runs from points[i]
## to points[i + 1] (wrapping), and faces_void[i] tells whether solid space
## (no sector) is on its other side.
class Loop:
	var points: PackedVector2Array
	var faces_void: Array[bool]

	func _init(pts: PackedVector2Array, voids: Array[bool]) -> void:
		points = pts
		faces_void = voids


## Builds the map: every floor, ceiling and wall face (see DMBuildInfo).
## Turn it into a renderable mesh with to_mesh().
static func build(data: DMMapData) -> DMBuildInfo:
	var info := DMBuildInfo.new()
	if data == null:
		info.finish()
		return info
	var sectors := data.sectors
	# Outline points are gathered per sector, then packed at the end.
	var outline_parts: Array[PackedVector2Array] = []
	for si in sectors.size():
		outline_parts.append(PackedVector2Array())

	# Floors and ceilings.
	var no_edge := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	for si in sectors.size():
		var s := sectors[si]
		if s.is_closed():
			continue
		var floor_uv := s.uv_transform(Part.FLOOR)
		var ceiling_uv := s.uv_transform(Part.CEILING)
		for poly in s.polygons:
			var tri := Geometry2D.triangulate_polygon(poly)
			var floor_pts := PackedVector3Array()
			var ceil_pts := PackedVector3Array()
			for q in poly:
				floor_pts.append(Vector3(q.x, s.floor_height, q.y))
				ceil_pts.append(Vector3(q.x, s.ceiling_height, q.y))
			if s.has_floor:
				info.add_face(floor_pts, tri, Vector3.UP, info.slot_of(s.floor_material), si, Part.FLOOR, no_edge, floor_uv)
			if s.has_ceiling:
				info.add_face(ceil_pts, tri, Vector3.DOWN, info.slot_of(s.ceiling_material), si, Part.CEILING, no_edge, ceiling_uv)

	# Walls: every polygon edge, split where it borders other sectors.
	var ea := PackedVector2Array()
	var eb := PackedVector2Array()
	var es := PackedInt32Array()
	for si in sectors.size():
		for poly in sectors[si].polygons:
			var n := poly.size()
			for i in n:
				ea.append(poly[i])
				eb.append(poly[(i + 1) % n])
				es.append(si)
	var grid := EdgeGrid.new(ea, eb, DMGeo.LINE_EPS)
	for k in ea.size():
		var a := ea[k]
		var b := eb[k]
		var length := a.distance_to(b)
		if length < DMGeo.LINE_EPS:
			continue
		var u := (b - a) / length
		var emin := a.min(b) - Vector2.ONE * DMGeo.LINE_EPS
		var emax := a.max(b) + Vector2.ONE * DMGeo.LINE_EPS
		# Pieces of this edge covered by other edges running the other way:
		# (from, to, that edge's sector), in meters along this edge.
		var spans: Array[Vector3] = []
		for j in grid.near(k):
			var c := ea[j]
			var d := eb[j]
			if c.max(d).x < emin.x or c.max(d).y < emin.y or c.min(d).x > emax.x or c.min(d).y > emax.y:
				continue
			if absf(u.cross(c - a)) > DMGeo.LINE_EPS or absf(u.cross(d - a)) > DMGeo.LINE_EPS:
				continue
			if u.dot(d - c) >= 0.0:
				continue
			var t0 := u.dot(d - a)
			var t1 := u.dot(c - a)
			var lo := maxf(0.0, minf(t0, t1))
			var hi := minf(length, maxf(t0, t1))
			if hi - lo > DMGeo.LINE_EPS:
				spans.append(Vector3(lo, hi, es[j]))
		spans.sort_custom(func(x: Vector3, y: Vector3) -> bool: return x.x < y.x)
		var at := 0.0
		var pieces: Array[Vector3] = []
		for sp in spans:
			if sp.x > at + DMGeo.LINE_EPS:
				pieces.append(Vector3(at, sp.x, -1))
			var lo2 := maxf(sp.x, at)
			if sp.y > lo2 + DMGeo.LINE_EPS:
				pieces.append(Vector3(lo2, sp.y, sp.z))
			at = maxf(at, sp.y)
		if length > at + DMGeo.LINE_EPS:
			pieces.append(Vector3(at, length, -1))
		for pc in pieces:
			var p0 := a + u * pc.x
			var p1 := a + u * pc.y
			var ni := roundi(pc.z)
			if ni != es[k]:
				outline_parts[es[k]].append(p0)
				outline_parts[es[k]].append(p1)
			_wall_piece(info, sectors, es[k], ni, p0, p1, a, b)

	info.outlines = outline_parts

	# Thick walls: solid blocks built outward from walls that face solid space.
	var locator: DMMapData.SectorLocator = null
	for si in sectors.size():
		var s := sectors[si]
		if s.is_closed() or (s.wall_thickness <= 0.0 and not _has_thickness_override(s)):
			continue
		if locator == null:
			locator = data.locator()
		for loop in chain_loops(info.outlines[si], data, locator):
			_thick_walls(info, s, si, loop)
	info.finish()
	return info


## Buckets edges into a uniform grid by their bounding boxes, so finding the
## edges that could touch one edge doesn't mean testing every edge in the map.
## Any two edges whose boxes (grown by `eps`) overlap share at least one cell.
class EdgeGrid:
	var _cell := 1.0
	## Cell -> PackedInt32Array of edge indices.
	var _cells := {}
	var _lo: Array[Vector2i] = []
	var _hi: Array[Vector2i] = []
	var _stamp := PackedInt32Array()
	var _query := 0

	func _init(ea: PackedVector2Array, eb: PackedVector2Array, eps: float) -> void:
		var n := ea.size()
		var total := 0.0
		for i in n:
			total += ea[i].distance_to(eb[i])
		# About one edge length per cell: long edges cover a few cells, short
		# ones one, and a cell holds only the edges near it.
		_cell = maxf(total / maxf(float(n), 1.0), 0.05)
		_stamp.resize(n)
		_stamp.fill(-1)
		var lists: Array[PackedInt32Array] = []
		var index_of := {}
		for i in n:
			var lo := _cell_of(ea[i].min(eb[i]) - Vector2.ONE * eps)
			var hi := _cell_of(ea[i].max(eb[i]) + Vector2.ONE * eps)
			_lo.append(lo)
			_hi.append(hi)
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					var c := Vector2i(x, y)
					if not index_of.has(c):
						index_of[c] = lists.size()
						lists.append(PackedInt32Array())
					var at: int = index_of[c]
					lists[at].append(i)
		for c: Vector2i in index_of:
			var at: int = index_of[c]
			_cells[c] = lists[at]

	func _cell_of(p: Vector2) -> Vector2i:
		return Vector2i(floori(p.x / _cell), floori(p.y / _cell))

	## Indices of the other edges sharing a cell with edge k (each once).
	func near(k: int) -> PackedInt32Array:
		_query += 1
		_stamp[k] = _query
		var out := PackedInt32Array()
		for x in range(_lo[k].x, _hi[k].x + 1):
			for y in range(_lo[k].y, _hi[k].y + 1):
				var c := Vector2i(x, y)
				if not _cells.has(c):
					continue
				var list: PackedInt32Array = _cells[c]
				for j in list:
					if _stamp[j] != _query:
						_stamp[j] = _query
						out.append(j)
		return out


static func _has_thickness_override(s: DMSector) -> bool:
	for o in s.wall_overrides:
		if o.has("thickness"):
			return true
	return false


## A sector's outline segments (see DMBuildInfo.outlines) chained into closed
## loops running with the sector on their left. `locator` (optional, from
## data.locator()) speeds up the solid-space test.
static func chain_loops(outline: PackedVector2Array, data: DMMapData, locator: DMMapData.SectorLocator = null) -> Array[Loop]:
	# Start point -> list of segment ends starting there.
	var next := {}
	for i in range(0, outline.size(), 2):
		var key := DMMapData.key_of(outline[i])
		if not next.has(key):
			next[key] = PackedVector2Array()
		var ends: PackedVector2Array = next[key]
		ends.append(outline[i + 1])
		next[key] = ends
	var loops: Array[Loop] = []
	while not next.is_empty():
		var start_key: Vector2i = next.keys()[0]
		var pts := PackedVector2Array()
		var voids: Array[bool] = []
		var k := start_key
		var guard := outline.size()
		while next.has(k) and guard > 0:
			guard -= 1
			var ends: PackedVector2Array = next[k]
			var b := ends[ends.size() - 1]
			ends.remove_at(ends.size() - 1)
			if ends.is_empty():
				next.erase(k)
			else:
				next[k] = ends
			var a := Vector2(k) * DMGeo.SNAP
			pts.append(a)
			var out := Vector2(b.y - a.y, a.x - b.x).normalized() * 0.01
			var probe := (a + b) * 0.5 + out
			voids.append((locator.sector_at(probe) if locator != null else data.sector_at(probe)) < 0)
			k = DMMapData.key_of(b)
			if k == start_key:
				break
		if pts.size() >= 3:
			loops.append(Loop.new(pts, voids))
	return loops


## Builds the outward blocks for one boundary loop of a sector: an outer face,
## a top and a bottom for each thick wall, mitered where two thick walls meet
## and closed with an end face where a thick wall stops.
static func _thick_walls(info: DMBuildInfo, s: DMSector, si: int, loop: Loop) -> void:
	var pts := loop.points
	var n := pts.size()
	var thick := PackedFloat32Array()
	var bottoms := PackedFloat32Array()
	var tops := PackedFloat32Array()
	var outs := PackedVector2Array()
	var uvs: Array[Transform2D] = []
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var o := s.wall_override(a, b)
		uvs.append(s.uv_transform(Part.WALL, o))
		var t := DMSector.setting_float(o, "thickness", s.wall_thickness)
		if not loop.faces_void[i] or DMSector.setting_bool(o, "hidden"):
			t = 0.0
		thick.append(t)
		bottoms.append(DMSector.setting_float(o, "bottom", s.floor_height))
		tops.append(DMSector.setting_float(o, "top", s.ceiling_height))
		var d := (b - a).normalized()
		outs.append(Vector2(d.y, -d.x))
	var slot := info.slot_of(s.wall_material)
	for i in n:
		var t := thick[i]
		if t <= 0.0 or tops[i] <= bottoms[i] + DMGeo.HEIGHT_EPS:
			continue
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var prev := (i - 1 + n) % n
		var nxt := (i + 1) % n
		var joined_start := is_equal_approx(thick[prev], t)
		var joined_end := is_equal_approx(thick[nxt], t)
		var oa := (_miter_dir(outs[prev], outs[i]) if joined_start else outs[i]) * t
		var ob := (_miter_dir(outs[i], outs[nxt]) if joined_end else outs[i]) * t
		var ka := DMMapData.key_of(a)
		var kb := DMMapData.key_of(b)
		if s.outer_corners.has(ka):
			oa = s.outer_corners[ka]
		if s.outer_corners.has(kb):
			ob = s.outer_corners[kb]
		var a2 := a + oa
		var b2 := b + ob
		var lo := bottoms[i]
		var hi := tops[i]
		var e := DMBuildInfo.OuterEdge.new()
		e.sector = si
		e.a = a
		e.b = b
		e.a2 = a2
		e.b2 = b2
		e.out = outs[i]
		e.thickness = t
		e.h = lo
		info.outer_edges.append(e)
		for corner: Array[Vector2] in [[a, a2] as Array[Vector2], [b, b2] as Array[Vector2]]:
			var known := false
			for c in info.outer_corners:
				if c.sector == si and c.inner.is_equal_approx(corner[0]) and c.outer.is_equal_approx(corner[1]):
					known = true
			if not known:
				info.outer_corners.append(DMBuildInfo.OuterCorner.new(si, corner[0], corner[1], lo))
		var edge := PackedVector2Array([a, b])
		var out3 := Vector3(outs[i].x, 0.0, outs[i].y)
		var quad := PackedInt32Array([0, 1, 2, 0, 2, 3])
		# Outer face.
		info.add_face(PackedVector3Array([Vector3(b2.x, lo, b2.y), Vector3(a2.x, lo, a2.y),
			Vector3(a2.x, hi, a2.y), Vector3(b2.x, hi, b2.y)]), quad, out3, slot, si, Part.WALL, edge, uvs[i])
		# Top and bottom.
		info.add_face(PackedVector3Array([Vector3(a.x, hi, a.y), Vector3(b.x, hi, b.y),
			Vector3(b2.x, hi, b2.y), Vector3(a2.x, hi, a2.y)]), quad, Vector3.UP, slot, si, Part.WALL, edge, uvs[i])
		info.add_face(PackedVector3Array([Vector3(a.x, lo, a.y), Vector3(b.x, lo, b.y),
			Vector3(b2.x, lo, b2.y), Vector3(a2.x, lo, a2.y)]), quad, Vector3.DOWN, slot, si, Part.WALL, edge, uvs[i])
		# Ends where this thick wall stops.
		var along := Vector3(b.x - a.x, 0.0, b.y - a.y).normalized()
		if not joined_start:
			info.add_face(PackedVector3Array([Vector3(a.x, lo, a.y), Vector3(a2.x, lo, a2.y),
				Vector3(a2.x, hi, a2.y), Vector3(a.x, hi, a.y)]), quad, -along, slot, si, Part.WALL, edge, uvs[i])
		if not joined_end:
			info.add_face(PackedVector3Array([Vector3(b.x, lo, b.y), Vector3(b2.x, lo, b2.y),
				Vector3(b2.x, hi, b2.y), Vector3(b.x, hi, b.y)]), quad, along, slot, si, Part.WALL, edge, uvs[i])


## Corner offset direction (length >= 1) for two neighbouring wall normals.
static func _miter_dir(n1: Vector2, n2: Vector2) -> Vector2:
	var m := (n1 + n2) / maxf(1.0 + n1.dot(n2), 0.1)
	return m.normalized() * 4.0 if m.length() > 4.0 else m


## One piece p0 -> p1 of sector si's edge ea -> eb, with sector ni (or -1:
## solid space) on its other side.
static func _wall_piece(info: DMBuildInfo, sectors: Array[DMSector],
		si: int, ni: int, p0: Vector2, p1: Vector2, ea: Vector2, eb: Vector2) -> void:
	var s := sectors[si]
	if s.is_closed() or ni == si:
		return
	var d := p1 - p0
	var inward := Vector3(-d.y, 0.0, d.x).normalized()
	var slot := info.slot_of(s.wall_material)
	var o := s.wall_override(p0, p1)
	var uvx := s.uv_transform(Part.WALL, o)
	var edge := PackedVector2Array([ea, eb])
	var hidden := DMSector.setting_bool(o, "hidden")
	if ni < 0:
		var bottom := DMSector.setting_float(o, "bottom", s.floor_height)
		var top := DMSector.setting_float(o, "top", s.ceiling_height)
		if hidden:
			info.hidden_walls.append(DMBuildInfo.HiddenWall.new(p0, p1, bottom, top, si))
		elif top > bottom + DMGeo.HEIGHT_EPS:
			_wall(info, p0, p1, bottom, top, inward, slot, si, edge, uvx)
		return
	if hidden:
		info.hidden_walls.append(DMBuildInfo.HiddenWall.new(p0, p1, s.floor_height, s.ceiling_height, si))
		return
	var t := sectors[ni]
	var lower_top := minf(t.floor_height, s.ceiling_height)
	if lower_top > s.floor_height + DMGeo.HEIGHT_EPS:
		_wall(info, p0, p1, s.floor_height, lower_top, inward, slot, si, edge, uvx)
	var upper_bottom := maxf(t.ceiling_height, s.floor_height)
	upper_bottom = maxf(upper_bottom, lower_top)
	# Two sectors open to the sky: no wall between their ceiling heights.
	if not s.has_ceiling and not t.has_ceiling:
		return
	if s.ceiling_height > upper_bottom + DMGeo.HEIGHT_EPS:
		_wall(info, p0, p1, upper_bottom, s.ceiling_height, inward, slot, si, edge, uvx)


static func _wall(info: DMBuildInfo, p0: Vector2, p1: Vector2, bottom: float, top: float,
		inward: Vector3, slot: int, si: int, edge: PackedVector2Array, uvx: Transform2D) -> void:
	var pts := PackedVector3Array([
		Vector3(p0.x, bottom, p0.y), Vector3(p1.x, bottom, p1.y),
		Vector3(p1.x, top, p1.y), Vector3(p0.x, top, p0.y)])
	info.add_face(pts, PackedInt32Array([0, 1, 2, 0, 2, 3]), inward, slot, si, Part.WALL, edge, uvx)


## World-aligned texture coordinates, so textures line up across neighbouring
## faces: floors and ceilings are mapped from above, walls along their length
## with the texture upright.
static func uv_at(p: Vector3, normal: Vector3) -> Vector2:
	if absf(normal.y) > 0.5:
		return Vector2(p.x, p.z) / UV_SCALE
	var along := Vector3.UP.cross(normal).normalized()
	return Vector2(p.dot(along), -p.y) / UV_SCALE


## The tangent (texture U direction, with the bitangent sign in w) matching
## uv_at() followed by the face's texture transform `uvx`, so normal-mapped
## materials work without generating tangents. (Checked against
## SurfaceTool.generate_tangents in map_test.)
static func tangent_at(normal: Vector3, uvx := Transform2D.IDENTITY) -> Plane:
	# How the world-aligned coordinates change across the face.
	var gu := Vector3.RIGHT
	var gv := Vector3.BACK
	if absf(normal.y) <= 0.5:
		gu = Vector3.UP.cross(normal).normalized()
		gv = Vector3.DOWN
	# ... and the final ones, after the texture transform.
	var tu := gu * uvx.x.x + gv * uvx.y.x
	var tv := gu * uvx.x.y + gv * uvx.y.y
	var t := tu.normalized()
	return Plane(t, -1.0 if normal.cross(t).dot(tv) > 0.0 else 1.0)


## A renderable mesh for a build() result: one surface per material.
static func to_mesh(info: DMBuildInfo) -> ArrayMesh:
	var out := ArrayMesh.new()
	var materials := info.materials
	var tris := info.tris
	var tri_face := info.tri_face
	var normals := info.face_normal
	var face_slot := info.face_slot
	var face_uv := info.face_uv
	# Sort the triangles by material in one pass (a counting sort), then fill
	# each surface's arrays in order.
	var slots := materials.size()
	var start := PackedInt32Array()
	start.resize(slots + 1)
	start.fill(0)
	for t in tri_face.size():
		start[face_slot[tri_face[t]] + 1] += 1
	for slot in slots:
		start[slot + 1] += start[slot]
	var fill := start.duplicate()
	var order := PackedInt32Array()
	order.resize(tri_face.size())
	for t in tri_face.size():
		var slot := face_slot[tri_face[t]]
		order[fill[slot]] = t
		fill[slot] += 1
	for slot in slots:
		if start[slot] == start[slot + 1]:
			continue
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var tans := PackedFloat32Array()
		for i in range(start[slot], start[slot + 1]):
			var t := order[i]
			var f := tri_face[t]
			var n := normals[f]
			var uvx := face_uv[f] if f < face_uv.size() else Transform2D.IDENTITY
			var tan := tangent_at(n, uvx)
			for k in 3:
				var p := tris[t * 3 + k]
				verts.append(p)
				norms.append(n)
				uvs.append(uvx * uv_at(p, n))
				tans.append_array([tan.normal.x, tan.normal.y, tan.normal.z, tan.d])
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TANGENT] = tans
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if materials[slot] != null:
			out.surface_set_material(out.get_surface_count() - 1, materials[slot])
	return out
