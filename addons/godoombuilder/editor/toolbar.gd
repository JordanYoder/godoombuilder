@tool
class_name DMToolbar
extends HBoxContainer
## The toolbar above the 3D viewport while a Sector Map is selected: tools,
## actions on the selection, and grid / units. The Sectors dock has the same
## actions plus every setting.


## What the buttons edit (the GoDoomBuilder editor).
var editor: DMEditor

var select_button: Button
var draw_button: Button
var rect_button: Button
var join_button: Button
var simplify_button: Button
var thicken_button: Button
var thickness: SpinBox
var delete_button: Button
var edit_menu: MenuButton
var floor_check: CheckBox
var ceiling_check: CheckBox
var grid: OptionButton
var units: OptionButton

var _built := false


func _ready() -> void:
	build()
	refresh()


func build() -> void:
	if _built:
		return
	_built = true
	add_child(VSeparator.new())
	var tools := ButtonGroup.new()
	select_button = _button("Select", "Select sectors and walls, drag corners and walls (Esc).", true, tools)
	select_button.pressed.connect(func() -> void: editor.set_drawing(false))
	draw_button = _button("Draw", "Draw a sector point by point (D). Type a length + Enter for an exact side.", true, tools)
	draw_button.pressed.connect(func() -> void: editor.set_drawing(true, false))
	rect_button = _button("Rectangle", "Draw a rectangle (B). Type width, Tab, depth, Enter for an exact size.", true, tools)
	rect_button.pressed.connect(func() -> void: editor.set_drawing(true, true))

	add_child(VSeparator.new())
	join_button = _button("Join", "Join the selected sectors into one (J).")
	join_button.pressed.connect(func() -> void: editor.join_selected())
	simplify_button = _button("Simplify", "Remove points that don't change the selected sectors' shapes.")
	simplify_button.pressed.connect(func() -> void: editor.simplify_selected())
	thicken_button = _button("Thicken", "Give the selected rooms' walls (or just the selected wall) this thickness. Direction is set in the Sectors panel.")
	thicken_button.pressed.connect(func() -> void: editor.thicken_selected())
	thickness = SpinBox.new()
	thickness.min_value = 0.001
	thickness.max_value = 100000.0
	thickness.step = 0.001
	thickness.allow_greater = true
	thickness.select_all_on_focus = true
	thickness.custom_minimum_size.x = 84
	thickness.tooltip_text = "Wall thickness for Thicken."
	thickness.value_changed.connect(func(v: float) -> void:
		editor.wall_thickness = DMUnits.from_display(v, editor.units)
		editor.save_settings())
	add_child(thickness)
	delete_button = _button("Delete", "Hide the selected wall, or delete the selected sectors (Delete).")
	delete_button.pressed.connect(_on_delete)
	edit_menu = MenuButton.new()
	edit_menu.text = "Edit"
	edit_menu.flat = true
	edit_menu.tooltip_text = "Copy / paste, rotate and mirror the selection, split or curve the selected wall, stairs."
	var popup := edit_menu.get_popup()
	for i in EDIT_ACTIONS.size():
		if EDIT_ACTIONS[i].is_empty():
			popup.add_separator()
		else:
			popup.add_item(EDIT_LABELS[i], i)
	popup.id_pressed.connect(_on_edit)
	add_child(edit_menu)

	add_child(VSeparator.new())
	floor_check = _check("Floor", "Selected sectors have a floor.")
	floor_check.toggled.connect(func(on: bool) -> void: editor.set_selected_floor(on))
	ceiling_check = _check("Ceiling", "Selected sectors have a ceiling (off: open to the sky).")
	ceiling_check.toggled.connect(func(on: bool) -> void: editor.set_selected_ceiling(on))

	add_child(VSeparator.new())
	grid = OptionButton.new()
	grid.flat = true
	grid.tooltip_text = "Grid snap size ([ and ] in the viewport)."
	grid.item_selected.connect(func(i: int) -> void: editor.set_grid_step(DMUnits.GRID_STEPS[i]))
	add_child(grid)
	units = OptionButton.new()
	units.flat = true
	units.add_item("Meters")
	units.add_item("Doom units")
	units.tooltip_text = "How sizes are shown and typed (Doom units: 32 per meter)."
	units.item_selected.connect(func(i: int) -> void: editor.set_units(i))
	add_child(units)


func refresh() -> void:
	if not _built or editor == null:
		return
	var tool := editor.tool
	var has_map := editor.map != null
	var mode := tool.mode
	select_button.set_pressed_no_signal(mode == DMTool.Mode.SELECT)
	draw_button.set_pressed_no_signal(mode == DMTool.Mode.DRAW)
	rect_button.set_pressed_no_signal(mode == DMTool.Mode.RECT)
	var sel: Array[int] = []
	if has_map:
		sel = tool.selected
	join_button.disabled = sel.size() < 2
	simplify_button.disabled = sel.is_empty()
	thicken_button.disabled = sel.is_empty()
	delete_button.disabled = sel.is_empty()
	delete_button.text = "Hide Wall" if tool.selected_wall != null else "Delete"
	thicken_button.text = "Thicken Wall" if tool.selected_wall != null else "Thicken"
	floor_check.disabled = sel.is_empty()
	_refresh_edit_menu(sel, tool.selected_wall != null)
	ceiling_check.disabled = sel.is_empty()
	if not sel.is_empty():
		var s := editor.map.data.sectors[sel[0]]
		floor_check.set_pressed_no_signal(s.has_floor)
		ceiling_check.set_pressed_no_signal(s.has_ceiling)
	var u := editor.units
	grid.clear()
	for step in DMUnits.GRID_STEPS:
		grid.add_item(DMUnits.format(step, u))
	grid.select(DMUnits.step_index(editor.grid_step))
	units.select(u)
	thickness.suffix = DMUnits.suffix(u)
	thickness.custom_arrow_step = DMUnits.to_display(editor.grid_step, u)
	if not thickness.get_line_edit().has_focus():
		thickness.set_value_no_signal(DMUnits.to_display(editor.wall_thickness, u))


## Edit menu: each item's label and action ("" for both: a separator).
const EDIT_LABELS: Array[String] = [
	"Copy  (Ctrl+C)", "Paste  (Ctrl+V)", "Save Selection as Prefab…", "Paste Prefab…", "",
	"Rotate 90° Clockwise", "Rotate 90° Counter-clockwise", "Rotate by Angle",
	"Mirror X (left-right)", "Mirror Z (front-back)", "",
	"Select Same Floor Height", "Select Same Ceiling Height", "Select Same Floor Material", "Select Same Wall Material", "",
	"Split Selected Wall", "Curve Selected Wall", "",
	"Make Stairs (selection order)", "Split into Steps",
]
const EDIT_ACTIONS: Array[String] = [
	"copy", "paste", "save_prefab", "load_prefab", "",
	"rotate_cw", "rotate_ccw", "rotate_angle",
	"mirror_x", "mirror_z", "",
	"similar_floor_height", "similar_ceiling_height", "similar_floor_material", "similar_wall_material", "",
	"split_wall", "curve_wall", "",
	"stairs", "split_steps",
]


func _on_edit(id: int) -> void:
	var action := EDIT_ACTIONS[id]
	match action:
		"copy": editor.copy_selected()
		"paste": editor.begin_paste()
		"split_wall": editor.split_selected_wall()
		"curve_wall": editor.curve_selected_wall()
		"stairs": editor.make_stairs()
		"split_steps": editor.split_into_steps()
		"save_prefab": editor.ask_save_prefab()
		"load_prefab": editor.ask_load_prefab()
		_:
			if action.begins_with("similar_"):
				editor.select_similar(action.trim_prefix("similar_"))
			else:
				editor.transform_selected(action)


func _refresh_edit_menu(sel: Array[int], wall: bool) -> void:
	var popup := edit_menu.get_popup()
	for i in EDIT_ACTIONS.size():
		var action := EDIT_ACTIONS[i]
		if action.is_empty():
			continue
		var idx := popup.get_item_index(i)
		var off := sel.is_empty()
		match action:
			"paste": off = editor.clipboard.is_empty()
			"split_wall", "curve_wall": off = not wall
			"stairs": off = sel.size() < 2
			"split_steps": off = sel.size() != 1
			"save_prefab": off = sel.is_empty() and editor.clipboard.is_empty()
			"load_prefab": off = false
			"rotate_angle":
				popup.set_item_text(idx, "Rotate by %s°" % str(snappedf(editor.rotate_angle, 0.01)))
		popup.set_item_disabled(idx, off)


func _on_delete() -> void:
	if editor.tool.selected_wall != null:
		editor.set_wall_hidden(true)
	else:
		editor.delete_selected()


func _button(text: String, tip: String, toggle := false, group: ButtonGroup = null) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if toggle:
		b.toggle_mode = true
		b.button_group = group
	add_child(b)
	return b


func _check(text: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	add_child(c)
	return c
