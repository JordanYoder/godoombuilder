# Headless tests for the viewport toolbar, with a stand-in plugin that records
# what the buttons ask for. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://test/toolbar_test.gd
extends SceneTree

var fails := 0


## The real editor with every action the toolbar calls only recorded.
class FakePlugin:
	extends DMEditor
	var calls: Array[String] = []
	func set_drawing(on: bool, rect := false) -> void:
		calls.append("draw %s %s" % [on, rect])
		if on:
			tool.mode = DMTool.Mode.RECT if rect else DMTool.Mode.DRAW
		else:
			tool.mode = DMTool.Mode.SELECT
	func join_selected() -> void: calls.append("join")
	func simplify_selected() -> void: calls.append("simplify")
	func thicken_selected() -> void: calls.append("thicken")
	func delete_selected() -> void: calls.append("delete")
	func set_wall_hidden(h: bool) -> void: calls.append("hide %s" % h)
	func set_selected_floor(on: bool) -> void: calls.append("floor %s" % on)
	func set_selected_ceiling(on: bool) -> void: calls.append("ceiling %s" % on)
	func set_grid_step(m: float) -> void:
		grid_step = m
		calls.append("grid %s" % m)
	func set_units(u: int) -> void:
		units = u as DMUnits.Units
		calls.append("units %d" % u)
	func copy_selected() -> void: calls.append("copy")
	func begin_paste() -> void: calls.append("paste")
	func transform_selected(kind: String) -> void: calls.append("transform " + kind)
	func split_selected_wall() -> void: calls.append("split wall")
	func curve_selected_wall() -> void: calls.append("curve wall")
	func make_stairs() -> void: calls.append("stairs")
	func split_into_steps() -> void: calls.append("split steps")


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var plugin := FakePlugin.new()
	plugin.map = DMMap.new()
	plugin.map.data = DMMapData.new()
	plugin.map.data.add_loop(PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)]), DMSector.new())
	plugin.map.data.add_loop(PackedVector2Array([Vector2(4, 0), Vector2(8, 0), Vector2(8, 4), Vector2(4, 4)]), DMSector.new())
	plugin.map.data.sectors[0].has_ceiling = false
	var bar := DMToolbar.new()
	bar.editor = plugin
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 10)
	panel.add_child(bar)
	root.add_child(panel)
	await process_frame

	check(bar.select_button.button_pressed and not bar.draw_button.button_pressed, "starts in Select")
	check(bar.join_button.disabled and bar.delete_button.disabled and bar.floor_check.disabled, "actions are off with nothing selected")
	bar.draw_button.emit_signal("pressed")
	bar.refresh()
	check(plugin.calls.back() == "draw true false" and bar.draw_button.button_pressed and not bar.select_button.button_pressed, "Draw starts drawing")
	bar.rect_button.emit_signal("pressed")
	bar.refresh()
	check(plugin.calls.back() == "draw true true" and bar.rect_button.button_pressed, "Rectangle starts a rectangle")
	bar.select_button.emit_signal("pressed")
	bar.refresh()
	check(plugin.calls.back() == "draw false false" and bar.select_button.button_pressed, "Select goes back to selecting")

	plugin.tool.selected = [0]
	bar.refresh()
	check(bar.join_button.disabled and not bar.simplify_button.disabled, "Join needs two sectors; Simplify works on one")
	check(bar.floor_check.button_pressed and not bar.ceiling_check.button_pressed, "Floor / Ceiling show the selected sector")
	plugin.tool.selected = [0, 1]
	bar.refresh()
	check(not bar.join_button.disabled, "Join is available with two selected")
	for b in [bar.join_button, bar.simplify_button, bar.thicken_button, bar.delete_button]:
		b.emit_signal("pressed")
	check(plugin.calls.slice(-4) == ["join", "simplify", "thicken", "delete"], "action buttons call the plugin")
	bar.ceiling_check.button_pressed = true
	check(plugin.calls.back() == "ceiling true", "Ceiling checkbox sets the selection's ceiling")
	plugin.tool.selected = [0]
	plugin.tool.selected_wall = DMTool.Wall.new(0, Vector2(0, 0), Vector2(4, 0))
	bar.refresh()
	check(bar.delete_button.text == "Hide Wall", "with a wall selected, Delete becomes Hide Wall")
	check(bar.thicken_button.text == "Thicken Wall", "with a wall selected, Thicken works on that wall")
	bar.delete_button.emit_signal("pressed")
	check(plugin.calls.back() == "hide true", "Hide Wall hides the selected wall")
	bar.grid.select(DMUnits.step_index(1.0))
	bar.grid.emit_signal("item_selected", DMUnits.step_index(1.0))
	check(plugin.grid_step == 1.0, "the grid menu sets the grid")
	bar.units.emit_signal("item_selected", 1)
	bar.refresh()
	check(plugin.units == 1 and bar.thickness.suffix == "du" and is_equal_approx(bar.thickness.value, 8.0),
		"Doom units: thickness shows 8 du (0.25 m)")
	bar.thickness.value = 16.0
	check(is_equal_approx(plugin.wall_thickness, 0.5), "typing 16 du sets 0.5 m thickness")

	# The Edit menu: each item calls its action; unusable ones are greyed out.
	var popup := bar.edit_menu.get_popup()
	var item_ids := {}
	for i in DMToolbar.EDIT_ACTIONS.size():
		if not DMToolbar.EDIT_ACTIONS[i].is_empty():
			item_ids[DMToolbar.EDIT_ACTIONS[i]] = i
	var disabled := func(action: String) -> bool: return popup.is_item_disabled(popup.get_item_index(item_ids[action]))
	plugin.tool.selected = [0]
	plugin.tool.selected_wall = null
	bar.refresh()
	check(disabled.call("paste") and disabled.call("split_wall") and disabled.call("stairs") and not disabled.call("split_steps")
		and not disabled.call("rotate_cw"), "Edit menu: paste needs a copy, wall items a wall, stairs two sectors")
	plugin.clipboard.append(DMSector.new())
	plugin.tool.selected = [0, 1]
	plugin.tool.selected_wall = null
	bar.refresh()
	check(not disabled.call("paste") and not disabled.call("stairs") and disabled.call("split_steps"), "Edit menu updates with the selection and clipboard")
	var expected := {"copy": "copy", "paste": "paste", "rotate_cw": "transform rotate_cw", "mirror_z": "transform mirror_z",
		"split_wall": "split wall", "curve_wall": "curve wall", "stairs": "stairs", "split_steps": "split steps"}
	var menu_ok := true
	for action in expected:
		popup.id_pressed.emit(item_ids[action])
		if plugin.calls.back() != expected[action]:
			menu_ok = false
			print("  menu item %s called %s" % [action, plugin.calls.back()])
	check(menu_ok, "every Edit menu item calls its action")

	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().get_region(Rect2i(0, 0, int(panel.size.x) + 20, int(panel.size.y) + 20)).save_png(
			"user://toolbar.png")
		print("saved toolbar.png to ", ProjectSettings.globalize_path("user://toolbar.png"))
	plugin.map.free()
	plugin.dispose()
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
