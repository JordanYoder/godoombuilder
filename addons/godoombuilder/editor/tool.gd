@tool
class_name DMTool
extends RefCounted
## Viewport interaction for a selected sector map: select sectors, draw new
## ones (freeform or as rectangles, with typed sizes), and raise or lower
## floors and ceilings.


enum Mode { SELECT, DRAW, RECT }

## Characters accepted when typing a size while drawing.
const TYPED_CHARS := "0123456789."

## Screen distance (px) within which the cursor snaps to an existing vertex.
const SNAP_PX := 12.0
## Screen distance (px) within which clicking the first point closes the shape.
const CLOSE_PX := 14.0
## Screen distance (px) for grabbing a corner or wall of a selected sector.
const HANDLE_PX := 9.0
const EDGE_PX := 6.0

const COLOR_SELECTED := Color(1.0, 0.75, 0.2)
const COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.55)
const COLOR_DRAW := Color(0.35, 0.85, 1.0)
const COLOR_CLOSE := Color(0.4, 1.0, 0.45)
const COLOR_BAD := Color(1.0, 0.3, 0.25)

## The GoDoomBuilder EditorPlugin (untyped: it calls the plugin's own methods).
var plugin
var map: DMMap
var mode := Mode.SELECT
var selected: Array[int] = []
var hover := {}
var points := PackedVector2Array()
var draw_height := 0.0
var cursor := Vector2.ZERO
var cursor_valid := false
var camera: Camera3D
var mouse_pos := Vector2.ZERO

## Number being typed while drawing (in display units), or "".
var typed := ""
## Rectangle drawing: first corner, and whether it has been placed.
var rect_anchor := Vector2.ZERO
var rect_started := false
## Rectangle field being typed: 0 = width (X), 1 = depth (Z).
var rect_field := 0
## Fixed rectangle size in meters per axis; negative follows the mouse.
var rect_size := Vector2(-1.0, -1.0)

## The single wall picked by clicking it: {sector, a, b} (a, b: the sector
## polygon edge), or {}. Its sector is the only selected sector.
var selected_wall := {}

## Corner or wall of a selected sector under the mouse:
## {kind: "vertex"|"edge", a, b (Vector2), h (float)} or {}.
var handle := {}
## Active corner/wall drag (see _start_drag), or {}.
var drag := {}

var _consume_release := false


func set_map(m: DMMap) -> void:
	if m == map:
		return
	cancel_drag()
	cancel_draw()
	selected.clear()
	hover = {}
	handle = {}
	map = m


func validate_selection() -> void:
	var count := map.data.sectors.size() if map != null and map.data != null else 0
	var keep: Array[int] = []
	for i in selected:
		if i < count and not keep.has(i):
			keep.append(i)
	selected = keep
	if not selected_wall.is_empty() and (selected != [int(selected_wall.sector)]):
		selected_wall = {}
	if not hover.is_empty() and int(hover.sector) >= count:
		hover = {}


func begin_draw(rectangle := false) -> void:
	if map == null:
		return
	_reset_draw_state()
	mode = Mode.RECT if rectangle else Mode.DRAW
	if not selected.is_empty():
		draw_height = map.data.sectors[selected[0]].floor_height
	_changed()


func cancel_draw() -> void:
	_reset_draw_state()
	mode = Mode.SELECT
	_changed()


func is_drawing() -> bool:
	return mode != Mode.SELECT


func _reset_draw_state() -> void:
	points.clear()
	typed = ""
	rect_started = false
	rect_field = 0
	rect_size = Vector2(-1.0, -1.0)


## Sets a rectangle side from the dock (meters; 0 or less follows the mouse).
func set_rect_size(field: int, meters: float) -> void:
	rect_size[field] = meters if meters > 0.0 else -1.0
	if field == rect_field:
		typed = ""
	_changed()


## Height of the plane the grid is shown on.
func grid_height() -> float:
	if map == null or map.data == null:
		return 0.0
	if is_drawing():
		return draw_height
	if not selected.is_empty():
		return map.data.sectors[selected[0]].floor_height
	return draw_height


func handle_input(cam: Camera3D, event: InputEvent) -> int:
	camera = cam
	if map == null or map.data == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	# Right mouse is Godot's fly camera; leave it alone.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
		if not drag.is_empty():
			_update_drag()
			plugin.update_overlays()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		_update_hover()
		plugin.update_overlays()
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		mouse_pos = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_update_hover()
				if mode == Mode.DRAW:
					_draw_click()
					_consume_release = true
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if mode == Mode.RECT:
					_rect_click()
					_consume_release = true
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if not handle.is_empty() and not mb.shift_pressed:
					_start_drag()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				return _select_click(mb.shift_pressed)
			if not drag.is_empty():
				_end_drag()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if _consume_release:
				_consume_release = false
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if mb.pressed and mb.alt_pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_update_hover()
			if _nudge_hovered(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1):
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventKey and (event as InputEventKey).pressed:
		return _key(event as InputEventKey)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _key(k: InputEventKey) -> int:
	var plain := not (k.ctrl_pressed or k.alt_pressed or k.meta_pressed)
	# Typing a size while drawing.
	if is_drawing() and plain and k.unicode > 0 and TYPED_CHARS.contains(char(k.unicode)):
		var ch := char(k.unicode)
		if not (ch == "." and typed.contains(".")):
			typed += ch
		_changed()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	match k.keycode:
		KEY_D, KEY_B:
			if plain and not k.shift_pressed and not k.echo:
				var want := Mode.RECT if k.keycode == KEY_B else Mode.DRAW
				if mode == want:
					cancel_draw()
				else:
					begin_draw(want == Mode.RECT)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_TAB:
			if mode == Mode.RECT:
				_store_typed()
				rect_field = 1 - rect_field
				_changed()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_ESCAPE:
			if not drag.is_empty():
				cancel_drag()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if is_drawing():
				if not typed.is_empty():
					typed = ""
					_changed()
				else:
					cancel_draw()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if not selected.is_empty():
				selected.clear()
				_changed()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_ENTER, KEY_KP_ENTER:
			if mode == Mode.DRAW:
				if not typed.is_empty():
					_place_typed_point()
				elif points.size() >= 3:
					_finish()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if mode == Mode.RECT:
				if rect_started:
					_store_typed()
					_finish_rect()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_BACKSPACE:
			if is_drawing() and not typed.is_empty():
				typed = typed.left(-1)
				_changed()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if mode == Mode.DRAW and not points.is_empty():
				points.remove_at(points.size() - 1)
				_changed()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if mode == Mode.RECT:
				if rect_size[rect_field] > 0.0:
					rect_size[rect_field] = -1.0
				else:
					rect_started = false
				_changed()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_J:
			if mode == Mode.SELECT and plain and not k.shift_pressed and not k.echo and selected.size() >= 2:
				plugin.join_selected()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_DELETE:
			if mode == Mode.SELECT and not selected_wall.is_empty() and plain:
				plugin.set_wall_hidden(true)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if mode == Mode.SELECT and not selected.is_empty() and plain:
				plugin.delete_selected()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_PAGEUP, KEY_PAGEDOWN:
			if plain and _nudge_hovered(1 if k.keycode == KEY_PAGEUP else -1):
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			if plain and not k.echo:
				plugin.shift_grid(-1 if k.keycode == KEY_BRACKETLEFT else 1)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _select_click(additive: bool) -> int:
	if hover.is_empty():
		if not additive and not selected.is_empty():
			selected.clear()
			_changed()
		# Let Godot handle clicks on empty space (select other nodes, etc.).
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var s := int(hover.sector)
	selected_wall = {}
	if additive:
		if selected.has(s):
			selected.erase(s)
		else:
			selected.append(s)
	else:
		selected = [s]
		if int(hover.part) == DMBuilder.Part.WALL:
			var fe: PackedVector2Array = map.build_info.face_edge
			var f := int(hover.face)
			selected_wall = {"sector": s, "a": fe[f * 2], "b": fe[f * 2 + 1]}
	_consume_release = true
	_changed()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


## Raises (dir 1) or lowers (dir -1) the hovered floor or ceiling by one grid
## step. When the hovered sector is selected, all selected sectors move.
func _nudge_hovered(dir: int) -> bool:
	if hover.is_empty() or int(hover.part) == DMBuilder.Part.WALL:
		return false
	var s := int(hover.sector)
	var targets: Array[int] = []
	if selected.has(s):
		targets.assign(selected)
	else:
		targets.append(s)
	plugin.nudge_heights(targets, int(hover.part), dir * plugin.grid_step)
	_update_hover()
	return true


func _draw_click() -> void:
	_update_cursor()
	if not cursor_valid:
		return
	if points.size() >= 3 and _near_first():
		_finish()
		return
	if not points.is_empty() and points[points.size() - 1].distance_to(cursor) < DMGeo.SNAP:
		return
	points.append(cursor)
	_changed()


func _finish() -> void:
	var result: Dictionary = plugin.commit_loop(points)
	if result.ok:
		_reset_draw_state()
		mode = Mode.SELECT
		selected = [int(result.index)]
	elif mode == Mode.RECT:
		points.clear()
	_changed()


## The typed number in meters, or -1 when nothing usable is typed.
func typed_meters() -> float:
	if typed.is_empty() or typed == ".":
		return -1.0
	return DMUnits.from_display(typed.to_float(), plugin.units)


## Freeform drawing: where a typed length would put the next point, or null.
func typed_point() -> Variant:
	var length := typed_meters()
	if mode != Mode.DRAW or points.is_empty() or length <= 0.0:
		return null
	var last := points[points.size() - 1]
	var dir := cursor - last
	var angle := 0.0 if dir.length() < 1e-6 else dir.angle()
	if not Input.is_key_pressed(KEY_SHIFT):
		angle = snappedf(angle, deg_to_rad(15.0))
	var p := last + Vector2.from_angle(angle) * length
	return Vector2(snappedf(p.x, DMGeo.SNAP), snappedf(p.y, DMGeo.SNAP))


func _place_typed_point() -> void:
	var p = typed_point()
	typed = ""
	if p != null:
		points.append(p)
	elif points.is_empty():
		plugin.notify("Click the first point, then type the length of each side.")
	_changed()


func _store_typed() -> void:
	var v := typed_meters()
	if v > 0.0:
		rect_size[rect_field] = v
	typed = ""


## Rectangle size along one axis: typed, fixed, or following the mouse.
func _rect_side(field: int, mouse_value: float) -> float:
	if field == rect_field and typed_meters() > 0.0:
		return typed_meters()
	if rect_size[field] > 0.0:
		return rect_size[field]
	return mouse_value


## The rectangle corner opposite the anchor, toward the mouse.
func rect_corner() -> Vector2:
	var d := cursor - rect_anchor
	var w := _rect_side(0, absf(d.x))
	var h := _rect_side(1, absf(d.y))
	return rect_anchor + Vector2(w * (-1.0 if d.x < 0.0 else 1.0), h * (-1.0 if d.y < 0.0 else 1.0))


func _rect_click() -> void:
	_update_cursor()
	if not cursor_valid:
		return
	if not rect_started:
		rect_anchor = cursor
		rect_started = true
		_changed()
		return
	_store_typed()
	_finish_rect()


func _finish_rect() -> void:
	var a := rect_anchor
	var c := rect_corner()
	if absf(c.x - a.x) < DMGeo.SNAP or absf(c.y - a.y) < DMGeo.SNAP:
		plugin.notify("Give the rectangle a width and a depth first (move the mouse or type them).")
		return
	points = PackedVector2Array([a, Vector2(c.x, a.y), c, Vector2(a.x, c.y)])
	_finish()


func _near_first() -> bool:
	if points.is_empty():
		return false
	if cursor.distance_to(points[0]) < DMGeo.SNAP:
		return true
	var sp = _screen(Vector3(points[0].x, draw_height, points[0].y))
	return sp != null and (sp as Vector2).distance_to(mouse_pos) <= CLOSE_PX


func _update_hover() -> void:
	if camera == null or map == null:
		hover = {}
		return
	hover = map.pick(camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos))
	handle = _find_handle() if mode == Mode.SELECT else {}
	if is_drawing():
		var started := rect_started if mode == Mode.RECT else not points.is_empty()
		if not started and not hover.is_empty() and int(hover.part) == DMBuilder.Part.FLOOR:
			draw_height = map.data.sectors[int(hover.sector)].floor_height
		_update_cursor()


func _update_cursor() -> void:
	cursor_valid = false
	if camera == null or map == null:
		return
	var xf := map.map_transform()
	var plane := xf * Plane(Vector3.UP, draw_height)
	var hit = plane.intersects_ray(camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos))
	if hit == null:
		return
	var local: Vector3 = xf.affine_inverse() * (hit as Vector3)
	var extra := points.duplicate()
	cursor = _snap_point(Vector2(local.x, local.z), draw_height, extra)
	cursor_valid = true


## Snaps a map point to a nearby corner (on screen) or else to the grid
## (Shift: no grid snap). `exclude` keys are corners not to snap to.
func _snap_point(p: Vector2, h: float, extra := PackedVector2Array(), exclude := {}) -> Vector2:
	var best := SNAP_PX
	var out := p
	var snapped_to_vertex := false
	var candidates := map.data.all_vertices()
	candidates.append_array(extra)
	for v in candidates:
		if exclude.has(DMMapData.key_of(v)):
			continue
		var sp = _screen(Vector3(v.x, h, v.y))
		if sp == null:
			continue
		var d := (sp as Vector2).distance_to(mouse_pos)
		if d < best:
			best = d
			out = v
			snapped_to_vertex = true
	if not snapped_to_vertex and not Input.is_key_pressed(KEY_SHIFT):
		var step: float = plugin.grid_step
		out = p.snapped(Vector2(step, step))
	return out


## The mouse ray hitting the horizontal plane at map height `h`, or null.
func _plane_point(h: float) -> Variant:
	var xf := map.map_transform()
	var hit = (xf * Plane(Vector3.UP, h)).intersects_ray(
		camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos))
	if hit == null:
		return null
	var local: Vector3 = xf.affine_inverse() * (hit as Vector3)
	return Vector2(local.x, local.z)


# --- Dragging corners and walls ------------------------------------------------

## The corner or wall of a selected sector under the mouse, if any.
func _find_handle() -> Dictionary:
	if selected.is_empty() or map.build_info.is_empty():
		return {}
	var best := HANDLE_PX
	var found := {}
	for si in selected:
		var outline: PackedVector2Array = map.build_info.outlines[si]
		var h := map.data.sectors[si].floor_height
		for q in outline:
			var sp = _screen(_v3(q, h))
			if sp != null and (sp as Vector2).distance_to(mouse_pos) < best:
				best = (sp as Vector2).distance_to(mouse_pos)
				found = {"kind": "vertex", "a": q, "b": q, "h": h}
	for c in map.build_info.get("outer_corners", []):
		if not selected.has(int(c.sector)):
			continue
		var sp = _screen(_v3(c.outer, c.h))
		if sp != null and (sp as Vector2).distance_to(mouse_pos) < best:
			best = (sp as Vector2).distance_to(mouse_pos)
			found = {"kind": "outer_vertex", "sector": int(c.sector), "inner": c.inner, "a": c.outer, "b": c.outer, "h": float(c.h)}
	if not found.is_empty():
		return found
	best = EDGE_PX
	for si in selected:
		var outline: PackedVector2Array = map.build_info.outlines[si]
		var h := map.data.sectors[si].floor_height
		for i in range(0, outline.size(), 2):
			var sa = _screen(_v3(outline[i], h))
			var sb = _screen(_v3(outline[i + 1], h))
			if sa == null or sb == null:
				continue
			var c := Geometry2D.get_closest_point_to_segment(mouse_pos, sa, sb)
			if c.distance_to(mouse_pos) < best:
				best = c.distance_to(mouse_pos)
				found = {"kind": "edge", "a": outline[i], "b": outline[i + 1], "h": h}
	for e in map.build_info.get("outer_edges", []):
		if not selected.has(int(e.sector)):
			continue
		var sa = _screen(_v3(e.a2, e.h))
		var sb = _screen(_v3(e.b2, e.h))
		if sa == null or sb == null:
			continue
		var c := Geometry2D.get_closest_point_to_segment(mouse_pos, sa, sb)
		if c.distance_to(mouse_pos) < best:
			best = c.distance_to(mouse_pos)
			found = {"kind": "outer_edge", "sector": int(e.sector), "inner_a": e.a, "inner_b": e.b,
				"out": e.out, "thickness": float(e.thickness), "a": e.a2, "b": e.b2, "h": float(e.h)}
	return found


func _start_drag() -> void:
	var start = _plane_point(float(handle.h))
	drag = handle.duplicate()
	drag["before"] = map.data.duplicate_data()
	drag["start"] = start if start != null else handle.a
	drag["valid"] = true
	drag["moved"] = false
	drag["to_a"] = handle.a
	drag["to_b"] = handle.b
	_consume_release = false


func _update_drag() -> void:
	var p = _plane_point(float(drag.h))
	if p == null:
		return
	var a: Vector2 = drag.a
	var b: Vector2 = drag.b
	if drag.kind == "outer_vertex" or drag.kind == "outer_edge":
		_update_outer_drag(p)
		return
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	if drag.kind == "vertex":
		var target := _snap_point(p, float(drag.h), PackedVector2Array(), {DMMapData.key_of(a): true})
		from.append(a)
		to.append(target)
		drag.to_a = target
		drag.to_b = target
	else:
		var d: Vector2 = (p as Vector2) - (drag.start as Vector2)
		if not Input.is_key_pressed(KEY_SHIFT):
			var step: float = plugin.grid_step
			d = d.snapped(Vector2(step, step))
		from.append_array([a, b])
		to.append_array([a + d, b + d])
		drag.to_a = a + d
		drag.to_b = b + d
	drag.moved = not (drag.to_a as Vector2).is_equal_approx(a) or not (drag.to_b as Vector2).is_equal_approx(b)
	map.data.copy_from(drag.before)
	if drag.moved:
		map.data.move_vertices(from, to)
	drag.valid = map.data.validate() == ""
	map.rebuild()


## Dragging a thick wall's outer corner (placed freely) or outer face
## (changes that wall's thickness).
func _update_outer_drag(p: Vector2) -> void:
	var a: Vector2 = drag.a
	map.data.copy_from(drag.before)
	var s: DMSector = map.data.sectors[int(drag.sector)]
	if drag.kind == "outer_vertex":
		var target := _snap_point(p, float(drag.h))
		drag.to_a = target
		drag.to_b = target
		drag.moved = not target.is_equal_approx(a)
		if drag.moved:
			s.outer_corners[DMMapData.key_of(drag.inner)] = target - (drag.inner as Vector2)
	else:
		var out: Vector2 = drag.out
		var t := maxf((p - (drag.inner_a as Vector2)).dot(out), 0.0)
		if not Input.is_key_pressed(KEY_SHIFT):
			t = maxf(snappedf(t, float(plugin.grid_step)), 0.0)
		drag.thickness_now = t
		drag.to_a = (drag.inner_a as Vector2) + out * t
		drag.to_b = (drag.inner_b as Vector2) + out * t
		drag.moved = not is_equal_approx(t, float(drag.thickness))
		if drag.moved:
			var edge := s.override_edge(drag.inner_a, drag.inner_b)
			s.set_wall_override(edge[0], edge[1], {"thickness": t})
			s.clear_outer_corners([drag.inner_a, drag.inner_b])
	drag.valid = true
	map.rebuild()


func _end_drag() -> void:
	var d := drag
	drag = {}
	var why := map.data.validate()
	if not why.is_empty():
		map.data.copy_from(d.before)
		map.rebuild()
		plugin.notify("Can't move it there: " + why + ".")
	elif d.moved:
		var names := {"vertex": "Move Corner", "edge": "Move Wall", "outer_vertex": "Move Wall Corner", "outer_edge": "Set Wall Thickness"}
		plugin.commit_snapshot(names.get(d.kind, "Move"), d.before)
	_update_hover()
	_changed()


func cancel_drag() -> void:
	if drag.is_empty() or map == null:
		drag = {}
		return
	map.data.copy_from(drag.before)
	map.rebuild()
	drag = {}
	_changed()


func _changed() -> void:
	if plugin != null:
		plugin.on_tool_changed()


# --- Overlay -----------------------------------------------------------------

func draw_overlay(overlay: Control) -> void:
	if camera == null or map == null or map.data == null:
		return
	map.ensure_built()
	validate_selection()
	var info := map.build_info
	var sectors := map.data.sectors

	# Selected sectors: outline at floor and ceiling height.
	for si in selected:
		var outline: PackedVector2Array = info.outlines[si] if si < (info.outlines as Array).size() else PackedVector2Array()
		var s := sectors[si]
		for i in range(0, outline.size(), 2):
			_line3(overlay, _v3(outline[i], s.floor_height), _v3(outline[i + 1], s.floor_height), COLOR_SELECTED, 3.0)
			_line3(overlay, _v3(outline[i], s.ceiling_height), _v3(outline[i + 1], s.ceiling_height), Color(COLOR_SELECTED, 0.45), 1.5)

	_draw_hidden_walls(overlay)
	if not selected_wall.is_empty():
		_draw_selected_wall(overlay)
	if mode == Mode.SELECT:
		_draw_handles(overlay)
	if mode == Mode.SELECT and drag.is_empty() and handle.is_empty() and not hover.is_empty():
		_draw_face_outline(overlay, int(hover.face), COLOR_HOVER, 2.0)
		var s := sectors[int(hover.sector)]
		var part := int(hover.part)
		var text := "Wall"
		if part == DMBuilder.Part.FLOOR:
			text = "Floor  " + DMUnits.format(s.floor_height, plugin.units)
		elif part == DMBuilder.Part.CEILING:
			text = "Ceiling  " + DMUnits.format(s.ceiling_height, plugin.units)
		_label(overlay, mouse_pos + Vector2(16, -8), text, Color.WHITE)

	if mode == Mode.DRAW:
		_draw_drawing(overlay)
	elif mode == Mode.RECT:
		_draw_rect(overlay)


## Faces built from the selected wall's edge.
func selected_wall_faces() -> Array[int]:
	var out: Array[int] = []
	if selected_wall.is_empty():
		return out
	var fe: PackedVector2Array = map.build_info.face_edge
	var fs: PackedInt32Array = map.build_info.face_sector
	for f in fs.size():
		if fs[f] == int(selected_wall.sector) and fe[f * 2].is_equal_approx(selected_wall.a) \
				and fe[f * 2 + 1].is_equal_approx(selected_wall.b):
			out.append(f)
	return out


func _draw_selected_wall(overlay: Control) -> void:
	for f in selected_wall_faces():
		_draw_face_outline(overlay, f, Color.WHITE, 3.0)
	var s: DMSector = map.data.sectors[int(selected_wall.sector)]
	var o := s.wall_override(selected_wall.a, selected_wall.b)
	if o.get("hidden", false):
		_dashed_wall(overlay, selected_wall.a, selected_wall.b, o.get("bottom", s.floor_height), o.get("top", s.ceiling_height), Color.WHITE)


## Hidden walls of the selected sectors, as dashed outlines.
func _draw_hidden_walls(overlay: Control) -> void:
	for hw in map.build_info.get("hidden_walls", []):
		if selected.has(int(hw[4])):
			_dashed_wall(overlay, hw[0], hw[1], hw[2], hw[3], Color(COLOR_SELECTED, 0.8))


func _dashed_wall(overlay: Control, p0: Vector2, p1: Vector2, bottom: float, top: float, color: Color) -> void:
	var c := [_v3(p0, bottom), _v3(p1, bottom), _v3(p1, top), _v3(p0, top)]
	for i in 4:
		var sa = _screen(c[i])
		var sb = _screen(c[(i + 1) % 4])
		if sa != null and sb != null:
			overlay.draw_dashed_line(sa, sb, color, 2.0, 6.0)


func _draw_handles(overlay: Control) -> void:
	var info := map.build_info
	for si in selected:
		if si >= (info.outlines as Array).size():
			continue
		var outline: PackedVector2Array = info.outlines[si]
		var h := map.data.sectors[si].floor_height
		for q in outline:
			var sp = _screen(_v3(q, h))
			if sp != null:
				overlay.draw_rect(Rect2((sp as Vector2) - Vector2(3.5, 3.5), Vector2(7, 7)), Color(0, 0, 0, 0.7))
				overlay.draw_rect(Rect2((sp as Vector2) - Vector2(2.5, 2.5), Vector2(5, 5)), COLOR_SELECTED)
	for c in info.get("outer_corners", []):
		if selected.has(int(c.sector)):
			var sp = _screen(_v3(c.outer, c.h))
			if sp != null:
				overlay.draw_rect(Rect2((sp as Vector2) - Vector2(3.5, 3.5), Vector2(7, 7)), Color(0, 0, 0, 0.7))
				overlay.draw_rect(Rect2((sp as Vector2) - Vector2(2.5, 2.5), Vector2(5, 5)), COLOR_DRAW)
	var active := drag if not drag.is_empty() else handle
	if active.is_empty():
		return
	var color := COLOR_BAD if not drag.is_empty() and not drag.valid else Color.WHITE
	var h := float(active.h)
	var a: Vector2 = active.get("to_a", active.a)
	var b: Vector2 = active.get("to_b", active.b)
	var is_edge: bool = active.kind == "edge" or active.kind == "outer_edge"
	if is_edge:
		_line3(overlay, _v3(a, h), _v3(b, h), color, 4.0)
		_length_label(overlay, a, b, h)
	_marker(overlay, _v3(a, h), color, 5.0)
	if is_edge:
		_marker(overlay, _v3(b, h), color, 5.0)
	var tips := {"vertex": "Drag to move this corner", "edge": "Drag to move this wall",
		"outer_vertex": "Drag to reshape the thick wall's outer corner", "outer_edge": "Drag to change this wall's thickness"}
	var tip: String = tips.get(active.kind, "")
	if not drag.is_empty() and active.kind == "outer_edge":
		tip = "Thickness: " + DMUnits.format(float(drag.get("thickness_now", drag.thickness)), plugin.units)
	elif not drag.is_empty() and active.kind == "outer_vertex":
		tip = "Corner: %s, %s" % [DMUnits.format(a.x, plugin.units), DMUnits.format(a.y, plugin.units)]
	elif not drag.is_empty():
		tip = "Can't go here (sides would cross or overlap)" if not drag.valid else (
			"Corner: %s, %s" % [DMUnits.format(a.x, plugin.units), DMUnits.format(a.y, plugin.units)]
			if active.kind == "vertex" else "Moved %s" % DMUnits.format(a.distance_to(active.a), plugin.units))
	_label(overlay, mouse_pos + Vector2(16, -8), tip, color)


func _draw_drawing(overlay: Control) -> void:
	var h := draw_height
	for i in range(1, points.size()):
		_line3(overlay, _v3(points[i - 1], h), _v3(points[i], h), COLOR_DRAW, 2.5)
		_length_label(overlay, points[i - 1], points[i], h)
	var tp = typed_point()
	if cursor_valid:
		var closing := tp == null and points.size() >= 3 and _near_first()
		if not points.is_empty():
			var end: Vector2 = tp if tp != null else (points[0] if closing else cursor)
			_line3(overlay, _v3(points[points.size() - 1], h), _v3(end, h), Color(COLOR_DRAW, 0.6), 2.0)
			_length_label(overlay, points[points.size() - 1], end, h)
			if tp != null:
				_marker(overlay, _v3(tp, h), COLOR_DRAW, 4.0)
		_marker(overlay, _v3(cursor, h), COLOR_CLOSE if closing else COLOR_DRAW, 5.0)
	for i in points.size():
		_marker(overlay, _v3(points[i], h), COLOR_CLOSE if i == 0 and points.size() >= 3 else COLOR_DRAW, 3.5)
	if not typed.is_empty():
		_label(overlay, mouse_pos + Vector2(16, 18), "Length: %s▏%s   Enter places the point" % [
			typed, DMUnits.suffix(plugin.units)], COLOR_DRAW)
	var hint := "Draw sector:  click to add points  •  type a length + Enter for an exact side  •  click the first point or Enter to finish  •  Backspace undoes  •  Shift: free angle / no snap  •  Esc cancels"
	_label(overlay, Vector2(12, overlay.size.y - 14), hint, Color(1, 1, 1, 0.85))


func _draw_rect(overlay: Control) -> void:
	var h := draw_height
	if cursor_valid:
		_marker(overlay, _v3(cursor, h), COLOR_DRAW, 5.0)
	var hint := "Draw rectangle:  click a corner"
	if rect_started:
		var a := rect_anchor
		var c := rect_corner()
		var corners := [a, Vector2(c.x, a.y), c, Vector2(a.x, c.y)]
		for i in 4:
			_line3(overlay, _v3(corners[i], h), _v3(corners[(i + 1) % 4], h), COLOR_DRAW, 2.5)
		_marker(overlay, _v3(a, h), COLOR_DRAW, 4.0)
		_length_label(overlay, corners[0], corners[1], h)
		_length_label(overlay, corners[1], corners[2], h)
		var fields := ["Width", "Depth"]
		var parts := []
		for f in 2:
			var value := DMUnits.format(absf(c.x - a.x) if f == 0 else absf(c.y - a.y), plugin.units)
			if f == rect_field and not typed.is_empty():
				value = "%s▏%s" % [typed, DMUnits.suffix(plugin.units)]
			var locked: bool = rect_size[f] > 0.0 or (f == rect_field and not typed.is_empty())
			var text: String = "%s: %s" % [fields[f], value]
			if locked:
				text += " (set)"
			parts.append(("[ %s ]" % text) if f == rect_field else text)
		_label(overlay, mouse_pos + Vector2(16, 18), "   ".join(parts), COLOR_DRAW)
		hint = "Draw rectangle:  click the opposite corner, or type the width, Tab, the depth, then Enter  •  Backspace clears a typed size  •  Esc cancels"
	_label(overlay, Vector2(12, overlay.size.y - 14), hint, Color(1, 1, 1, 0.85))


func _draw_face_outline(overlay: Control, f: int, color: Color, width: float) -> void:
	var faces: Array = map.build_info.get("face_points", [])
	if f < 0 or f >= faces.size():
		return
	var pts: PackedVector3Array = faces[f]
	for i in pts.size():
		_line3(overlay, pts[i], pts[(i + 1) % pts.size()], color, width)


func _length_label(overlay: Control, a: Vector2, b: Vector2, h: float) -> void:
	var length := a.distance_to(b)
	if length < 1e-4:
		return
	var sp = _screen(_v3((a + b) * 0.5, h))
	if sp != null:
		_label(overlay, (sp as Vector2) + Vector2(6, -6), DMUnits.format(length, plugin.units), Color.WHITE)


static func _v3(p: Vector2, h: float) -> Vector3:
	return Vector3(p.x, h, p.y)


## Map-local point to screen, or null when behind the camera.
func _screen(local: Vector3) -> Variant:
	var world := map.map_transform() * local
	if camera.is_position_behind(world):
		return null
	return camera.unproject_position(world)


func _line3(overlay: Control, a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var sa = _screen(a)
	var sb = _screen(b)
	if sa == null or sb == null:
		return
	overlay.draw_line(sa, sb, color, width, true)


func _marker(overlay: Control, local: Vector3, color: Color, radius: float) -> void:
	var sp = _screen(local)
	if sp != null:
		overlay.draw_circle(sp, radius + 1.5, Color(0, 0, 0, 0.6))
		overlay.draw_circle(sp, radius, color)


func _label(overlay: Control, pos: Vector2, text: String, color: Color) -> void:
	var font := overlay.get_theme_font("font", "Label")
	var size := overlay.get_theme_font_size("font_size", "Label")
	overlay.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.85))
	overlay.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
