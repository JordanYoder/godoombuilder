# Headless tests for the editor's operations on a selection (DMEditor, the
# part the dock, toolbar and viewport tool call): rotate by any angle,
# texture tools (Fit, nudge, copy / paste alignment), Select Similar and
# prefabs. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://test/editor_test.gd
extends SceneTree

const F := DMBuilder.Part.FLOOR
const C := DMBuilder.Part.CEILING
const W := DMBuilder.Part.WALL
const PREFAB_PATH := "user://godoombuilder_test_prefab.tres"


## The real editor, with undo steps and messages recorded.
class Recorder:
	extends DMEditor
	var commits: Array[String] = []
	var notes: Array[String] = []
	var last_before: DMMapData

	func _record_undo(action: String, before: DMMapData, _after: DMMapData, _merge: bool) -> void:
		commits.append(action)
		last_before = before

	func notify(message: String, _severity := Severity.WARNING) -> void:
		notes.append(message)

	## Undoes the last recorded step.
	func undo() -> void:
		map.data.copy_from(last_before)
		map.rebuild()


var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


static func rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


static func near_v(a: Vector2, b: Vector2, eps := 0.001) -> bool:
	return a.distance_to(b) <= eps


static func defaults() -> DMSector:
	var d := DMSector.new()
	d.floor_height = 0.0
	d.ceiling_height = 4.0
	return d


## A fresh map in the tree with an editor on it, and these rooms drawn.
func make_editor(rooms: Array[PackedVector2Array]) -> Recorder:
	var map := DMMap.new()
	map.data = DMMapData.new()
	root.add_child(map)
	for r in rooms:
		map.data.add_loop(r, defaults())
	map.rebuild()
	var ed := Recorder.new()
	ed.set_map(map)
	return ed


func done(ed: Recorder) -> void:
	var map := ed.map
	ed.dispose()
	map.queue_free()


## The sector polygon edge of sector `si` running along z == `z` (or x == `x`).
static func edge_where(s: DMSector, axis: int, value: float) -> DMTool.Wall:
	for poly in s.polygons:
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			if is_equal_approx(a[axis], value) and is_equal_approx(b[axis], value):
				return DMTool.Wall.new(0, a, b)
	return null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_rotate_by_angle()
	_fit_texture()
	_nudge_and_copy_texture()
	_select_similar()
	_prefabs()
	_wall_length()
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)


func _rotate_by_angle() -> void:
	var ed := make_editor([rect(0, 0, 4, 4)])
	ed.tool.selected.assign([0])
	ed.rotate_selected(45.0)
	var s := ed.map.data.sectors[0]
	var box := ed.map.data.bounds_of([0])
	check(ed.commits.back() == "Rotate Sectors" and absf(s.area() - 16.0) < 0.001 and ed.map.data.validate() == "",
		"rotating by 45° keeps the room's size")
	check(absf(box.size.x - 4.0 * sqrt(2.0)) < 0.001 and near_v(box.get_center(), Vector2(2, 2)),
		"it turns about the grid point at its center")
	var top := Vector2(INF, INF)
	for v in s.polygons[0]:
		if v.y < top.y:
			top = v
	check(near_v(top, Vector2(2, 2 - 2.0 * sqrt(2.0))), "the corner ends up straight above the center")
	var count := ed.commits.size()
	ed.rotate_selected(360.0)
	check(ed.commits.size() == count, "a full turn does nothing")
	ed.rotate_angle = -45.0
	ed.transform_selected("rotate_angle")
	check(near_v(ed.map.data.bounds_of([0]).size, Vector2(4, 4)), "Rotate by Angle with -45° turns it back")
	done(ed)

	ed = make_editor([rect(0, 0, 4, 4), rect(4, 0, 8, 4)])
	ed.tool.selected.assign([0])
	ed.rotate_selected(30.0)
	check(ed.notes.back().begins_with("Can't do that here") and absf(ed.map.data.sectors[0].area() - 16.0) < 0.001
		and near_v(ed.map.data.bounds_of([0]).size, Vector2(4, 4)), "a rotation into the neighbouring room is refused and undone")
	done(ed)


func _fit_texture() -> void:
	var ed := make_editor([rect(1, 1, 5, 3)])
	ed.tool.selected.assign([0])
	ed.fit_selected_uv(F)
	var s := ed.map.data.sectors[0]
	var t := s.uv_transform(F)
	check(near_v(t * DMBuilder.uv_at(Vector3(1, 0, 1), Vector3.UP), Vector2.ZERO)
		and near_v(t * DMBuilder.uv_at(Vector3(5, 0, 3), Vector3.UP), Vector2.ONE) and ed.commits.back() == "Fit Texture",
		"Fit: one floor texture repeat covers the floor exactly")

	var w := edge_where(s, 1, 1.0)
	ed.tool.selected_wall = w
	ed.fit_selected_uv(W)
	var o := s.wall_override(w.a, w.b)
	var tw := s.uv_transform(W, o)
	var d := w.b - w.a
	var inward := Vector3(-d.y, 0.0, d.x).normalized()
	check(near_v(tw * DMBuilder.uv_at(Vector3(w.a.x, 4, w.a.y), inward), Vector2.ZERO)
		and near_v(tw * DMBuilder.uv_at(Vector3(w.b.x, 0, w.b.y), inward), Vector2.ONE),
		"Fit with a wall selected: one texture repeat covers that wall")
	check(s.wall_overrides.size() == 1, "only the selected wall gets its own alignment")
	ed.tool.selected_wall = null
	ed.fit_selected_uv(W)
	var all_fit := s.wall_overrides.size() == 4
	for poly in s.polygons:
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			var e := b - a
			var n := Vector3(-e.y, 0.0, e.x).normalized()
			var tk := s.uv_transform(W, s.wall_override(a, b))
			if not near_v(tk * DMBuilder.uv_at(Vector3(b.x, 0, b.y), n), Vector2.ONE):
				all_fit = false
	check(all_fit, "Fit with the room selected: every wall gets one repeat")
	ed.reset_selected_uv(F)
	check(s.uv_transform(F) == Transform2D.IDENTITY, "Reset Texture undoes a fit")
	done(ed)


func _nudge_and_copy_texture() -> void:
	var ed := make_editor([rect(0, 0, 4, 4), rect(4, 0, 8, 4)])
	var one: Array[int] = [0]
	ed.nudge_uv(one, F, null, Vector2(0.5, 0))
	ed.nudge_uv(one, F, null, Vector2(0, -0.25))
	var s0 := ed.map.data.sectors[0]
	check(near_v(s0.floor_uv_offset, Vector2(-0.5, 0.25)) and ed.commits.back() == "Move Texture", "nudging moves the floor texture")
	var before := s0.floor_uv_offset
	ed.undo()
	check(not near_v(ed.map.data.sectors[0].floor_uv_offset, before), "a nudge can be undone")
	s0 = ed.map.data.sectors[0]

	var w := edge_where(s0, 1, 0.0)
	var wall_only: Array[int] = [0]
	ed.nudge_uv(wall_only, W, w, Vector2(0, -1))
	var o := s0.wall_override(w.a, w.b)
	check(near_v(DMSector.setting_vector(o, "uv_offset", Vector2.ZERO), Vector2(0, 1)) and s0.wall_uv_offset == Vector2.ZERO,
		"nudging a wall moves just that wall's texture")

	s0.set_uv_values(F, Vector2(0.3, 0.2), Vector2(2, 2), 30.0)
	ed.copy_uv(0, F)
	var other: Array[int] = [1]
	ed.paste_uv(other, F, null)
	var s1 := ed.map.data.sectors[1]
	check(near_v(s1.floor_uv_offset, Vector2(0.3, 0.2)) and near_v(s1.floor_uv_size, Vector2(2, 2))
		and is_equal_approx(s1.floor_uv_rotation, 30.0) and ed.commits.back() == "Paste Texture Alignment",
		"copy / paste alignment gives another floor the same offset, size and rotation")
	ed.copy_uv(0, W, w)
	ed.paste_uv(other, C, null)
	check(near_v(s1.ceiling_uv_offset, Vector2(0, 1)), "an alignment copied from a wall pastes onto a ceiling")
	ed.tool.selected.assign([0, 1])
	ed.uv_clipboard = DMSector.UV.make(Vector2(1, 1), Vector2.ONE, 0.0)
	ed.paste_selected_uv(F)
	check(near_v(s0.floor_uv_offset, Vector2(1, 1)) and near_v(s1.floor_uv_offset, Vector2(1, 1)), "Paste Alignment (dock) applies to every selected floor")
	ed.uv_clipboard = null
	ed.paste_uv(other, F, null)
	check(ed.notes.back().begins_with("Copy a texture alignment first"), "pasting with nothing copied says how to copy")
	done(ed)


func _select_similar() -> void:
	var ed := make_editor([rect(0, 0, 4, 4), rect(4, 0, 8, 4), rect(8, 0, 12, 4), rect(0, 4, 4, 8)])
	var sectors := ed.map.data.sectors
	sectors[2].floor_height = 1.0
	sectors[3].ceiling_height = 3.0
	var mat := StandardMaterial3D.new()
	sectors[0].wall_material = mat
	sectors[2].wall_material = mat
	ed.tool.selected.assign([0])
	ed.select_similar("floor_height")
	check(ed.tool.selected == [0, 1, 3], "Select Similar: same floor height")
	ed.tool.selected.assign([0])
	ed.select_similar("heights")
	check(ed.tool.selected == [0, 1], "both heights")
	ed.tool.selected.assign([2])
	ed.select_similar("wall_material")
	check(ed.tool.selected == [2, 0], "same wall material (the first selected stays first)")
	ed.tool.selected.assign([1])
	ed.select_similar("materials")
	check(ed.tool.selected == [1, 3], "all materials alike")
	ed.tool.selected.clear()
	ed.select_similar("floor_height")
	check(ed.tool.selected.is_empty() and ed.notes.back().begins_with("Select a sector first"), "with nothing selected it explains")
	done(ed)


func _prefabs() -> void:
	var ed := make_editor([rect(10, 10, 14, 14), rect(14, 10, 16, 12)])
	var src := ed.map.data.sectors
	src[1].floor_height = 0.5
	src[0].set_uv_values(F, Vector2(0.25, 0), Vector2(2, 2), 0.0)
	src[0].set_wall_override(Vector2(10, 10), Vector2(14, 10), {"hidden": true})
	ed.tool.selected.assign([0, 1])
	check(ed.save_prefab(PREFAB_PATH) == OK and ResourceLoader.exists(PREFAB_PATH), "Save as Prefab writes a resource file")
	done(ed)

	var ed2 := make_editor([rect(0, 0, 20, 20)])
	check(ed2.load_prefab(PREFAB_PATH) and ed2.clipboard.size() == 2 and ed2.tool.mode == DMTool.Mode.PASTE,
		"Paste Prefab loads it into another map's clipboard and starts placing it")
	var lo := Vector2(INF, INF)
	for s in ed2.clipboard:
		for p in s.polygons:
			for v in p:
				lo = lo.min(v)
	check(near_v(lo, Vector2.ZERO), "the prefab is placed by its corner")
	check(ed2.paste_at(Transform2D(0.0, Vector2(2, 2))) and ed2.map.data.validate() == "" and ed2.map.data.sectors.size() == 3,
		"it pastes into the room, cutting its space")
	var pasted := ed2.map.data.sectors
	var kept_settings := false
	for i in ed2.tool.selected:
		var s := pasted[i]
		if near_v(s.floor_uv_size, Vector2(2, 2)) and s.hidden_wall_count() == 1:
			kept_settings = true
	check(kept_settings, "heights, texture alignment and wall settings come with it")
	check(not ed2.load_prefab("user://no_such_prefab.tres") and ed2.notes.back().contains("isn't a sector prefab"),
		"a missing file is refused")
	var empty := DMMapData.new()
	ResourceSaver.save(empty, "user://godoombuilder_empty_prefab.tres")
	check(not ed2.load_prefab("user://godoombuilder_empty_prefab.tres"), "an empty prefab is refused")
	ed2.tool.selected.clear()
	ed2.clipboard.clear()
	check(ed2.save_prefab("user://godoombuilder_nothing.tres") != OK, "saving with nothing selected or copied is refused")
	done(ed2)
	for path in [PREFAB_PATH, "user://godoombuilder_empty_prefab.tres"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# Removing a corner never deletes a sector: a triangle keeps its corners.
	var tri: Array[PackedVector2Array] = [PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(0, 4)])]
	var ed3 := make_editor(tri)
	ed3.remove_corner(Vector2(4, 0))
	check(ed3.map.data.sectors.size() == 1 and ed3.map.data.sectors[0].polygons[0].size() == 3
		and ed3.notes.back().contains("at least 3"), "a triangle's corner can't be removed (the sector would vanish)")
	# Unfinished polygons are saved with the map and survive a reload.
	ed3.keep_draft(PackedVector2Array([Vector2(10, 0), Vector2(12, 0), Vector2(12, 3)]), 1.5)
	var draft_path := "user://godoombuilder_draft_test.tres"
	ResourceSaver.save(ed3.map.data, draft_path)
	var loaded := ResourceLoader.load(draft_path, "", ResourceLoader.CACHE_MODE_IGNORE) as DMMapData
	check(loaded != null and loaded.drafts.size() == 1 and loaded.drafts[0].points.size() == 3
		and is_equal_approx(loaded.drafts[0].height, 1.5), "an unfinished polygon is saved and loaded with the map")
	ed3.discard_draft(0)
	check(ed3.map.data.drafts.is_empty(), "discard_draft removes it")
	done(ed3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(draft_path))


func _wall_length() -> void:
	# Two rooms side by side, sharing the corner (4, 0).
	var ed := make_editor([rect(0, 0, 4, 4), rect(4, 0, 8, 4)])
	var s := ed.map.data.sectors[0]
	var w := edge_where(s, 1, 0.0)
	ed.tool.selected.assign([0])
	ed.tool.selected_wall = w
	var far := w.b if w.b.x > w.a.x else w.a
	ed.length_anchor = DMEditor.LengthAnchor.KEEP_A if far == w.b else DMEditor.LengthAnchor.KEEP_B
	ed.set_wall_length(6.0)
	var sw := ed.tool.selected_wall
	check(ed.commits.back() == "Set Wall Length" and sw != null and absf(sw.a.distance_to(sw.b) - 6.0) < 0.001
		and ed.map.data.validate() == "", "Set Wall Length makes the wall 6 m long and keeps it selected")
	check(absf(s.area() - 20.0) < 0.001 and absf(ed.map.data.sectors[1].area() - 12.0) < 0.001,
		"the shared corner moves, so the neighbour shrinks with no gap")
	check(near_v(sw.a, Vector2(0, 0)) or near_v(sw.b, Vector2(0, 0)), "the fixed end stays put")
	var count := ed.commits.size()
	ed.set_wall_length(9.0)
	check(ed.commits.size() == count and ed.notes.back().begins_with("Can't make the wall that long")
		and absf(ed.map.data.sectors[0].area() - 20.0) < 0.001, "a length that would cross the neighbour is refused and undone")
	ed.set_wall_length(6.0)
	check(ed.commits.size() == count, "setting the same length does nothing")
	done(ed)

	ed = make_editor([rect(0, 0, 4, 4)])
	s = ed.map.data.sectors[0]
	ed.tool.selected.assign([0])
	ed.tool.selected_wall = edge_where(s, 1, 0.0)
	ed.length_anchor = DMEditor.LengthAnchor.CENTER
	ed.set_wall_length(2.0)
	sw = ed.tool.selected_wall
	check(near_v((sw.a + sw.b) * 0.5, Vector2(2, 0)) and absf(sw.a.distance_to(sw.b) - 2.0) < 0.001
		and absf(s.area() - 12.0) < 0.001, "with Center fixed, both ends move in")
	done(ed)
