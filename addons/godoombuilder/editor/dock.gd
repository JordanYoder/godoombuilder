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
	_floor_mat = _picker(func(m: Resource) -> void: plugin.set_selected_material(DMBuilder.Part.FLOOR, m))
	_row(_sel_box, "Floor material", _floor_mat)
	_ceiling_mat = _picker(func(m: Resource) -> void: plugin.set_selected_material(DMBuilder.Part.CEILING, m))
	_row(_sel_box, "Ceiling material", _ceiling_mat)
	_wall_mat = _picker(func(m: Resource) -> void: plugin.set_selected_material(DMBuilder.Part.WALL, m))
	_row(_sel_box, "Wall material", _wall_mat)
	_delete = Button.new()
	_delete.text = "Delete Sector"
	_delete.tooltip_text = "Remove the selected sectors (Delete key). Their area becomes solid."
	_delete.pressed.connect(func() -> void: plugin.delete_selected())
	_sel_box.add_child(_delete)

	box.add_child(HSeparator.new())
	_header(box, "New sectors in empty space")
	_def_floor = _height_spin(func(v: float) -> void: plugin.set_default_height(DMBuilder.Part.FLOOR, v))
	_row(box, "Floor height", _def_floor)
	_def_ceiling = _height_spin(func(v: float) -> void: plugin.set_default_height(DMBuilder.Part.CEILING, v))
	_row(box, "Ceiling height", _def_ceiling)
	_def_floor_mat = _picker(func(m: Resource) -> void: plugin.set_default_material(DMBuilder.Part.FLOOR, m))
	_row(box, "Floor material", _def_floor_mat)
	_def_ceiling_mat = _picker(func(m: Resource) -> void: plugin.set_default_material(DMBuilder.Part.CEILING, m))
	_row(box, "Ceiling material", _def_ceiling_mat)
	_def_wall_mat = _picker(func(m: Resource) -> void: plugin.set_default_material(DMBuilder.Part.WALL, m))
	_row(box, "Wall material", _def_wall_mat)
	var note := Label.new()
	note.text = "A sector drawn inside another copies its heights and materials instead."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.6)
	box.add_child(note)

	box.add_child(HSeparator.new())
	_header(box, "Controls (with the map selected)")
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
		"Delete: delete selected sectors",
		"Esc: cancel drawing / clear selection",
		"Top-down map view: numpad 7, then numpad 5 for flat (orthographic)",
	])
	box.add_child(help)


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
	for spin in [_floor, _ceiling, _def_floor, _def_ceiling, _rect_w, _rect_d, _width, _depth]:
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
		_floor_mat.edited_resource = s.floor_material
		_ceiling_mat.edited_resource = s.ceiling_material
		_wall_mat.edited_resource = s.wall_material
		_delete.text = "Delete Sector" if sel.size() == 1 else "Delete %d Sectors" % sel.size()

	var d: DMSector = plugin.defaults
	_set_spin(_def_floor, DMUnits.to_display(d.floor_height, units))
	_set_spin(_def_ceiling, DMUnits.to_display(d.ceiling_height, units))
	_def_floor_mat.edited_resource = d.floor_material
	_def_ceiling_mat.edited_resource = d.ceiling_material
	_def_wall_mat.edited_resource = d.wall_material


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


static func _header(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_font("bold", "EditorFonts"):
		l.add_theme_font_override("font", theme.get_font("bold", "EditorFonts"))
	parent.add_child(l)
	return l
