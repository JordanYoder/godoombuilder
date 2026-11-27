# Simulated viewport input for the sector tool. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://test/tool_test.gd
extends SceneTree


## The real editor, with undo steps and messages recorded instead of sent
## to Godot, and a few actions only counted.
class FakePlugin:
	extends DMEditor
	var grid_shifts := 0
	var notes: Array[String] = []
	var commits: Array[String] = []
	var joins := 0
	var hides := 0
	func _record_undo(action: String, _before: DMMapData, _after: DMMapData, _merge: bool) -> void:
		commits.append(action)
	func notify(msg: String, _severity := Severity.WARNING) -> void: notes.append(msg)
	func shift_grid(d: int) -> void: grid_shifts += d
	func set_wall_hidden(_h: bool) -> void: hides += 1
	func join_selected() -> void: joins += 1
	func copy_selected() -> void:
		super.copy_selected()
		commits.append("Copy")


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
	tool = plugin.tool
	plugin.set_map(map)

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

	# Stopping a polygon with 2+ points keeps it unfinished; either end continues it.
	key(KEY_D)
	click(screen(100, 0))
	click(screen(104, 0))
	click(screen(104, 4))
	key(KEY_ESCAPE)
	check(tool.mode == DMTool.Mode.SELECT and map.data.drafts.size() == 1 and map.data.drafts[0].points.size() == 3
		and plugin.commits.back() == "Keep Unfinished Polygon", "Esc keeps a 3-point polygon unfinished")
	check(map.data.duplicate_data().drafts.size() == 1, "undo snapshots include unfinished polygons")
	move(screen(104, 4))
	check(tool.draft_hover == 0 and tool.draft_hover_end == 1, "hovering its last point offers to continue it")
	click(screen(104, 4))
	check(tool.mode == DMTool.Mode.DRAW and tool.points.size() == 3 and tool.draft_index == 0, "clicking its end continues drawing it")
	click(screen(100, 4))
	click(screen(100, 0))
	check(map.data.sectors.size() == 3 and map.data.drafts.is_empty() and plugin.commits.back() == "Draw Sector",
		"closing it makes the sector and removes the unfinished polygon")
	map.data.delete_sectors([2])
	key(KEY_D)
	click(screen(110, 0))
	click(screen(114, 0))
	key(KEY_ESCAPE)
	var commits_now := plugin.commits.size()
	click(screen(110, 0))
	check(tool.mode == DMTool.Mode.DRAW and tool.points[tool.points.size() - 1].is_equal_approx(Vector2(110, 0)),
		"clicking its first point continues from that end")
	key(KEY_ESCAPE)
	check(map.data.drafts.size() == 1 and plugin.commits.size() == commits_now, "stopping again with nothing added changes nothing")
	key(KEY_D)
	click(screen(120, 0))
	key(KEY_ESCAPE)
	check(map.data.drafts.size() == 1, "a single point isn't kept")
	move(screen(112, 0))
	key(KEY_DELETE)
	check(map.data.drafts.is_empty() and plugin.commits.back() == "Discard Unfinished Polygon", "Delete over its side discards it")
	check(map.data.sectors.size() == 2, "...and deletes no sector")
	key(KEY_BRACKETRIGHT)
	check(plugin.grid_shifts == 1, "] asks for a larger grid")
	click(screen(1, 1))
	key(KEY_DELETE)
	check(map.data.sectors.size() == 1, "Delete removes the selected sector")

	# J joins when two or more sectors are selected.
	tool.selected = [0]
	check(key(KEY_J) == EditorPlugin.AFTER_GUI_INPUT_PASS and plugin.joins == 0, "J needs two selected sectors")
	tool.selected = [0, 1]
	check(key(KEY_J) == EditorPlugin.AFTER_GUI_INPUT_STOP and plugin.joins == 1, "J joins the selection")
	tool.selected = []

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
	plugin.set_map(map2)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(105, 25, 3))
	var w := func(x: float, z: float) -> Vector2: return cam.unproject_position(Vector3(100 + x, 0, z))
	click(w.call(3, 3))
	check(tool.selected == [0], "select the left room")
	move(w.call(0, 0))
	check(tool.handle != null and tool.handle.kind == DMTool.Handle.Kind.VERTEX, "hovering a selected room's corner shows a corner handle")
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
	check(absf(map2.data.sectors[0].area() - areas[0]) < 0.01 and tool.drag == null, "Esc cancels a drag")

	# Clicking a wall selects just that wall; Delete hides it.
	tool.selected = []
	cam.global_transform = Transform3D(Basis(), Vector3(102, 2, 3))
	click(cam.unproject_position(Vector3(102, 2, -10)))
	var wall_ok: bool = tool.selected_wall != null and tool.selected.size() == 1
	check(wall_ok, "clicking a wall selects that wall (%s)" % str(tool.selected_wall))
	if wall_ok:
		check(tool.selected_wall_faces().size() > 0, "the selected wall's faces are found for highlighting")
	key(KEY_DELETE)
	check(plugin.hides == 1, "Delete with a wall selected hides the wall instead of deleting the sector")
	# Typing a number with a wall selected sets its length.
	type_text("9")
	key(KEY_ESCAPE)
	check(tool.typed.is_empty() and tool.selected_wall != null, "Esc clears a typed wall length but keeps the wall selected")
	var kp := InputEventKey.new()
	kp.keycode = KEY_KP_7
	kp.unicode = "7".unicode_at(0)
	kp.pressed = true
	tool.handle_input(cam, kp)
	check(tool.typed.is_empty(), "keypad digits are left to Godot's view shortcuts")
	type_text("2")
	key(KEY_ENTER)
	var sw := tool.selected_wall
	check(sw != null and absf(sw.a.distance_to(sw.b) - 2.0) < 0.001 and plugin.commits.back() == "Set Wall Length"
		and map2.data.validate() == "", "typing 2 + Enter makes the selected wall 2 m long, and it stays selected")
	click(cam.unproject_position(Vector3(102, 0, 1)))
	check(tool.selected_wall == null and tool.selected.size() == 1, "clicking a floor selects the sector, not a wall")

	# Thick walls: outer corners and outer faces have handles.
	var map3 := DMMap.new()
	map3.data = DMMapData.new()
	map3.position = Vector3(200, 0, 0)
	vp.add_child(map3)
	map3.data.add_loop(rect2(0, 0, 4, 4), DMSector.new())
	map3.data.sectors[0].wall_thickness = 0.5
	map3.rebuild()
	plugin.set_map(map3)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(202, 14, 2))
	var w3 := func(x: float, z: float) -> Vector2: return cam.unproject_position(Vector3(200 + x, 0, z))
	click(w3.call(2, 2))
	check(tool.selected == [0], "select the thick-walled room")
	move(w3.call(-0.5, -0.5))
	check(tool.handle != null and tool.handle.kind == DMTool.Handle.Kind.OUTER_VERTEX, "the thick wall's outer corner has a handle")
	drag_from_to(w3.call(-0.5, -0.5), w3.call(-1.5, -1.0))
	var oc: Dictionary = map3.data.sectors[0].outer_corners
	check(oc.size() == 1 and (oc.values()[0] as Vector2).is_equal_approx(Vector2(-1.5, -1.0)) and plugin.commits.back() == "Move Wall Corner",
		"dragging the outer corner places it there (%s)" % str(oc))
	check(absf(map3.data.sectors[0].area() - 16.0) < 0.001, "the room itself doesn't change")
	move(w3.call(4.5, 2))
	check(tool.handle != null and tool.handle.kind == DMTool.Handle.Kind.OUTER_EDGE, "the thick wall's outer face has a handle")
	drag_from_to(w3.call(4.5, 2), w3.call(5.6, 2.3))
	var east := map3.data.sectors[0].wall_override(Vector2(4, 0), Vector2(4, 4))
	check(absf(float(east.get("thickness", -1)) - 1.5) < 0.001 and plugin.commits.back() == "Set Wall Thickness",
		"dragging the outer face out makes that wall 1.5 m thick (snapped)")
	drag_from_to(w3.call(5.5, 2), w3.call(3.0, 2))
	east = map3.data.sectors[0].wall_override(Vector2(4, 0), Vector2(4, 4))
	check(absf(float(east.get("thickness", -1))) < 0.001, "dragging it all the way in makes the wall thin")
	move(w3.call(-0.5, -0.5))
	mouse_button(w3.call(-0.5, -0.5), true)
	move(w3.call(-3, -3))
	key(KEY_ESCAPE)
	mouse_button(w3.call(-3, -3), false)
	check((map3.data.sectors[0].outer_corners.values()[0] as Vector2).is_equal_approx(Vector2(-1.5, -1.0)), "Esc cancels an outer-corner drag")
	# Copy, paste (rotated), double-click to add a corner, Delete to remove it.
	var map4 := DMMap.new()
	map4.position = Vector3(300, 0, 0)
	map4.data = DMMapData.new()
	vp.add_child(map4)
	map4.data.add_loop(rect2(0, 0, 4, 2), DMSector.new())
	map4.data.sectors[0].floor_height = 0.5
	map4.rebuild()
	plugin.set_map(map4)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(305, 20, 4))
	var w4 := func(x: float, z: float) -> Vector2: return cam.unproject_position(Vector3(300 + x, 0.5, z))
	click(w4.call(2, 1))
	check(tool.selected == [0], "select the room to copy")
	var ctrl_key := func(code: Key) -> int:
		var ke := InputEventKey.new()
		ke.keycode = code
		ke.ctrl_pressed = true
		ke.pressed = true
		return tool.handle_input(cam, ke)
	ctrl_key.call(KEY_C)
	check(plugin.clipboard.size() == 1, "Ctrl+C copies the selection")
	ctrl_key.call(KEY_V)
	check(tool.mode == DMTool.Mode.PASTE, "Ctrl+V starts placing the copy")
	key(KEY_R)
	move(w4.call(6, 0))
	overlay.queue_redraw()
	await process_frame
	click(w4.call(6, 0))
	check(tool.mode == DMTool.Mode.SELECT and map4.data.sectors.size() == 2 and plugin.commits.back() == "Paste Sectors",
		"clicking places the copy")
	var pasted_box := map4.data.bounds_of([1])
	check(pasted_box.position.is_equal_approx(Vector2(6, 0)) and pasted_box.size.is_equal_approx(Vector2(2, 4)) and tool.selected == [1],
		"R turned it 90° before placing, its corner at the cursor; the copy is selected")
	check(map4.data.sectors[1].floor_height == 0.5, "the copy keeps its floor height")
	ctrl_key.call(KEY_V)
	key(KEY_ESCAPE)
	check(tool.mode == DMTool.Mode.SELECT and map4.data.sectors.size() == 2, "Esc cancels a paste")
	# Double-click the selected room's wall to add a corner on the grid.
	click(w4.call(2, 1))
	var wall_point: Vector2 = w4.call(1.0, 2.0)
	move(wall_point)
	check(tool.handle != null and tool.handle.kind == DMTool.Handle.Kind.EDGE, "hovering the selected room's wall shows its handle")
	click(wall_point)
	var dbl := InputEventMouseButton.new()
	dbl.button_index = MOUSE_BUTTON_LEFT
	dbl.position = wall_point
	dbl.pressed = true
	dbl.double_click = true
	tool.handle_input(cam, dbl)
	mouse_button(wall_point, false)
	var has_new := false
	for v in map4.data.sectors[0].polygons[0]:
		if v.is_equal_approx(Vector2(1, 2)):
			has_new = true
	check(has_new and plugin.commits.back() == "Split Wall", "double-clicking a wall adds a corner there")
	move(w4.call(1.0, 2.0))
	check(tool.handle != null and tool.handle.kind == DMTool.Handle.Kind.VERTEX, "the new corner has a handle")
	key(KEY_DELETE)
	check(map4.data.sectors[0].polygons[0].size() == 4 and plugin.commits.back() == "Remove Corner" and map4.data.sectors.size() == 2,
		"Delete over a corner removes just the corner")
	var del := InputEventKey.new()
	del.keycode = KEY_DELETE
	del.pressed = true
	tool.handle_input(cam, del)
	var rep := del.duplicate() as InputEventKey
	rep.echo = true
	tool.handle_input(cam, rep)
	key(KEY_DELETE)
	check(map4.data.sectors.size() == 2 and plugin.commits.back() == "Remove Corner",
		"pressing Delete again (or holding it) where the corner was doesn't delete the sector")

	# Box select: drag from a floor across the rooms (the left mouse held).
	var box_drag := func(a: Vector2, b: Vector2, shift: bool, cancel: bool) -> void:
		move(a)
		var down := InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.position = a
		down.pressed = true
		down.shift_pressed = shift
		tool.handle_input(cam, down)
		for t: float in [0.3, 0.7, 1.0]:
			var mm := InputEventMouseMotion.new()
			mm.position = a.lerp(b, t)
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
			tool.handle_input(cam, mm)
		if cancel:
			key(KEY_ESCAPE)
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.position = b
		tool.handle_input(cam, up)
	box_drag.call(w4.call(0.5, 0.5), w4.call(9, 5), false, false)
	check(tool.selected.size() == 2 and tool.selected.has(0) and tool.selected.has(1) and not tool.box_active,
		"dragging from a floor across both rooms box-selects them")
	click(w4.call(2, 1))
	box_drag.call(w4.call(6.5, 0.5), w4.call(9, 5), true, false)
	check(tool.selected.size() == 2, "Shift+drag adds the boxed rooms to the selection")
	click(w4.call(2, 1))
	box_drag.call(w4.call(2, 1), w4.call(2, 1) + Vector2(3, 2), false, false)
	check(tool.selected == [0], "a small wobble while clicking is still a click")
	box_drag.call(w4.call(2.5, 1.5), w4.call(9, 5), false, true)
	check(tool.selected == [0] and not tool.box_active, "Esc cancels a box select")

	# Texture tools over the surface under the mouse.
	click(w4.call(2, 1))
	move(w4.call(2, 1))
	var alt_key := func(code: Key, shift := false) -> int:
		var ke := InputEventKey.new()
		ke.keycode = code
		ke.alt_pressed = true
		ke.shift_pressed = shift
		ke.pressed = true
		return tool.handle_input(cam, ke)
	var r_alt: int = alt_key.call(KEY_RIGHT)
	check(r_alt == EditorPlugin.AFTER_GUI_INPUT_STOP and map4.data.sectors[0].floor_uv_offset.is_equal_approx(Vector2(-0.5, 0))
		and plugin.commits.back() == "Move Texture", "Alt+Right over a floor moves its texture one grid step")
	alt_key.call(KEY_UP, true)
	check(map4.data.sectors[0].floor_uv_offset.is_equal_approx(Vector2(-0.5, 0.0625)), "Alt+Shift+Up moves it an eighth of a step")
	check(map4.data.sectors[1].floor_uv_offset == Vector2.ZERO, "the other room's texture stays")
	var cs_key := func(code: Key) -> int:
		var ke := InputEventKey.new()
		ke.keycode = code
		ke.ctrl_pressed = true
		ke.shift_pressed = true
		ke.pressed = true
		return tool.handle_input(cam, ke)
	cs_key.call(KEY_C)
	move(w4.call(7, 2))
	cs_key.call(KEY_V)
	check(map4.data.sectors[1].floor_uv_offset.is_equal_approx(Vector2(-0.5, 0.0625)) and plugin.commits.back() == "Paste Texture Alignment",
		"Ctrl+Shift+C / V copy one floor's alignment onto another")
	overlay.queue_redraw()
	await process_frame

	plugin.dispose()
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
