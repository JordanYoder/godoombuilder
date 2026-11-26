@tool
class_name DMDock
extends ScrollContainer
## The Sectors dock: create a map, draw sectors, and edit the selected ones.


## What the buttons edit (the GoDoomBuilder editor).
var editor: DMEditor

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
var _paste: Button
var _paste_prefab: Button
var _similar: OptionButton
var _rotate_angle: SpinBox
var _uv_part: OptionButton
var _uv_offset_x: SpinBox
var _uv_offset_y: SpinBox
var _uv_size_x: SpinBox
var _uv_size_y: SpinBox
var _uv_rotation: SpinBox
var _uv_note: Label
var _split_wall: Button
var _curve_segments: SpinBox
var _curve_bulge: SpinBox
var _curve: Button
var _stairs_box: VBoxContainer
var _stair_step: SpinBox
var _stair_ceilings: CheckBox
var _make_stairs: Button
var _stair_count: SpinBox
var _stair_dir: OptionButton
var _split_steps: Button
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
	_new_map.pressed.connect(func() -> void: editor.new_map())
	box.add_child(_new_map)

	_draw = Button.new()
	_draw.text = "Draw Polygon  (D)"
	_draw.toggle_mode = true
	_draw.tooltip_text = "Click points on the grid to outline a floor area. Click the first point (or press Enter) to finish."
	_draw.toggled.connect(func(on: bool) -> void: editor.set_drawing(on, false))
	box.add_child(_draw)
	_rect = Button.new()
	_rect.text = "Draw Rectangle  (B)"
	_rect.toggle_mode = true
	_rect.tooltip_text = "Click one corner, then the opposite corner. Or type the width, press Tab, type the depth, and press Enter."
	_rect.toggled.connect(func(on: bool) -> void: editor.set_drawing(on, true))
	box.add_child(_rect)
	_rect_box = VBoxContainer.new()
	box.add_child(_rect_box)
	_rect_w = _height_spin(func(v: float) -> void: editor.tool.set_rect_size(0, v))
	_rect_w.min_value = 0.0
	_rect_w.allow_lesser = false
	_rect_w.tooltip_text = "Exact width (X). 0 = follow the mouse."
	_row(_rect_box, "Width", _rect_w)
	_rect_d = _height_spin(func(v: float) -> void: editor.tool.set_rect_size(1, v))
	_rect_d.min_value = 0.0
	_rect_d.allow_lesser = false
	_rect_d.tooltip_text = "Exact depth (Z). 0 = follow the mouse."
	_row(_rect_box, "Depth", _rect_d)
	var rect_note := Label.new()
	rect_note.text = "0 = follow the mouse. You can also type sizes in the viewport (Tab switches)."
	rect_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rect_note.modulate = Color(1, 1, 1, 0.6)
	_rect_box.add_child(rect_note)

	_paste = Button.new()
	_paste.text = "Paste  (Ctrl+V)"
	_paste.tooltip_text = "Place a copy of the copied sectors (Ctrl+C copies the selection). R rotates and M mirrors while placing; it cuts what's under it, like drawing."
	_paste.pressed.connect(func() -> void: editor.begin_paste())
	box.add_child(_paste)
	_paste_prefab = Button.new()
	_paste_prefab.text = "Paste Prefab…"
	_paste_prefab.tooltip_text = "Place a prefab: sectors saved with Save as Prefab (a .tres file), into this or any other map."
	_paste_prefab.pressed.connect(func() -> void: editor.ask_load_prefab())
	box.add_child(_paste_prefab)

	_grid = OptionButton.new()
	_grid.tooltip_text = "Grid snap size. Shortcut: [ and ] in the viewport."
	_grid.item_selected.connect(func(i: int) -> void: editor.set_grid_step(DMUnits.GRID_STEPS[i]))
	_row(box, "Grid", _grid)
	_units = OptionButton.new()
	_units.add_item("Meters")
	_units.add_item("Doom units (32 per m)")
	_units.tooltip_text = "How sizes are shown and typed. Maps are always stored in meters."
	_units.item_selected.connect(func(i: int) -> void: editor.set_units(i))
	_row(box, "Units", _units)

	box.add_child(HSeparator.new())
	_sel_label = _header(box, "No sector selected")
	_sel_box = VBoxContainer.new()
	box.add_child(_sel_box)
	_width = _height_spin(func(v: float) -> void: editor.resize_selected(0, v))
	_width.min_value = 0.001
	_width.allow_lesser = false
	_width.tooltip_text = "Width (X) of the selected area. Corners shared with neighbours move too."
	_row(_sel_box, "Width", _width)
	_depth = _height_spin(func(v: float) -> void: editor.resize_selected(1, v))
	_depth.min_value = 0.001
	_depth.allow_lesser = false
	_depth.tooltip_text = "Depth (Z) of the selected area. Corners shared with neighbours move too."
	_row(_sel_box, "Depth", _depth)
	_anchor = OptionButton.new()
	for label: String in ["Center", "-X / -Z corner", "+X / -Z corner", "-X / +Z corner", "+X / +Z corner"]:
		_anchor.add_item(label)
	_anchor.tooltip_text = "Which point stays in place when you change Width or Depth."
	_anchor.item_selected.connect(func(i: int) -> void: editor.resize_anchor = i)
	_row(_sel_box, "Keep fixed", _anchor)
	var similar_row := HBoxContainer.new()
	_similar = OptionButton.new()
	for label: String in ["Floor height", "Ceiling height", "Both heights", "Floor material", "Ceiling material", "Wall material", "All materials"]:
		_similar.add_item(label)
	_similar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_similar.tooltip_text = "What Select Similar compares with the first selected sector."
	similar_row.add_child(_similar)
	var similar := Button.new()
	similar.text = "Select Similar"
	similar.tooltip_text = "Select every sector with the same value as the first selected one. (Drag across rooms from a floor to box-select; Shift adds.)"
	similar.pressed.connect(func() -> void:
		editor.select_similar(DMEditor.SIMILAR_KINDS[clampi(_similar.selected, 0, DMEditor.SIMILAR_KINDS.size() - 1)]))
	similar_row.add_child(similar)
	_sel_box.add_child(similar_row)
	_floor = _height_spin(func(v: float) -> void: editor.set_selected_height(DMBuilder.Part.FLOOR, v))
	_row(_sel_box, "Floor height", _floor)
	_ceiling = _height_spin(func(v: float) -> void: editor.set_selected_height(DMBuilder.Part.CEILING, v))
	_row(_sel_box, "Ceiling height", _ceiling)
	_has_ceiling = CheckBox.new()
	_has_ceiling.text = "Has ceiling"
	_has_ceiling.tooltip_text = "Off: open to the sky. Walls still rise to the ceiling height; no upper walls between two open sectors."
	_has_ceiling.toggled.connect(func(on: bool) -> void: editor.set_selected_ceiling(on))
	_sel_box.add_child(_has_ceiling)
	_has_floor = CheckBox.new()
	_has_floor.text = "Has floor"
	_has_floor.tooltip_text = "Off: no floor (a hole). Walls still start at the floor height."
	_has_floor.toggled.connect(func(on: bool) -> void: editor.set_selected_floor(on))
	_sel_box.add_child(_has_floor)
	_sector_thick = _height_spin(func(v: float) -> void: editor.set_selected_wall_thickness(v))
	_sector_thick.min_value = 0.0
	_sector_thick.allow_lesser = false
	_sector_thick.tooltip_text = "How thick this room's outer walls are, built outward as solid blocks (the room keeps its size). 0 = thin."
	_row(_sel_box, "Wall thickness", _sector_thick)
	_hidden_walls = Button.new()
	_hidden_walls.tooltip_text = "Bring back walls that were hidden (shown as dashed outlines)."
	_hidden_walls.pressed.connect(func() -> void: editor.show_hidden_walls())
	_sel_box.add_child(_hidden_walls)

	_wall_label = _header(_sel_box, "Selected wall")
	_wall_box = VBoxContainer.new()
	_sel_box.add_child(_wall_box)
	_wall_hidden = CheckBox.new()
	_wall_hidden.text = "Hidden (opening)"
	_wall_hidden.tooltip_text = "Remove just this wall: no surface and no collision. Delete key does the same."
	_wall_hidden.toggled.connect(func(on: bool) -> void: editor.set_wall_hidden(on))
	_wall_box.add_child(_wall_hidden)
	_wall_bottom = _height_spin(func(v: float) -> void: editor.set_wall_height(false, v))
	_wall_bottom.tooltip_text = "This wall's own bottom height. The room's other walls don't change."
	_row(_wall_box, "Wall bottom", _wall_bottom)
	_wall_top = _height_spin(func(v: float) -> void: editor.set_wall_height(true, v))
	_wall_top.tooltip_text = "This wall's own top height, e.g. lower it for a half wall. The room's other walls don't change."
	_row(_wall_box, "Wall top", _wall_top)
	_wall_thick = _height_spin(func(v: float) -> void: editor.set_wall_thickness(v))
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
	_wall_reset.tooltip_text = "Back to the sector's heights, thickness and texture alignment, and shown."
	_wall_reset.pressed.connect(func() -> void: editor.reset_wall())
	_wall_box.add_child(_wall_reset)
	_split_wall = Button.new()
	_split_wall.text = "Split Wall"
	_split_wall.tooltip_text = "Add a corner in the middle of this wall (neighbours sharing it get it too). Or double-click a selected sector's wall to add one there."
	_split_wall.pressed.connect(func() -> void: editor.split_selected_wall())
	_wall_box.add_child(_split_wall)
	_curve_segments = SpinBox.new()
	_curve_segments.min_value = 2
	_curve_segments.max_value = 128
	_curve_segments.step = 1
	_curve_segments.tooltip_text = "How many straight pieces the curve is made of."
	_curve_segments.value_changed.connect(func(v: float) -> void:
		editor.curve_segments = int(v)
		editor.save_settings())
	_row(_wall_box, "Segments", _curve_segments)
	_curve_bulge = _height_spin(func(v: float) -> void:
		editor.curve_bulge = v
		editor.save_settings())
	_curve_bulge.tooltip_text = "How far the middle of the wall moves: positive bulges outward (the room grows), negative into the room. At most half the wall's length (a half circle)."
	_row(_wall_box, "Bulge", _curve_bulge)
	_curve = Button.new()
	_curve.text = "Curve Wall"
	_curve.tooltip_text = "Bend this wall into an arc. A sector sharing the wall bends with it."
	_curve.pressed.connect(func() -> void: editor.curve_selected_wall())
	_wall_box.add_child(_curve)
	_floor_mat = _picker(func(m: Resource) -> void: editor.set_selected_material(DMBuilder.Part.FLOOR, m as Material))
	_row(_sel_box, "Floor material", _floor_mat)
	_ceiling_mat = _picker(func(m: Resource) -> void: editor.set_selected_material(DMBuilder.Part.CEILING, m as Material))
	_row(_sel_box, "Ceiling material", _ceiling_mat)
	_wall_mat = _picker(func(m: Resource) -> void: editor.set_selected_material(DMBuilder.Part.WALL, m as Material))
	_row(_sel_box, "Wall material", _wall_mat)

	var tex := _section(_sel_box, "Texture alignment", true)
	_uv_part = OptionButton.new()
	_uv_part.add_item("Floor")
	_uv_part.add_item("Ceiling")
	_uv_part.add_item("Walls")
	_uv_part.tooltip_text = "Which surface of the selected sectors to align. Walls with one wall selected: just that wall."
	_uv_part.item_selected.connect(func(_i: int) -> void: refresh())
	_row(tex, "Surface", _uv_part)
	_uv_offset_x = _height_spin(func(_v: float) -> void: _apply_uv())
	_uv_offset_x.tooltip_text = "Shift the texture along its width."
	_row(tex, "Offset X", _uv_offset_x)
	_uv_offset_y = _height_spin(func(_v: float) -> void: _apply_uv())
	_uv_offset_y.tooltip_text = "Shift the texture along its height."
	_row(tex, "Offset Y", _uv_offset_y)
	_uv_size_x = _height_spin(func(_v: float) -> void: _apply_uv())
	_uv_size_x.tooltip_text = "How wide one repeat of the texture is (1 m by default). Negative mirrors it."
	_row(tex, "Size X", _uv_size_x)
	_uv_size_y = _height_spin(func(_v: float) -> void: _apply_uv())
	_uv_size_y.tooltip_text = "How tall one repeat of the texture is (1 m by default). Negative mirrors it."
	_row(tex, "Size Y", _uv_size_y)
	_uv_rotation = SpinBox.new()
	_uv_rotation.min_value = -360
	_uv_rotation.max_value = 360
	_uv_rotation.step = 0.1
	_uv_rotation.custom_arrow_step = 15.0
	_uv_rotation.suffix = "°"
	_uv_rotation.select_all_on_focus = true
	_uv_rotation.tooltip_text = "Rotate the texture (degrees)."
	_uv_rotation.value_changed.connect(func(_v: float) -> void: _apply_uv())
	_row(tex, "Rotation", _uv_rotation)
	_uv_note = Label.new()
	_uv_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_uv_note.modulate = Color(1, 1, 1, 0.6)
	tex.add_child(_uv_note)
	var uv_reset := Button.new()
	uv_reset.text = "Reset Texture"
	uv_reset.tooltip_text = "Back to plain world alignment (for a single wall: back to its room's)."
	uv_reset.pressed.connect(func() -> void: editor.reset_selected_uv(_uv_part_value()))
	var uv_tools := GridContainer.new()
	uv_tools.columns = 2
	var fit := Button.new()
	fit.text = "Fit"
	fit.tooltip_text = "One texture repeat exactly covering each floor / ceiling, or each wall (its length and height)."
	fit.pressed.connect(func() -> void: editor.fit_selected_uv(_uv_part_value()))
	for b: Button in [uv_reset, fit]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		uv_tools.add_child(b)
	var uv_copy := Button.new()
	uv_copy.text = "Copy Alignment"
	uv_copy.tooltip_text = "Remember this surface's offset, size and rotation (Ctrl+Shift+C over a surface in the viewport)."
	uv_copy.pressed.connect(func() -> void: editor.copy_selected_uv(_uv_part_value()))
	var uv_paste := Button.new()
	uv_paste.text = "Paste Alignment"
	uv_paste.tooltip_text = "Give the selection's surface the copied alignment (Ctrl+Shift+V over a surface)."
	uv_paste.pressed.connect(func() -> void: editor.paste_selected_uv(_uv_part_value()))
	for b: Button in [uv_copy, uv_paste]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		uv_tools.add_child(b)
	tex.add_child(uv_tools)
	var uv_keys := Label.new()
	uv_keys.text = "In the viewport: Alt+arrow keys over a surface move its texture one grid step (Shift: ⅛ step)."
	uv_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	uv_keys.modulate = Color(1, 1, 1, 0.6)
	tex.add_child(uv_keys)

	var xform := GridContainer.new()
	xform.columns = 2
	for item: Array in [["Rotate 90° ⟳", "rotate_cw", "Turn the selected sectors 90° clockwise (seen from above)."],
			["Rotate 90° ⟲", "rotate_ccw", "Turn the selected sectors 90° counter-clockwise (seen from above)."],
			["Mirror X", "mirror_x", "Flip the selected sectors left-right."],
			["Mirror Z", "mirror_z", "Flip the selected sectors front-back."]]:
		var b := Button.new()
		b.text = item[0]
		b.tooltip_text = item[2] + " Neighbours stay where they are."
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kind: String = item[1]
		b.pressed.connect(func() -> void: editor.transform_selected(kind))
		xform.add_child(b)
	var copy := Button.new()
	copy.text = "Copy  (Ctrl+C)"
	copy.tooltip_text = "Copy the selected sectors; Paste (Ctrl+V) places copies."
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(func() -> void: editor.copy_selected())
	xform.add_child(copy)
	var save_prefab := Button.new()
	save_prefab.text = "Save as Prefab…"
	save_prefab.tooltip_text = "Save the selected sectors as a prefab (.tres) to paste into any map (Paste Prefab)."
	save_prefab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_prefab.pressed.connect(func() -> void: editor.ask_save_prefab())
	xform.add_child(save_prefab)
	_rotate_angle = SpinBox.new()
	_rotate_angle.min_value = -360
	_rotate_angle.max_value = 360
	_rotate_angle.step = 0.1
	_rotate_angle.custom_arrow_step = 15.0
	_rotate_angle.suffix = "°"
	_rotate_angle.select_all_on_focus = true
	_rotate_angle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rotate_angle.tooltip_text = "Angle for Rotate by (positive: clockwise seen from above). E / Shift+E turn a paste by it."
	_rotate_angle.value_changed.connect(func(v: float) -> void: editor.set_rotate_angle(v))
	xform.add_child(_rotate_angle)
	var rotate_by := Button.new()
	rotate_by.text = "Rotate by Angle"
	rotate_by.tooltip_text = "Turn the selected sectors by the angle on the left about the grid point nearest their center. Neighbours stay where they are."
	rotate_by.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_by.pressed.connect(func() -> void: editor.rotate_selected(editor.rotate_angle))
	xform.add_child(rotate_by)
	_sel_box.add_child(xform)

	_stairs_box = _section(_sel_box, "Stairs", true)
	_stair_step = _height_spin(func(v: float) -> void:
		editor.stair_step = v
		editor.save_settings())
	_stair_step.tooltip_text = "How much each step rises (negative: goes down)."
	_row(_stairs_box, "Step height", _stair_step)
	_stair_ceilings = CheckBox.new()
	_stair_ceilings.text = "Ceilings move too"
	_stair_ceilings.tooltip_text = "On: each ceiling moves as much as its floor (a sloping corridor). Off: ceilings stay, rising only where a floor would pass them."
	_stair_ceilings.toggled.connect(func(on: bool) -> void:
		editor.stair_ceilings = on
		editor.save_settings())
	_stairs_box.add_child(_stair_ceilings)
	_make_stairs = Button.new()
	_make_stairs.text = "Make Stairs"
	_make_stairs.tooltip_text = "Shift+click the steps in order, then press this: each floor is one step above the one before, starting from the first one's floor."
	_make_stairs.pressed.connect(func() -> void: editor.make_stairs())
	_stairs_box.add_child(_make_stairs)
	_stair_count = SpinBox.new()
	_stair_count.min_value = 2
	_stair_count.max_value = 256
	_stair_count.step = 1
	_stair_count.tooltip_text = "How many steps Split into Steps makes."
	_stair_count.value_changed.connect(func(v: float) -> void:
		editor.stair_count = int(v)
		editor.save_settings())
	_row(_stairs_box, "Steps", _stair_count)
	_stair_dir = OptionButton.new()
	for label: String in ["+X", "-X", "+Z", "-Z"]:
		_stair_dir.add_item(label)
	_stair_dir.tooltip_text = "The direction the steps climb."
	_stair_dir.item_selected.connect(func(i: int) -> void:
		editor.stair_direction = i
		editor.save_settings())
	_row(_stairs_box, "Climbing", _stair_dir)
	_split_steps = Button.new()
	_split_steps.text = "Split into Steps"
	_split_steps.tooltip_text = "Cut the selected sector into equal strips across the climbing direction and make them stairs (the first strip keeps the floor height)."
	_split_steps.pressed.connect(func() -> void: editor.split_into_steps())
	_stairs_box.add_child(_split_steps)
	_join = Button.new()
	_join.text = "Join Sectors  (J)"
	_join.tooltip_text = "Make the selected sectors one sector, with the first-selected one's heights and materials. Walls between them disappear."
	_join.pressed.connect(func() -> void: editor.join_selected())
	_sel_box.add_child(_join)
	_simplify = Button.new()
	_simplify.text = "Simplify Sector"
	_simplify.tooltip_text = "Remove points that don't change the shape: extra points along straight walls and seams inside the sector."
	_simplify.pressed.connect(func() -> void: editor.simplify_selected())
	_sel_box.add_child(_simplify)
	_thick = _height_spin(func(v: float) -> void:
		editor.wall_thickness = v
		editor.save_settings())
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
		editor.wall_side = i - 1
		editor.save_settings())
	_row(_sel_box, "Thicken toward", _thick_side)
	_thicken = Button.new()
	_thicken.text = "Thicken Walls"
	_thicken.tooltip_text = "Turn the space along the selected rooms' walls into solid wall. Draw a sector across it to cut a doorway."
	_thicken.pressed.connect(func() -> void: editor.thicken_selected())
	_sel_box.add_child(_thicken)
	_delete = Button.new()
	_delete.text = "Delete Sector"
	_delete.tooltip_text = "Remove the selected sectors (Delete key). Their area becomes solid."
	_delete.pressed.connect(func() -> void: editor.delete_selected())
	_sel_box.add_child(_delete)

	var defs := _section(box, "New sectors in empty space", true)
	_def_floor = _height_spin(func(v: float) -> void: editor.set_default_height(DMBuilder.Part.FLOOR, v))
	_row(defs, "Floor height", _def_floor)
	_def_ceiling = _height_spin(func(v: float) -> void: editor.set_default_height(DMBuilder.Part.CEILING, v))
	_row(defs, "Ceiling height", _def_ceiling)
	_def_has_ceiling = CheckBox.new()
	_def_has_ceiling.text = "Has ceiling"
	_def_has_ceiling.toggled.connect(func(on: bool) -> void: editor.set_default_ceiling(on))
	defs.add_child(_def_has_ceiling)
	_def_floor_mat = _picker(func(m: Resource) -> void: editor.set_default_material(DMBuilder.Part.FLOOR, m as Material))
	_row(defs, "Floor material", _def_floor_mat)
	_def_ceiling_mat = _picker(func(m: Resource) -> void: editor.set_default_material(DMBuilder.Part.CEILING, m as Material))
	_row(defs, "Ceiling material", _def_ceiling_mat)
	_def_wall_mat = _picker(func(m: Resource) -> void: editor.set_default_material(DMBuilder.Part.WALL, m as Material))
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
		"D: draw a polygon sector point by point (type a length + Enter for an exact side)",
		"B: draw a rectangle (type width, Tab, depth, Enter for an exact size)",
		"Esc while drawing a polygon keeps it unfinished (red, saved with the scene): click either end to continue it, or Delete over it to discard it",
		"Click: select a sector (Shift+click adds)",
		"Drag a selected sector's corner or wall to reshape it (neighbours follow); Esc while dragging cancels",
		"Width / Depth in this panel resize the selection exactly",
		"Page Up / Page Down or Alt+wheel over a floor or ceiling: raise / lower it one grid step (all selected sectors if it's selected)",
		"[ and ]: smaller / larger grid",
		"J: join the selected sectors into one",
		"Thicken Walls (in this panel): give the selected rooms solid walls; draw a sector across one to cut a doorway",
		"Click a wall: select just that wall (set its own height, or Delete to hide it as an opening)",
		"Double-click a selected sector's wall: add a corner there; Delete over a corner: remove it (a triangle keeps its 3)",
		"Ctrl+C / Ctrl+V: copy / paste sectors (R / E rotate, M mirrors while placing)",
		"Drag from a floor across rooms: box select (Shift adds)",
		"Alt+arrows over a surface: move its texture; Ctrl+Shift+C / V: copy / paste its alignment",
		"Delete: hide the selected wall, or delete the selected sectors",
		"Esc: stop drawing / clear selection",
		"Top-down map view: numpad 7, then numpad 5 for flat (orthographic)",
	])
	controls.add_child(help)


func refresh() -> void:
	if not _built or editor == null:
		return
	var map := editor.map
	var units := editor.units
	var has_map := map != null and map.data != null
	_status.text = ("Editing: %s  (%d sectors)" % [map.name, map.data.sectors.size()]) if has_map \
		else "Select a Sector Map node, or create one:"
	_new_map.visible = not has_map
	_draw.disabled = not has_map
	_draw.set_pressed_no_signal(has_map and editor.tool.mode == DMTool.Mode.DRAW)
	_rect.disabled = not has_map
	_rect.set_pressed_no_signal(has_map and editor.tool.mode == DMTool.Mode.RECT)
	_rect_box.visible = has_map and editor.tool.mode == DMTool.Mode.RECT
	if _rect_box.visible:
		var rs := editor.tool.rect_size
		_set_spin(_rect_w, DMUnits.to_display(maxf(rs.x, 0.0), units))
		_set_spin(_rect_d, DMUnits.to_display(maxf(rs.y, 0.0), units))

	_paste.visible = has_map
	_paste.disabled = editor.clipboard.is_empty()
	_paste_prefab.visible = has_map
	if not _rotate_angle.get_line_edit().has_focus():
		_rotate_angle.set_value_no_signal(editor.rotate_angle)
	_grid.clear()
	for step in DMUnits.GRID_STEPS:
		_grid.add_item(DMUnits.format(step, units))
	_grid.select(DMUnits.step_index(editor.grid_step))
	_units.select(units)

	var arrow := DMUnits.to_display(editor.grid_step, units)
	var spins: Array[SpinBox] = [_floor, _ceiling, _def_floor, _def_ceiling, _rect_w, _rect_d, _width, _depth, _thick, _wall_bottom, _wall_top,
		_sector_thick, _wall_thick, _uv_offset_x, _uv_offset_y, _uv_size_x, _uv_size_y, _curve_bulge, _stair_step]
	for spin in spins:
		spin.suffix = DMUnits.suffix(units)
		spin.custom_arrow_step = arrow

	var sel: Array[int] = []
	if has_map:
		sel = editor.tool.selected
	_sel_box.visible = not sel.is_empty()
	if sel.is_empty():
		_sel_label.text = "No sector selected"
	else:
		_sel_label.text = "Selected: %d sector%s" % [sel.size(), "" if sel.size() == 1 else "s"]
		var s := map.data.sectors[sel[0]]
		var box := map.data.bounds_of(sel)
		_set_spin(_width, DMUnits.to_display(box.size.x, units))
		_set_spin(_depth, DMUnits.to_display(box.size.y, units))
		_anchor.select(editor.resize_anchor)
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
		var w := editor.tool.selected_wall
		_wall_label.visible = w != null
		_wall_box.visible = w != null
		if w != null:
			var o := s.wall_override(w.a, w.b)
			var outer := _is_outer_wall(map, w)
			_wall_hidden.set_pressed_no_signal(DMSector.setting_bool(o, "hidden"))
			(_wall_bottom.get_parent() as Control).visible = outer
			(_wall_top.get_parent() as Control).visible = outer
			(_wall_thick.get_parent() as Control).visible = outer
			_set_spin(_wall_thick, DMUnits.to_display(DMSector.setting_float(o, "thickness", s.wall_thickness), units))
			_wall_note.visible = not outer
			_set_spin(_wall_bottom, DMUnits.to_display(DMSector.setting_float(o, "bottom", s.floor_height), units))
			_set_spin(_wall_top, DMUnits.to_display(DMSector.setting_float(o, "top", s.ceiling_height), units))
		(_ceiling_mat.get_parent() as Control).visible = s.has_ceiling
		_join.visible = sel.size() >= 2
		_set_spin(_thick, DMUnits.to_display(editor.wall_thickness, units))
		_thick_side.select(editor.wall_side + 1)
		_thicken.text = "Thicken This Wall" if editor.tool.selected_wall != null else "Thicken Walls"
		_floor_mat.edited_resource = s.floor_material
		_ceiling_mat.edited_resource = s.ceiling_material
		_wall_mat.edited_resource = s.wall_material
		_delete.text = "Delete Sector" if sel.size() == 1 else "Delete %d Sectors" % sel.size()
		_refresh_uv(map, s, units)
		_curve_segments.set_value_no_signal(editor.curve_segments)
		_set_spin(_curve_bulge, DMUnits.to_display(editor.curve_bulge, units))
		_set_spin(_stair_step, DMUnits.to_display(editor.stair_step, units))
		_stair_ceilings.set_pressed_no_signal(editor.stair_ceilings)
		_make_stairs.disabled = sel.size() < 2
		_make_stairs.text = "Make Stairs (%d steps)" % sel.size() if sel.size() >= 2 else "Make Stairs (Shift+click steps)"
		_stair_count.set_value_no_signal(editor.stair_count)
		_stair_dir.select(clampi(editor.stair_direction, 0, 3))
		_split_steps.disabled = sel.size() != 1

	var d := editor.defaults
	_set_spin(_def_floor, DMUnits.to_display(d.floor_height, units))
	_set_spin(_def_ceiling, DMUnits.to_display(d.ceiling_height, units))
	_def_has_ceiling.set_pressed_no_signal(d.has_ceiling)
	_def_floor_mat.edited_resource = d.floor_material
	_def_ceiling_mat.edited_resource = d.ceiling_material
	_def_wall_mat.edited_resource = d.wall_material


const UV_PARTS: Array[int] = [DMBuilder.Part.FLOOR, DMBuilder.Part.CEILING, DMBuilder.Part.WALL]


func _uv_part_value() -> int:
	return UV_PARTS[clampi(_uv_part.selected, 0, 2)]


func _refresh_uv(map: DMMap, s: DMSector, units: int) -> void:
	var part := _uv_part_value()
	var w := editor.tool.selected_wall
	var o := {}
	if part == DMBuilder.Part.WALL and w != null:
		s = map.data.sectors[w.sector]
		o = s.wall_override(w.a, w.b)
	var v := s.uv_values(part, o)
	var offset := v.offset
	var size := v.size
	_set_spin(_uv_offset_x, DMUnits.to_display(offset.x, units))
	_set_spin(_uv_offset_y, DMUnits.to_display(offset.y, units))
	_set_spin(_uv_size_x, DMUnits.to_display(size.x, units))
	_set_spin(_uv_size_y, DMUnits.to_display(size.y, units))
	_set_spin(_uv_rotation, v.rotation)
	if part == DMBuilder.Part.WALL:
		_uv_note.text = "Just the selected wall." if w != null else "All walls of the selected sectors (click one wall to align it alone)."
	else:
		_uv_note.text = "Textures are world-aligned, so neighbouring surfaces line up; these shift, size and turn them."


func _apply_uv() -> void:
	var u := editor.units
	var offset := Vector2(DMUnits.from_display(_uv_offset_x.value, u), DMUnits.from_display(_uv_offset_y.value, u))
	var size := Vector2(DMUnits.from_display(_uv_size_x.value, u), DMUnits.from_display(_uv_size_y.value, u))
	editor.set_selected_uv(_uv_part_value(), offset, size, _uv_rotation.value)


## True when the selected wall faces solid space (not another sector).
static func _is_outer_wall(map: DMMap, w: DMTool.Wall) -> bool:
	var a := w.a
	var b := w.b
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
		on_change.call(DMUnits.from_display(v, editor.units)))
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
