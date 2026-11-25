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

	map.queue_free()
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
