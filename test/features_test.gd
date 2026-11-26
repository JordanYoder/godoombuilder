# Headless tests for texture alignment, copy / paste / rotate / mirror, adding
# and removing corners, curved walls and stairs. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://test/features_test.gd
extends SceneTree

const F := DMBuilder.Part.FLOOR
const C := DMBuilder.Part.CEILING
const W := DMBuilder.Part.WALL

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


static func rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


static func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


static func total_area(data: DMMapData) -> float:
	var a := 0.0
	for s in data.sectors:
		a += s.area()
	return a


static func has_vertex(s: DMSector, p: Vector2) -> bool:
	for poly in s.polygons:
		for v in poly:
			if v.is_equal_approx(p):
				return true
	return false


## The UV of the mesh vertex at `p` on a face facing `normal` (or null).
static func uv_at_vertex(mesh: ArrayMesh, p: Vector3, normal: Vector3) -> Variant:
	for surf in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surf)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in verts.size():
			if verts[i].is_equal_approx(p) and norms[i].dot(normal) > 0.99:
				return uvs[i]
	return null


func defaults() -> DMSector:
	var d := DMSector.new()
	d.floor_height = 0.0
	d.ceiling_height = 4.0
	return d


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_texture_alignment()
	_copy_paste_transform()
	_corners()
	_curves()
	_stairs()
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)


func _texture_alignment() -> void:
	var data := DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	var plain := DMBuilder.to_mesh(DMBuilder.build(data))
	check((uv_at_vertex(plain, Vector3(4, 0, 4), Vector3.UP) as Vector2).is_equal_approx(Vector2(4, 4)), "floors are world-aligned by default")
	var s := data.sectors[0]
	s.set_uv_values(F, Vector2(0.5, 0.25), Vector2(2, 4), 0.0)
	var mesh := DMBuilder.to_mesh(DMBuilder.build(data))
	check((uv_at_vertex(mesh, Vector3(4, 0, 4), Vector3.UP) as Vector2).is_equal_approx(Vector2((4 + 0.5) / 2.0, (4 + 0.25) / 4.0)),
		"floor offset and size: uv = (world + offset) / size")
	s.set_uv_values(F, Vector2.ZERO, Vector2.ONE, 90.0)
	mesh = DMBuilder.to_mesh(DMBuilder.build(data))
	check((uv_at_vertex(mesh, Vector3(4, 0, 0), Vector3.UP) as Vector2).is_equal_approx(Vector2(0, 4)), "floor rotation turns the texture")
	s.set_uv_values(C, Vector2(1, 0), Vector2.ONE, 0.0)
	mesh = DMBuilder.to_mesh(DMBuilder.build(data))
	check((uv_at_vertex(mesh, Vector3(4, 4, 4), Vector3.DOWN) as Vector2).is_equal_approx(Vector2(5, 4)), "ceilings have their own alignment")
	# Walls: the sector's setting for all walls, a single wall can override it.
	s.set_uv_values(W, Vector2(0, 0.5), Vector2.ONE, 0.0)
	s.set_wall_override(Vector2(0, 0), Vector2(4, 0), {"uv_offset": Vector2(0.25, 0)})
	var info := DMBuilder.build(data)
	var shifted := 0
	var walls := 0
	for f in (info.face_part as PackedInt32Array).size():
		if info.face_part[f] != W:
			continue
		walls += 1
		var o: Vector2 = (info.face_uv[f] as Transform2D).origin
		if o.is_equal_approx(Vector2(0.25, 0)):
			shifted += 1
		elif not o.is_equal_approx(Vector2(0, 0.5)):
			shifted = -100
	check(walls == 4 and shifted == 1, "one wall has its own texture offset, the others the room's")
	check(s.wall_overrides.size() == 1 and not s.wall_override(Vector2(0, 0), Vector2(4, 0)).has("hidden"),
		"a texture-only wall setting is kept")
	s.set_wall_override(Vector2(0, 0), Vector2(4, 0), {"uv_offset": null})
	check(s.wall_overrides.is_empty(), "clearing it removes the setting")
	# A sector drawn inside copies the alignment, so its texture lines up.
	s.set_uv_values(F, Vector2(0.3, 0), Vector2(2, 2), 45.0)
	data.add_loop(rect(1, 1, 2, 2), defaults())
	var inner := data.sectors[data.sectors.size() - 1]
	check(inner.floor_uv_offset == Vector2(0.3, 0) and inner.floor_uv_size == Vector2(2, 2) and inner.floor_uv_rotation == 45.0,
		"a sector drawn inside another copies its texture alignment")
	# Simplify keeps a point between walls with different texture settings.
	data = DMMapData.new()
	data.add_loop(PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)]), defaults())
	data.sectors[0].polygons = [PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])]
	data.sectors[0].set_wall_override(Vector2(0, 0), Vector2(2, 0), {"uv_rotation": 90.0})
	data.simplify_sector(0)
	check(has_vertex(data.sectors[0], Vector2(2, 0)), "Simplify keeps the corner between walls with different textures")
	data.sectors[0].set_wall_override(Vector2(2, 0), Vector2(4, 0), {"uv_rotation": 90.0})
	data.simplify_sector(0)
	check(not has_vertex(data.sectors[0], Vector2(2, 0)) and is_equal_approx(float(data.sectors[0].wall_override(Vector2(0, 0), Vector2(4, 0)).get("uv_rotation", 0.0)), 90.0),
		"... and removes it when both have the same, keeping the setting")
	# check() doesn't complain about a zero size (it's clamped).
	data.sectors[0].floor_uv_size = Vector2.ZERO
	var t := data.sectors[0].uv_transform(F)
	check(is_finite(t.x.x) and is_finite(t.y.y), "a zero texture size doesn't break the mesh")


func _copy_paste_transform() -> void:
	# Rotate 90° about (2, 2): the room, its wall setting and outer corner move.
	var data := DMMapData.new()
	data.add_loop(rect(0, 0, 4, 2), defaults())
	var s := data.sectors[0]
	s.set_wall_override(Vector2(0, 0), Vector2(4, 0), {"hidden": true})
	s.wall_thickness = 0.5
	s.outer_corners[DMMapData.key_of(Vector2(0, 2))] = Vector2(-1, 1)
	var rot := Transform2D(0.0, Vector2(2, 2)) * Transform2D(PI * 0.5, Vector2.ZERO) * Transform2D(0.0, -Vector2(2, 2))
	data.transform_sectors([0], rot)
	var box := data.bounds_of([0])
	check(box.position.is_equal_approx(Vector2(2, 0)) and box.size.is_equal_approx(Vector2(2, 4)), "rotating 90° turns a 4 x 2 room into 2 x 4")
	check(DMGeo.signed_area(s.polygons[0]) > 0.0 and data.validate() == "", "the rotated room is valid")
	check(s.wall_override(Vector2(4, 0), Vector2(4, 4)).get("hidden", false), "the hidden wall turns with the room")
	check(s.outer_corners.has(DMMapData.key_of(Vector2(2, 0))) and (s.outer_corners[DMMapData.key_of(Vector2(2, 0))] as Vector2).is_equal_approx(Vector2(-1, -1)),
		"a hand-placed outer corner turns with the room")
	# Mirror: still counter-clockwise, and the wall setting still finds its wall.
	var mirror := Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(8, 0))
	data.transform_sectors([0], mirror)
	check(DMGeo.signed_area(s.polygons[0]) > 0.0 and data.validate() == "", "a mirrored room stays counter-clockwise and valid")
	check(s.wall_override(Vector2(4, 4), Vector2(4, 0)).get("hidden", false), "a mirrored wall setting still matches its wall")
	var info := DMBuilder.build(data)
	check((info.hidden_walls as Array).size() == 1, "the mirrored map builds with its hidden wall")

	# Paste: cuts what's underneath, like drawing.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 10, 10), defaults())
	var copy := DMMapData.transformed_sectors([data.sectors[0]] as Array[DMSector], Transform2D(0.0, Vector2.ZERO))
	copy[0].polygons = [rect(0, 0, 2, 2)]
	copy[0].floor_height = 1.0
	var r := data.paste_sectors(copy, Transform2D(0.0, Vector2(3, 3)))
	check(r.ok and (r.indices as Array) == [1] and data.validate() == "", "paste adds the copy")
	check(near(total_area(data), 100.0) and near(data.sectors[1].area(), 4.0) and data.sector_at(Vector2(4, 4)) == 1,
		"the paste is cut out of the room under it (areas add up)")
	check(data.sectors[1].floor_height == 1.0 and copy[0].polygons[0] == rect(0, 0, 2, 2), "the pasted copy keeps its heights; the clipboard is unchanged")
	r = data.paste_sectors(copy, Transform2D(0.0, Vector2(3, 3)))
	check(r.ok and data.sectors.size() == 2 and data.validate() == "", "pasting again on the same spot replaces it")
	# Pasted over empty space and across a room's edge.
	r = data.paste_sectors(copy, Transform2D(0.0, Vector2(9, 9)))
	check(r.ok and data.validate() == "" and near(total_area(data), 100.0 + 3.0), "a paste across a room's edge cuts only the overlap")


func _corners() -> void:
	# Two rooms sharing a wall: a new corner on it goes into both.
	var data := DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 0, 8, 4), defaults())
	check(data.insert_vertex(Vector2(4, 1.5)), "a corner can be added on a wall")
	check(has_vertex(data.sectors[0], Vector2(4, 1.5)) and has_vertex(data.sectors[1], Vector2(4, 1.5)), "both rooms sharing the wall get it")
	check(not data.insert_vertex(Vector2(4, 1.5)) and not data.insert_vertex(Vector2(2, 2)), "no corner is added twice, or off any wall")
	# Moving the new corner bends both rooms' shared wall.
	data.move_vertices(PackedVector2Array([Vector2(4, 1.5)]), PackedVector2Array([Vector2(5, 1.5)]))
	check(data.validate() == "" and near(total_area(data), 32.0), "dragging the new corner keeps the rooms together")
	check(data.remove_vertex(Vector2(5, 1.5)) and data.validate() == "" and near(total_area(data), 32.0)
		and not has_vertex(data.sectors[0], Vector2(5, 1.5)) and not has_vertex(data.sectors[1], Vector2(5, 1.5)),
		"removing it straightens the wall in both rooms")
	check(not data.remove_vertex(Vector2(3, 3)), "removing where there's no corner does nothing")
	# Removing a corner of a triangle removes the triangle.
	data = DMMapData.new()
	data.add_loop(PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(0, 2)]), defaults())
	data.remove_vertex(Vector2(2, 0))
	check(data.sectors.is_empty(), "removing a triangle's corner removes it")


func _curves() -> void:
	# Outward: the room grows by the arc's segment area.
	var data := DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	var r := data.curve_edge(0, Vector2(0, 0), Vector2(4, 0), 16, 2.0)
	check(r.ok and data.validate() == "", "a wall bulging outward is valid")
	# A half circle of radius 2 adds pi * 2² / 2; 16 straight pieces a bit less.
	var area := data.sectors[0].area()
	check(area > 16.0 + 6.0 and area < 16.0 + PI * 2.0, "the room grows by about a half circle (%.3f m²)" % area)
	check(data.sectors[0].polygons[0].size() == 4 + 15, "16 pieces means 15 new corners")
	var lowest := INF
	for v in data.sectors[0].polygons[0]:
		lowest = minf(lowest, v.y)
	check(near(lowest, -2.0, 0.01), "outward bulges away from the room (-Z for its bottom wall)")
	# Inward.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	r = data.curve_edge(0, Vector2(0, 0), Vector2(4, 0), 8, -1.0)
	check(r.ok and data.validate() == "" and data.sectors[0].area() < 16.0, "a negative bulge curves into the room")
	# Shared wall: the neighbour bends along, so nothing overlaps or opens up.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 0, 8, 4), defaults())
	data.add_loop(rect(4, 4, 8, 6), defaults()) # touches the wall's end
	r = data.curve_edge(0, Vector2(4, 0), Vector2(4, 4), 8, 1.0)
	check(r.ok and data.validate() == "" and near(total_area(data), 40.0), "curving a shared wall bends the neighbour too")
	check(data.sectors[1].polygons[0].size() == 4 + 7, "the neighbour gets the same corners")
	# A corner of a third room in the middle of the wall moves onto the arc.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 0, 8, 2), defaults())
	data.add_loop(rect(4, 2, 8, 4), defaults())
	r = data.curve_edge(0, Vector2(4, 0), Vector2(4, 4), 8, 1.0)
	check(r.ok and data.validate() == "" and near(total_area(data), 32.0) and has_vertex(data.sectors[1], Vector2(5, 2)) and has_vertex(data.sectors[2], Vector2(5, 2)),
		"a neighbour's corner on the wall moves onto the arc")
	# Refusals.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	check(not data.curve_edge(0, Vector2(0, 0), Vector2(4, 0), 8, 3.0).ok, "a bulge over half the wall's length is refused")
	check(not data.curve_edge(0, Vector2(0, 0), Vector2(4, 0), 1, 1.0).ok and not data.curve_edge(0, Vector2(0, 0), Vector2(4, 0), 8, 0.0).ok,
		"too few segments or no bulge is refused")
	check(not data.curve_edge(0, Vector2(9, 9), Vector2(12, 9), 8, 1.0).ok, "a wall that isn't there is refused")
	# Bulging into a neighbour that doesn't share the wall overlaps it.
	data.add_loop(rect(1, -3, 3, -1), defaults())
	data.curve_edge(0, Vector2(0, 0), Vector2(4, 0), 8, 2.0)
	check(data.validate() != "", "a curve into another room shows as invalid (the editor refuses it)")


func _stairs() -> void:
	var data := DMMapData.new()
	for i in 4:
		data.add_loop(rect(i, 0, i + 1, 2), defaults())
	data.sectors[0].floor_height = 1.0
	data.make_stairs([0, 1, 2, 3], 0.25, false)
	var heights := []
	for s in data.sectors:
		heights.append(s.floor_height)
	check(heights == [1.0, 1.25, 1.5, 1.75], "Make Stairs: each floor one step above the one before")
	check(data.sectors[3].ceiling_height == 4.0, "ceilings stay put by default")
	data.make_stairs([3, 2, 1, 0], -1.5, true)
	check(near(data.sectors[0].floor_height, -2.75) and near(data.sectors[0].ceiling_height, 4.0 + (-2.75 - 1.0)),
		"selection order decides the stairs; ceilings can move along")
	data.make_stairs([0, 1], 10.0, false)
	check(data.sectors[1].ceiling_height >= data.sectors[1].floor_height, "a floor raised past its ceiling pushes the ceiling up")

	# Split into Steps.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 2), defaults())
	data.add_loop(rect(4, 0, 6, 2), defaults())
	var r := data.split_into_steps(0, 4, Vector2(1, 0), 0.5, false)
	check(r.ok and (r.indices as Array).size() == 4 and data.validate() == "" and near(total_area(data), 12.0), "a room splits into 4 equal steps")
	var ok := true
	for k in 4:
		var s := data.sectors[int(r.indices[k])]
		var b := data.bounds_of([int(r.indices[k])])
		if not (near(s.area(), 2.0) and near(b.position.x, k) and near(s.floor_height, 0.5 * k)):
			ok = false
	check(ok, "steps climb toward +X, the first keeping the floor height")
	var info := DMBuilder.build(data)
	var risers := 0
	for f in (info.face_part as PackedInt32Array).size():
		if info.face_part[f] == W and absf((info.face_normal[f] as Vector3).x) > 0.99:
			risers += 1
	check(risers >= 3, "the steps build risers between them")
	data = DMMapData.new()
	data.add_loop(PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4)]), defaults())
	r = data.split_into_steps(0, 3, Vector2(0, -1), 0.25, true)
	check(r.ok and data.validate() == "" and near(total_area(data), 8.0) and data.sectors[int(r.indices[2])].floor_height == 0.5,
		"an odd shape splits too, climbing toward -Z")
	check(not data.split_into_steps(0, 1, Vector2(1, 0), 0.25, false).ok, "fewer than 2 steps is refused")
