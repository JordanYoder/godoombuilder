@tool
class_name DMBuilder
extends RefCounted
## Turns sector data into a mesh: floors, ceilings and the walls between
## sectors, the way a Doom map is built from its sectors.


enum Part { FLOOR, CEILING, WALL }


## Texture size in meters: one texture repeat per meter by default.
const UV_SCALE := 1.0


## Builds the map. Returns:
##   materials: Array of Material (null = default), indexed by face_slot
##   face_points: Array of PackedVector3Array, each face's outline in order
##   face_slot / face_sector / face_part / face_normal: per face
##   tris / tri_face: triangles (3 points each) and the face each belongs to
##   face_edge: PackedVector2Array, 2 per face: for walls, the sector polygon
##              edge it was built from (zeros for floors and ceilings)
##   hidden_walls: Array of [p0, p1, bottom, top, sector] for hidden walls
##   outer_corners: Array of {sector, inner, outer, h}: thick walls' outer corners
##   outer_edges: Array of {sector, a, b (inner piece), a2, b2 (outer), out
##                (outward normal), thickness, h}: thick walls' outer faces
##   outlines: Array (per sector) of PackedVector2Array segment pairs, the
##             sector's boundary without seams between its own pieces
## Turn it into a renderable mesh with to_mesh().
static func build(data: DMMapData) -> Dictionary:
	var info := {
		"materials": [],
		"face_points": [],
		"face_slot": PackedInt32Array(),
		"face_edge": PackedVector2Array(),
		"hidden_walls": [],
		"outer_corners": [],
		"outer_edges": [],
		"face_sector": PackedInt32Array(),
		"face_part": PackedInt32Array(),
		"face_normal": PackedVector3Array(),
		"tris": PackedVector3Array(),
		"tri_face": PackedInt32Array(),
		"outlines": [],
	}
	if data == null:
		return info
	var slots := {}
	var sectors := data.sectors
	for si in sectors.size():
		(info.outlines as Array).append(PackedVector2Array())

	# Floors and ceilings.
	for si in sectors.size():
		var s := sectors[si]
		if s.is_closed():
			continue
		for poly in s.polygons:
			var tri := Geometry2D.triangulate_polygon(poly)
			var floor_pts := PackedVector3Array()
			var ceil_pts := PackedVector3Array()
			for q in poly:
				floor_pts.append(Vector3(q.x, s.floor_height, q.y))
				ceil_pts.append(Vector3(q.x, s.ceiling_height, q.y))
			if s.has_floor:
				_add_face(info, floor_pts, tri, Vector3.UP, _slot(info, slots, s.floor_material), si, Part.FLOOR)
			if s.has_ceiling:
				_add_face(info, ceil_pts, tri, Vector3.DOWN, _slot(info, slots, s.ceiling_material), si, Part.CEILING)

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
	for k in ea.size():
		var a := ea[k]
		var b := eb[k]
		var length := a.distance_to(b)
		if length < DMGeo.LINE_EPS:
			continue
		var u := (b - a) / length
		var emin := a.min(b) - Vector2.ONE * DMGeo.LINE_EPS
		var emax := a.max(b) + Vector2.ONE * DMGeo.LINE_EPS
		var spans: Array = []
		for j in ea.size():
			if j == k:
				continue
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
				spans.append([lo, hi, es[j]])
		spans.sort_custom(func(x, y): return x[0] < y[0])
		var at := 0.0
		var pieces: Array = []
		for sp in spans:
			if sp[0] > at + DMGeo.LINE_EPS:
				pieces.append([at, sp[0], -1])
			var lo2: float = maxf(sp[0], at)
			if sp[1] > lo2 + DMGeo.LINE_EPS:
				pieces.append([lo2, sp[1], sp[2]])
			at = maxf(at, sp[1])
		if length > at + DMGeo.LINE_EPS:
			pieces.append([at, length, -1])
		for pc in pieces:
			_wall_piece(info, slots, sectors, es[k], int(pc[2]), a + u * float(pc[0]), a + u * float(pc[1]), a, b)

	# Thick walls: solid blocks built outward from walls that face solid space.
	for si in sectors.size():
		var s := sectors[si]
		if s.is_closed() or (s.wall_thickness <= 0.0 and not _has_thickness_override(s)):
			continue
		for loop in chain_loops(info.outlines[si], data):
			_thick_walls(info, slots, s, si, loop)
	return info


static func _has_thickness_override(s: DMSector) -> bool:
	for o in s.wall_overrides:
		if o.has("thickness"):
			return true
	return false


## A sector's outline segments (see build) chained into closed loops running
## with the sector on their left: [{points, faces_void}], where segment i runs
## from points[i] to points[i + 1] and faces_void[i] tells whether solid space
## (no sector) is on its other side.
static func chain_loops(outline: PackedVector2Array, data: DMMapData) -> Array:
	var next := {}
	for i in range(0, outline.size(), 2):
		var k := DMMapData.key_of(outline[i])
		if not next.has(k):
			next[k] = []
		next[k].append([outline[i], outline[i + 1]])
	var loops: Array = []
	while not next.is_empty():
		var start_key: Vector2i = next.keys()[0]
		var pts := PackedVector2Array()
		var voids: Array = []
		var k := start_key
		var guard := outline.size()
		while next.has(k) and guard > 0:
			guard -= 1
			var ends: Array = next[k]
			var seg: Array = ends.pop_back()
			if ends.is_empty():
				next.erase(k)
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			pts.append(a)
			var out := Vector2(b.y - a.y, a.x - b.x).normalized() * 0.01
			voids.append(data.sector_at((a + b) * 0.5 + out) < 0)
			k = DMMapData.key_of(b)
			if k == start_key:
				break
		if pts.size() >= 3:
			loops.append({"points": pts, "faces_void": voids})
	return loops


## Builds the outward blocks for one boundary loop of a sector: an outer face,
## a top and a bottom for each thick wall, mitered where two thick walls meet
## and closed with an end face where a thick wall stops.
static func _thick_walls(info: Dictionary, slots: Dictionary, s: DMSector, si: int, loop: Dictionary) -> void:
	var pts: PackedVector2Array = loop.points
	var n := pts.size()
	var thick := PackedFloat32Array()
	var bottoms := PackedFloat32Array()
	var tops := PackedFloat32Array()
	var outs := PackedVector2Array()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var o := s.wall_override(a, b)
		var t: float = o.get("thickness", s.wall_thickness)
		if not loop.faces_void[i] or o.get("hidden", false):
			t = 0.0
		thick.append(t)
		bottoms.append(o.get("bottom", s.floor_height))
		tops.append(o.get("top", s.ceiling_height))
		var d := (b - a).normalized()
		outs.append(Vector2(d.y, -d.x))
	var slot := _slot(info, slots, s.wall_material)
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
		info.outer_edges.append({"sector": si, "a": a, "b": b, "a2": a2, "b2": b2, "out": outs[i], "thickness": t, "h": lo})
		for corner in [[a, a2], [b, b2]]:
			var known := false
			for c in info.outer_corners:
				if c.sector == si and (c.inner as Vector2).is_equal_approx(corner[0]) and (c.outer as Vector2).is_equal_approx(corner[1]):
					known = true
			if not known:
				info.outer_corners.append({"sector": si, "inner": corner[0], "outer": corner[1], "h": lo})
		var edge := PackedVector2Array([a, b])
		var out3 := Vector3(outs[i].x, 0.0, outs[i].y)
		# Outer face.
		_add_face(info, PackedVector3Array([Vector3(b2.x, lo, b2.y), Vector3(a2.x, lo, a2.y),
			Vector3(a2.x, hi, a2.y), Vector3(b2.x, hi, b2.y)]), PackedInt32Array([0, 1, 2, 0, 2, 3]),
			out3, slot, si, Part.WALL, edge)
		# Top and bottom.
		var cap := PackedInt32Array([0, 1, 2, 0, 2, 3])
		_add_face(info, PackedVector3Array([Vector3(a.x, hi, a.y), Vector3(b.x, hi, b.y),
			Vector3(b2.x, hi, b2.y), Vector3(a2.x, hi, a2.y)]), cap, Vector3.UP, slot, si, Part.WALL, edge)
		_add_face(info, PackedVector3Array([Vector3(a.x, lo, a.y), Vector3(b.x, lo, b.y),
			Vector3(b2.x, lo, b2.y), Vector3(a2.x, lo, a2.y)]), cap, Vector3.DOWN, slot, si, Part.WALL, edge)
		# Ends where this thick wall stops.
		var along := Vector3(b.x - a.x, 0.0, b.y - a.y).normalized()
		if not joined_start:
			_add_face(info, PackedVector3Array([Vector3(a.x, lo, a.y), Vector3(a2.x, lo, a2.y),
				Vector3(a2.x, hi, a2.y), Vector3(a.x, hi, a.y)]), cap, -along, slot, si, Part.WALL, edge)
		if not joined_end:
			_add_face(info, PackedVector3Array([Vector3(b.x, lo, b.y), Vector3(b2.x, lo, b2.y),
				Vector3(b2.x, hi, b2.y), Vector3(b.x, hi, b.y)]), cap, along, slot, si, Part.WALL, edge)


## Corner offset direction (length >= 1) for two neighbouring wall normals.
static func _miter_dir(n1: Vector2, n2: Vector2) -> Vector2:
	var m := (n1 + n2) / maxf(1.0 + n1.dot(n2), 0.1)
	return m.normalized() * 4.0 if m.length() > 4.0 else m


static func _wall_piece(info: Dictionary, slots: Dictionary, sectors: Array[DMSector],
		si: int, ni: int, p0: Vector2, p1: Vector2, ea: Vector2, eb: Vector2) -> void:
	var s := sectors[si]
	if ni != si:
		var outline: PackedVector2Array = info.outlines[si]
		outline.append(p0)
		outline.append(p1)
		info.outlines[si] = outline
	if s.is_closed():
		return
	var d := p1 - p0
	var inward := Vector3(-d.y, 0.0, d.x).normalized()
	var slot := _slot(info, slots, s.wall_material)
	if ni == si:
		return
	var o := s.wall_override(p0, p1)
	var edge := PackedVector2Array([ea, eb])
	if ni < 0:
		var bottom: float = o.get("bottom", s.floor_height)
		var top: float = o.get("top", s.ceiling_height)
		if o.get("hidden", false):
			info.hidden_walls.append([p0, p1, bottom, top, si])
		elif top > bottom + DMGeo.HEIGHT_EPS:
			_wall(info, p0, p1, bottom, top, inward, slot, si, edge)
		return
	if o.get("hidden", false):
		info.hidden_walls.append([p0, p1, s.floor_height, s.ceiling_height, si])
		return
	var t := sectors[ni]
	var lower_top := minf(t.floor_height, s.ceiling_height)
	if lower_top > s.floor_height + DMGeo.HEIGHT_EPS:
		_wall(info, p0, p1, s.floor_height, lower_top, inward, slot, si, edge)
	var upper_bottom := maxf(t.ceiling_height, s.floor_height)
	upper_bottom = maxf(upper_bottom, lower_top)
	# Two sectors open to the sky: no wall between their ceiling heights.
	if not s.has_ceiling and not t.has_ceiling:
		return
	if s.ceiling_height > upper_bottom + DMGeo.HEIGHT_EPS:
		_wall(info, p0, p1, upper_bottom, s.ceiling_height, inward, slot, si, edge)


static func _wall(info: Dictionary, p0: Vector2, p1: Vector2, bottom: float, top: float,
		inward: Vector3, slot: int, si: int, edge: PackedVector2Array) -> void:
	var pts := PackedVector3Array([
		Vector3(p0.x, bottom, p0.y), Vector3(p1.x, bottom, p1.y),
		Vector3(p1.x, top, p1.y), Vector3(p0.x, top, p0.y)])
	_add_face(info, pts, PackedInt32Array([0, 1, 2, 0, 2, 3]), inward, slot, si, Part.WALL, edge)


## Adds a face: its outline, triangles (indices into `pts`) and the direction
## it faces. Triangles are stored wound so their front side faces `want`.
static func _add_face(info: Dictionary, pts: PackedVector3Array, tri: PackedInt32Array,
		want: Vector3, slot: int, si: int, part: int, edge := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])) -> int:
	var f: int = (info.face_points as Array).size()
	info.face_edge.append_array(edge)
	info.face_points.append(pts)
	info.face_slot.append(slot)
	info.face_sector.append(si)
	info.face_part.append(part)
	info.face_normal.append(want.normalized())
	for i in range(0, tri.size(), 3):
		var a := pts[tri[i]]
		var b := pts[tri[i + 1]]
		var c := pts[tri[i + 2]]
		# Godot shows a triangle's front when its corners run clockwise as seen
		# from the front, i.e. when (b - a) x (c - a) points away from the viewer.
		if (b - a).cross(c - a).dot(want) > 0.0:
			var t := b
			b = c
			c = t
		info.tris.append_array([a, b, c])
		info.tri_face.append(f)
	return f


static func _slot(info: Dictionary, slots: Dictionary, mat: Material) -> int:
	if slots.has(mat):
		return slots[mat]
	info.materials.append(mat)
	slots[mat] = (info.materials as Array).size() - 1
	return slots[mat]


## World-aligned texture coordinates, so textures line up across neighbouring
## faces: floors and ceilings are mapped from above, walls along their length
## with the texture upright.
static func uv_at(p: Vector3, normal: Vector3) -> Vector2:
	if absf(normal.y) > 0.5:
		return Vector2(p.x, p.z) / UV_SCALE
	var along := Vector3.UP.cross(normal).normalized()
	return Vector2(p.dot(along), -p.y) / UV_SCALE


## A renderable mesh for a build() result: one surface per material.
static func to_mesh(info: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	var materials: Array = info.get("materials", [])
	var tris: PackedVector3Array = info.tris
	var tri_face: PackedInt32Array = info.tri_face
	var normals: PackedVector3Array = info.face_normal
	var face_slot: PackedInt32Array = info.face_slot
	for slot in materials.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any := false
		for t in tri_face.size():
			var f := tri_face[t]
			if face_slot[f] != slot:
				continue
			any = true
			var n := normals[f]
			for k in 3:
				var p := tris[t * 3 + k]
				st.set_normal(n)
				st.set_uv(uv_at(p, n))
				st.add_vertex(p)
		if not any:
			continue
		st.index()
		st.generate_tangents()
		st.commit(out)
		if materials[slot] != null:
			out.surface_set_material(out.get_surface_count() - 1, materials[slot])
	return out
