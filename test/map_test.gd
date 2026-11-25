# Headless tests for the sector map core. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://test/map_test.gd
extends SceneTree

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


## Only reports failures (for checks run many times in a loop).
func check_quiet(ok: bool, what: String) -> void:
	if not ok:
		check(false, what)


func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


static func rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## The direction triangle t is seen from in Godot (its front side).
static func tri_front(info: Dictionary, t: int) -> Vector3:
	var a: Vector3 = info.tris[t * 3]
	return -(info.tris[t * 3 + 1] - a).cross(info.tris[t * 3 + 2] - a).normalized()


## Total area of faces of `part`, optionally only for one sector.
static func part_area(info: Dictionary, part: int, sector := -1) -> float:
	var total := 0.0
	for t in (info.tri_face as PackedInt32Array).size():
		var f: int = info.tri_face[t]
		if info.face_part[f] == part and (sector < 0 or info.face_sector[f] == sector):
			var a: Vector3 = info.tris[t * 3]
			total += (info.tris[t * 3 + 1] - a).cross(info.tris[t * 3 + 2] - a).length() * 0.5
	return total


func defaults() -> DMSector:
	var d := DMSector.new()
	d.floor_height = 0.0
	d.ceiling_height = 4.0
	return d


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var W := DMBuilder.Part.WALL
	var F := DMBuilder.Part.FLOOR
	var C := DMBuilder.Part.CEILING

	# 1. A single room.
	var data := DMMapData.new()
	var r := data.add_loop(rect(0, 0, 4, 4), defaults())
	check(r.ok and data.sectors.size() == 1, "draw a 4x4 room")
	var info := DMBuilder.build(data)
	check(near(part_area(info, F), 16.0) and near(part_area(info, C), 16.0), "room has 16 m² floor and ceiling")
	check(near(part_area(info, W), 64.0), "room has 4 walls of 4x4 m (got %.3f)" % part_area(info, W))
	var inward_ok := true
	var up_ok := true
	for t in (info.tri_face as PackedInt32Array).size():
		var f: int = info.tri_face[t]
		var n := tri_front(info, t)
		check_quiet(n.is_equal_approx(info.face_normal[f]), "triangle front matches its face direction")
		if info.face_part[f] == W:
			inward_ok = inward_ok and n.dot(Vector3(2, 2, 2) - info.tris[t * 3]) > 0.0
		elif info.face_part[f] == F:
			up_ok = up_ok and n.dot(Vector3.UP) > 0.99
		else:
			up_ok = up_ok and n.dot(Vector3.DOWN) > 0.99
	check(inward_ok, "walls face into the room")
	check(up_ok, "floor faces up, ceiling faces down")

	# 2. A platform drawn inside the room.
	r = data.add_loop(rect(1, 1, 2, 2), defaults())
	check(r.ok and data.sectors.size() == 2, "draw a sector inside the room")
	check(near(data.sectors[0].area(), 15.0) and near(data.sectors[1].area(), 1.0),
		"room area 15, inner area 1 (got %.3f, %.3f)" % [data.sectors[0].area(), data.sectors[1].area()])
	info = DMBuilder.build(data)
	check(near(part_area(info, W), 64.0), "same heights: no walls around the inner sector")
	data.sectors[1].floor_height = 1.0
	info = DMBuilder.build(data)
	check(near(part_area(info, W, 0), 64.0 + 4.0), "raised platform: 4 m² of step wall facing the room (got %.3f)" % part_area(info, W, 0))
	check(near(part_area(info, W, 1), 0.0), "no walls on top of the platform")
	data.sectors[1].ceiling_height = 3.0
	info = DMBuilder.build(data)
	check(near(part_area(info, W, 0), 64.0 + 4.0 + 4.0), "lowered ceiling above it adds an upper wall")
	check((info.outlines[0] as PackedVector2Array).size() / 2 >= 8, "room outline includes the platform edge")
	var seams := 0
	var out0: PackedVector2Array = info.outlines[0]
	for i in range(0, out0.size(), 2):
		var mid := (out0[i] + out0[i + 1]) * 0.5
		if mid.x > 0.01 and mid.x < 3.99 and mid.y > 0.01 and mid.y < 3.99 \
				and not (mid.x > 0.99 and mid.x < 2.01 and mid.y > 0.99 and mid.y < 2.01):
			seams += 1
	check(seams == 0, "outline hides seams between the room's own pieces")

	# 3. A neighbouring room sharing a wall.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	r = data.add_loop(rect(4, 0, 8, 4), defaults())
	check(r.ok and data.sectors.size() == 2, "draw a neighbouring room")
	info = DMBuilder.build(data)
	check(near(part_area(info, W), 2 * 48.0), "shared wall is open (got %.3f)" % part_area(info, W))
	data.sectors[1].floor_height = 0.5
	info = DMBuilder.build(data)
	check(near(part_area(info, W, 0), 48.0 + 2.0), "higher neighbour floor: step wall on the lower side")

	# 4. A partial overlap is cut out of the existing room.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	r = data.add_loop(rect(2, 1, 6, 3), defaults())
	check(r.ok and data.sectors.size() == 2, "draw overlapping a room")
	check(near(data.sectors[0].area(), 12.0) and near(data.sectors[1].area(), 8.0),
		"overlap goes to the new sector (got %.3f, %.3f)" % [data.sectors[0].area(), data.sectors[1].area()])

	# 5. A loop around an existing room keeps it.
	data = DMMapData.new()
	data.add_loop(rect(2, 2, 4, 4), defaults())
	r = data.add_loop(rect(0, 0, 6, 6), defaults())
	check(r.ok and near(data.sectors[0].area(), 4.0) and near(data.sectors[1].area(), 32.0),
		"drawing around a room keeps it (got %.3f, %.3f)" % [data.sectors[0].area(), data.sectors[1].area()])

	# 6. Bad loops are refused.
	r = data.add_loop(PackedVector2Array([Vector2(10, 10), Vector2(12, 12), Vector2(12, 10), Vector2(10, 12)]), defaults())
	check(not r.ok, "crossing lines are refused")
	r = data.add_loop(PackedVector2Array([Vector2(10, 10), Vector2(12, 10), Vector2(14, 10)]), defaults())
	check(not r.ok, "a flat shape is refused")

	# 7. Deleting the inner sector leaves a pillar.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(1, 1, 2, 2), defaults())
	data.delete_sectors([1])
	info = DMBuilder.build(data)
	check(near(part_area(info, W), 64.0 + 16.0), "deleted sector becomes a solid pillar (got %.3f)" % part_area(info, W))

	# 8. Undo snapshots are independent copies.
	var snap := data.duplicate_data()
	data.sectors[0].floor_height = 9.0
	check(near(snap.sectors[0].floor_height, 0.0), "snapshot is not changed by later edits")
	data.copy_from(snap)
	check(near(data.sectors[0].floor_height, 0.0), "restoring a snapshot works")

	# 9. Concave room (L shape) builds and compiles.
	data = DMMapData.new()
	r = data.add_loop(PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 2), Vector2(2, 2), Vector2(2, 6), Vector2(0, 6)]), defaults())
	info = DMBuilder.build(data)
	check(r.ok and near(part_area(info, F), 20.0), "L-shaped room floor is 20 m²")
	var compiled := DMBuilder.to_mesh(info)
	check(compiled != null and compiled.get_surface_count() > 0, "map compiles to a renderable mesh")
	var arrays := compiled.surface_get_arrays(0)
	check((arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		and arrays[Mesh.ARRAY_TANGENT] != null, "mesh has texture coordinates and tangents")
	check(DMBuilder.uv_at(Vector3(3, 0, 5), Vector3.UP).is_equal_approx(Vector2(3, 5))
		and is_equal_approx(DMBuilder.uv_at(Vector3(3, 2, 0), Vector3.BACK).y, -2.0),
		"textures are world-aligned: 1 repeat per meter, walls upright")
	var mats := DMMapData.new()
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()
	var md := defaults()
	md.floor_material = red
	md.wall_material = blue
	mats.add_loop(rect(0, 0, 2, 2), md)
	var mm := DMBuilder.to_mesh(DMBuilder.build(mats))
	var found := []
	for i in mm.get_surface_count():
		found.append(mm.surface_get_material(i))
	check(mm.get_surface_count() == 3 and found.has(red) and found.has(blue), "one surface per material, materials applied")

	# 10. The map node builds, and picking hits the floor through the ceiling.
	var map := DMMap.new()
	map.data = data
	root.add_child(map)
	map.ensure_built()
	var hit := map.pick(Vector3(1, 10, 1), Vector3.DOWN)
	check(not hit.is_empty() and hit.part == F and near(hit.point.y, 0.0), "pick from above hits the floor")
	hit = map.pick(Vector3(1, 1, 1), Vector3.UP)
	check(not hit.is_empty() and hit.part == C, "pick from inside looking up hits the ceiling")
	hit = map.pick(Vector3(1, 1, 1), Vector3.LEFT)
	check(not hit.is_empty() and hit.part == W, "pick sideways hits a wall")
	check(map.mesh_node().mesh != null, "map node has a mesh")
	var body := map.collision_body()
	var shape := body.get_child(0) as CollisionShape3D
	check(body.collision_layer == 1 and shape.shape is ConcavePolygonShape3D
		and (shape.shape as ConcavePolygonShape3D).get_faces().size() > 0, "map node has collision")
	map.collision_enabled = false
	check(shape.disabled and body.collision_layer == 0, "collision can be turned off")
	map.collision_enabled = true
	var space := map.get_world_3d().direct_space_state
	await physics_frame
	var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1, 1, 1), Vector3(1, -5, 1)))
	check(not ray.is_empty() and near(ray.position.y, 0.0, 0.01), "physics ray hits the floor")

	# 11. Units.
	check(near(DMUnits.to_display(4.0, DMUnits.Units.DOOM), 128.0), "4 m = 128 Doom units")
	check(DMUnits.format(0.25, DMUnits.Units.DOOM) == "8 du", "0.25 m shows as 8 du")
	check(DMUnits.format(1.5, DMUnits.Units.METERS) == "1.5 m", "1.5 m shows as 1.5 m")

	# 12. Saving and loading a scene keeps the sectors; the mesh is rebuilt, not stored.
	var scene_root := Node3D.new()
	scene_root.name = "Level"
	var saved_map := DMMap.new()
	saved_map.name = "SectorMap"
	saved_map.data = DMMapData.new()
	saved_map.data.add_loop(rect(0, 0, 4, 4), defaults())
	saved_map.data.add_loop(rect(1, 1, 2, 2), defaults())
	saved_map.data.sectors[1].floor_height = 0.75
	scene_root.add_child(saved_map)
	saved_map.owner = scene_root
	var packed := PackedScene.new()
	check(packed.pack(scene_root) == OK, "scene with a sector map packs")
	var path := "user://sector_save_test.tscn"
	check(ResourceSaver.save(packed, path) == OK, "scene saves")
	var text := FileAccess.get_file_as_string(path)
	check(not text.contains("MapMesh") and not text.contains("ArrayMesh"), "generated mesh is not stored in the scene file")
	var loaded := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var loaded_map := loaded.get_node("SectorMap") as DMMap
	check(loaded_map != null and loaded_map.data.sectors.size() == 2, "loaded map has both sectors")
	check(loaded_map != null and near(loaded_map.data.sectors[1].floor_height, 0.75), "loaded map keeps the raised floor")
	root.add_child(loaded)
	loaded_map.ensure_built()
	check(loaded_map.mesh_node().mesh != null, "loaded map rebuilds its mesh")
	loaded.queue_free()
	scene_root.free()

	# 13. Moving corners and walls; neighbours stretch with shared corners.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 0, 8, 4), defaults())
	data.move_vertices(PackedVector2Array([Vector2(4, 4)]), PackedVector2Array([Vector2(5, 4)]))
	check(data.validate() == "", "moving a shared corner keeps the map valid")
	check(near(data.sectors[0].area() + data.sectors[1].area(), 32.0) and near(data.sectors[0].area(), 18.0),
		"both rooms follow the shared corner (%.2f + %.2f)" % [data.sectors[0].area(), data.sectors[1].area()])
	info = DMBuilder.build(data)
	check(near(part_area(info, W), 2 * 48.0), "the slanted shared wall stays open between the rooms")
	data.move_vertices(PackedVector2Array([Vector2(0, 0), Vector2(0, 4)]), PackedVector2Array([Vector2(-2, 0), Vector2(-2, 4)]))
	check(near(data.sectors[0].area(), 26.0) and data.validate() == "", "moving a wall line widens the room")
	var bad := data.duplicate_data()
	bad.move_vertices(PackedVector2Array([Vector2(0, 0) + Vector2(-2, 0)]), PackedVector2Array([Vector2(7, 2)]))
	check(bad.validate() != "", "a move that crosses into the neighbour is reported invalid")

	# T-junction: a corner in the middle of a neighbour's wall drags the wall along.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 8), defaults())
	data.add_loop(rect(4, 0, 8, 4), defaults())
	data.move_vertices(PackedVector2Array([Vector2(4, 4)]), PackedVector2Array([Vector2(5, 4)]))
	# The tall room's wall bends out to the new corner (into empty space): 36 + 14.
	check(data.validate() == "" and near(data.sectors[0].area(), 36.0) and near(data.sectors[1].area(), 14.0),
		"a corner on a neighbour's wall bends that wall along, without gaps or overlaps (%.2f, %.2f)" % [
			data.sectors[0].area(), data.sectors[1].area()])

	# Exact resize of one room, anchored at a corner; the neighbour stretches.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 0, 8, 4), defaults())
	data.scale_sectors([0], Vector2(0, 0), Vector2(1.5, 1.0))
	var box := data.bounds_of([0])
	check(near(box.size.x, 6.0) and near(box.position.x, 0.0), "resize to 6 m wide from the -X corner")
	check(near(data.sectors[1].area(), 8.0) and data.validate() == "", "the neighbour shrinks to fit (%.2f)" % data.sectors[1].area())
	var room_with_platform := DMMapData.new()
	room_with_platform.add_loop(rect(0, 0, 6, 6), defaults())
	room_with_platform.add_loop(rect(2, 2, 4, 4), defaults())
	room_with_platform.scale_sectors([1], Vector2(3, 3), Vector2(2.0, 2.0))
	check(near(room_with_platform.sectors[1].area(), 16.0) and near(room_with_platform.sectors[0].area(), 20.0)
		and room_with_platform.validate() == "", "resizing a platform inside a room reshapes the room around it")

	# 14. Joining sectors.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 0, 8, 4), defaults())
	data.add_loop(rect(20, 0, 22, 2), defaults())
	data.sectors[1].floor_height = 0.5
	info = DMBuilder.build(data)
	var walls_before := part_area(info, W)
	var j := data.join_sectors([0, 1])
	check(data.sectors.size() == 2 and j == 0 and near(data.sectors[0].area(), 32.0), "join two rooms into one sector")
	check(data.sectors[0].polygons.size() == 1, "the seam between them is merged away")
	info = DMBuilder.build(data)
	check(near(part_area(info, W), 4 * 24.0 + 4 * 8.0 * 2.0 / 2.0) and near(data.sectors[0].floor_height, 0.0),
		"the joined room takes the first one's heights; the step wall is gone (walls %.1f, before %.1f)" % [part_area(info, W), walls_before])
	j = data.join_sectors([1, 0])
	check(data.sectors.size() == 1 and data.sectors[0].polygons.size() == 2 and near(data.sectors[0].area(), 36.0),
		"separate areas can be joined into one sector")
	# Joining a ring of pieces around a hole keeps them hole-free.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 6, 6), defaults())
	data.add_loop(rect(2, 2, 4, 4), defaults())
	data.add_loop(rect(2.5, 2.5, 3.5, 3.5), defaults())
	j = data.join_sectors([0, 1])
	check(data.validate() == "" and near(data.sectors[j].area(), 35.0), "joining around an inner sector stays valid")

	# 15. No ceiling.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 0, 8, 4), defaults())
	data.sectors[1].ceiling_height = 3.0
	data.sectors[0].has_ceiling = false
	info = DMBuilder.build(data)
	check(near(part_area(info, C, 0), 0.0) and near(part_area(info, C, 1), 16.0), "an open sector has no ceiling")
	check(near(part_area(info, W, 0), 3 * 16.0 + 4.0), "its walls still rise to its ceiling height, with the upper wall over the neighbour")
	data.sectors[1].has_ceiling = false
	info = DMBuilder.build(data)
	check(near(part_area(info, W), 3 * 16.0 + 3 * 12.0), "no upper wall between two open sectors")
	check(data.sectors[0].duplicate_sector().has_ceiling == false, "the setting is copied with the sector")

	# 16. Thick walls: an inner room inside an outer room.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 10, 10), defaults())
	data.add_loop(rect(3, 3, 7, 7), defaults())
	var tw := data.thicken_walls(1, 0.5, 1)
	check(tw.ok and data.validate() == "", "thicken the inner room's walls outward")
	check(near(data.sectors[tw.index].area(), 16.0) and near(data.sectors[0].area(), 100.0 - 25.0),
		"outside: the room keeps its size; the band comes out of the outer room (%.2f)" % data.sectors[0].area())
	check(data.sector_at(Vector2(2.75, 5)) == -1 and data.sector_at(Vector2(2.75, 2.75)) == -1 and data.sector_at(Vector2(2.4, 5)) == 0,
		"the wall band (including its corners) is solid")
	info = DMBuilder.build(data)
	check(near(part_area(info, W, tw.index), 4 * 4.0 * 4.0) and near(part_area(info, W, 0), 4 * 10.0 * 4.0 + 4 * 5.0 * 4.0),
		"both rooms get full-height walls facing the solid band")
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 10, 10), defaults())
	data.add_loop(rect(3, 3, 7, 7), defaults())
	tw = data.thicken_walls(1, 0.5, -1)
	check(tw.ok and near(data.sectors[tw.index].area(), 9.0) and near(data.sectors[0].area(), 84.0), "inside: the room shrinks by the thickness")
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 10, 10), defaults())
	data.add_loop(rect(3, 3, 7, 7), defaults())
	tw = data.thicken_walls(1, 1.0, 0)
	check(tw.ok and near(data.sectors[tw.index].area(), 9.0) and near(data.sectors[0].area(), 75.0), "centered: half each way")
	# An L-shaped room keeps square corners, including the inner corner.
	data = DMMapData.new()
	data.add_loop(rect(-5, -5, 15, 15), defaults())
	data.add_loop(PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 2), Vector2(2, 2), Vector2(2, 6), Vector2(0, 6)]), defaults())
	tw = data.thicken_walls(1, 0.5, 1)
	check(tw.ok and data.validate() == "" and near(data.sectors[tw.index].area(), 20.0), "L-shaped room thickens")
	# L grown by 0.5 outward (mitered): (7 x 3) + (3 x 4) area = 21 + 12 = 33.
	check(near(data.sectors[0].area(), 400.0 - 33.0, 0.01), "mitered corners: band area exact (outer room %.3f)" % data.sectors[0].area())
	# A sector next to the room's wall on one side, and the map edge on the other.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 0, 8, 4), defaults())
	tw = data.thicken_walls(0, 0.25, 1)
	check(tw.ok and near(data.sectors[0].wall_thickness, 0.25) and near(data.sectors[0].area(), 16.0) and near(data.sectors[1].area(), 16.0),
		"outward on walls facing solid space: they become thick blocks; neither room changes size")
	tw = data.thicken_walls(0, 0.25, 1)
	check(not tw.ok and tw.message.begins_with("Nothing changed"), "doing it again says nothing changed")
	tw = data.thicken_walls(0, 3.0, -1)
	check(not tw.ok, "too thick for the room is refused")

	# 17. Single walls: hide one, or give it its own height.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	var room := data.sectors[0]
	room.set_wall_override(Vector2(0, 0), Vector2(4, 0), {"hidden": true})
	info = DMBuilder.build(data)
	check(near(part_area(info, W), 3 * 16.0) and (info.hidden_walls as Array).size() == 1, "a hidden wall is not built; the other three stay")
	var col_map := DMMap.new()
	col_map.data = data
	col_map.position = Vector3(50, 0, 0)
	root.add_child(col_map)
	col_map.ensure_built()
	await physics_frame
	await physics_frame
	var space2 := col_map.get_world_3d().direct_space_state
	var through := space2.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(52, 1, 2), Vector3(52, 1, -3)))
	var solid := space2.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(52, 1, 2), Vector3(52, 1, 7)))
	check(through.is_empty() and not solid.is_empty(), "the opening has no collision; the other walls do")
	col_map.queue_free()
	room.set_wall_override(Vector2(0, 0), Vector2(4, 0), {"hidden": null, "top": 1.0})
	info = DMBuilder.build(data)
	check(near(part_area(info, W), 3 * 16.0 + 4.0) and (info.hidden_walls as Array).is_empty(), "a wall with its own 1 m top: half wall, others full height")
	check(near(part_area(info, F), 16.0) and near(part_area(info, C), 16.0), "the floor and ceiling are untouched")
	room.set_wall_override(Vector2(0, 0), Vector2(4, 0), {"bottom": 0.5, "top": 6.0})
	info = DMBuilder.build(data)
	check(near(part_area(info, W), 3 * 16.0 + 4.0 * 5.5), "a wall can be taller and start higher")
	# Splitting the edge (drawing a sector against it) keeps the setting on both parts.
	data.add_loop(rect(1, 1, 3, 3), defaults())
	data.split_edges_at(Vector2(2, 0))
	info = DMBuilder.build(data)
	check(near(part_area(info, W, 0), 3 * 16.0 + 4.0 * 5.5), "the setting still covers the edge after it is split")
	# Dragging a corner moves the setting along.
	data.move_vertices(PackedVector2Array([Vector2(4, 0)]), PackedVector2Array([Vector2(6, 0)]))
	info = DMBuilder.build(data)
	var o := data.sectors[0].wall_override(Vector2(0, 0), Vector2(6, 0))
	check(not o.is_empty() and near(o.top, 6.0), "dragging a corner keeps the wall's setting")
	# Copies are independent; reset removes the setting.
	var copy := data.duplicate_data()
	copy.sectors[0].set_wall_override(Vector2(0, 0), Vector2(6, 0), {"top": null, "bottom": null})
	check(copy.sectors[0].wall_overrides.is_empty() and data.sectors[0].wall_overrides.size() == 1, "undo snapshots don't share wall settings; reset clears it")
	# Step walls between sectors can be hidden too.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 0, 8, 4), defaults())
	data.sectors[1].floor_height = 0.5
	data.sectors[0].set_wall_override(Vector2(4, 0), Vector2(4, 4), {"hidden": true})
	info = DMBuilder.build(data)
	check(near(part_area(info, W, 0), 3 * 16.0), "a step wall can be hidden")
	data.sectors[0].show_hidden_walls()
	check(data.sectors[0].wall_overrides.is_empty() and data.sectors[0].hidden_wall_count() == 0, "show hidden walls brings them back")
	# No floor.
	data.sectors[0].has_floor = false
	info = DMBuilder.build(data)
	check(near(part_area(info, F, 0), 0.0) and near(part_area(info, W, 0), 3 * 16.0 + 4 * 0.5), "a sector without a floor: walls unchanged")
	# Wall settings save with the scene.
	var save_root := Node3D.new()
	var save_map := DMMap.new()
	save_map.name = "M"
	save_map.data = DMMapData.new()
	save_map.data.add_loop(rect(0, 0, 4, 4), defaults())
	save_map.data.sectors[0].set_wall_override(Vector2(0, 0), Vector2(4, 0), {"hidden": true})
	save_map.data.sectors[0].set_wall_override(Vector2(4, 0), Vector2(4, 4), {"top": 1.25})
	save_map.data.sectors[0].has_floor = false
	save_root.add_child(save_map)
	save_map.owner = save_root
	var pk := PackedScene.new()
	pk.pack(save_root)
	ResourceSaver.save(pk, "user://wall_save_test.tscn")
	var back := (ResourceLoader.load("user://wall_save_test.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var bs: DMSector = (back.get_node("M") as DMMap).data.sectors[0]
	check(bs.wall_overrides.size() == 2 and bs.wall_override(Vector2(0, 0), Vector2(4, 0)).get("hidden", false)
		and near(bs.wall_override(Vector2(4, 0), Vector2(4, 4)).top, 1.25) and not bs.has_floor, "wall settings and no-floor save and load")
	back.free()
	save_root.free()

	# 18. Simplify: points that don't change the shape go.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.sectors[0].polygons = [PackedVector2Array([Vector2(0, 0), Vector2(1.5, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])]
	check(data.simplify_sector(0) == 1 and data.sectors[0].polygons[0].size() == 4 and near(data.sectors[0].area(), 16.0),
		"a rectangle with an extra point in one wall simplifies to 4 corners")
	check(data.simplify_sector(0) == 0, "nothing left to simplify")
	# Nearly straight (within 1 mm) goes; a real bend stays.
	data.sectors[0].polygons = [PackedVector2Array([Vector2(0, 0), Vector2(2, 0.0004), Vector2(4, 0), Vector2(4, 2), Vector2(4.5, 3), Vector2(4, 4), Vector2(0, 4)])]
	check(data.simplify_sector(0) == 1 and data.sectors[0].polygons[0].size() == 6, "a nearly-straight point goes; a real bend stays")
	# A sector stored as two pieces with a seam becomes one piece.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.sectors[0].polygons = [rect(0, 0, 2, 4), rect(2, 0, 4, 4)]
	check(data.simplify_sector(0) == 4 and data.sectors[0].polygons.size() == 1 and data.sectors[0].polygons[0].size() == 4,
		"seams inside a sector are fused away")
	# A neighbour's corner on the wall: walls between the rooms still work.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 1, 6, 3), defaults())
	data.sectors[1].floor_height = 0.5
	data.split_edges_at(Vector2(4, 1))
	data.split_edges_at(Vector2(4, 3))
	var walls_now := part_area(DMBuilder.build(data), W)
	data.simplify_sector(0)
	check(data.sectors[0].polygons[0].size() == 4 and near(part_area(DMBuilder.build(data), W), walls_now) and data.validate() == "",
		"simplifying next to a neighbour keeps the step wall")
	# Wall settings: a point between differently-set walls stays.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.sectors[0].polygons = [PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])]
	data.sectors[0].set_wall_override(Vector2(0, 0), Vector2(2, 0), {"hidden": true})
	check(data.simplify_sector(0) == 0, "a point between a hidden and a normal wall stays")
	data.sectors[0].set_wall_override(Vector2(2, 0), Vector2(4, 0), {"hidden": true})
	check(data.simplify_sector(0) == 1 and data.sectors[0].wall_override(Vector2(0, 0), Vector2(4, 0)).get("hidden", false),
		"between two hidden walls it goes, and the whole wall stays hidden")

	# 19. Thickening a single wall.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 10, 10), defaults())
	data.add_loop(rect(3, 3, 7, 7), defaults())
	tw = data.thicken_edge(1, Vector2(3, 3), Vector2(7, 3), 0.5, 1)
	check(tw.ok and data.validate() == "" and near(data.sectors[tw.index].area(), 16.0) and near(data.sectors[0].area(), 84.0 - 2.0),
		"outside: only that wall gets thick; the room keeps its size (outer %.2f)" % data.sectors[0].area())
	check(data.sector_at(Vector2(5, 2.75)) == -1 and data.sector_at(Vector2(2.75, 5)) == 0 and data.sector_at(Vector2(7.25, 2.75)) == 0,
		"the band is behind that wall only, with square ends")
	tw = data.thicken_edge(1, Vector2(7, 3), Vector2(7, 7), 0.5, 1)
	check(tw.ok and near(data.sectors[0].area(), 84.0 - 4.25) and data.sector_at(Vector2(7.25, 2.75)) == -1,
		"thickening the next wall fills the corner between them (outer %.2f)" % data.sectors[0].area())
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 10, 10), defaults())
	data.add_loop(rect(3, 3, 7, 7), defaults())
	tw = data.thicken_edge(1, Vector2(3, 3), Vector2(7, 3), 0.5, -1)
	check(tw.ok and near(data.sectors[tw.index].area(), 14.0) and near(data.sectors[0].area(), 84.0), "inside: the room loses a strip along that wall")
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 10, 10), defaults())
	data.add_loop(rect(3, 3, 7, 7), defaults())
	tw = data.thicken_edge(1, Vector2(3, 3), Vector2(7, 3), 1.0, 0)
	check(tw.ok and near(data.sectors[tw.index].area(), 14.0) and near(data.sectors[0].area(), 82.0), "centered: half each way")
	tw = data.thicken_edge(1, Vector2(3, 3.5), Vector2(7, 3.5), 5.0, -1)
	check(not tw.ok, "too thick for the room is refused")

	# 20. Thickening a room like the demo hall: things inside it and openings
	# into other rooms are left alone.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 12, 10), defaults())
	var step_r := data.add_loop(rect(8, 2, 9, 8), defaults())
	data.sectors[step_r.index].floor_height = 0.25
	var pit_r := data.add_loop(rect(1.5, 6, 4.5, 9), defaults())
	data.sectors[pit_r.index].floor_height = -0.75
	data.add_loop(rect(4, 10, 6, 16), defaults()) # corridor out of the north wall
	var hall_i := data.sector_at(Vector2(0.5, 0.5))
	var areas_before := []
	for sec in data.sectors:
		areas_before.append(sec.area())
	tw = data.thicken_walls(hall_i, 0.5, -1)
	check(tw.ok and data.validate() == "", "thicken the hall inward")
	check(near(data.sectors[data.sector_at(Vector2(8.5, 5))].area(), 6.0) and near(data.sectors[data.sector_at(Vector2(3, 7))].area(), 9.0),
		"the step and the pit inside the hall are untouched")
	check(data.sector_at(Vector2(0.25, 5)) == -1 and data.sector_at(Vector2(6, 0.25)) == -1 and data.sector_at(Vector2(11.75, 5)) == -1,
		"the hall's outer walls are 0.5 m thick")
	check(data.sector_at(Vector2(5, 9.75)) == tw.index and data.sector_at(Vector2(3.9, 9.75)) == -1,
		"the opening into the corridor stays open, with square wall ends beside it")
	check(near(data.sectors[data.sector_at(Vector2(5, 12))].area(), 12.0), "the corridor is untouched")
	tw = data.thicken_walls(data.sector_at(Vector2(0.75, 0.75)), 0.5, 1)
	check(tw.ok and near(data.sectors[tw.index].wall_thickness, 0.5), "outward on the hall: its outer walls become thick blocks")

	# 21. Thick walls as blocks: the wall becomes a solid box, the room keeps its size.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	info = DMBuilder.build(data)
	var thin_walls := part_area(info, W)
	data.sectors[0].wall_thickness = 0.5
	info = DMBuilder.build(data)
	# Inside 4 x (4 x 4) + outer faces 4 x (5 x 4) + top and bottom rings 2 x (25 - 16).
	check(near(part_area(info, W), thin_walls + 80.0 + 18.0) and near(data.sectors[0].area(), 16.0),
		"a 0.5 m thick room: outer faces, top and bottom, room unchanged (walls %.1f)" % part_area(info, W))
	var outer_ok := true
	for t in (info.tri_face as PackedInt32Array).size():
		var f: int = info.tri_face[t]
		var c: Vector3 = (info.tris[t * 3] + info.tris[t * 3 + 1] + info.tris[t * 3 + 2]) / 3.0
		var nrm := tri_front(info, t)
		if absf(nrm.y) < 0.5 and (c.x < -0.25 or c.x > 4.25 or c.z < -0.25 or c.z > 4.25):
			outer_ok = outer_ok and nrm.dot(Vector3(c.x - 2.0, 0, c.z - 2.0)) > 0.0
	check(outer_ok, "outer faces face outward")
	var top_hit := DMMap.new()
	top_hit.data = data
	top_hit.position = Vector3(80, 0, 0)
	root.add_child(top_hit)
	top_hit.ensure_built()
	var top_pick := top_hit.pick(Vector3(80 - 0.25, 10, 2), Vector3.DOWN)
	check(not top_pick.is_empty() and near(top_pick.point.y, 4.0) and top_pick.part == W, "the top of the thick wall is there (and can be clicked)")
	await physics_frame
	await physics_frame
	var wall_ray := top_hit.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(80 - 3, 1, 2), Vector3(80 + 2, 1, 2)))
	check(not wall_ray.is_empty() and near(wall_ray.position.x, 80 - 0.5, 0.01), "from outside you bump into the thick wall's outer face")
	top_hit.queue_free()
	# One wall only: square ends.
	data.sectors[0].wall_thickness = 0.0
	data.sectors[0].set_wall_override(Vector2(0, 0), Vector2(4, 0), {"thickness": 0.5})
	info = DMBuilder.build(data)
	# Outer face 4 x 4, top and bottom 2 x (4 x 0.5), two ends 2 x (0.5 x 4).
	check(near(part_area(info, W), thin_walls + 16.0 + 4.0 + 4.0), "one thick wall: a box with square ends (walls %.1f)" % part_area(info, W))
	# Thicken on a single wall facing solid space sets that wall's thickness.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	tw = data.thicken_edge(0, Vector2(0, 0), Vector2(4, 0), 0.5, 1)
	check(tw.ok and near(data.sectors[0].wall_override(Vector2(0, 0), Vector2(4, 0)).thickness, 0.5) and near(data.sectors[0].area(), 16.0),
		"Thicken on one outer wall makes just that wall a block; the room keeps its size")
	# Thick walls are not built where a room is open to a neighbour.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.add_loop(rect(4, 1, 6, 3), defaults())
	data.sectors[0].wall_thickness = 0.5
	info = DMBuilder.build(data)
	check(data.sector_at(Vector2(4.25, 2)) == 1 and near(data.sectors[0].area(), 16.0), "the opening to the neighbour stays open")
	var blocked := false
	for t in (info.tri_face as PackedInt32Array).size():
		var c: Vector3 = (info.tris[t * 3] + info.tris[t * 3 + 1] + info.tris[t * 3 + 2]) / 3.0
		if c.x > 4.01 and c.z > 1.01 and c.z < 2.99 and info.face_sector[info.tri_face[t]] == 0:
			blocked = true
	check(not blocked, "no thick-wall block in front of the opening")
	check(data.sectors[0].duplicate_sector().wall_thickness == 0.5, "the thickness is copied with the sector")

	# 22. Hand-placed outer corners of thick walls.
	data = DMMapData.new()
	data.add_loop(rect(0, 0, 4, 4), defaults())
	data.sectors[0].wall_thickness = 0.5
	info = DMBuilder.build(data)
	check((info.outer_corners as Array).size() == 4 and (info.outer_edges as Array).size() == 4, "a thick room reports 4 outer corners and 4 outer faces")
	var before_walls := part_area(info, W)
	data.sectors[0].outer_corners[DMMapData.key_of(Vector2(0, 0))] = Vector2(-2, -0.5)
	info = DMBuilder.build(data)
	var moved_corner := false
	for c in info.outer_corners:
		if (c.inner as Vector2).is_equal_approx(Vector2(0, 0)) and (c.outer as Vector2).is_equal_approx(Vector2(-2, -0.5)):
			moved_corner = true
	check(moved_corner and part_area(info, W) > before_walls, "a hand-placed outer corner reshapes the thick wall")
	data.move_vertices(PackedVector2Array([Vector2(0, 0)]), PackedVector2Array([Vector2(-1, 0)]))
	check(data.sectors[0].outer_corners.has(DMMapData.key_of(Vector2(-1, 0))), "it follows when the room's corner is dragged")
	check(data.sectors[0].duplicate_sector().outer_corners.size() == 1, "it is copied with the sector (undo)")
	tw = data.thicken_walls(0, 0.75, 1)
	check(tw.ok and data.sectors[0].outer_corners.is_empty(), "setting a new thickness puts the corners back to square")

	map.queue_free()
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
