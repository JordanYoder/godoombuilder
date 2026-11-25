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
##   outlines: Array (per sector) of PackedVector2Array segment pairs, the
##             sector's boundary without seams between its own pieces
## Turn it into a renderable mesh with to_mesh().
static func build(data: DMMapData) -> Dictionary:
	var info := {
		"materials": [],
		"face_points": [],
		"face_slot": PackedInt32Array(),
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
			_add_face(info, floor_pts, tri, Vector3.UP, _slot(info, slots, s.floor_material), si, Part.FLOOR)
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
			_wall_piece(info, slots, sectors, es[k], int(pc[2]), a + u * float(pc[0]), a + u * float(pc[1]))
	return info


static func _wall_piece(info: Dictionary, slots: Dictionary, sectors: Array[DMSector],
		si: int, ni: int, p0: Vector2, p1: Vector2) -> void:
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
	if ni < 0:
		_wall(info, p0, p1, s.floor_height, s.ceiling_height, inward, slot, si)
		return
	if ni == si:
		return
	var t := sectors[ni]
	var lower_top := minf(t.floor_height, s.ceiling_height)
	if lower_top > s.floor_height + DMGeo.HEIGHT_EPS:
		_wall(info, p0, p1, s.floor_height, lower_top, inward, slot, si)
	var upper_bottom := maxf(t.ceiling_height, s.floor_height)
	upper_bottom = maxf(upper_bottom, lower_top)
	if s.ceiling_height > upper_bottom + DMGeo.HEIGHT_EPS:
		_wall(info, p0, p1, upper_bottom, s.ceiling_height, inward, slot, si)


static func _wall(info: Dictionary, p0: Vector2, p1: Vector2, bottom: float, top: float,
		inward: Vector3, slot: int, si: int) -> void:
	var pts := PackedVector3Array([
		Vector3(p0.x, bottom, p0.y), Vector3(p1.x, bottom, p1.y),
		Vector3(p1.x, top, p1.y), Vector3(p0.x, top, p0.y)])
	_add_face(info, pts, PackedInt32Array([0, 1, 2, 0, 2, 3]), inward, slot, si, Part.WALL)


## Adds a face: its outline, triangles (indices into `pts`) and the direction
## it faces. Triangles are stored wound so their front side faces `want`.
static func _add_face(info: Dictionary, pts: PackedVector3Array, tri: PackedInt32Array,
		want: Vector3, slot: int, si: int, part: int) -> int:
	var f: int = (info.face_points as Array).size()
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
