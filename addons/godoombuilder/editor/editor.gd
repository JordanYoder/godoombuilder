@tool
class_name DMEditor
extends RefCounted
## Everything you can do to the selected sector map, each edit one undo step:
## drawing, heights, materials, walls, copy / paste and the rest. The tool,
## dock and toolbar call these.
##
## The GoDoomBuilder EditorPlugin fills in the editor-specific parts (undo
## history, messages, saved settings, the grid) by overriding the hooks at the
## bottom; tests use it headless with their own hooks.


enum Severity { INFO, WARNING }

const STAIR_DIRECTIONS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

var tool: DMTool
var map: DMMap
## Display units (DMUnits.Units).
var units := DMUnits.Units.METERS
## Grid snap size in meters.
var grid_step := 0.5
## Heights and materials for sectors drawn in empty space.
var defaults := DMSector.new()
## Which point stays put when resizing: 0 center, then corners
## (-X -Z), (+X -Z), (-X +Z), (+X +Z).
var resize_anchor := 0
## Which point of the selected wall stays put when setting its length: its
## middle, or its A or B end (labelled in the viewport).
enum LengthAnchor { CENTER, KEEP_A, KEEP_B }
var length_anchor := LengthAnchor.KEEP_A
## Wall thickness settings used by thicken_selected (meters; -1 inside,
## 0 centered, 1 outside).
var wall_thickness := 0.25
var wall_side := 1
## Curve Wall settings: number of straight pieces, and how far the middle of
## the wall moves (meters; positive outward, negative into the room).
var curve_segments := 8
var curve_bulge := 1.0
## Stairs settings: rise per step (meters), whether ceilings move with the
## floors, and for Split into Steps the number of steps and the direction
## they climb (an index into STAIR_DIRECTIONS).
var stair_step := 0.25
var stair_ceilings := false
var stair_count := 4
var stair_direction := 0
## Copied sectors, placed so their bounding box starts at (0, 0).
var clipboard: Array[DMSector] = []
## Rotate by Angle: degrees, positive clockwise as seen from above.
var rotate_angle := 45.0
## Copied texture alignment (Copy / Paste Alignment), or null.
var uv_clipboard: DMSector.UV


func _init() -> void:
	tool = DMTool.new()
	tool.editor = self


## Stops editing and lets go of the tool (the two refer to each other).
func dispose() -> void:
	set_map(null)
	tool.editor = null
	clipboard.clear()


## Starts editing `m` (or nothing, for null).
func set_map(m: DMMap) -> void:
	if m == map:
		return
	# A polygon being drawn is kept with the map it was drawn on.
	if is_instance_valid(map) and map.data != null:
		tool.cancel_draw()
	if is_instance_valid(map) and map.data != null and map.data.changed.is_connected(_on_map_data_changed):
		map.data.changed.disconnect(_on_map_data_changed)
	map = m if is_instance_valid(m) else null
	if map != null:
		if map.data == null:
			map.data = DMMapData.new()
		map.data.changed.connect(_on_map_data_changed)
	tool.set_map(map)
	on_tool_changed()


func _on_map_data_changed() -> void:
	tool.validate_selection()
	_refresh_ui()
	update_overlays()
	tool.update_highlight()


## Called by the tool whenever its state changes.
func on_tool_changed() -> void:
	_refresh_ui()
	update_overlays()
	tool.update_highlight()


func has_map() -> bool:
	return map != null and map.data != null


func _sectors() -> Array[DMSector]:
	return map.data.sectors


# --- Drawing and heights ---------------------------------------------------------

## Adds a sector from the drawn loop. `draft` is the unfinished polygon it
## continues (an index into map.data.drafts, or -1); it's removed in the same
## undo step.
func commit_loop(points: PackedVector2Array, draft := -1) -> DMResult:
	var before := map.data.duplicate_data()
	var result := map.data.add_loop(points, defaults)
	if not result.ok:
		map.data.copy_from(before)
		notify(result.message)
		return result
	if draft >= 0 and draft < map.data.drafts.size():
		map.data.drafts.remove_at(draft)
	_commit("Draw Sector", before)
	return result


## Saves a polygon left unfinished so it can be continued later: as a new
## unfinished polygon (`index` -1) or in place of the one it continued.
func keep_draft(points: PackedVector2Array, height: float, index := -1) -> void:
	if not has_map():
		return
	var d := DMDraft.make(points, height)
	var drafts := map.data.drafts
	if index >= 0 and index < drafts.size() and drafts[index].same_as(d):
		return
	var before := map.data.duplicate_data()
	if index >= 0 and index < drafts.size():
		drafts[index] = d
	else:
		drafts.append(d)
	_commit("Keep Unfinished Polygon", before)
	notify("Saved the unfinished polygon (red). Click either end to continue it.", Severity.INFO)


func discard_draft(index: int) -> void:
	if not has_map() or index < 0 or index >= map.data.drafts.size():
		return
	var before := map.data.duplicate_data()
	map.data.drafts.remove_at(index)
	_commit("Discard Unfinished Polygon", before)


func nudge_heights(targets: Array[int], part: int, delta: float) -> void:
	var before := map.data.duplicate_data()
	for i in targets:
		_set_height(_sectors()[i], part, _height(_sectors()[i], part) + delta)
	var what := "Floor" if part == DMBuilder.Part.FLOOR else "Ceiling"
	_commit(("Raise " if delta > 0.0 else "Lower ") + what, before, true)


func set_selected_height(part: int, meters: float) -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		_set_height(_sectors()[i], part, meters)
	_commit("Set Floor Height" if part == DMBuilder.Part.FLOOR else "Set Ceiling Height", before, true)


func set_selected_material(part: int, mat: Material) -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		var s := _sectors()[i]
		match part:
			DMBuilder.Part.FLOOR:
				s.floor_material = mat
			DMBuilder.Part.CEILING:
				s.ceiling_material = mat
			_:
				s.wall_material = mat
	_commit("Set Sector Material", before)


## Puts a dropped material (or texture) on the surface `hit` of map `m`:
## that sector's floor, ceiling or walls, or those of every selected sector
## when it was dropped on one of them. A texture gets a material made for it
## (shared by every surface it's dropped on in the map). Returns false when
## `res` isn't a material or texture.
func drop_on_surface(m: DMMap, hit: DMMap.Hit, res: Resource) -> bool:
	if m == null or hit == null or res == null:
		return false
	if m != map:
		_focus_map(m)
	if map != m or hit.sector < 0 or hit.sector >= _sectors().size():
		return false
	var mat := material_for(res)
	if mat == null:
		return false
	var targets: Array[int] = []
	if tool.selected.has(hit.sector):
		targets.assign(tool.selected)
	else:
		targets.append(hit.sector)
	var before := map.data.duplicate_data()
	for i in targets:
		var s := _sectors()[i]
		match hit.part:
			DMBuilder.Part.FLOOR:
				s.floor_material = mat
			DMBuilder.Part.CEILING:
				s.ceiling_material = mat
			_:
				s.wall_material = mat
	var what: String = ["Floor", "Ceiling", "Wall"][clampi(hit.part, 0, 2)]
	_commit("Drop %s Material" % what, before)
	return true


## `res` as a material for a surface: a material as it is; for a texture, the
## material already made for it in this map, or a new one showing it.
func material_for(res: Resource) -> Material:
	if res is Material:
		return res as Material
	var tex := res as Texture2D
	if tex == null:
		return null
	if map != null:
		for s in _sectors():
			for m: Material in [s.floor_material, s.ceiling_material, s.wall_material]:
				var made := m as StandardMaterial3D
				if made != null and made.albedo_texture == tex and made.get_meta(TEXTURE_MATERIAL_META, false):
					return made
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.resource_name = tex.resource_path.get_file().get_basename() if not tex.resource_path.is_empty() else "Texture"
	mat.set_meta(TEXTURE_MATERIAL_META, true)
	return mat


## Marks materials made for a dropped texture (so they're reused).
const TEXTURE_MATERIAL_META := &"godoombuilder_texture_material"


## Shows which surface a drop would land on (while dragging over a 3D view).
func show_drop_hint(m: DMMap, hit: DMMap.Hit) -> void:
	if m != map or m == null:
		return
	tool.hover = hit
	update_overlays()


## Records an edit the tool already applied to map.data (e.g. a drag).
func commit_snapshot(action: String, before: DMMapData) -> void:
	_commit(action, before)


## Resizes the selected sectors to `meters` along axis 0 (X, width) or 1 (Z,
## depth). Neighbours sharing their corners stretch along.
func resize_selected(axis: int, meters: float) -> void:
	if not has_map() or tool.selected.is_empty() or meters <= 0.0:
		return
	var box := map.data.bounds_of(tool.selected)
	var old := box.size[axis]
	if old < DMGeo.SNAP or is_equal_approx(old, meters):
		return
	var anchor := box.get_center()
	match resize_anchor:
		1: anchor = box.position
		2: anchor = Vector2(box.end.x, box.position.y)
		3: anchor = Vector2(box.position.x, box.end.y)
		4: anchor = box.end
	var factor := Vector2.ONE
	factor[axis] = meters / old
	var before := map.data.duplicate_data()
	map.data.scale_sectors(tool.selected, anchor, factor)
	var why := map.data.validate()
	if not why.is_empty():
		_refuse(before, "Can't resize to that: " + why + ".")
		return
	_commit("Resize Sector", before, true)


## Joins the selected sectors into one (the first selected one's heights and
## materials win).
func join_selected() -> void:
	if not has_map() or tool.selected.size() < 2:
		notify("Shift+click two or more sectors to join them.")
		return
	var before := map.data.duplicate_data()
	var index := map.data.join_sectors(tool.selected)
	tool.selected.assign([index])
	_commit("Join Sectors", before)


## Gives each selected sector's walls a thickness (a solid band along its
## boundary), or just the selected wall.
func thicken_selected() -> void:
	if not has_map() or tool.selected.is_empty():
		return
	if tool.selected_wall != null:
		_thicken_wall()
		return
	var before := map.data.duplicate_data()
	var targets: Array[DMSector] = []
	for i in tool.selected:
		targets.append(_sectors()[i])
	for t in targets:
		var i := _sectors().find(t)
		if i < 0:
			continue
		var r := map.data.thicken_walls(i, wall_thickness, wall_side)
		if not r.ok:
			_refuse(before, r.message)
			return
	var why := map.data.validate()
	if not why.is_empty():
		_refuse(before, "Can't thicken the walls: " + why + ".")
		return
	var kept: Array[int] = []
	for t in targets:
		var i := _sectors().find(t)
		if i >= 0:
			kept.append(i)
	tool.selected = kept
	_commit("Thicken Walls", before)


func _thicken_wall() -> void:
	var w := tool.selected_wall
	var before := map.data.duplicate_data()
	var r := map.data.thicken_edge(w.sector, w.a, w.b, wall_thickness, wall_side)
	var why := r.message if not r.ok else map.data.validate()
	if not why.is_empty():
		_refuse(before, why if not r.ok else "Can't thicken the wall: " + why + ".")
		return
	tool.selected.assign([r.index])
	# Thickening outward leaves the wall where it is; otherwise it moved.
	tool.selected_wall = DMTool.Wall.new(r.index, w.a, w.b) if wall_side > 0 else null
	_commit("Thicken Wall", before)


func set_selected_floor(on: bool) -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		_sectors()[i].has_floor = on
	_commit("Floor On" if on else "Remove Floor", before)


func set_selected_ceiling(on: bool) -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		_sectors()[i].has_ceiling = on
	_commit("Ceiling On" if on else "Open to Sky", before)


## Removes points that don't change the selected sectors' shapes.
func simplify_selected() -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	var removed := 0
	for i in tool.selected:
		removed += map.data.simplify_sector(i)
	if removed == 0:
		notify("Nothing to simplify: every point changes the shape.", Severity.INFO)
		return
	var why := map.data.validate()
	if not why.is_empty():
		_refuse(before, "Can't simplify: " + why + ".")
		return
	_commit("Simplify Sector", before)
	notify("Removed %d point%s." % [removed, "" if removed == 1 else "s"], Severity.INFO)


func delete_selected() -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	map.data.delete_sectors(tool.selected)
	tool.selected.clear()
	_commit("Delete Sectors", before)


# --- Single walls ----------------------------------------------------------------

## The selected wall's sector, or null.
func _wall_sector() -> DMSector:
	if not has_map() or tool.selected_wall == null:
		return null
	var i := tool.selected_wall.sector
	return _sectors()[i] if i < _sectors().size() else null


func set_wall_hidden(hidden: bool) -> void:
	var s := _wall_sector()
	if s == null:
		return
	var before := map.data.duplicate_data()
	s.set_wall_override(tool.selected_wall.a, tool.selected_wall.b, {"hidden": true if hidden else null})
	_commit("Hide Wall" if hidden else "Show Wall", before)


## Sets the selected wall's own bottom or top height (meters).
func set_wall_height(top: bool, meters: float) -> void:
	var s := _wall_sector()
	if s == null:
		return
	var before := map.data.duplicate_data()
	s.set_wall_override(tool.selected_wall.a, tool.selected_wall.b, {("top" if top else "bottom"): meters})
	_commit("Set Wall Height", before, true)


## Sets the selected wall's length (meters) by moving its corners along the
## wall: which point stays put is `length_anchor`. Shared corners move too,
## so neighbouring rooms stretch along. The wall stays selected.
func set_wall_length(meters: float) -> void:
	var s := _wall_sector()
	if s == null or meters <= 0.0:
		return
	var w := tool.selected_wall
	var old := w.a.distance_to(w.b)
	if old < DMGeo.LINE_EPS or absf(old - meters) < DMGeo.SNAP:
		return
	var dir := (w.b - w.a) / old
	var new_a := w.a
	var new_b := w.b
	match length_anchor:
		LengthAnchor.CENTER:
			var mid := (w.a + w.b) * 0.5
			new_a = mid - dir * meters * 0.5
			new_b = mid + dir * meters * 0.5
		LengthAnchor.KEEP_A:
			new_b = w.a + dir * meters
		LengthAnchor.KEEP_B:
			new_a = w.b - dir * meters
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	if not new_a.is_equal_approx(w.a):
		from.append(w.a)
		to.append(new_a)
	if not new_b.is_equal_approx(w.b):
		from.append(w.b)
		to.append(new_b)
	var before := map.data.duplicate_data()
	map.data.move_vertices(from, to, false)
	var why := map.data.validate()
	if not why.is_empty():
		_refuse(before, "Can't make the wall that long: " + why + ".")
		return
	# move_vertices snaps to DMGeo.SNAP: select the wall where it ended up.
	w.a = Vector2(snappedf(new_a.x, DMGeo.SNAP), snappedf(new_a.y, DMGeo.SNAP))
	w.b = Vector2(snappedf(new_b.x, DMGeo.SNAP), snappedf(new_b.y, DMGeo.SNAP))
	_commit("Set Wall Length", before, true)


## Back to the sector's heights, thickness and texture, and shown.
func reset_wall() -> void:
	var s := _wall_sector()
	if s == null:
		return
	var before := map.data.duplicate_data()
	s.set_wall_override(tool.selected_wall.a, tool.selected_wall.b, DMSector.cleared_settings())
	s.clear_outer_corners([tool.selected_wall.a, tool.selected_wall.b])
	_commit("Reset Wall", before)


func show_hidden_walls() -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		_sectors()[i].show_hidden_walls()
	_commit("Show Hidden Walls", before)


## Sets the selected sectors' outer wall thickness directly (0 = thin).
func set_selected_wall_thickness(meters: float) -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		_sectors()[i].wall_thickness = maxf(meters, 0.0)
		_sectors()[i].clear_outer_corners()
	_commit("Set Wall Thickness", before, true)


## Sets the selected wall's own thickness (0 = thin; negative: back to the
## sector's).
func set_wall_thickness(meters: float) -> void:
	var s := _wall_sector()
	if s == null:
		return
	var before := map.data.duplicate_data()
	s.set_wall_override(tool.selected_wall.a, tool.selected_wall.b, {"thickness": meters if meters >= 0.0 else null})
	s.clear_outer_corners([tool.selected_wall.a, tool.selected_wall.b])
	_commit("Set Wall Thickness", before, true)


# --- Texture alignment -----------------------------------------------------------

## Sets the texture alignment of the selection's floors, ceilings or walls.
## For walls with a single wall selected, only that wall changes.
func set_selected_uv(part: int, offset: Vector2, size: Vector2, rotation_deg: float) -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	if part == DMBuilder.Part.WALL and tool.selected_wall != null:
		var w := tool.selected_wall
		var s := _sectors()[w.sector]
		var edge := s.override_edge(w.a, w.b)
		s.set_wall_override(edge[0], edge[1], {"uv_offset": offset, "uv_size": size, "uv_rotation": rotation_deg})
	else:
		for i in tool.selected:
			_sectors()[i].set_uv_values(part, offset, size, rotation_deg)
	_commit("Align Texture", before, true)


## Back to plain world alignment (for a selected wall: back to its sector's).
func reset_selected_uv(part: int) -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	if part == DMBuilder.Part.WALL and tool.selected_wall != null:
		var w := tool.selected_wall
		var s := _sectors()[w.sector]
		var edge := s.override_edge(w.a, w.b)
		s.set_wall_override(edge[0], edge[1], {"uv_offset": null, "uv_size": null, "uv_rotation": null})
	else:
		for i in tool.selected:
			_sectors()[i].set_uv_values(part, Vector2.ZERO, Vector2.ONE, 0.0)
	_commit("Reset Texture", before)


# --- Copy, paste, rotate, mirror -------------------------------------------------

func copy_selected() -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var list: Array[DMSector] = []
	for i in tool.selected:
		list.append(_sectors()[i])
	var origin := map.data.bounds_of(tool.selected).position
	clipboard = DMMapData.transformed_sectors(list, Transform2D(0.0, -origin))
	notify("Copied %d sector%s. Ctrl+V to paste." % [list.size(), "" if list.size() == 1 else "s"], Severity.INFO)


## Starts placing the clipboard (it follows the mouse until clicked).
func begin_paste() -> void:
	if not has_map():
		return
	if clipboard.is_empty():
		notify("Nothing copied yet: select sectors and press Ctrl+C.")
		return
	tool.begin_paste()


## Pastes the clipboard moved by `xf` (from the tool's paste placement).
func paste_at(xf: Transform2D) -> bool:
	if not has_map() or clipboard.is_empty():
		return false
	var before := map.data.duplicate_data()
	var r := map.data.paste_sectors(clipboard, xf)
	if not r.ok:
		_refuse(before, r.message)
		return false
	var why := map.data.validate()
	if not why.is_empty():
		_refuse(before, "Can't paste there: " + why + ".")
		return false
	tool.selected.assign(r.indices)
	tool.selected_wall = null
	_commit("Paste Sectors", before)
	return true


## Rotates (90° steps, positive clockwise as seen from above) or mirrors
## ("x": left-right, "z": front-back) the selected sectors about the grid
## point nearest their center. Their neighbours stay where they are.
func transform_selected(kind: String) -> void:
	match kind:
		"rotate_cw":
			_transform_selected(Transform2D(PI * 0.5, Vector2.ZERO), "Rotate Sectors")
		"rotate_ccw":
			_transform_selected(Transform2D(-PI * 0.5, Vector2.ZERO), "Rotate Sectors")
		"rotate_angle":
			rotate_selected(rotate_angle)
		"mirror_x":
			_transform_selected(Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO), "Mirror Sectors")
		"mirror_z":
			_transform_selected(Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2.ZERO), "Mirror Sectors")


## Rotates the selected sectors by any angle (degrees, positive clockwise
## as seen from above) about the grid point nearest their center.
func rotate_selected(degrees: float) -> void:
	if is_zero_approx(fmod(degrees, 360.0)):
		return
	_transform_selected(Transform2D(deg_to_rad(degrees), Vector2.ZERO), "Rotate Sectors")


func _transform_selected(basis: Transform2D, action: String) -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var box := map.data.bounds_of(tool.selected)
	var pivot := box.get_center().snapped(Vector2(grid_step, grid_step))
	var xf := Transform2D(0.0, pivot) * basis * Transform2D(0.0, -pivot)
	var before := map.data.duplicate_data()
	map.data.transform_sectors(tool.selected, xf)
	var why := map.data.validate()
	if not why.is_empty():
		_refuse(before, "Can't do that here: " + why + " (move them into open space first).")
		return
	tool.selected_wall = null
	_commit(action, before)


func set_rotate_angle(degrees: float) -> void:
	rotate_angle = degrees
	save_settings()


# --- Prefabs ---------------------------------------------------------------------

## Saves the selection (or, with nothing selected, the clipboard) as a
## prefab: a DMMapData resource file, placed so its corner is at (0, 0).
## Paste it into any map with load_prefab().
func save_prefab(path: String) -> Error:
	var list: Array[DMSector] = []
	if has_map() and not tool.selected.is_empty():
		for i in tool.selected:
			list.append(_sectors()[i])
		list = DMMapData.transformed_sectors(list, Transform2D(0.0, -map.data.bounds_of(tool.selected).position))
	else:
		list = clipboard
	if list.is_empty():
		notify("Select the sectors to save as a prefab first.")
		return ERR_INVALID_DATA
	var prefab := DMMapData.new()
	for s in list:
		prefab.sectors.append(s.duplicate_sector())
	var err := ResourceSaver.save(prefab, path)
	if err != OK:
		notify("Couldn't save the prefab to %s (%s)." % [path, error_string(err)])
	else:
		notify("Saved %d sector%s as %s." % [list.size(), "" if list.size() == 1 else "s", path.get_file()], Severity.INFO)
	return err


## Loads a prefab saved by save_prefab() (any DMMapData resource works) into
## the clipboard and starts placing it.
func load_prefab(path: String) -> bool:
	var res: Resource = load(path) if ResourceLoader.exists(path) else null
	var prefab := res as DMMapData
	if prefab == null or prefab.sectors.is_empty() or not prefab.check().is_empty():
		notify("%s isn't a sector prefab (or it's empty or damaged)." % path.get_file())
		return false
	var all: Array[int] = []
	for i in prefab.sectors.size():
		all.append(i)
	clipboard = DMMapData.transformed_sectors(prefab.sectors, Transform2D(0.0, -prefab.bounds_of(all).position))
	begin_paste()
	return true


## Asks for a file and saves the selection as a prefab there.
func ask_save_prefab() -> void:
	if not has_map() or (tool.selected.is_empty() and clipboard.is_empty()):
		notify("Select the sectors to save as a prefab first.")
		return
	_pick_file(true, func(path: String) -> void: save_prefab(path))


## Asks for a prefab file and starts placing it.
func ask_load_prefab() -> void:
	if not has_map():
		return
	_pick_file(false, func(path: String) -> void: load_prefab(path))


# --- Selecting -------------------------------------------------------------------

## What select_similar() can compare.
const SIMILAR_KINDS: Array[String] = ["floor_height", "ceiling_height", "heights", "floor_material", "ceiling_material", "wall_material", "materials"]


## Selects every sector like the first selected one: same floor height,
## ceiling height, both ("heights"), floor / ceiling / wall material, or all
## three materials ("materials").
func select_similar(kind: String) -> void:
	if not has_map() or tool.selected.is_empty():
		notify("Select a sector first: Select Similar finds the ones like it.")
		return
	var ref := _sectors()[tool.selected[0]]
	var out: Array[int] = [tool.selected[0]]
	for i in _sectors().size():
		if i != tool.selected[0] and _similar(ref, _sectors()[i], kind):
			out.append(i)
	tool.selected = out
	tool.selected_wall = null
	on_tool_changed()
	notify("Selected %d sector%s." % [out.size(), "" if out.size() == 1 else "s"], Severity.INFO)


static func _similar(a: DMSector, b: DMSector, kind: String) -> bool:
	var floors := is_equal_approx(a.floor_height, b.floor_height)
	var ceilings := is_equal_approx(a.ceiling_height, b.ceiling_height)
	match kind:
		"floor_height": return floors
		"ceiling_height": return ceilings
		"heights": return floors and ceilings
		"floor_material": return a.floor_material == b.floor_material
		"ceiling_material": return a.ceiling_material == b.ceiling_material
		"wall_material": return a.wall_material == b.wall_material
		"materials":
			return a.floor_material == b.floor_material and a.ceiling_material == b.ceiling_material \
				and a.wall_material == b.wall_material
	return false


# --- Texture tools ---------------------------------------------------------------

## The texture alignment of one surface: sector `si`'s floor, ceiling or
## walls (`wall`: just that wall).
func surface_uv(si: int, part: int, wall: DMTool.Wall = null) -> DMSector.UV:
	var s := _sectors()[si]
	var o := s.wall_override(wall.a, wall.b) if part == DMBuilder.Part.WALL and wall != null else {}
	return s.uv_values(part, o)


static func _apply_surface_uv(s: DMSector, part: int, wall: DMTool.Wall, uv: DMSector.UV) -> void:
	if part == DMBuilder.Part.WALL and wall != null:
		var edge := s.override_edge(wall.a, wall.b)
		s.set_wall_override(edge[0], edge[1], {"uv_offset": uv.offset, "uv_size": uv.size, "uv_rotation": uv.rotation})
	else:
		s.set_uv_values(part, uv.offset, uv.size, uv.rotation)


## Moves the texture on a surface by `delta` meters (x along its width, y
## along its height, in the texture's own directions): the floors or
## ceilings of `targets`, or the one wall `wall` of targets[0].
func nudge_uv(targets: Array[int], part: int, wall: DMTool.Wall, delta: Vector2) -> void:
	if not has_map() or targets.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in targets:
		var uv := surface_uv(i, part, wall)
		# The offset is added to the coordinates, so the texture moves the
		# other way.
		uv.offset -= delta
		_apply_surface_uv(_sectors()[i], part, wall, uv)
		if wall != null:
			break
	_commit("Move Texture", before, true)


## Remembers a surface's texture alignment for paste_uv().
func copy_uv(si: int, part: int, wall: DMTool.Wall = null) -> void:
	uv_clipboard = surface_uv(si, part, wall)
	notify("Copied the texture alignment.", Severity.INFO)


## Gives surfaces the copied alignment (see nudge_uv for the targets).
func paste_uv(targets: Array[int], part: int, wall: DMTool.Wall) -> void:
	if not has_map() or targets.is_empty():
		return
	if uv_clipboard == null:
		notify("Copy a texture alignment first (Ctrl+Shift+C over a surface).")
		return
	var before := map.data.duplicate_data()
	for i in targets:
		_apply_surface_uv(_sectors()[i], part, wall, uv_clipboard)
		if wall != null:
			break
	_commit("Paste Texture Alignment", before)


## Copy / paste alignment for the dock's surface choice on the selection.
func copy_selected_uv(part: int) -> void:
	if has_map() and not tool.selected.is_empty():
		copy_uv(tool.selected[0], part, tool.selected_wall if part == DMBuilder.Part.WALL else null)


func paste_selected_uv(part: int) -> void:
	if has_map() and not tool.selected.is_empty():
		paste_uv(tool.selected, part, tool.selected_wall if part == DMBuilder.Part.WALL else null)


## Fits the texture to the surface: one repeat exactly covering each
## selected floor or ceiling (its bounding box), or each wall (its length
## and height; with a single wall selected, just that one).
func fit_selected_uv(part: int) -> void:
	if not has_map() or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		var s := _sectors()[i]
		if part != DMBuilder.Part.WALL:
			var one: Array[int] = [i]
			var box := map.data.bounds_of(one)
			s.set_uv_values(part, -box.position, box.size.max(Vector2.ONE * DMGeo.SNAP), 0.0)
			continue
		var edges: Array[DMTool.Wall] = []
		if tool.selected_wall != null:
			edges.append(tool.selected_wall)
		else:
			for poly in s.polygons:
				for k in poly.size():
					edges.append(DMTool.Wall.new(i, poly[k], poly[(k + 1) % poly.size()]))
		for w in edges:
			var o := s.wall_override(w.a, w.b)
			var bottom := DMSector.setting_float(o, "bottom", s.floor_height)
			var top := DMSector.setting_float(o, "top", s.ceiling_height)
			var length := w.a.distance_to(w.b)
			if length < DMGeo.LINE_EPS:
				continue
			# Along the wall the coordinate is the position along a -> b; down
			# it, minus the height (see DMBuilder.uv_at).
			var along := (w.b - w.a) / length
			var uv := DMSector.UV.make(Vector2(-w.a.dot(along), top), Vector2(length, maxf(top - bottom, DMGeo.SNAP)), 0.0)
			_apply_surface_uv(s, part, w, uv)
	_commit("Fit Texture", before)


# --- Corners and curves ----------------------------------------------------------

## Adds a corner at `p` on the wall(s) through it.
func insert_corner(p: Vector2) -> void:
	if not has_map():
		return
	var before := map.data.duplicate_data()
	if not map.data.insert_vertex(p):
		notify("There's no wall there to split (or there's already a corner).")
		return
	_commit("Split Wall", before)


## Splits the selected wall in the middle.
func split_selected_wall() -> void:
	if not has_map() or tool.selected_wall == null:
		return
	var w := tool.selected_wall
	var before := map.data.duplicate_data()
	if not map.data.insert_vertex((w.a + w.b) * 0.5):
		notify("That wall is too short to split.")
		return
	tool.selected_wall = null
	_commit("Split Wall", before)


## Removes the corner at `p`: its two walls become one.
func remove_corner(p: Vector2) -> void:
	if not has_map():
		return
	var before := map.data.duplicate_data()
	var count := _sectors().size()
	if not map.data.remove_vertex(p):
		return
	if _sectors().size() != count:
		_refuse(before, "Can't remove that corner: a sector needs at least 3. Delete the sector instead.")
		return
	var why := map.data.validate()
	if not why.is_empty():
		_refuse(before, "Can't remove that corner: " + why + ".")
		return
	tool.selected_wall = null
	_commit("Remove Corner", before)


func curve_selected_wall() -> void:
	if not has_map() or tool.selected_wall == null:
		notify("Click a wall to select it, then Curve Wall.")
		return
	var w := tool.selected_wall
	var before := map.data.duplicate_data()
	var r := map.data.curve_edge(w.sector, w.a, w.b, curve_segments, curve_bulge)
	if not r.ok:
		_refuse(before, r.message)
		return
	var why := map.data.validate()
	if not why.is_empty():
		_refuse(before, "Can't curve that wall: " + why + ". Try a smaller bulge, or the other direction.")
		return
	tool.selected_wall = null
	_commit("Curve Wall", before)


# --- Stairs ----------------------------------------------------------------------

## Makes stairs from the selected sectors, in the order they were selected.
func make_stairs() -> void:
	if not has_map() or tool.selected.size() < 2:
		notify("Shift+click the steps in order (two or more sectors), then Make Stairs.")
		return
	var before := map.data.duplicate_data()
	map.data.make_stairs(tool.selected, stair_step, stair_ceilings)
	_commit("Make Stairs", before)


## Cuts the selected sector into stair_count steps climbing in stair_direction.
func split_into_steps() -> void:
	if not has_map() or tool.selected.size() != 1:
		notify("Select one sector to split into steps.")
		return
	var before := map.data.duplicate_data()
	var r := map.data.split_into_steps(tool.selected[0], stair_count, STAIR_DIRECTIONS[clampi(stair_direction, 0, 3)], stair_step, stair_ceilings)
	if not r.ok:
		_refuse(before, r.message)
		return
	var why := map.data.validate()
	if not why.is_empty():
		_refuse(before, "Can't split it into steps: " + why + ".")
		return
	tool.selected.assign(r.indices)
	tool.selected_wall = null
	_commit("Split into Steps", before)


# --- Settings and modes ----------------------------------------------------------

func set_drawing(on: bool, rectangle := false) -> void:
	if not has_map():
		return
	if on:
		tool.begin_draw(rectangle)
	else:
		tool.cancel_draw()


func set_grid_step(meters: float) -> void:
	grid_step = meters
	save_settings()
	on_tool_changed()


func shift_grid(direction: int) -> void:
	var i := clampi(DMUnits.step_index(grid_step) + direction, 0, DMUnits.GRID_STEPS.size() - 1)
	set_grid_step(DMUnits.GRID_STEPS[i])
	notify("Grid: " + DMUnits.format(grid_step, units), Severity.INFO)


func set_units(u: int) -> void:
	units = u as DMUnits.Units
	save_settings()
	on_tool_changed()


func set_default_height(part: int, meters: float) -> void:
	_set_height(defaults, part, meters)
	save_settings()
	on_tool_changed()


func set_default_ceiling(on: bool) -> void:
	defaults.has_ceiling = on
	save_settings()
	on_tool_changed()


func set_default_material(part: int, mat: Material) -> void:
	match part:
		DMBuilder.Part.FLOOR:
			defaults.floor_material = mat
		DMBuilder.Part.CEILING:
			defaults.ceiling_material = mat
		_:
			defaults.wall_material = mat
	if mat != null and mat.resource_path.is_empty():
		notify("This default material isn't saved as a file, so it will be forgotten when the editor restarts. Save it as a .tres to keep it.", Severity.INFO)
	save_settings()


func load_settings() -> void:
	units = _setting_int("units", DMUnits.Units.METERS) as DMUnits.Units
	grid_step = _setting_float("grid_step", 0.5)
	defaults.floor_height = _setting_float("default_floor", 0.0)
	defaults.ceiling_height = _setting_float("default_ceiling", 4.0)
	defaults.has_ceiling = _setting_bool("default_has_ceiling", true)
	wall_thickness = _setting_float("wall_thickness", 0.25)
	wall_side = _setting_int("thicken_side", 1)
	curve_segments = _setting_int("curve_segments", 8)
	curve_bulge = _setting_float("curve_bulge", 1.0)
	stair_step = _setting_float("stair_step", 0.25)
	stair_ceilings = _setting_bool("stair_ceilings", false)
	stair_count = _setting_int("stair_count", 4)
	stair_direction = _setting_int("stair_direction", 0)
	rotate_angle = _setting_float("rotate_angle", 45.0)
	length_anchor = clampi(_setting_int("length_anchor", LengthAnchor.KEEP_A), 0, 2) as LengthAnchor
	defaults.floor_material = _load_material(_setting_string("default_floor_mat"))
	defaults.ceiling_material = _load_material(_setting_string("default_ceiling_mat"))
	defaults.wall_material = _load_material(_setting_string("default_wall_mat"))


func _setting_float(key: String, fallback: float) -> float:
	var v: Variant = _get_setting(key, fallback)
	if v is float or v is int:
		var f: float = v
		return f
	return fallback


func _setting_int(key: String, fallback: int) -> int:
	var v: Variant = _get_setting(key, fallback)
	if v is float or v is int:
		var f: float = v
		return roundi(f)
	return fallback


func _setting_bool(key: String, fallback: bool) -> bool:
	var v: Variant = _get_setting(key, fallback)
	if v is bool:
		var b: bool = v
		return b
	return fallback


func _setting_string(key: String) -> String:
	var v: Variant = _get_setting(key, "")
	if v is String:
		var t: String = v
		return t
	return ""


func save_settings() -> void:
	_set_setting("units", units)
	_set_setting("grid_step", grid_step)
	_set_setting("default_floor", defaults.floor_height)
	_set_setting("default_ceiling", defaults.ceiling_height)
	_set_setting("default_has_ceiling", defaults.has_ceiling)
	_set_setting("wall_thickness", wall_thickness)
	_set_setting("thicken_side", wall_side)
	_set_setting("curve_segments", curve_segments)
	_set_setting("curve_bulge", curve_bulge)
	_set_setting("stair_step", stair_step)
	_set_setting("stair_ceilings", stair_ceilings)
	_set_setting("stair_count", stair_count)
	_set_setting("stair_direction", stair_direction)
	_set_setting("rotate_angle", rotate_angle)
	_set_setting("length_anchor", length_anchor)
	_set_setting("default_floor_mat", _material_path(defaults.floor_material))
	_set_setting("default_ceiling_mat", _material_path(defaults.ceiling_material))
	_set_setting("default_wall_mat", _material_path(defaults.wall_material))


static func _material_path(mat: Material) -> String:
	return mat.resource_path if mat != null else ""


static func _load_material(path: String) -> Material:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Material


# --- Helpers ---------------------------------------------------------------------

static func _height(s: DMSector, part: int) -> float:
	return s.floor_height if part == DMBuilder.Part.FLOOR else s.ceiling_height


## Sets a height, pushing the other one along so the floor never goes above the ceiling.
static func _set_height(s: DMSector, part: int, meters: float) -> void:
	if part == DMBuilder.Part.FLOOR:
		s.floor_height = meters
		s.ceiling_height = maxf(s.ceiling_height, meters)
	else:
		s.ceiling_height = meters
		s.floor_height = minf(s.floor_height, meters)


## Restores `before` after a refused edit and tells the user why.
func _refuse(before: DMMapData, message: String) -> void:
	map.data.copy_from(before)
	map.rebuild()
	notify(message)
	on_tool_changed()


## Records an edit already applied to map.data as one undo step.
func _commit(action: String, before: DMMapData, merge := false) -> void:
	_record_undo(action, before, map.data.duplicate_data(), merge)
	map.data.notify_changed()
	map.rebuild()
	on_tool_changed()


# --- Hooks (overridden by the plugin, and by tests) ------------------------------

## Starts editing map `m` (the plugin also selects its node).
func _focus_map(m: DMMap) -> void:
	set_map(m)


## Adds an applied edit to the undo history: undo restores `before`, redo
## `after` (both via DMMapData.copy_from).
func _record_undo(_action: String, _before: DMMapData, _after: DMMapData, _merge: bool) -> void:
	pass


## Shows a message to the user.
func notify(message: String, _severity := Severity.WARNING) -> void:
	print("GoDoomBuilder: ", message)


## Redraws the viewport overlay.
func update_overlays() -> void:
	pass


## Refreshes the dock, toolbar and grid after a change.
func _refresh_ui() -> void:
	pass


## Asks the user for a prefab file (to save to when `save`), then calls
## `on_pick` with its path.
func _pick_file(_save: bool, _on_pick: Callable) -> void:
	notify("Choosing a file needs the Godot editor.")


## Adds a new sector map to the open scene.
func new_map() -> void:
	notify("Open a scene in the editor to add a sector map.")


func _get_setting(_key: String, fallback: Variant) -> Variant:
	return fallback


func _set_setting(_key: String, _value: Variant) -> void:
	pass
