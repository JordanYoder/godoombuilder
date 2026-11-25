@tool
extends EditorPlugin
## GoDoomBuilder: Doom-style sector mapping for Godot.


const SETTINGS := "godoombuilder"

var tool: DMTool
var dock_panel: DMDock
var map: DMMap
## Display units (DMUnits.Units).
var units := DMUnits.Units.METERS
## Grid snap size in meters.
var grid_step := 0.5
## Heights and materials for sectors drawn in empty space.
var defaults := DMSector.new()

var _dock: EditorDock
var _toolbar: DMToolbar
var _grid: DMGrid


func _enter_tree() -> void:
	tool = DMTool.new()
	tool.plugin = self
	_grid = DMGrid.new()
	_load_settings()

	dock_panel = DMDock.new()
	dock_panel.plugin = self
	_dock = EditorDock.new()
	_dock.name = "DMDock"
	_dock.title = "Sectors"
	_dock.layout_key = "godoombuilder"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_dock.dock_icon = preload("res://addons/godoombuilder/icons/map.svg")
	_dock.add_child(dock_panel)
	add_dock(_dock)

	_toolbar = DMToolbar.new()
	_toolbar.plugin = self
	_toolbar.visible = false
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)


func _exit_tree() -> void:
	_save_settings()
	_bind_map(null)
	if _grid != null:
		_grid.cleanup()
		_grid = null
	if _toolbar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
		_toolbar = null
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null


func _handles(object: Object) -> bool:
	return object is DMMap


func _edit(object: Object) -> void:
	_bind_map(object as DMMap)


func _make_visible(visible: bool) -> void:
	if not visible:
		_bind_map(null)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if map == null:
		return AFTER_GUI_INPUT_PASS
	return tool.handle_input(camera, event)


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if map != null:
		tool.draw_overlay(overlay)


func _bind_map(m: DMMap) -> void:
	if m == map:
		return
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
	if dock_panel != null:
		dock_panel.refresh()
	if _toolbar != null:
		_toolbar.refresh()
	update_overlays()


## Called by the tool whenever its state changes.
func on_tool_changed() -> void:
	if dock_panel != null:
		dock_panel.refresh()
	if _toolbar != null:
		_toolbar.visible = map != null
		_toolbar.refresh()
	_update_grid()
	update_overlays()


func _update_grid() -> void:
	if _grid == null:
		return
	if map == null or not map.is_inside_tree():
		_grid.update(null, false, 0.0, grid_step)
		return
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var world: World3D = vp.find_world_3d() if vp != null else map.get_world_3d()
	var y := (map.global_transform * Vector3(0, tool.grid_height(), 0)).y
	_grid.update(world, true, y, grid_step)


# --- Edits (each one is a single undo step) ------------------------------------

## Adds a sector from the drawn loop. Returns the data's add_loop result.
func commit_loop(points: PackedVector2Array) -> Dictionary:
	var before := map.data.duplicate_data()
	var result := map.data.add_loop(points, defaults)
	if not result.ok:
		map.data.copy_from(before)
		notify(result.message)
		return result
	_commit("Draw Sector", before)
	return result


func nudge_heights(targets: Array[int], part: int, delta: float) -> void:
	var before := map.data.duplicate_data()
	for i in targets:
		_set_height(map.data.sectors[i], part, _height(map.data.sectors[i], part) + delta)
	var what := "Floor" if part == DMBuilder.Part.FLOOR else "Ceiling"
	_commit(("Raise " if delta > 0.0 else "Lower ") + what, before, true)


func set_selected_height(part: int, meters: float) -> void:
	if map == null or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		_set_height(map.data.sectors[i], part, meters)
	_commit("Set Floor Height" if part == DMBuilder.Part.FLOOR else "Set Ceiling Height", before, true)


func set_selected_material(part: int, mat: Resource) -> void:
	if map == null or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		var s := map.data.sectors[i]
		match part:
			DMBuilder.Part.FLOOR:
				s.floor_material = mat as Material
			DMBuilder.Part.CEILING:
				s.ceiling_material = mat as Material
			_:
				s.wall_material = mat as Material
	_commit("Set Sector Material", before)


## Records an edit the tool already applied to map.data (e.g. a drag).
func commit_snapshot(action: String, before: DMMapData) -> void:
	_commit(action, before)


## Which point stays put when resizing: 0 center, then corners
## (-X -Z), (+X -Z), (-X +Z), (+X +Z).
var resize_anchor := 0


## Resizes the selected sectors to `meters` along axis 0 (X, width) or 1 (Z,
## depth). Neighbours sharing their corners stretch along.
func resize_selected(axis: int, meters: float) -> void:
	if map == null or tool.selected.is_empty() or meters <= 0.0:
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
		map.data.copy_from(before)
		map.rebuild()
		notify("Can't resize to that: " + why + ".")
		on_tool_changed()
		return
	_commit("Resize Sector", before, true)


## Joins the selected sectors into one (the first selected one's heights and
## materials win).
func join_selected() -> void:
	if map == null or tool.selected.size() < 2:
		notify("Shift+click two or more sectors to join them.")
		return
	var before := map.data.duplicate_data()
	var index := map.data.join_sectors(tool.selected)
	tool.selected = [index]
	_commit("Join Sectors", before)


## Wall thickness settings used by thicken_selected (meters; -1 inside,
## 0 centered, 1 outside).
var wall_thickness := 0.25
var wall_side := 1


## Gives each selected sector's walls a thickness (a solid band along its
## boundary).
func thicken_selected() -> void:
	if map == null or tool.selected.is_empty():
		return
	if not tool.selected_wall.is_empty():
		_thicken_wall()
		return
	var before := map.data.duplicate_data()
	var targets: Array = []
	for i in tool.selected:
		targets.append(map.data.sectors[i])
	var kept: Array[int] = []
	for t in targets:
		var i: int = map.data.sectors.find(t)
		if i < 0:
			continue
		var r := map.data.thicken_walls(i, wall_thickness, wall_side)
		if not r.ok:
			map.data.copy_from(before)
			map.rebuild()
			notify(r.message)
			on_tool_changed()
			return
	var why := map.data.validate()
	if not why.is_empty():
		map.data.copy_from(before)
		map.rebuild()
		notify("Can't thicken the walls: " + why + ".")
		on_tool_changed()
		return
	for t in targets:
		var i: int = map.data.sectors.find(t)
		if i >= 0:
			kept.append(i)
	tool.selected = kept
	_commit("Thicken Walls", before)


# --- Single walls --------------------------------------------------------------

## The selected wall's sector, or null.
func _wall_sector() -> DMSector:
	if map == null or tool.selected_wall.is_empty():
		return null
	var i := int(tool.selected_wall.sector)
	return map.data.sectors[i] if i < map.data.sectors.size() else null


func set_wall_hidden(hidden: bool) -> void:
	var s := _wall_sector()
	if s == null:
		return
	var before := map.data.duplicate_data()
	map.data.sectors[int(tool.selected_wall.sector)].set_wall_override(
		tool.selected_wall.a, tool.selected_wall.b, {"hidden": true if hidden else null})
	_commit("Hide Wall" if hidden else "Show Wall", before)


## Sets the selected wall's own bottom or top height (meters).
func set_wall_height(top: bool, meters: float) -> void:
	var s := _wall_sector()
	if s == null:
		return
	var before := map.data.duplicate_data()
	map.data.sectors[int(tool.selected_wall.sector)].set_wall_override(
		tool.selected_wall.a, tool.selected_wall.b, {("top" if top else "bottom"): meters})
	_commit("Set Wall Height", before, true)


## Back to the sector's heights, and shown.
func reset_wall() -> void:
	var s := _wall_sector()
	if s == null:
		return
	var before := map.data.duplicate_data()
	map.data.sectors[int(tool.selected_wall.sector)].set_wall_override(
		tool.selected_wall.a, tool.selected_wall.b, {"hidden": null, "top": null, "bottom": null, "thickness": null})
	map.data.sectors[int(tool.selected_wall.sector)].clear_outer_corners([tool.selected_wall.a, tool.selected_wall.b])
	_commit("Reset Wall", before)


func show_hidden_walls() -> void:
	if map == null or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		map.data.sectors[i].show_hidden_walls()
	_commit("Show Hidden Walls", before)


## Sets the selected sectors' outer wall thickness directly (0 = thin).
func set_selected_wall_thickness(meters: float) -> void:
	if map == null or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		map.data.sectors[i].wall_thickness = maxf(meters, 0.0)
		map.data.sectors[i].clear_outer_corners()
	_commit("Set Wall Thickness", before, true)


## Sets the selected wall's own thickness (0 = thin, null = the sector's).
func set_wall_thickness(meters) -> void:
	var s := _wall_sector()
	if s == null:
		return
	var before := map.data.duplicate_data()
	map.data.sectors[int(tool.selected_wall.sector)].set_wall_override(
		tool.selected_wall.a, tool.selected_wall.b, {"thickness": maxf(float(meters), 0.0) if meters != null else null})
	map.data.sectors[int(tool.selected_wall.sector)].clear_outer_corners([tool.selected_wall.a, tool.selected_wall.b])
	_commit("Set Wall Thickness", before, true)


func set_selected_floor(on: bool) -> void:
	if map == null or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		map.data.sectors[i].has_floor = on
	_commit("Floor On" if on else "Remove Floor", before)


## Removes points that don't change the selected sectors' shapes.
func simplify_selected() -> void:
	if map == null or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	var removed := 0
	for i in tool.selected:
		removed += map.data.simplify_sector(i)
	if removed == 0:
		notify("Nothing to simplify: every point changes the shape.", EditorToaster.SEVERITY_INFO)
		return
	var why := map.data.validate()
	if not why.is_empty():
		map.data.copy_from(before)
		map.rebuild()
		notify("Can't simplify: " + why + ".")
		on_tool_changed()
		return
	_commit("Simplify Sector", before)
	notify("Removed %d point%s." % [removed, "" if removed == 1 else "s"], EditorToaster.SEVERITY_INFO)


func _thicken_wall() -> void:
	var w: Dictionary = tool.selected_wall
	var before := map.data.duplicate_data()
	var r := map.data.thicken_edge(int(w.sector), w.a, w.b, wall_thickness, wall_side)
	var why: String = r.message if not r.ok else map.data.validate()
	if not why.is_empty():
		map.data.copy_from(before)
		map.rebuild()
		notify(why if not r.ok else "Can't thicken the wall: " + why + ".")
		on_tool_changed()
		return
	tool.selected = [int(r.index)]
	# Thickening outward leaves the wall where it is; otherwise it moved.
	if wall_side > 0:
		tool.selected_wall = {"sector": int(r.index), "a": w.a, "b": w.b}
	else:
		tool.selected_wall = {}
	_commit("Thicken Wall", before)


func set_selected_ceiling(on: bool) -> void:
	if map == null or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	for i in tool.selected:
		map.data.sectors[i].has_ceiling = on
	_commit("Ceiling On" if on else "Open to Sky", before)


func set_default_ceiling(on: bool) -> void:
	defaults.has_ceiling = on
	_save_settings()
	on_tool_changed()


func delete_selected() -> void:
	if map == null or tool.selected.is_empty():
		return
	var before := map.data.duplicate_data()
	map.data.delete_sectors(tool.selected)
	tool.selected.clear()
	_commit("Delete Sectors", before)


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


## Records an edit already applied to map.data as one undo step.
func _commit(action: String, before: DMMapData, merge := false) -> void:
	var after := map.data.duplicate_data()
	var ur := get_undo_redo()
	ur.create_action(action, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE, map)
	ur.add_do_method(map.data, "copy_from", after)
	ur.add_undo_method(map.data, "copy_from", before)
	ur.commit_action(false)
	map.data.notify_changed()
	map.rebuild()
	on_tool_changed()


# --- Dock actions --------------------------------------------------------------

func new_map() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		notify("Open or create a 3D scene first.")
		return
	var m := DMMap.new()
	m.name = "SectorMap"
	m.data = DMMapData.new()
	var ur := get_undo_redo()
	ur.create_action("Add Sector Map", UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(root, "add_child", m, true)
	ur.add_do_method(m, "set_owner", root)
	ur.add_do_reference(m)
	ur.add_undo_method(root, "remove_child", m)
	ur.commit_action()
	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(m)


func set_drawing(on: bool, rectangle := false) -> void:
	if map == null:
		return
	if on:
		tool.begin_draw(rectangle)
	else:
		tool.cancel_draw()


func set_grid_step(meters: float) -> void:
	grid_step = meters
	_save_settings()
	on_tool_changed()


func shift_grid(direction: int) -> void:
	var i := clampi(DMUnits.step_index(grid_step) + direction, 0, DMUnits.GRID_STEPS.size() - 1)
	set_grid_step(DMUnits.GRID_STEPS[i])
	notify("Grid: " + DMUnits.format(grid_step, units), EditorToaster.SEVERITY_INFO)


func set_units(u: int) -> void:
	units = u
	_save_settings()
	on_tool_changed()


func set_default_height(part: int, meters: float) -> void:
	_set_height(defaults, part, meters)
	_save_settings()
	on_tool_changed()


func set_default_material(part: int, mat: Resource) -> void:
	match part:
		DMBuilder.Part.FLOOR:
			defaults.floor_material = mat as Material
		DMBuilder.Part.CEILING:
			defaults.ceiling_material = mat as Material
		_:
			defaults.wall_material = mat as Material
	if mat != null and mat.resource_path.is_empty():
		notify("This default material isn't saved as a file, so it will be forgotten when the editor restarts. Save it as a .tres to keep it.", EditorToaster.SEVERITY_INFO)
	_save_settings()


func notify(message: String, severity := EditorToaster.SEVERITY_WARNING) -> void:
	var toaster := EditorInterface.get_editor_toaster()
	if toaster != null:
		toaster.push_toast(message, severity)
	else:
		print("GoDoomBuilder: ", message)


# --- Settings (stored per project, outside the scene) ---------------------------

func _load_settings() -> void:
	var es := EditorInterface.get_editor_settings()
	units = int(es.get_project_metadata(SETTINGS, "units", DMUnits.Units.METERS))
	grid_step = float(es.get_project_metadata(SETTINGS, "grid_step", 0.5))
	defaults.floor_height = float(es.get_project_metadata(SETTINGS, "default_floor", 0.0))
	defaults.ceiling_height = float(es.get_project_metadata(SETTINGS, "default_ceiling", 4.0))
	defaults.has_ceiling = bool(es.get_project_metadata(SETTINGS, "default_has_ceiling", true))
	wall_thickness = float(es.get_project_metadata(SETTINGS, "wall_thickness", 0.25))
	wall_side = int(es.get_project_metadata(SETTINGS, "thicken_side", 1))
	defaults.floor_material = _load_material(es.get_project_metadata(SETTINGS, "default_floor_mat", ""))
	defaults.ceiling_material = _load_material(es.get_project_metadata(SETTINGS, "default_ceiling_mat", ""))
	defaults.wall_material = _load_material(es.get_project_metadata(SETTINGS, "default_wall_mat", ""))


func _save_settings() -> void:
	var es := EditorInterface.get_editor_settings()
	es.set_project_metadata(SETTINGS, "units", units)
	es.set_project_metadata(SETTINGS, "grid_step", grid_step)
	es.set_project_metadata(SETTINGS, "default_floor", defaults.floor_height)
	es.set_project_metadata(SETTINGS, "default_ceiling", defaults.ceiling_height)
	es.set_project_metadata(SETTINGS, "default_has_ceiling", defaults.has_ceiling)
	es.set_project_metadata(SETTINGS, "wall_thickness", wall_thickness)
	es.set_project_metadata(SETTINGS, "thicken_side", wall_side)
	es.set_project_metadata(SETTINGS, "default_floor_mat", _material_path(defaults.floor_material))
	es.set_project_metadata(SETTINGS, "default_ceiling_mat", _material_path(defaults.ceiling_material))
	es.set_project_metadata(SETTINGS, "default_wall_mat", _material_path(defaults.wall_material))


static func _material_path(mat: Material) -> String:
	return mat.resource_path if mat != null else ""


static func _load_material(path) -> Material:
	var p := str(path)
	if p.is_empty() or not ResourceLoader.exists(p):
		return null
	return load(p) as Material
