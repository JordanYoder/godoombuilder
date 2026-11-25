# Simulated viewport input for the sector tool. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://test/tool_test.gd
extends SceneTree


## Stands in for the editor plugin (same methods the tool calls).
class FakePlugin:
	extends RefCounted
	var grid_step := 0.5
	var units := 0
	var map: DMMap
	var defaults := DMSector.new()
	var tool: DMTool
	var grid_shifts := 0
	func update_overlays() -> void: pass
	func on_tool_changed() -> void: pass
	func commit_loop(points: PackedVector2Array) -> Dictionary:
		var r := map.data.add_loop(points, defaults)
		map.rebuild()
		return r
	func nudge_heights(targets: Array[int], part: int, delta: float) -> void:
		for i in targets:
			if part == DMBuilder.Part.FLOOR:
				map.data.sectors[i].floor_height += delta
			else:
				map.data.sectors[i].ceiling_height += delta
		map.rebuild()
	func shift_grid(d: int) -> void: grid_shifts += d
	var notes: Array[String] = []
	func notify(msg: String, _severity := 0) -> void: notes.append(msg)
	var commits: Array[String] = []
	func commit_snapshot(action: String, _before: DMMapData) -> void:
		commits.append(action)
		map.rebuild()
	func delete_selected() -> void:
		map.data.delete_sectors(tool.selected)
		tool.selected.clear()
		map.rebuild()


var fails := 0
var cam: Camera3D
var tool: DMTool
var plugin: FakePlugin


static func rect2(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func screen(x: float, z: float, y := 0.0) -> Vector2:
	return cam.unproject_position(Vector3(x, y, z))


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	tool.handle_input(cam, e)


func click(p: Vector2, shift := false) -> int:
	move(p)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = p
	e.pressed = true
	e.shift_pressed = shift
	var r := tool.handle_input(cam, e)
	e = e.duplicate()
	e.pressed = false
	tool.handle_input(cam, e)
	return r


func mouse_button(p: Vector2, down: bool) -> int:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = p
	e.pressed = down
	return tool.handle_input(cam, e)


func drag_from_to(a: Vector2, b: Vector2) -> void:
	move(a)
	mouse_button(a, true)
	move(a.lerp(b, 0.5))
	move(b)
	mouse_button(b, false)


func type_text(text: String) -> void:
	for ch in text:
		var e := InputEventKey.new()
		e.keycode = KEY_PERIOD if ch == "." else (KEY_0 + int(ch)) as Key
		e.unicode = ch.unicode_at(0)
		e.pressed = true
		tool.handle_input(cam, e)


## Area of the last sector and whether it contains `p`.
func last_sector() -> DMSector:
	return tool.map.data.sectors[tool.map.data.sectors.size() - 1]


func key(code: Key) -> int:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return tool.handle_input(cam, e)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# A realistic editor-sized viewport (the headless window is tiny).
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 1000)
	vp.own_world_3d = true
	root.add_child(vp)
	cam = Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(4, 30, 4))
	var map := DMMap.new()
	map.data = DMMapData.new()
	vp.add_child(map)
	plugin = FakePlugin.new()
	plugin.map = map
	tool = DMTool.new()
	tool.plugin = plugin
	plugin.tool = tool
	tool.set_map(map)

	# Draw a room with D, four clicks slightly off-grid, and a click on the first point.
	check(key(KEY_D) == EditorPlugin.AFTER_GUI_INPUT_STOP and tool.mode == DMTool.Mode.DRAW, "D starts drawing")
	click(screen(0.1, 0.12))
	click(screen(5.9, 0.1))
	click(screen(6.1, 5.95))
	click(screen(0.05, 6.1))
	check(tool.points.size() == 4 and tool.points[1].is_equal_approx(Vector2(6, 0)), "clicks snap to the 0.5 m grid")
	click(screen(0.0, 0.0))
	check(map.data.sectors.size() == 1 and absf(map.data.sectors[0].area() - 36.0) < 0.01, "clicking the first point makes a 6x6 room")
	check(tool.mode == DMTool.Mode.SELECT and tool.selected == [0], "the new room is selected afterwards")

	# Draw a platform inside, finishing with Enter; it snaps to the room's corner.
	key(KEY_D)
	click(screen(0.15, 0.1))
	click(screen(2, 0))
	click(screen(2, 2))
	click(screen(0, 2))
	check(tool.points[0].is_equal_approx(Vector2(0, 0)), "first point snaps onto the room's corner")
	key(KEY_BACKSPACE)
	check(tool.points.size() == 3, "Backspace removes the last point")
	click(screen(0, 2))
	key(KEY_ENTER)
	check(map.data.sectors.size() == 2 and absf(map.data.sectors[1].area() - 4.0) < 0.01, "Enter finishes a 2x2 sector inside the room")

	# Clicking selects; Shift adds; clicking empty space clears.
	click(screen(4, 4))
	check(tool.selected == [0], "click selects the room")
	click(screen(1, 1), true)
	check(tool.selected.size() == 2, "Shift+click adds the platform")
	var r := click(screen(20, 20))
	check(tool.selected.is_empty() and r == EditorPlugin.AFTER_GUI_INPUT_PASS, "clicking outside clears and lets Godot handle the click")

	# Page Up over the platform raises its floor one grid step.
	move(screen(1, 1))
	key(KEY_PAGEUP)
	check(absf(map.data.sectors[1].floor_height - 0.5) < 1e-4, "Page Up raises the hovered floor by 0.5 m")
	check(absf(map.data.sectors[0].floor_height) < 1e-4, "the room's floor is unchanged")
	move(screen(1, 1, 0.5))
	key(KEY_PAGEDOWN)
	check(absf(map.data.sectors[1].floor_height) < 1e-4, "Page Down lowers it back")

	# Esc cancels drawing; brackets change the grid; Delete removes.
	key(KEY_D)
	click(screen(10, 10))
	key(KEY_ESCAPE)
	check(tool.mode == DMTool.Mode.SELECT and tool.points.is_empty() and map.data.sectors.size() == 2, "Esc cancels a drawing")
	key(KEY_BRACKETRIGHT)
	check(plugin.grid_shifts == 1, "] asks for a larger grid")
	click(screen(1, 1))
	key(KEY_DELETE)
	check(map.data.sectors.size() == 1, "Delete removes the selected sector")

	# Rectangle by two clicks.
	var count := map.data.sectors.size()
	check(key(KEY_B) == EditorPlugin.AFTER_GUI_INPUT_STOP and tool.mode == DMTool.Mode.RECT, "B starts a rectangle")
	click(screen(10, 0))
	click(screen(13, 3))
	check(map.data.sectors.size() == count + 1 and absf(last_sector().area() - 9.0) < 0.01, "two clicks make a 3x3 rectangle")

	# Rectangle with typed width and depth.
	key(KEY_B)
	click(screen(20, 0))
	type_text("4")
	key(KEY_TAB)
	type_text("2.5")
	key(KEY_ENTER)
	var rs := last_sector()
	check(absf(rs.area() - 10.0) < 0.01 and rs.contains_point(Vector2(23.9, 2.4)), "typed 4 Tab 2.5 Enter makes a 4 x 2.5 m room")

	# Typed width with the depth from the mouse, toward the mouse's side.
	key(KEY_B)
	click(screen(30, 5))
	type_text("2")
	move(screen(27, 3))
	click(screen(27, 3))
	rs = last_sector()
	check(absf(rs.area() - 4.0) < 0.01 and rs.contains_point(Vector2(28.1, 3.1)), "typed width + mouse depth, drawn toward the mouse")

	# Backspace clears typing; Esc first clears typing, then cancels.
	key(KEY_B)
	click(screen(40, 0))
	type_text("57")
	key(KEY_BACKSPACE)
	check(tool.typed == "5", "Backspace deletes a typed digit")
	key(KEY_ESCAPE)
	check(tool.typed == "" and tool.mode == DMTool.Mode.RECT, "Esc clears typing first")
	key(KEY_ESCAPE)
	check(tool.mode == DMTool.Mode.SELECT, "Esc again cancels the rectangle")

	# Freeform drawing with typed side lengths.
	key(KEY_D)
	click(screen(50, 0))
	move(screen(55, 0.2))
	type_text("3")
	key(KEY_ENTER)
	move(screen(53, 6))
	type_text("2")
	key(KEY_ENTER)
	move(screen(45, 2.3))
	type_text("3")
	key(KEY_ENTER)
	check(tool.points.size() == 4 and tool.points[2].is_equal_approx(Vector2(53, 2)), "typed lengths place exact points at right angles")
	key(KEY_ENTER)
	check(absf(last_sector().area() - 6.0) < 0.01, "Enter closes a typed 3 x 2 m shape")

	# Doom units: 64 x 32 du = 2 x 1 m.
	plugin.units = DMUnits.Units.DOOM
	key(KEY_B)
	click(screen(60, 0))
	type_text("64")
	key(KEY_TAB)
	type_text("32")
	key(KEY_ENTER)
	check(absf(last_sector().area() - 2.0) < 0.01, "in Doom units, 64 x 32 makes a 2 x 1 m room")
	plugin.units = DMUnits.Units.METERS

	# Typing numbers does nothing when not drawing.
	var e := InputEventKey.new()
	e.keycode = KEY_5
	e.unicode = "5".unicode_at(0)
	e.pressed = true
	check(tool.handle_input(cam, e) == EditorPlugin.AFTER_GUI_INPUT_PASS, "digits pass through when not drawing")

	# The overlay draws without errors.
	var overlay := Control.new()
	vp.add_child(overlay)
	click(screen(4, 4))
	key(KEY_D)
	click(screen(8, 8))
	move(screen(10, 8))
	overlay.draw.connect(func() -> void: tool.draw_overlay(overlay))
	overlay.size = Vector2(1600, 1000)
	var drawn := [0]
	overlay.draw.connect(func() -> void: drawn[0] += 1)
	overlay.queue_redraw()
	await process_frame
	await process_frame
	check(drawn[0] > 0, "overlay draws while drawing a sector")
	key(KEY_ESCAPE)
	click(screen(4, 4))
	move(screen(4, 4))
	overlay.queue_redraw()
	await process_frame
	check(drawn[0] > 1, "overlay draws selection and hover")
	key(KEY_B)
	click(screen(70, 0))
	type_text("3")
	move(screen(72, 2))
	overlay.queue_redraw()
	await process_frame
	check(drawn[0] > 2, "overlay draws a rectangle being typed")

	# --- Dragging corners and walls of a selected sector. ---
	var map2 := DMMap.new()
	map2.data = DMMapData.new()
	map2.position = Vector3(100, 0, 0)
	vp.add_child(map2)
	map2.data.add_loop(rect2(0, 0, 6, 6), DMSector.new())
	map2.data.add_loop(rect2(6, 0, 10, 6), DMSector.new())
	map2.rebuild()
	plugin.map = map2
	tool.set_map(map2)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(105, 25, 3))
	var w := func(x: float, z: float) -> Vector2: return cam.unproject_position(Vector3(100 + x, 0, z))
	click(w.call(3, 3))
	check(tool.selected == [0], "select the left room")
	move(w.call(0, 0))
	check(tool.handle.get("kind", "") == "vertex", "hovering a selected room's corner shows a corner handle")
	drag_from_to(w.call(0, 0), w.call(-2.1, 0.1))
	check(absf(map2.data.sectors[0].area() - 42.0) < 0.01 and plugin.commits.back() == "Move Corner",
		"dragging a corner reshapes the room (area %.2f)" % map2.data.sectors[0].area())
	drag_from_to(w.call(3, 6), w.call(3.1, 7.9))
	check(absf(map2.data.sectors[0].area() - (42.0 + 2.0 * 7.0)) < 0.01 and plugin.commits.back() == "Move Wall",
		"dragging a wall moves both its corners (area %.2f)" % map2.data.sectors[0].area())
	var neighbour_before := map2.data.sectors[1].area()
	drag_from_to(w.call(6, 0), w.call(7, 0))
	check(absf(map2.data.sectors[0].area() + map2.data.sectors[1].area() - (56.0 + neighbour_before)) < 0.01
		and map2.data.validate() == "", "dragging a shared corner stretches the neighbour too, with no gap")
	var areas := [map2.data.sectors[0].area(), map2.data.sectors[1].area()]
	drag_from_to(w.call(7, 0), w.call(12, 3))
	check(absf(map2.data.sectors[0].area() - areas[0]) < 0.01 and map2.data.validate() == ""
		and plugin.notes.back().begins_with("Can't move it there"), "a drag that would overlap is refused and undone")
	move(w.call(7, 0))
	mouse_button(w.call(7, 0), true)
	move(w.call(4, 2))
	key(KEY_ESCAPE)
	mouse_button(w.call(4, 2), false)
	check(absf(map2.data.sectors[0].area() - areas[0]) < 0.01 and tool.drag.is_empty(), "Esc cancels a drag")

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
