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
var _rect_w: EditorSpinSlider
var _rect_d: EditorSpinSlider
var _grid: OptionButton
var _units: OptionButton
var _sel_label: Label
var _sel_box: VBoxContainer
var _floor: EditorSpinSlider
var _width: EditorSpinSlider
var _depth: EditorSpinSlider
var _anchor: OptionButton
var _ceiling: EditorSpinSlider
var _has_ceiling: CheckBox
var _has_floor: CheckBox
var _sector_thick: EditorSpinSlider
var _wall_thick: EditorSpinSlider
var _hidden_walls: Button
var _draw_section: Control
var _wall_section: Control
var _wall_box: VBoxContainer
var _wall_hidden: CheckBox
var _wall_length: EditorSpinSlider
var _length_anchor: OptionButton
var _wall_bottom: EditorSpinSlider
var _wall_top: EditorSpinSlider
var _wall_note: Label
var _wall_reset: Button
var _join: Button
var _simplify: Button
var _thick: EditorSpinSlider
var _thick_side: OptionButton
var _thicken: Button
var _def_has_ceiling: CheckBox
var _floor_mat: EditorResourcePicker
var _ceiling_mat: EditorResourcePicker
var _wall_mat: EditorResourcePicker
var _delete: Button
var _def_floor: EditorSpinSlider
var _def_ceiling: EditorSpinSlider
var _def_floor_mat: EditorResourcePicker
var _def_ceiling_mat: EditorResourcePicker
var _def_wall_mat: EditorResourcePicker
var _paste: Button
var _paste_prefab: Button
var _similar: OptionButton
var _rotate_angle: EditorSpinSlider
var _uv_part: OptionButton
var _uv_offset_x: EditorSpinSlider
var _uv_offset_y: EditorSpinSlider
var _uv_size_x: EditorSpinSlider
var _uv_size_y: EditorSpinSlider
var _uv_rotation: EditorSpinSlider
var _uv_note: Label
var _split_wall: Button
var _curve_segments: EditorSpinSlider
var _curve_bulge: EditorSpinSlider
var _curve: Button
var _stairs_box: VBoxContainer
var _stair_step: EditorSpinSlider
var _stair_ceilings: CheckBox
var _make_stairs: Button
var _stair_count: EditorSpinSlider
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
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	# --- Map and drawing tools ---------------------------------------------------
	_status = _header(box, "")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_new_map = _button("New Sector Map", "Add a Sector Map node to the open scene and select it.", "Add")
	_new_map.pressed.connect(func() -> void: editor.new_map())
	box.add_child(_new_map)

	var draw := _section(box, "Draw", false)
	_draw_section = draw.get_parent().get_parent() as Control
	_draw = _button("Polygon  (D)", "Click points on the grid to outline a floor area. Click the first point (or press Enter) to finish.", "Polygon2D")
	_draw.toggle_mode = true
	_draw.toggled.connect(func(on: bool) -> void: editor.set_drawing(on, false))
	_rect = _button("Rectangle  (B)", "Click one corner, then the opposite corner. Or type the width, press Tab, type the depth, and press Enter.", "ColorRect")
	_rect.toggle_mode = true
	_rect.toggled.connect(func(on: bool) -> void: editor.set_drawing(on, true))
	_pair(draw, _draw, _rect)
	_rect_box = VBoxContainer.new()
	draw.add_child(_rect_box)
	var rect_grid := _grid_box(_rect_box)
	_rect_w = _height_spin(func(v: float) -> void: editor.tool.set_rect_size(0, v))
	_rect_w.min_value = 0.0
	_rect_w.allow_lesser = false
	_rect_w.tooltip_text = "Exact width (X). 0 = follow the mouse."
	_prop(rect_grid, "Width", _rect_w)
	_rect_d = _height_spin(func(v: float) -> void: editor.tool.set_rect_size(1, v))
	_rect_d.min_value = 0.0
	_rect_d.allow_lesser = false
	_rect_d.tooltip_text = "Exact depth (Z). 0 = follow the mouse."
	_prop(rect_grid, "Depth", _rect_d)
	_hint(_rect_box, "0 = follow the mouse. You can also type sizes in the viewport (Tab switches).")
	_paste = _button("Paste", "Place a copy of the copied sectors (Ctrl+V; Ctrl+C copies the selection). R rotates and M mirrors while placing; it cuts what's under it, like drawing.", "ActionPaste")
	_paste.pressed.connect(func() -> void: editor.begin_paste())
	_paste_prefab = _button("Prefab…", "Place a prefab: sectors saved with Save as Prefab (a .tres file), into this or any other map.", "Load")
	_paste_prefab.pressed.connect(func() -> void: editor.ask_load_prefab())
	_pair(draw, _paste, _paste_prefab)
	var grid_props := _grid_box(draw)
	_grid = _option("Grid snap size. Shortcut: [ and ] in the viewport.")
	_grid.item_selected.connect(func(i: int) -> void: editor.set_grid_step(DMUnits.GRID_STEPS[i]))
	_prop(grid_props, "Grid", _grid)
	_units = _option("How sizes are shown and typed. Maps are always stored in meters.")
	_units.add_item("Meters")
	_units.add_item("Doom units (32 per m)")
	_units.item_selected.connect(func(i: int) -> void: editor.set_units(i))
	_prop(grid_props, "Units", _units)

	# --- Selection ---------------------------------------------------------------
	box.add_child(HSeparator.new())
	_sel_label = _header(box, "No sector selected")
	_sel_box = VBoxContainer.new()
	_sel_box.add_theme_constant_override("separation", 8)
	box.add_child(_sel_box)

	_similar = _option("What Select Similar compares with the first selected sector.")
	for label: String in ["Floor height", "Ceiling height", "Both heights", "Floor material", "Ceiling material", "Wall material", "All materials"]:
		_similar.add_item(label)
	var similar := _button("Select Similar", "Select every sector with the same value (chosen on the left) as the first selected one. (Drag across rooms from a floor to box-select; Shift adds.)")
	similar.pressed.connect(func() -> void:
		editor.select_similar(DMEditor.SIMILAR_KINDS[clampi(_similar.selected, 0, DMEditor.SIMILAR_KINDS.size() - 1)]))
	_pair(_sel_box, _similar, similar)
	_join = _button("Join  (J)", "Make the selected sectors one sector, with the first-selected one's heights and materials. Walls between them disappear.")
	_join.pressed.connect(func() -> void: editor.join_selected())
	_simplify = _button("Simplify", "Remove points that don't change the shape: extra points along straight walls and seams inside the sector.")
	_simplify.pressed.connect(func() -> void: editor.simplify_selected())
	_pair(_sel_box, _join, _simplify)

	var sector := _section(_sel_box, "Sector", false)
	var heights := _grid_box(sector)
	_floor = _height_spin(func(v: float) -> void: editor.set_selected_height(DMBuilder.Part.FLOOR, v))
	_floor.tooltip_text = "Floor height. Page Up / Page Down over the floor in the viewport nudges it."
	_prop(heights, "Floor", _floor)
	_ceiling = _height_spin(func(v: float) -> void: editor.set_selected_height(DMBuilder.Part.CEILING, v))
	_ceiling.tooltip_text = "Ceiling height. Page Up / Page Down over the ceiling in the viewport nudges it."
	_prop(heights, "Ceiling", _ceiling)
	_has_floor = _check("Floor", "Off: no floor (a hole). Walls still start at the floor height.")
	_has_floor.toggled.connect(func(on: bool) -> void: editor.set_selected_floor(on))
	_has_ceiling = _check("Ceiling", "Off: open to the sky. Walls still rise to the ceiling height; no upper walls between two open sectors.")
	_has_ceiling.toggled.connect(func(on: bool) -> void: editor.set_selected_ceiling(on))
	var surfaces := HBoxContainer.new()
	surfaces.add_child(_has_floor)
	surfaces.add_child(_has_ceiling)
	_prop(heights, "Has", surfaces)
	_width = _height_spin(func(v: float) -> void: editor.resize_selected(0, v))
	_width.min_value = 0.001
	_width.allow_lesser = false
	_width.tooltip_text = "Width (X) of the selected area. Corners shared with neighbours move too."
	_prop(heights, "Width", _width)
	_depth = _height_spin(func(v: float) -> void: editor.resize_selected(1, v))
	_depth.min_value = 0.001
	_depth.allow_lesser = false
	_depth.tooltip_text = "Depth (Z) of the selected area. Corners shared with neighbours move too."
	_prop(heights, "Depth", _depth)
	_anchor = _option("Which point stays in place when you change Width or Depth.")
	for label: String in ["Center", "-X / -Z corner", "+X / -Z corner", "-X / +Z corner", "+X / +Z corner"]:
		_anchor.add_item(label)
	_anchor.item_selected.connect(func(i: int) -> void: editor.resize_anchor = i)
	_prop(heights, "Keep fixed", _anchor)
	_sector_thick = _height_spin(func(v: float) -> void: editor.set_selected_wall_thickness(v))
	_sector_thick.min_value = 0.0
	_sector_thick.allow_lesser = false
	_sector_thick.tooltip_text = "How thick this room's outer walls are, built outward as solid blocks (the room keeps its size). 0 = thin."
	_prop(heights, "Walls", _sector_thick)
	_hidden_walls = _button("", "Bring back walls that were hidden (shown as dashed outlines).", "GuiVisibilityVisible")
	_hidden_walls.pressed.connect(func() -> void: editor.show_hidden_walls())
	sector.add_child(_hidden_walls)

	var mats := _section(_sel_box, "Materials", false)
	var mat_grid := _grid_box(mats)
	_floor_mat = _picker(func(m: Resource) -> void: editor.set_selected_material(DMBuilder.Part.FLOOR, m as Material))
	_prop(mat_grid, "Floor", _floor_mat)
	_ceiling_mat = _picker(func(m: Resource) -> void: editor.set_selected_material(DMBuilder.Part.CEILING, m as Material))
	_prop(mat_grid, "Ceiling", _ceiling_mat)
	_wall_mat = _picker(func(m: Resource) -> void: editor.set_selected_material(DMBuilder.Part.WALL, m as Material))
	_prop(mat_grid, "Walls", _wall_mat)

	_wall_box = _section(_sel_box, "Selected Wall", false)
	_wall_section = _wall_box.get_parent().get_parent() as Control
	_wall_hidden = _check("Hidden (an opening)", "Remove just this wall: no surface and no collision. Delete key does the same.")
	_wall_hidden.toggled.connect(func(on: bool) -> void: editor.set_wall_hidden(on))
	_wall_box.add_child(_wall_hidden)
	var wall_grid := _grid_box(_wall_box)
	_wall_length = _height_spin(func(v: float) -> void: editor.set_wall_length(v))
	_wall_length.min_value = 0.001
	_wall_length.allow_lesser = false
	_wall_length.tooltip_text = "This wall's length. Its corners move along the wall; neighbours sharing them stretch along. Or type the length in the viewport and press Enter."
	_prop(wall_grid, "Length", _wall_length)
	_length_anchor = _option("Which point stays in place when you change the wall's length (the ends are labelled A and B in the viewport).")
	for label: String in ["Center", "End A", "End B"]:
		_length_anchor.add_item(label)
	_length_anchor.item_selected.connect(func(i: int) -> void:
		editor.length_anchor = i as DMEditor.LengthAnchor
		editor.save_settings()
		editor.update_overlays())
	_prop(wall_grid, "Keep fixed", _length_anchor)
	_wall_bottom = _height_spin(func(v: float) -> void: editor.set_wall_height(false, v))
	_wall_bottom.tooltip_text = "This wall's own bottom height. The room's other walls don't change."
	_prop(wall_grid, "Bottom", _wall_bottom)
	_wall_top = _height_spin(func(v: float) -> void: editor.set_wall_height(true, v))
	_wall_top.tooltip_text = "This wall's own top height, e.g. lower it for a half wall. The room's other walls don't change."
	_prop(wall_grid, "Top", _wall_top)
	_wall_thick = _height_spin(func(v: float) -> void: editor.set_wall_thickness(v))
	_wall_thick.min_value = 0.0
	_wall_thick.allow_lesser = false
	_wall_thick.tooltip_text = "This wall's own thickness, built outward as a solid block. 0 = thin. Reset Wall goes back to the room's thickness."
	_prop(wall_grid, "Thickness", _wall_thick)
	_wall_note = _hint(_wall_box, "Between two sectors: its height comes from the neighbouring floor or ceiling. It can be hidden but not resized, and Thicken takes the space from the neighbouring room.")
	_split_wall = _button("Split", "Add a corner in the middle of this wall (neighbours sharing it get it too). Or double-click a selected sector's wall to add one there.")
	_split_wall.pressed.connect(func() -> void: editor.split_selected_wall())
	_wall_reset = _button("Reset", "Back to the sector's heights, thickness and texture alignment, and shown.", "Reload")
	_wall_reset.pressed.connect(func() -> void: editor.reset_wall())
	_pair(_wall_box, _split_wall, _wall_reset)
	_subheader(_wall_box, "Curve")
	var curve_grid := _grid_box(_wall_box)
	_curve_segments = _int_spin(2, 128)
	_curve_segments.tooltip_text = "How many straight pieces the curve is made of."
	_curve_segments.value_changed.connect(func(v: float) -> void:
		editor.curve_segments = int(v)
		editor.save_settings())
	_prop(curve_grid, "Segments", _curve_segments)
	_curve_bulge = _height_spin(func(v: float) -> void:
		editor.curve_bulge = v
		editor.save_settings())
	_curve_bulge.tooltip_text = "How far the middle of the wall moves: positive bulges outward (the room grows), negative into the room. At most half the wall's length (a half circle)."
	_prop(curve_grid, "Bulge", _curve_bulge)
	_curve = _button("Curve Wall", "Bend this wall into an arc. A sector sharing the wall bends with it.")
	_curve.pressed.connect(func() -> void: editor.curve_selected_wall())
	_wall_box.add_child(_curve)

	var tex := _section(_sel_box, "Texture Alignment", true)
	var tex_grid := _grid_box(tex)
	_uv_part = _option("Which surface of the selected sectors to align. Walls with one wall selected: just that wall.")
	_uv_part.add_item("Floor")
	_uv_part.add_item("Ceiling")
	_uv_part.add_item("Walls")
	_uv_part.item_selected.connect(func(_i: int) -> void: refresh())
	_prop(tex_grid, "Surface", _uv_part)
	_uv_offset_x = _height_spin(func(_v: float) -> void: _apply_uv())
	_uv_offset_x.tooltip_text = "Shift the texture along its width."
	_prop(tex_grid, "Offset X", _uv_offset_x)
	_uv_offset_y = _height_spin(func(_v: float) -> void: _apply_uv())
	_uv_offset_y.tooltip_text = "Shift the texture along its height."
	_prop(tex_grid, "Offset Y", _uv_offset_y)
	_uv_size_x = _height_spin(func(_v: float) -> void: _apply_uv())
	_uv_size_x.tooltip_text = "How wide one repeat of the texture is (1 m by default). Negative mirrors it."
	_prop(tex_grid, "Size X", _uv_size_x)
	_uv_size_y = _height_spin(func(_v: float) -> void: _apply_uv())
	_uv_size_y.tooltip_text = "How tall one repeat of the texture is (1 m by default). Negative mirrors it."
	_prop(tex_grid, "Size Y", _uv_size_y)
	_uv_rotation = _angle_spin("Rotate the texture (degrees).")
	_uv_rotation.value_changed.connect(func(_v: float) -> void: _apply_uv())
	_prop(tex_grid, "Rotation", _uv_rotation)
	_uv_note = _hint(tex, "")
	var fit := _button("Fit", "One texture repeat exactly covering each floor / ceiling, or each wall (its length and height).")
	fit.pressed.connect(func() -> void: editor.fit_selected_uv(_uv_part_value()))
	var uv_reset := _button("Reset", "Back to plain world alignment (for a single wall: back to its room's).", "Reload")
	uv_reset.pressed.connect(func() -> void: editor.reset_selected_uv(_uv_part_value()))
	_pair(tex, fit, uv_reset)
	var uv_copy := _button("Copy", "Remember this surface's offset, size and rotation (Ctrl+Shift+C over a surface in the viewport).", "ActionCopy")
	uv_copy.pressed.connect(func() -> void: editor.copy_selected_uv(_uv_part_value()))
	var uv_paste := _button("Paste", "Give the selection's surface the copied alignment (Ctrl+Shift+V over a surface).", "ActionPaste")
	uv_paste.pressed.connect(func() -> void: editor.paste_selected_uv(_uv_part_value()))
	_pair(tex, uv_copy, uv_paste)
	_hint(tex, "In the viewport: Alt+arrow keys over a surface move its texture one grid step (Shift: ⅛ step).")

	var xform := _section(_sel_box, "Rotate, Mirror & Copy", true)
	var turns: Array[Button] = []
	for item: Array in [["90° ⟳", "rotate_cw", "Turn the selected sectors 90° clockwise (seen from above).", "RotateRight"],
			["90° ⟲", "rotate_ccw", "Turn the selected sectors 90° counter-clockwise (seen from above).", "RotateLeft"],
			["Mirror X", "mirror_x", "Flip the selected sectors left-right.", "MirrorX"],
			["Mirror Z", "mirror_z", "Flip the selected sectors front-back.", "MirrorY"]]:
		var kind: String = item[1]
		var label: String = item[0]
		var tip: String = item[2]
		var icon_name: String = item[3]
		var b := _button(label, tip + " Neighbours stay where they are (a sector inside another takes its hole along).", icon_name)
		b.pressed.connect(func() -> void: editor.transform_selected(kind))
		turns.append(b)
	_pair(xform, turns[0], turns[1])
	_pair(xform, turns[2], turns[3])
	_rotate_angle = _angle_spin("Angle for Rotate (positive: clockwise seen from above). E / Shift+E turn a paste by it.")
	_rotate_angle.value_changed.connect(func(v: float) -> void: editor.set_rotate_angle(v))
	var rotate_by := _button("Rotate", "Turn the selected sectors by this angle about the grid point nearest their center. Neighbours stay where they are.")
	rotate_by.pressed.connect(func() -> void: editor.rotate_selected(editor.rotate_angle))
	_pair(xform, _rotate_angle, rotate_by)
	var copy := _button("Copy", "Copy the selected sectors (Ctrl+C); Paste (Ctrl+V) places copies.", "ActionCopy")
	copy.pressed.connect(func() -> void: editor.copy_selected())
	var save_prefab := _button("Save Prefab…", "Save the selected sectors as a prefab (.tres) to paste into any map (Prefab… under Draw).", "Save")
	save_prefab.pressed.connect(func() -> void: editor.ask_save_prefab())
	_pair(xform, copy, save_prefab)

	var thicken := _section(_sel_box, "Thicken Walls", true)
	var thick_grid := _grid_box(thicken)
	_thick = _height_spin(func(v: float) -> void:
		editor.wall_thickness = v
		editor.save_settings())
	_thick.min_value = 0.001
	_thick.allow_lesser = false
	_thick.tooltip_text = "How thick the walls become."
	_prop(thick_grid, "Thickness", _thick)
	_thick_side = _option("Where the thickness goes: into this room (it shrinks), half each way, or into the space around it (the room keeps its size).")
	_thick_side.add_item("Inward", 0)
	_thick_side.add_item("Centered", 1)
	_thick_side.add_item("Outward", 2)
	_thick_side.item_selected.connect(func(i: int) -> void:
		editor.wall_side = i - 1
		editor.save_settings())
	_prop(thick_grid, "Toward", _thick_side)
	_thicken = _button("Thicken Walls", "Turn the space along the selected rooms' walls into solid wall. Draw a sector across it to cut a doorway.")
	_thicken.pressed.connect(func() -> void: editor.thicken_selected())
	thicken.add_child(_thicken)

	_stairs_box = _section(_sel_box, "Stairs", true)
	var stair_grid := _grid_box(_stairs_box)
	_stair_step = _height_spin(func(v: float) -> void:
		editor.stair_step = v
		editor.save_settings())
	_stair_step.tooltip_text = "How much each step rises (negative: goes down)."
	_prop(stair_grid, "Step height", _stair_step)
	_stair_ceilings = _check("Ceilings move too", "On: each ceiling moves as much as its floor (a sloping corridor). Off: ceilings stay, rising only where a floor would pass them.")
	_stair_ceilings.toggled.connect(func(on: bool) -> void:
		editor.stair_ceilings = on
		editor.save_settings())
	_stairs_box.add_child(_stair_ceilings)
	_make_stairs = _button("Make Stairs", "Shift+click the steps in order, then press this: each floor is one step above the one before, starting from the first one's floor.")
	_make_stairs.pressed.connect(func() -> void: editor.make_stairs())
	_stairs_box.add_child(_make_stairs)
	_subheader(_stairs_box, "Split one sector into steps")
	var split_grid := _grid_box(_stairs_box)
	_stair_count = _int_spin(2, 256)
	_stair_count.tooltip_text = "How many steps Split into Steps makes."
	_stair_count.value_changed.connect(func(v: float) -> void:
		editor.stair_count = int(v)
		editor.save_settings())
	_prop(split_grid, "Steps", _stair_count)
	_stair_dir = _option("The direction the steps climb.")
	for label: String in ["+X", "-X", "+Z", "-Z"]:
		_stair_dir.add_item(label)
	_stair_dir.item_selected.connect(func(i: int) -> void:
		editor.stair_direction = i
		editor.save_settings())
	_prop(split_grid, "Climbing", _stair_dir)
	_split_steps = _button("Split into Steps", "Cut the selected sector into equal strips across the climbing direction and make them stairs (the first strip keeps the floor height).")
	_split_steps.pressed.connect(func() -> void: editor.split_into_steps())
	_stairs_box.add_child(_split_steps)

	_delete = _button("Delete Sector", "Remove the selected sectors (Delete key). Their area becomes solid.", "Remove")
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_color("error_color", "Editor"):
		var red := theme.get_color("error_color", "Editor")
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			_delete.add_theme_color_override(state, red)
	_sel_box.add_child(_delete)

	# --- Settings and help -------------------------------------------------------
	box.add_child(HSeparator.new())
	var defs := _section(box, "New Sectors in Empty Space", true)
	var def_grid := _grid_box(defs)
	_def_floor = _height_spin(func(v: float) -> void: editor.set_default_height(DMBuilder.Part.FLOOR, v))
	_prop(def_grid, "Floor", _def_floor)
	_def_ceiling = _height_spin(func(v: float) -> void: editor.set_default_height(DMBuilder.Part.CEILING, v))
	_prop(def_grid, "Ceiling", _def_ceiling)
	_def_has_ceiling = _check("Ceiling", "Off: new sectors are open to the sky.")
	_def_has_ceiling.toggled.connect(func(on: bool) -> void: editor.set_default_ceiling(on))
	_prop(def_grid, "Has", _def_has_ceiling)
	_def_floor_mat = _picker(func(m: Resource) -> void: editor.set_default_material(DMBuilder.Part.FLOOR, m as Material))
	_prop(def_grid, "Floor mat.", _def_floor_mat)
	_def_ceiling_mat = _picker(func(m: Resource) -> void: editor.set_default_material(DMBuilder.Part.CEILING, m as Material))
	_prop(def_grid, "Ceiling mat.", _def_ceiling_mat)
	_def_wall_mat = _picker(func(m: Resource) -> void: editor.set_default_material(DMBuilder.Part.WALL, m as Material))
	_prop(def_grid, "Wall mat.", _def_wall_mat)
	_hint(defs, "A sector drawn inside another copies its heights and materials instead.")

	var controls := _section(box, "Controls", true)
	var help := RichTextLabel.new()
	help.bbcode_enabled = true
	help.fit_content = true
	help.scroll_active = false
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 80
	help.add_theme_constant_override("paragraph_separation", 6)
	help.modulate = Color(1, 1, 1, 0.85)
	controls.add_child(help)
	var lines: Array[String] = []
	for pair: Array in [
		["D", "Draw a polygon point by point (type a length + Enter for an exact side)"],
		["B", "Draw a rectangle (type width, Tab, depth, Enter for an exact size)"],
		["Esc", "While drawing: keep the polygon unfinished (red, saved with the scene); click either end to continue it, Delete over it to discard it. Otherwise: stop drawing / clear the selection"],
		["Click", "Select a sector (Shift+click adds)"],
		["Drag", "From a floor across rooms: box select (Shift adds). On a selected sector's corner or wall: reshape it (neighbours follow; Esc cancels)"],
		["Click wall", "Select just that wall (set its own height, or Delete to hide it as an opening)"],
		["Dbl-click", "On a selected sector's wall: add a corner there"],
		["Delete", "Hide the selected wall, remove the corner under the mouse, or delete the selected sectors"],
		["PgUp / PgDn", "Over a floor or ceiling (or Alt+wheel): raise / lower it one grid step"],
		["[lb] [rb]", "Smaller / larger grid"],
		["J", "Join the selected sectors into one"],
		["Ctrl+C / V", "Copy / paste sectors (R / E rotate, M mirrors while placing)"],
		["Alt+arrows", "Over a surface: move its texture"],
		["Ctrl+Shift+C / V", "Over a surface: copy / paste its texture alignment"],
		["Numpad 7, 5", "Top-down map view, then flat (orthographic)"],
	]:
		lines.append("[b]%s[/b]  %s" % [pair[0], pair[1]])
	help.text = "\n".join(lines)


func refresh() -> void:
	if not _built or editor == null:
		return
	var map := editor.map
	var units := editor.units
	var has_map := map != null and map.data != null
	_status.text = ("%s  ·  %d sector%s" % [map.name, map.data.sectors.size(), "" if map.data.sectors.size() == 1 else "s"]) if has_map \
		else "Select a Sector Map node, or create one:"
	_new_map.visible = not has_map
	_draw_section.visible = has_map
	_sel_label.visible = has_map
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
	_set_spin(_rotate_angle, editor.rotate_angle)
	_grid.clear()
	for step in DMUnits.GRID_STEPS:
		_grid.add_item(DMUnits.format(step, units))
	_grid.select(DMUnits.step_index(editor.grid_step))
	_units.select(units)

	var spins: Array[EditorSpinSlider] = [_floor, _ceiling, _def_floor, _def_ceiling, _rect_w, _rect_d, _width, _depth, _thick, _wall_bottom, _wall_top,
		_wall_length, _sector_thick, _wall_thick, _uv_offset_x, _uv_offset_y, _uv_size_x, _uv_size_y, _curve_bulge, _stair_step]
	for spin in spins:
		spin.suffix = DMUnits.suffix(units)

	var sel: Array[int] = []
	if has_map:
		sel = editor.tool.selected
	_sel_box.visible = not sel.is_empty()
	if sel.is_empty():
		_sel_label.text = "No sector selected"
	else:
		_sel_label.text = "%d sector%s selected" % [sel.size(), "" if sel.size() == 1 else "s"]
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
		_wall_section.visible = w != null
		if w != null:
			var o := s.wall_override(w.a, w.b)
			var outer := _is_outer_wall(map, w)
			_wall_hidden.set_pressed_no_signal(DMSector.setting_bool(o, "hidden"))
			_set_spin(_wall_length, DMUnits.to_display(w.a.distance_to(w.b), units))
			_length_anchor.select(editor.length_anchor)
			_show_row(_wall_bottom, outer)
			_show_row(_wall_top, outer)
			_show_row(_wall_thick, outer)
			_set_spin(_wall_thick, DMUnits.to_display(DMSector.setting_float(o, "thickness", s.wall_thickness), units))
			_wall_note.visible = not outer
			_set_spin(_wall_bottom, DMUnits.to_display(DMSector.setting_float(o, "bottom", s.floor_height), units))
			_set_spin(_wall_top, DMUnits.to_display(DMSector.setting_float(o, "top", s.ceiling_height), units))
		_show_row(_ceiling_mat, s.has_ceiling)
		_join.disabled = sel.size() < 2
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
		_make_stairs.text = "Make Stairs (%d steps)" % sel.size() if sel.size() >= 2 else "Make Stairs (Shift+click the steps)"
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


## Shows `v` unless the field is being typed in or dragged.
static func _set_spin(spin: EditorSpinSlider, v: float) -> void:
	if spin.get_meta("editing", false):
		return
	if not is_equal_approx(spin.value, v):
		spin.set_value_no_signal(v)


## A number field like the Inspector's (drag it sideways or click to type).
static func _spin(tip := "") -> EditorSpinSlider:
	var spin := EditorSpinSlider.new()
	spin.hide_slider = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.custom_minimum_size.x = 60
	spin.tooltip_text = tip
	spin.value_focus_entered.connect(func() -> void: spin.set_meta("editing", true))
	spin.value_focus_exited.connect(func() -> void: spin.set_meta("editing", false))
	spin.grabbed.connect(func() -> void: spin.set_meta("editing", true))
	spin.ungrabbed.connect(func() -> void: spin.set_meta("editing", false))
	return spin


## A length in the current units (shown with its suffix); `on_change` gets meters.
func _height_spin(on_change: Callable) -> EditorSpinSlider:
	var spin := _spin()
	spin.min_value = -100000.0
	spin.max_value = 100000.0
	spin.step = 0.001
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value_changed.connect(func(v: float) -> void:
		on_change.call(DMUnits.from_display(v, editor.units)))
	return spin


static func _angle_spin(tip: String) -> EditorSpinSlider:
	var spin := _spin(tip)
	spin.min_value = -360
	spin.max_value = 360
	spin.step = 0.1
	spin.suffix = "°"
	return spin


static func _int_spin(lo: int, hi: int) -> EditorSpinSlider:
	var spin := _spin()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = 1
	spin.editing_integer = true
	return spin


func _picker(on_change: Callable) -> EditorResourcePicker:
	var picker := EditorResourcePicker.new()
	picker.base_type = "Material"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.x = 60
	picker.resource_changed.connect(func(r: Resource) -> void: on_change.call(r))
	return picker


## A button that fills its row; `icon_name` is an editor icon (if it has one).
static func _button(text: String, tip: String, icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.clip_text = true
	b.custom_minimum_size.x = 40
	var theme := EditorInterface.get_editor_theme()
	if not icon_name.is_empty() and theme != null and theme.has_icon(icon_name, "EditorIcons"):
		b.icon = theme.get_icon(icon_name, "EditorIcons")
	return b


## A drop-down that can shrink with the dock instead of widening it.
static func _option(tip: String) -> OptionButton:
	var o := OptionButton.new()
	o.tooltip_text = tip
	o.theme_type_variation = &"EditorInspectorButton"
	o.fit_to_longest_item = false
	# The same dark field as the number fields (and the Inspector's drop-downs).
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_stylebox("normal", "LineEdit"):
		var field := theme.get_stylebox("normal", "LineEdit")
		var hover := field.duplicate() as StyleBox
		if hover is StyleBoxFlat:
			var flat := hover as StyleBoxFlat
			flat.bg_color = flat.bg_color.lightened(0.06)
		for state: String in ["normal", "disabled", "focus"]:
			o.add_theme_stylebox_override(state, field)
		for state: String in ["hover", "pressed", "hover_pressed"]:
			o.add_theme_stylebox_override(state, hover)
	o.clip_text = true
	o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size.x = 60
	return o


static func _check(text: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	return c


## Two controls side by side, sharing the row equally.
static func _pair(parent: Control, a: Control, b: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for c: Control in [a, b]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_stretch_ratio = 1.0
		row.add_child(c)
	parent.add_child(row)


## A two-column grid of labels and their controls, so the controls line up.
static func _grid_box(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	return grid


## A labelled row in a _grid_box. _show_row() shows or hides both.
static func _prop(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 76
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_color("property_color", "EditorProperty"):
		l.add_theme_color_override("font_color", theme.get_color("property_color", "EditorProperty"))
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.set_meta("row_label", l)
	grid.add_child(control)


static func _show_row(control: Control, on: bool) -> void:
	control.visible = on
	if control.has_meta("row_label"):
		var l: Label = control.get_meta("row_label")
		l.visible = on


## Small dimmed explanation text.
static func _hint(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 80
	l.modulate = Color(1, 1, 1, 0.55)
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_default_font_size():
		l.add_theme_font_size_override("font_size", maxi(theme.default_font_size - 2, 10))
	parent.add_child(l)
	return l


## A collapsible section; returns the box to put its contents in.
static func _section(parent: Control, title: String, folded: bool) -> VBoxContainer:
	var fold := FoldableContainer.new()
	fold.title = title
	fold.folded = folded
	_style_section(fold)
	parent.add_child(fold)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 2)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 6)
	fold.add_child(margin)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	margin.add_child(inner)
	return inner


## Gives a section header the Inspector's look: a light bar with bold text
## instead of the default dark title panel.
static func _style_section(fold: FoldableContainer) -> void:
	var theme := EditorInterface.get_editor_theme()
	fold.add_theme_stylebox_override("title_panel", _title_bar(0.06, true))
	fold.add_theme_stylebox_override("title_hover_panel", _title_bar(0.1, true))
	fold.add_theme_stylebox_override("title_collapsed_panel", _title_bar(0.06, false))
	fold.add_theme_stylebox_override("title_collapsed_hover_panel", _title_bar(0.1, false))
	var body := StyleBoxFlat.new()
	body.bg_color = Color(1, 1, 1, 0.02)
	body.corner_radius_bottom_left = 3
	body.corner_radius_bottom_right = 3
	fold.add_theme_stylebox_override("panel", body)
	if theme == null:
		return
	if theme.has_font("bold", "EditorFonts"):
		fold.add_theme_font_override("font", theme.get_font("bold", "EditorFonts"))
	if theme.has_color("font_color", "EditorInspectorSection"):
		var c := theme.get_color("font_color", "EditorInspectorSection")
		for item: String in ["font_color", "collapsed_font_color"]:
			fold.add_theme_color_override(item, c)
	var arrows := {"expanded_arrow": "GuiTreeArrowDown", "folded_arrow": "GuiTreeArrowRight"}
	for item: String in arrows:
		var icon_name: String = arrows[item]
		if theme.has_icon(icon_name, "EditorIcons"):
			fold.add_theme_icon_override(item, theme.get_icon(icon_name, "EditorIcons"))


## A section's title bar: a faint light fill, square at the bottom when open.
static func _title_bar(alpha: float, open: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, alpha)
	sb.set_corner_radius_all(3)
	if open:
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


static func _header(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	_bold(l)
	parent.add_child(l)
	return l


## A small heading inside a section.
static func _subheader(parent: Control, text: String) -> Label:
	var l := _header(parent, text)
	l.modulate = Color(1, 1, 1, 0.7)
	return l


static func _bold(l: Label) -> void:
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_font("bold", "EditorFonts"):
		l.add_theme_font_override("font", theme.get_font("bold", "EditorFonts"))
