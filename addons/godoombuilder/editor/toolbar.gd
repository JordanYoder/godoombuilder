@tool
class_name DMToolbar
extends HBoxContainer
## The toolbar above the 3D viewport while a Sector Map is selected: tools,
## actions on the selection, and grid / units. The Sectors dock has the same
## actions plus every setting.


## The GoDoomBuilder EditorPlugin (untyped: it calls the plugin's own methods).
var plugin

var select_button: Button
var draw_button: Button
var rect_button: Button
var join_button: Button
var simplify_button: Button
var thicken_button: Button
var thickness: SpinBox
var delete_button: Button
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
	select_button.pressed.connect(func() -> void: plugin.set_drawing(false))
	draw_button = _button("Draw", "Draw a sector point by point (D). Type a length + Enter for an exact side.", true, tools)
	draw_button.pressed.connect(func() -> void: plugin.set_drawing(true, false))
	rect_button = _button("Rectangle", "Draw a rectangle (B). Type width, Tab, depth, Enter for an exact size.", true, tools)
	rect_button.pressed.connect(func() -> void: plugin.set_drawing(true, true))

	add_child(VSeparator.new())
	join_button = _button("Join", "Join the selected sectors into one (J).")
	join_button.pressed.connect(func() -> void: plugin.join_selected())
	simplify_button = _button("Simplify", "Remove points that don't change the selected sectors' shapes.")
	simplify_button.pressed.connect(func() -> void: plugin.simplify_selected())
	thicken_button = _button("Thicken", "Give the selected rooms' walls (or just the selected wall) this thickness. Direction is set in the Sectors panel.")
	thicken_button.pressed.connect(func() -> void: plugin.thicken_selected())
	thickness = SpinBox.new()
	thickness.min_value = 0.001
	thickness.max_value = 100000.0
	thickness.step = 0.001
	thickness.allow_greater = true
	thickness.select_all_on_focus = true
	thickness.custom_minimum_size.x = 84
	thickness.tooltip_text = "Wall thickness for Thicken."
	thickness.value_changed.connect(func(v: float) -> void:
		plugin.wall_thickness = DMUnits.from_display(v, plugin.units)
		plugin._save_settings())
	add_child(thickness)
	delete_button = _button("Delete", "Hide the selected wall, or delete the selected sectors (Delete).")
	delete_button.pressed.connect(_on_delete)

	add_child(VSeparator.new())
	floor_check = _check("Floor", "Selected sectors have a floor.")
	floor_check.toggled.connect(func(on: bool) -> void: plugin.set_selected_floor(on))
	ceiling_check = _check("Ceiling", "Selected sectors have a ceiling (off: open to the sky).")
	ceiling_check.toggled.connect(func(on: bool) -> void: plugin.set_selected_ceiling(on))

	add_child(VSeparator.new())
	grid = OptionButton.new()
	grid.flat = true
	grid.tooltip_text = "Grid snap size ([ and ] in the viewport)."
	grid.item_selected.connect(func(i: int) -> void: plugin.set_grid_step(DMUnits.GRID_STEPS[i]))
	add_child(grid)
	units = OptionButton.new()
	units.flat = true
	units.add_item("Meters")
	units.add_item("Doom units")
	units.tooltip_text = "How sizes are shown and typed (Doom units: 32 per meter)."
	units.item_selected.connect(func(i: int) -> void: plugin.set_units(i))
	add_child(units)


func refresh() -> void:
	if not _built or plugin == null:
		return
	var tool = plugin.tool
	var has_map: bool = plugin.map != null
	var mode: int = tool.mode
	select_button.set_pressed_no_signal(mode == DMTool.Mode.SELECT)
	draw_button.set_pressed_no_signal(mode == DMTool.Mode.DRAW)
	rect_button.set_pressed_no_signal(mode == DMTool.Mode.RECT)
	var sel: Array = tool.selected if has_map else []
	join_button.disabled = sel.size() < 2
	simplify_button.disabled = sel.is_empty()
	thicken_button.disabled = sel.is_empty()
	delete_button.disabled = sel.is_empty()
	delete_button.text = "Hide Wall" if not tool.selected_wall.is_empty() else "Delete"
	thicken_button.text = "Thicken Wall" if not tool.selected_wall.is_empty() else "Thicken"
	floor_check.disabled = sel.is_empty()
	ceiling_check.disabled = sel.is_empty()
	if not sel.is_empty():
		var s: DMSector = plugin.map.data.sectors[sel[0]]
		floor_check.set_pressed_no_signal(s.has_floor)
		ceiling_check.set_pressed_no_signal(s.has_ceiling)
	var u: int = plugin.units
	grid.clear()
	for step in DMUnits.GRID_STEPS:
		grid.add_item(DMUnits.format(step, u))
	grid.select(DMUnits.step_index(plugin.grid_step))
	units.select(u)
	thickness.suffix = DMUnits.suffix(u)
	thickness.custom_arrow_step = DMUnits.to_display(plugin.grid_step, u)
	if not thickness.get_line_edit().has_focus():
		thickness.set_value_no_signal(DMUnits.to_display(plugin.wall_thickness, u))


func _on_delete() -> void:
	if not plugin.tool.selected_wall.is_empty():
		plugin.set_wall_hidden(true)
	else:
		plugin.delete_selected()


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
