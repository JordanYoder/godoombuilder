@tool
class_name DMBuildInfo
extends RefCounted
## What DMBuilder.build() makes of a map: every face (floors, ceilings and
## walls) with its triangles, plus what the editor needs to show and pick
## them. Turn it into a renderable mesh with DMBuilder.to_mesh().


## A wall that isn't built (an opening), shown dashed in the editor.
class HiddenWall:
	var p0: Vector2
	var p1: Vector2
	var bottom: float
	var top: float
	var sector: int

	func _init(from: Vector2, to: Vector2, low: float, high: float, si: int) -> void:
		p0 = from
		p1 = to
		bottom = low
		top = high
		sector = si


## A thick wall's outer corner: `outer` is where the block's corner is for the
## room corner `inner`, at floor height `h`.
class OuterCorner:
	var sector: int
	var inner: Vector2
	var outer: Vector2
	var h: float

	func _init(si: int, inner_point: Vector2, outer_point: Vector2, height: float) -> void:
		sector = si
		inner = inner_point
		outer = outer_point
		h = height


## A thick wall's outer face: a -> b is the room's wall piece, a2 -> b2 the
## block's outer side, `out` the outward normal.
class OuterEdge:
	var sector: int
	var a: Vector2
	var b: Vector2
	var a2: Vector2
	var b2: Vector2
	var out: Vector2
	var thickness: float
	var h: float


## Materials (null = default), indexed by face_slot.
var materials: Array[Material] = []
## Each face's outline, in order.
var face_points: Array[PackedVector3Array] = []
var face_slot := PackedInt32Array()
var face_sector := PackedInt32Array()
## DMBuilder.Part of each face.
var face_part := PackedInt32Array()
## The direction each face faces.
var face_normal := PackedVector3Array()
## Two points per face: for walls, the sector polygon edge it was built from
## (zeros for floors and ceilings).
var face_edge := PackedVector2Array()
## Faces + 1 entries: face f's triangles are face_tri_start[f] ..
## face_tri_start[f + 1] - 1.
var face_tri_start := PackedInt32Array()
## Each face's bounds (slightly grown), for picking.
var face_box: Array[AABB] = []
## Each face's texture alignment, applied to DMBuilder.uv_at().
var face_uv: Array[Transform2D] = []
## Triangles, three points each, and the face each belongs to.
var tris := PackedVector3Array()
var tri_face := PackedInt32Array()
var hidden_walls: Array[HiddenWall] = []
var outer_corners: Array[OuterCorner] = []
var outer_edges: Array[OuterEdge] = []
## Per sector: its boundary as segment pairs, without seams between its own
## pieces.
var outlines: Array[PackedVector2Array] = []

var _slots := {}


## True for a map that hasn't been built (or has nothing in it).
func is_empty() -> bool:
	return face_points.is_empty() and outlines.is_empty()


func face_count() -> int:
	return face_points.size()


## Sector `si`'s outline (see outlines), or empty.
func outline(si: int) -> PackedVector2Array:
	return outlines[si] if si >= 0 and si < outlines.size() else PackedVector2Array()


## The sector polygon edge wall face `f` was built from: [a, b].
func edge_of(f: int) -> Array[Vector2]:
	var out: Array[Vector2] = [face_edge[f * 2], face_edge[f * 2 + 1]]
	return out


## The material slot of `mat`, added if new.
func slot_of(mat: Material) -> int:
	if _slots.has(mat):
		return _slots[mat]
	materials.append(mat)
	_slots[mat] = materials.size() - 1
	return materials.size() - 1


## Adds a face: its outline, triangles (indices into `pts`) and the direction
## it faces. Triangles are stored wound so their front side faces `want`.
func add_face(pts: PackedVector3Array, tri: PackedInt32Array, want: Vector3, slot: int, si: int, part: int,
		edge := PackedVector2Array([Vector2.ZERO, Vector2.ZERO]), uvx := Transform2D.IDENTITY) -> int:
	var f := face_points.size()
	face_tri_start.append(tri_face.size())
	var box := AABB(pts[0], Vector3.ZERO)
	for q in pts:
		box = box.expand(q)
	face_box.append(box.grow(0.001))
	face_uv.append(uvx)
	face_edge.append_array(edge)
	face_points.append(pts)
	face_slot.append(slot)
	face_sector.append(si)
	face_part.append(part)
	face_normal.append(want.normalized())
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
		tris.append_array([a, b, c])
		tri_face.append(f)
	return f


## Closes the face_tri_start table (call once, after the last face).
func finish() -> void:
	face_tri_start.append(tri_face.size())
