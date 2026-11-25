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
@export var floor_material: Material
@export var ceiling_material: Material
@export var wall_material: Material


## A copy that owns its polygon arrays (materials stay shared).
func duplicate_sector() -> DMSector:
	var s := DMSector.new()
	s.copy_props_from(self)
	for p in polygons:
		s.polygons.append(p.duplicate())
	return s


## Copies heights and materials, not the area.
func copy_props_from(other: DMSector) -> void:
	floor_height = other.floor_height
	ceiling_height = other.ceiling_height
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
