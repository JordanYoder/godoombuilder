@tool
class_name DMDock
extends ScrollContainer
## The Sectors dock: create a map, draw sectors, and edit the selected ones.


## The GoDoomBuilder EditorPlugin (untyped: it calls the plugin's own methods).
var plugin

var _status: Label
var _new_map: Button
var _draw: Button
var _rect: Button
var _rect_box: VBoxContainer
var _rect_w: SpinBox
var _rect_d: SpinBox
var _grid: OptionButton
var _units: OptionButton
var _sel_label: Label
var _sel_box: VBoxContainer
var _floor: SpinBox
var _width: SpinBox
var _depth: SpinBox
var _anchor: OptionButton
var _ceiling: SpinBox
var _has_ceiling: CheckBox
var _has_floor: CheckBox
var _sector_thick: SpinBox
var _wall_thick: SpinBox
var _hidden_walls: Button
var _wall_label: Label
var _wall_box: VBoxContainer
var _wall_hidden: CheckBox
var _wall_bottom: SpinBox
var _wall_top: SpinBox
var _wall_note: Label
var _wall_reset: Button
var _join: Button
var _simplify: Button
var _thick: SpinBox
var _thick_side: OptionButton
var _thicken: Button
var _def_has_ceiling: CheckBox
var _floor_mat: EditorResourcePicker
var _ceiling_mat: EditorResourcePicker
var _wall_mat: EditorResourcePicker
var _delete: Button
var _def_floor: SpinBox
var _def_ceiling: SpinBox
var _def_floor_mat: EditorResourcePicker
var _def_ceiling_mat: EditorResourcePicker
var _def_wall_mat: EditorResourcePicker
var _built := false


func _init() -> void:
	name = "Sectors"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size = Vector2(200, 0)


func _ready() -> void:
	_build()
	refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_new_map = Button.new()
	_new_map.text = "New Sector Map"
	_new_map.tooltip_text = "Add a Sector Map node to the open scene and select it."
	_new_map.pressed.connect(func() -> void: plugin.new_map())
	box.add_child(_new_map)

	_draw = Button.new()
	_draw.text = "Draw Sector  (D)"
	_draw.toggle_mode = true
	_draw.tooltip_text = "Click points on the grid to outline a floor area. Click the first point (or press Enter) to finish."
	_draw.toggled.connect(func(on: bool) -> void: plugin.set_drawing(on, false))
	box.add_child(_draw)
	_rect = Button.new()
	_rect.text = "Draw Rectangle  (B)"
	_rect.toggle_mode = true
	_rect.tooltip_text = "Click one corner, then the opposite corner. Or type the width, press Tab, type the depth, and press Enter."
	_rect.toggled.connect(func(on: bool) -> void: plugin.set_drawing(on, true))
	box.add_child(_rect)
	_rect_box = VBoxContainer.new()
	box.add_child(_rect_box)
	_rect_w = _height_spin(func(v: float) -> void: plugin.tool.set_rect_size(0, v))
	_rect_w.min_value = 0.0
	_rect_w.allow_lesser = false
	_rect_w.tooltip_text = "Exact width (X). 0 = follow the mouse."
	_row(_rect_box, "Width", _rect_w)
	_rect_d = _height_spin(func(v: float) -> void: plugin.tool.set_rect_size(1, v))
	_rect_d.min_value = 0.0
	_rect_d.allow_lesser = false
	_rect_d.tooltip_text = "Exact depth (Z). 0 = follow the mouse."
	_row(_rect_box, "Depth", _rect_d)
	var rect_note := Label.new()
	rect_note.text = "0 = follow the mouse. You can also type sizes in the viewport (Tab switches)."
	rect_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rect_note.modulate = Color(1, 1, 1, 0.6)
	_rect_box.add_child(rect_note)

	_grid = OptionButton.new()
	_grid.tooltip_text = "Grid snap size. Shortcut: [ and ] in the viewport."
	_grid.item_selected.connect(func(i: int) -> void: plugin.set_grid_step(DMUnits.GRID_STEPS[i]))
	_row(box, "Grid", _grid)
	_units = OptionButton.new()
	_units.add_item("Meters")
	_units.add_item("Doom units (32 per m)")
	_units.tooltip_text = "How sizes are shown and typed. Maps are always stored in meters."
	_units.item_selected.connect(func(i: int) -> void: plugin.set_units(i))
	_row(box, "Units", _units)

	box.add_child(HSeparator.new())
	_sel_label = _header(box, "No sector selected")
	_sel_box = VBoxContainer.new()
	box.add_child(_sel_box)
	_width = _height_spin(func(v: float) -> void: plugin.resize_selected(0, v))
	_width.min_value = 0.001
	_width.allow_lesser = false
	_width.tooltip_text = "Width (X) of the selected area. Corners shared with neighbours move too."
	_row(_sel_box, "Width", _width)
	_depth = _height_spin(func(v: float) -> void: plugin.resize_selected(1, v))
	_depth.min_value = 0.001
	_depth.allow_lesser = false
	_depth.tooltip_text = "Depth (Z) of the selected area. Corners shared with neighbours move too."
	_row(_sel_box, "Depth", _depth)
	_anchor = OptionButton.new()
	for label in ["Center", "-X / -Z corner", "+X / -Z corner", "-X / +Z corner", "+X / +Z corner"]:
		_anchor.add_item(label)
	_anchor.tooltip_text = "Which point stays in place when you change Width or Depth."
	_anchor.item_selected.connect(func(i: int) -> void: plugin.resize_anchor = i)
	_row(_sel_box, "Keep fixed", _anchor)
	_floor = _height_spin(func(v: float) -> void: plugin.set_selected_height(DMBuilder.Part.FLOOR, v))
	_row(_sel_box, "Floor height", _floor)
	_ceiling = _height_spin(func(v: float) -> void: plugin.set_selected_height(DMBuilder.Part.CEILING, v))
	_row(_sel_box, "Ceiling height", _ceiling)
	_has_ceiling = CheckBox.new()
	_has_ceiling.text = "Has ceiling"
	_has_ceiling.tooltip_text = "Off: open to the sky. Walls still rise to the ceiling height; no upper walls between two open sectors."
	_has_ceiling.toggled.connect(func(on: bool) -> void: plugin.set_selected_ceiling(on))
	_sel_box.add_child(_has_ceiling)
	_has_floor = CheckBox.new()
	_has_floor.text = "Has floor"
	_has_floor.tooltip_text = "Off: no floor (a hole). Walls still start at the floor height."
	_has_floor.toggled.connect(func(on: bool) -> void: plugin.set_selected_floor(on))
	_sel_box.add_child(_has_floor)
	_sector_thick = _height_spin(func(v: float) -> void: plugin.set_selected_wall_thickness(v))
	_sector_thick.min_value = 0.0
	_sector_thick.allow_lesser = false
	_sector_thick.tooltip_text = "How thick this room's outer walls are, built outward as solid blocks (the room keeps its size). 0 = thin."
	_row(_sel_box, "Wall thickness", _sector_thick)
	_hidden_walls = Button.new()
	_hidden_walls.tooltip_text = "Bring back walls that were hidden (shown as dashed outlines)."
	_hidden_walls.pressed.connect(func() -> void: plugin.show_hidden_walls())
	_sel_box.add_child(_hidden_walls)

	_wall_label = _header(_sel_box, "Selected wall")
	_wall_box = VBoxContainer.new()
	_sel_box.add_child(_wall_box)
	_wall_hidden = CheckBox.new()
	_wall_hidden.text = "Hidden (opening)"
	_wall_hidden.tooltip_text = "Remove just this wall: no surface and no collision. Delete key does the same."
	_wall_hidden.toggled.connect(func(on: bool) -> void: plugin.set_wall_hidden(on))
	_wall_box.add_child(_wall_hidden)
	_wall_bottom = _height_spin(func(v: float) -> void: plugin.set_wall_height(false, v))
	_wall_bottom.tooltip_text = "This wall's own bottom height. The room's other walls don't change."
	_row(_wall_box, "Wall bottom", _wall_bottom)
	_wall_top = _height_spin(func(v: float) -> void: plugin.set_wall_height(true, v))
	_wall_top.tooltip_text = "This wall's own top height, e.g. lower it for a half wall. The room's other walls don't change."
	_row(_wall_box, "Wall top", _wall_top)
	_wall_thick = _height_spin(func(v: float) -> void: plugin.set_wall_thickness(v))
	_wall_thick.min_value = 0.0
	_wall_thick.allow_lesser = false
	_wall_thick.tooltip_text = "This wall's own thickness, built outward as a solid block. 0 = thin. Reset Wall goes back to the room's thickness."
	_row(_wall_box, "Thickness", _wall_thick)
	_wall_note = Label.new()
	_wall_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wall_note.modulate = Color(1, 1, 1, 0.6)
	_wall_note.text = "This wall is between two sectors: its height comes from the neighbouring floor or ceiling. It can be hidden but not resized, and Thicken takes the space from the neighbouring room."
	_wall_box.add_child(_wall_note)
	_wall_reset = Button.new()
	_wall_reset.text = "Reset Wall"
	_wall_reset.tooltip_text = "Back to the sector's heights, and shown."
	_wall_reset.pressed.connect(func() -> void: plugin.reset_wall())
	_wall_box.add_child(_wall_reset)
	_floor_mat = _picker(func(m: Resource) -> void: plugin.set_selected_material(DMBuilder.Part.FLOOR, m))
	_row(_sel_box, "Floor material", _floor_mat)
	_ceiling_mat = _picker(func(m: Resource) -> void: plugin.set_selected_material(DMBuilder.Part.CEILING, m))
	_row(_sel_box, "Ceiling material", _ceiling_mat)
	_wall_mat = _picker(func(m: Resource) -> void: plugin.set_selected_material(DMBuilder.Part.WALL, m))
	_row(_sel_box, "Wall material", _wall_mat)
	_join = Button.new()
	_join.text = "Join Sectors  (J)"
	_join.tooltip_text = "Make the selected sectors one sector, with the first-selected one's heights and materials. Walls between them disappear."
	_join.pressed.connect(func() -> void: plugin.join_selected())
	_sel_box.add_child(_join)
	_simplify = Button.new()
	_simplify.text = "Simplify Sector"
	_simplify.tooltip_text = "Remove points that don't change the shape: extra points along straight walls and seams inside the sector."
	_simplify.pressed.connect(func() -> void: plugin.simplify_selected())
	_sel_box.add_child(_simplify)
	_thick = _height_spin(func(v: float) -> void:
		plugin.wall_thickness = v
		plugin._save_settings())
	_thick.min_value = 0.001
	_thick.allow_lesser = false
	_thick.tooltip_text = "How thick the walls become."
	_row(_sel_box, "Thicken by", _thick)
	_thick_side = OptionButton.new()
	_thick_side.add_item("Inward (room shrinks)", 0)
	_thick_side.add_item("Centered", 1)
	_thick_side.add_item("Outward (room keeps its size)", 2)
	_thick_side.tooltip_text = "Where the thickness goes: into this room, half each way, or into the space around it."
	_thick_side.item_selected.connect(func(i: int) -> void:
		plugin.wall_side = i - 1
		plugin._save_settings())
	_row(_sel_box, "Thicken toward", _thick_side)
	_thicken = Button.new()
	_thicken.text = "Thicken Walls"
	_thicken.tooltip_text = "Turn the space along the selected rooms' walls into solid wall. Draw a sector across it to cut a doorway."
	_thicken.pressed.connect(func() -> void: plugin.thicken_selected())
	_sel_box.add_child(_thicken)
	_delete = Button.new()
	_delete.text = "Delete Sector"
	_delete.tooltip_text = "Remove the selected sectors (Delete key). Their area becomes solid."
	_delete.pressed.connect(func() -> void: plugin.delete_selected())
	_sel_box.add_child(_delete)

	var defs := _section(box, "New sectors in empty space", true)
	_def_floor = _height_spin(func(v: float) -> void: plugin.set_default_height(DMBuilder.Part.FLOOR, v))
	_row(defs, "Floor height", _def_floor)
	_def_ceiling = _height_spin(func(v: float) -> void: plugin.set_default_height(DMBuilder.Part.CEILING, v))
	_row(defs, "Ceiling height", _def_ceiling)
	_def_has_ceiling = CheckBox.new()
	_def_has_ceiling.text = "Has ceiling"
	_def_has_ceiling.toggled.connect(func(on: bool) -> void: plugin.set_default_ceiling(on))
	defs.add_child(_def_has_ceiling)
	_def_floor_mat = _picker(func(m: Resource) -> void: plugin.set_default_material(DMBuilder.Part.FLOOR, m))
	_row(defs, "Floor material", _def_floor_mat)
	_def_ceiling_mat = _picker(func(m: Resource) -> void: plugin.set_default_material(DMBuilder.Part.CEILING, m))
	_row(defs, "Ceiling material", _def_ceiling_mat)
	_def_wall_mat = _picker(func(m: Resource) -> void: plugin.set_default_material(DMBuilder.Part.WALL, m))
	_row(defs, "Wall material", _def_wall_mat)
	var note := Label.new()
	note.text = "A sector drawn inside another copies its heights and materials instead."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.6)
	defs.add_child(note)

	var controls := _section(box, "Controls (with the map selected)", true)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.8)
	help.text = "\n".join([
		"D: draw a sector point by point (type a length + Enter for an exact side)",
		"B: draw a rectangle (type width, Tab, depth, Enter for an exact size)",
		"Click: select a sector (Shift+click adds)",
		"Drag a selected sector's corner or wall to reshape it (neighbours follow); Esc while dragging cancels",
		"Width / Depth in this panel resize the selection exactly",
		"Page Up / Page Down or Alt+wheel over a floor or ceiling: raise / lower it one grid step (all selected sectors if it's selected)",
		"[ and ]: smaller / larger grid",
		"J: join the selected sectors into one",
		"Thicken Walls (in this panel): give the selected rooms solid walls; draw a sector across one to cut a doorway",
		"Click a wall: select just that wall (set its own height, or Delete to hide it as an opening)",
		"Delete: hide the selected wall, or delete the selected sectors",
		"Esc: cancel drawing / clear selection",
		"Top-down map view: numpad 7, then numpad 5 for flat (orthographic)",
	])
	controls.add_child(help)


func refresh() -> void:
	if not _built or plugin == null:
		return
	var map: DMMap = plugin.map
	var units: int = plugin.units
	var has_map := map != null and map.data != null
	_status.text = ("Editing: %s  (%d sectors)" % [map.name, map.data.sectors.size()]) if has_map \
		else "Select a Sector Map node, or create one:"
	_new_map.visible = not has_map
	_draw.disabled = not has_map
	_draw.set_pressed_no_signal(has_map and plugin.tool.mode == DMTool.Mode.DRAW)
	_rect.disabled = not has_map
	_rect.set_pressed_no_signal(has_map and plugin.tool.mode == DMTool.Mode.RECT)
	_rect_box.visible = has_map and plugin.tool.mode == DMTool.Mode.RECT
	if _rect_box.visible:
		var rs: Vector2 = plugin.tool.rect_size
		_set_spin(_rect_w, DMUnits.to_display(maxf(rs.x, 0.0), units))
		_set_spin(_rect_d, DMUnits.to_display(maxf(rs.y, 0.0), units))

	_grid.clear()
	for step in DMUnits.GRID_STEPS:
		_grid.add_item(DMUnits.format(step, units))
	_grid.select(DMUnits.step_index(plugin.grid_step))
	_units.select(units)

	var arrow := DMUnits.to_display(plugin.grid_step, units)
	for spin in [_floor, _ceiling, _def_floor, _def_ceiling, _rect_w, _rect_d, _width, _depth, _thick, _wall_bottom, _wall_top, _sector_thick, _wall_thick]:
		(spin as SpinBox).suffix = DMUnits.suffix(units)
		(spin as SpinBox).custom_arrow_step = arrow

	var sel: Array[int] = plugin.tool.selected if has_map else ([] as Array[int])
	_sel_box.visible = not sel.is_empty()
	if sel.is_empty():
		_sel_label.text = "No sector selected"
	else:
		_sel_label.text = "Selected: %d sector%s" % [sel.size(), "" if sel.size() == 1 else "s"]
		var s: DMSector = map.data.sectors[sel[0]]
		var box: Rect2 = map.data.bounds_of(sel)
		_set_spin(_width, DMUnits.to_display(box.size.x, units))
		_set_spin(_depth, DMUnits.to_display(box.size.y, units))
		_anchor.select(plugin.resize_anchor)
		_set_spin(_floor, DMUnits.to_display(s.floor_height, units))
		_set_spin(_ceiling, DMUnits.to_display(s.ceiling_height, units))
		_has_ceiling.set_pressed_no_signal(s.has_ceiling)
		_has_floor.set_pressed_no_signal(s.has_floor)
		_set_spin(_sector_thick, DMUnits.to_display(s.wall_thickness, units))
		var hidden := 0
		for i in sel:
			hidden += map.data.sectors[i].hidden_wall_count()
		_hidden_walls.visible = hidden > 0
		_hidden_walls.text = "Show %d Hidden Wall%s" % [hidden, "" if hidden == 1 else "s"]
		var w: Dictionary = plugin.tool.selected_wall
		_wall_label.visible = not w.is_empty()
		_wall_box.visible = not w.is_empty()
		if not w.is_empty():
			var o := s.wall_override(w.a, w.b)
			var outer := _is_outer_wall(map, w)
			_wall_hidden.set_pressed_no_signal(o.get("hidden", false))
			_wall_bottom.get_parent().visible = outer
			_wall_top.get_parent().visible = outer
			_wall_thick.get_parent().visible = outer
			_set_spin(_wall_thick, DMUnits.to_display(o.get("thickness", s.wall_thickness), units))
			_wall_note.visible = not outer
			_set_spin(_wall_bottom, DMUnits.to_display(o.get("bottom", s.floor_height), units))
			_set_spin(_wall_top, DMUnits.to_display(o.get("top", s.ceiling_height), units))
		_ceiling_mat.get_parent().visible = s.has_ceiling
		_join.visible = sel.size() >= 2
		_set_spin(_thick, DMUnits.to_display(plugin.wall_thickness, units))
		_thick_side.select(int(plugin.wall_side) + 1)
		_thicken.text = "Thicken This Wall" if not plugin.tool.selected_wall.is_empty() else "Thicken Walls"
		_floor_mat.edited_resource = s.floor_material
		_ceiling_mat.edited_resource = s.ceiling_material
		_wall_mat.edited_resource = s.wall_material
		_delete.text = "Delete Sector" if sel.size() == 1 else "Delete %d Sectors" % sel.size()

	var d: DMSector = plugin.defaults
	_set_spin(_def_floor, DMUnits.to_display(d.floor_height, units))
	_set_spin(_def_ceiling, DMUnits.to_display(d.ceiling_height, units))
	_def_has_ceiling.set_pressed_no_signal(d.has_ceiling)
	_def_floor_mat.edited_resource = d.floor_material
	_def_ceiling_mat.edited_resource = d.ceiling_material
	_def_wall_mat.edited_resource = d.wall_material


## True when the selected wall faces solid space (not another sector).
static func _is_outer_wall(map: DMMap, w: Dictionary) -> bool:
	var a: Vector2 = w.a
	var b: Vector2 = w.b
	var mid := (a + b) * 0.5
	var out := Vector2(b.y - a.y, a.x - b.x).normalized() * 0.01
	return map.data.sector_at(mid + out) < 0


static func _set_spin(spin: SpinBox, v: float) -> void:
	if spin.get_line_edit().has_focus():
		return
	if not is_equal_approx(spin.value, v):
		spin.set_value_no_signal(v)


func _height_spin(on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -100000.0
	spin.max_value = 100000.0
	spin.step = 0.001
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.select_all_on_focus = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float) -> void:
		on_change.call(DMUnits.from_display(v, plugin.units)))
	return spin


func _picker(on_change: Callable) -> EditorResourcePicker:
	var picker := EditorResourcePicker.new()
	picker.base_type = "Material"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.resource_changed.connect(func(r: Resource) -> void: on_change.call(r))
	return picker


static func _row(parent: Control, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 96
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


## A collapsible section; returns the box to put its contents in.
static func _section(parent: Control, title: String, folded: bool) -> VBoxContainer:
	var fold := FoldableContainer.new()
	fold.title = title
	fold.folded = folded
	parent.add_child(fold)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	fold.add_child(inner)
	return inner


static func _header(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_font("bold", "EditorFonts"):
		l.add_theme_font_override("font", theme.get_font("bold", "EditorFonts"))
	parent.add_child(l)
	return l
