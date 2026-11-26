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
##   thickness: float, own wall thickness
##   uv_offset (Vector2), uv_size (Vector2), uv_rotation (float, degrees):
##         own texture alignment, in place of the sector's wall_uv_* values
@export var wall_overrides: Array[Dictionary] = []
@export var floor_material: Material
@export var ceiling_material: Material
@export var wall_material: Material

@export_group("Texture alignment")
## Texture alignment per surface. Textures are world-aligned (they line up
## across neighbouring faces); these shift (meters), size (meters per texture
## repeat, per axis) and rotate (degrees) them.
@export var floor_uv_offset := Vector2.ZERO
@export var floor_uv_size := Vector2.ONE
@export var floor_uv_rotation := 0.0
@export var ceiling_uv_offset := Vector2.ZERO
@export var ceiling_uv_size := Vector2.ONE
@export var ceiling_uv_rotation := 0.0
## For all of this sector's walls; a single wall can override them.
@export var wall_uv_offset := Vector2.ZERO
@export var wall_uv_size := Vector2.ONE
@export var wall_uv_rotation := 0.0


## Keys of a single-wall setting (see wall_overrides).
const OVERRIDE_KEYS: Array[String] = ["hidden", "top", "bottom", "thickness", "uv_offset", "uv_size", "uv_rotation"]
## The texture-alignment keys among them.
const UV_KEYS: Array[String] = ["uv_offset", "uv_size", "uv_rotation"]


## A single-wall setting's value as a float (`fallback` when not set).
static func setting_float(o: Dictionary, key: String, fallback: float) -> float:
	if not o.has(key):
		return fallback
	var v: float = o[key]
	return v


## A single-wall setting's value as a bool (false when not set).
static func setting_bool(o: Dictionary, key: String) -> bool:
	if not o.has(key):
		return false
	var v: bool = o[key]
	return v


## A single-wall setting's value as a Vector2 (`fallback` when not set).
static func setting_vector(o: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var v: Variant = o.get(key, fallback)
	return v if v is Vector2 else fallback


## The edge [a, b] a single-wall setting belongs to.
static func setting_edge(o: Dictionary) -> Array[Vector2]:
	var a: Variant = o.get("a", Vector2.ZERO)
	var b: Variant = o.get("b", Vector2.ZERO)
	var out: Array[Vector2] = [a if a is Vector2 else Vector2.ZERO, b if b is Vector2 else Vector2.ZERO]
	return out


## Every single-wall setting set to null (for set_wall_override: clears them).
static func cleared_settings() -> Dictionary:
	var out := {}
	for k in OVERRIDE_KEYS:
		out[k] = null
	return out


## True when a single-wall setting holds anything (else it is dropped).
static func has_settings(o: Dictionary) -> bool:
	if o.get("hidden", false):
		return true
	for k in OVERRIDE_KEYS:
		if k != "hidden" and o.has(k):
			return true
	return false


## Texture alignment as a transform from world-aligned texture coordinates
## (meters, see DMBuilder.uv_at) to final ones: rotate, shift, then divide by
## the size of one repeat.
static func make_uv_transform(offset: Vector2, size: Vector2, rotation_deg: float) -> Transform2D:
	var sx := size.x if absf(size.x) >= 0.001 else 0.001
	var sy := size.y if absf(size.y) >= 0.001 else 0.001
	var r := deg_to_rad(rotation_deg)
	var c := cos(r)
	var n := sin(r)
	# uv = (R * base + offset) / size, per component.
	return Transform2D(Vector2(c / sx, n / sy), Vector2(-n / sx, c / sy), Vector2(offset.x / sx, offset.y / sy))


## The texture transform of a floor or ceiling, or of a wall (with that
## wall's own settings `o`, see wall_override()).
func uv_transform(part: int, o: Dictionary = {}) -> Transform2D:
	match part:
		DMBuilder.Part.FLOOR:
			return make_uv_transform(floor_uv_offset, floor_uv_size, floor_uv_rotation)
		DMBuilder.Part.CEILING:
			return make_uv_transform(ceiling_uv_offset, ceiling_uv_size, ceiling_uv_rotation)
	return make_uv_transform(setting_vector(o, "uv_offset", wall_uv_offset), setting_vector(o, "uv_size", wall_uv_size),
		setting_float(o, "uv_rotation", wall_uv_rotation))


## A surface's texture alignment.
class UV:
	var offset := Vector2.ZERO
	## Meters per texture repeat, per axis (negative mirrors).
	var size := Vector2.ONE
	## Degrees.
	var rotation := 0.0

	static func make(at: Vector2, scale: Vector2, degrees: float) -> UV:
		var uv := UV.new()
		uv.offset = at
		uv.size = scale
		uv.rotation = degrees
		return uv

	func transform() -> Transform2D:
		return DMSector.make_uv_transform(offset, size, rotation)


## Texture alignment of a surface; for walls, the wall's own settings `o`
## win.
func uv_values(part: int, o: Dictionary = {}) -> UV:
	match part:
		DMBuilder.Part.FLOOR:
			return UV.make(floor_uv_offset, floor_uv_size, floor_uv_rotation)
		DMBuilder.Part.CEILING:
			return UV.make(ceiling_uv_offset, ceiling_uv_size, ceiling_uv_rotation)
	return UV.make(setting_vector(o, "uv_offset", wall_uv_offset), setting_vector(o, "uv_size", wall_uv_size),
		setting_float(o, "uv_rotation", wall_uv_rotation))


## Sets a surface's texture alignment (all walls of the sector for WALL).
func set_uv_values(part: int, offset: Vector2, size: Vector2, rotation_deg: float) -> void:
	match part:
		DMBuilder.Part.FLOOR:
			floor_uv_offset = offset
			floor_uv_size = size
			floor_uv_rotation = rotation_deg
		DMBuilder.Part.CEILING:
			ceiling_uv_offset = offset
			ceiling_uv_size = size
			ceiling_uv_rotation = rotation_deg
		_:
			wall_uv_offset = offset
			wall_uv_size = size
			wall_uv_rotation = rotation_deg


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
func override_edge(p0: Vector2, p1: Vector2) -> Array[Vector2]:
	var o := wall_override(p0, p1)
	if o.is_empty():
		return [p0, p1]
	return setting_edge(o)


## Drops hand-placed outer corners at these inner corners (all when empty).
func clear_outer_corners(at: Array[Vector2] = []) -> void:
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
		var edge := setting_edge(o)
		if edge[0].is_equal_approx(a) and edge[1].is_equal_approx(b):
			for k: String in props:
				if props[k] == null:
					o.erase(k)
				else:
					o[k] = props[k]
			if not has_settings(o):
				wall_overrides.remove_at(i)
			return
	var o := {"a": a, "b": b}
	for k: String in props:
		if props[k] != null:
			o[k] = props[k]
	if has_settings(o):
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
	wall_overrides = wall_overrides.filter(func(o: Dictionary) -> bool: return has_settings(o))


## Copies heights, flags and materials, not the area (nor the per-wall
## settings and outer corners, which belong to the area's edges).
func copy_props_from(other: DMSector) -> void:
	floor_height = other.floor_height
	ceiling_height = other.ceiling_height
	has_ceiling = other.has_ceiling
	has_floor = other.has_floor
	wall_thickness = other.wall_thickness
	floor_material = other.floor_material
	ceiling_material = other.ceiling_material
	wall_material = other.wall_material
	floor_uv_offset = other.floor_uv_offset
	floor_uv_size = other.floor_uv_size
	floor_uv_rotation = other.floor_uv_rotation
	ceiling_uv_offset = other.ceiling_uv_offset
	ceiling_uv_size = other.ceiling_uv_size
	ceiling_uv_rotation = other.ceiling_uv_rotation
	wall_uv_offset = other.wall_uv_offset
	wall_uv_size = other.wall_uv_size
	wall_uv_rotation = other.wall_uv_rotation


## Total floor area in square meters.
func area() -> float:
	var a := 0.0
	for p in polygons:
		a += absf(DMGeo.signed_area(p))
	return a


func contains_point(pt: Vector2) -> bool:
	for p in polygons:
		if DMGeo.point_in_polygon(pt, p):
			return true
	return false


## True when the sector has no open space between floor and ceiling.
func is_closed() -> bool:
	return ceiling_height - floor_height <= DMGeo.HEIGHT_EPS
