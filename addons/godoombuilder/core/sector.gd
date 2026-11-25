@tool
class_name DMSector
extends Resource
## One sector: a floor area with its own floor and ceiling heights and surfaces.
##
## The area is stored as one or more hole-free polygons (counter-clockwise in
## map X/Z). Pieces of the same sector may share edges; those seams produce no
## walls because both sides have the same heights.


@export var polygons: Array[PackedVector2Array] = []
@export var floor_height := 0.0
@export var ceiling_height := 4.0
## Off: open to the sky. No ceiling is built; walls still rise to
## ceiling_height, and no upper walls are built between two open sectors.
@export var has_ceiling := true
## Off: no floor is built (a hole). Walls still start at floor_height.
@export var has_floor := true
## Thickness (meters) of this sector's walls that face solid space: they are
## built as solid blocks extending outward, so the room keeps its size. 0 is a
## thin wall. A single wall can override it ("thickness" in wall_overrides).
@export var wall_thickness := 0.0
## Hand-placed outer corners of thick walls: DMMapData.key_of(inner corner) ->
## offset (Vector2, meters) from that corner to its outer corner. Corners not
## listed are placed automatically (square / mitered).
@export var outer_corners: Dictionary = {}
## Settings for single walls of this sector. Each entry is a Dictionary:
##   a, b: the polygon edge (map points) the setting belongs to; it also
##         covers any part of that edge after the edge is split
##   hidden: bool, the wall isn't built (an opening; no collision)
##   bottom, top: float, own height range (outer walls only), when present
@export var wall_overrides: Array[Dictionary] = []
@export var floor_material: Material
@export var ceiling_material: Material
@export var wall_material: Material


## A copy that owns its polygon arrays (materials stay shared).
func duplicate_sector() -> DMSector:
	var s := DMSector.new()
	s.copy_props_from(self)
	for p in polygons:
		s.polygons.append(p.duplicate())
	for o in wall_overrides:
		s.wall_overrides.append(o.duplicate())
	s.outer_corners = outer_corners.duplicate()
	return s


## The edge a single-wall setting for the wall piece p0 -> p1 is stored on:
## the existing setting's edge if there is one, else the piece itself.
func override_edge(p0: Vector2, p1: Vector2) -> Array:
	var o := wall_override(p0, p1)
	return [o.a, o.b] if not o.is_empty() else [p0, p1]


## Drops hand-placed outer corners at these inner corners (all when empty).
func clear_outer_corners(at: Array = []) -> void:
	if at.is_empty():
		outer_corners.clear()
		return
	for p in at:
		outer_corners.erase(DMMapData.key_of(p))


## The settings for the wall from p0 to p1 (a piece of one of this sector's
## edges), or {}.
func wall_override(p0: Vector2, p1: Vector2) -> Dictionary:
	for o in wall_overrides:
		var a: Vector2 = o.a
		var b: Vector2 = o.b
		var d := b - a
		var length := d.length()
		if length < DMGeo.LINE_EPS:
			continue
		var u := d / length
		if absf(u.cross(p0 - a)) > DMGeo.LINE_EPS or absf(u.cross(p1 - a)) > DMGeo.LINE_EPS:
			continue
		var t0 := u.dot(p0 - a)
		var t1 := u.dot(p1 - a)
		if t1 <= t0 or t0 < -DMGeo.LINE_EPS or t1 > length + DMGeo.LINE_EPS:
			continue
		return o
	return {}


## Sets (merges) settings for the edge a -> b. Empty settings remove it.
func set_wall_override(a: Vector2, b: Vector2, props: Dictionary) -> void:
	for i in wall_overrides.size():
		var o := wall_overrides[i]
		if (o.a as Vector2).is_equal_approx(a) and (o.b as Vector2).is_equal_approx(b):
			for k in props:
				if props[k] == null:
					o.erase(k)
				else:
					o[k] = props[k]
			if not (o.get("hidden", false) or o.has("top") or o.has("bottom") or o.has("thickness")):
				wall_overrides.remove_at(i)
			return
	var o := {"a": a, "b": b}
	for k in props:
		if props[k] != null:
			o[k] = props[k]
	if o.get("hidden", false) or o.has("top") or o.has("bottom") or o.has("thickness"):
		wall_overrides.append(o)


## Number of hidden walls.
func hidden_wall_count() -> int:
	var n := 0
	for o in wall_overrides:
		if o.get("hidden", false):
			n += 1
	return n


## Shows every hidden wall again.
func show_hidden_walls() -> void:
	for o in wall_overrides:
		o.erase("hidden")
	wall_overrides = wall_overrides.filter(func(o): return o.has("top") or o.has("bottom") or o.has("thickness"))


## Copies heights and materials, not the area.
func copy_props_from(other: DMSector) -> void:
	floor_height = other.floor_height
	ceiling_height = other.ceiling_height
	has_ceiling = other.has_ceiling
	wall_thickness = other.wall_thickness
	floor_material = other.floor_material
	ceiling_material = other.ceiling_material
	wall_material = other.wall_material


## Total floor area in square meters.
func area() -> float:
	var a := 0.0
	for p in polygons:
		a += absf(DMGeo.signed_area(p))
	return a


func contains_point(pt: Vector2) -> bool:
	for p in polygons:
		if Geometry2D.is_point_in_polygon(pt, p):
			return true
	return false


## True when the sector has no open space between floor and ceiling.
func is_closed() -> bool:
	return ceiling_height - floor_height <= DMGeo.HEIGHT_EPS
