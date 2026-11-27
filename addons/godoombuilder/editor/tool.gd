@tool
class_name DMTool
extends RefCounted
## Viewport interaction for a selected sector map: select sectors, draw new
## ones (as polygons or rectangles, with typed sizes), and raise or lower
## floors and ceilings.


enum Mode { SELECT, DRAW, RECT, PASTE }

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
## How strongly the selected sectors' surfaces are tinted (0 = not at all).
const SELECTION_TINT := 0.18
const COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.55)
const COLOR_DRAW := Color(0.35, 0.85, 1.0)
const COLOR_CLOSE := Color(0.4, 1.0, 0.45)
const COLOR_BAD := Color(1.0, 0.3, 0.25)
## Unfinished polygons saved with the map.
const COLOR_DRAFT := Color(1.0, 0.2, 0.2)

## Returned by _screen() and _plane_point() when there is no such point.
const NOWHERE := Vector2(INF, INF)


## A single wall: sector `sector`'s polygon edge a -> b.
class Wall:
	var sector: int
	var a: Vector2
	var b: Vector2

	func _init(si: int, from: Vector2, to: Vector2) -> void:
		sector = si
		a = from
		b = to


## A corner or wall of a selected sector you can drag.
class Handle:
	enum Kind { VERTEX, EDGE, OUTER_VERTEX, OUTER_EDGE }
	var kind := Kind.VERTEX
	## Where it is (a == b for corners), at height h.
	var a: Vector2
	var b: Vector2
	var h := 0.0
	## Thick walls only: the sector, the room corner an outer corner belongs
	## to, and for an outer face the room's wall, its outward normal and
	## thickness.
	var sector := -1
	var inner: Vector2
	var inner_a: Vector2
	var inner_b: Vector2
	var out: Vector2
	var thickness := 0.0

	static func make(k: Kind, from: Vector2, to: Vector2, height: float) -> Handle:
		var hd := Handle.new()
		hd.kind = k
		hd.a = from
		hd.b = to
		hd.h = height
		return hd

	func is_edge() -> bool:
		return kind == Kind.EDGE or kind == Kind.OUTER_EDGE


## A drag in progress: the handle, the map before it, and where it is now.
class Drag:
	var handle: Handle
	var before: DMMapData
	## Where the mouse went down (on the handle's height plane).
	var start: Vector2
	var valid := true
	var moved := false
	var to_a: Vector2
	var to_b: Vector2
	## Outer faces: the thickness the drag sets.
	var thickness_now := 0.0


## What the tool asks of the editor: edits, settings and messages.
var editor: DMEditor
var map: DMMap
var mode := Mode.SELECT
var selected: Array[int] = []
## The face under the mouse, or null.
var hover: DMMap.Hit
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

## The unfinished polygon (index into map.data.drafts) being continued, or -1.
var draft_index := -1
## The unfinished polygon under the mouse (-1 for none), and which end of it:
## 0 the first point, 1 the last, -1 a side (not an end).
var draft_hover := -1
var draft_hover_end := -1
## The last Delete key event handled (the same press arriving twice acts once).
var _delete_event := 0
## Where (on screen) a corner was just removed with Delete, or NOWHERE. Until
## the mouse moves away, Delete there removes nothing more: pressing it again
## for a corner that's already gone mustn't delete the whole sector.
var _removed_corner_at := Vector2(INF, INF)
const REMOVED_CORNER_PX := 24.0

## The single wall picked by clicking it, or null. Its sector is the only
## selected sector.
var selected_wall: Wall

## Corner or wall of a selected sector under the mouse, or null.
var handle: Handle
## Active corner/wall drag, or null.
var drag: Drag

var _consume_release := false

## Box select: where the mouse went down (screen), whether it has moved far
## enough to be a box, whether Shift was held (adds to the selection), and
## the selection before it started.
const BOX_START_PX := 6.0
var box_pending := false
var box_active := false
var box_start := Vector2.ZERO
var _box_additive := false
var _box_before: Array[int] = []
var _box_click: Array[int] = []

## Pasting: rotation / mirror applied to the clipboard before it's moved to
## the cursor (R rotates, M mirrors while placing).
var paste_basis := Transform2D.IDENTITY


func set_map(m: DMMap) -> void:
	if m == map:
		return
	cancel_drag()
	cancel_draw()
	selected.clear()
	selected_wall = null
	hover = null
	handle = null
	# The selection tint goes with the selection.
	if is_instance_valid(map):
		map.set_highlight(PackedInt32Array(), Color.TRANSPARENT)
	map = m


func validate_selection() -> void:
	var count := map.data.sectors.size() if map != null and map.data != null else 0
	var keep: Array[int] = []
	for i in selected:
		if i < count and not keep.has(i):
			keep.append(i)
	selected = keep
	if selected_wall != null and (selected.size() != 1 or selected[0] != selected_wall.sector):
		selected_wall = null
	if selected_wall == null and mode == Mode.SELECT:
		typed = ""
	if hover != null and hover.sector >= count:
		hover = null
	var drafts := map.data.drafts.size() if map != null and map.data != null else 0
	if draft_hover >= drafts:
		draft_hover = -1
	if draft_index >= drafts:
		draft_index = -1


func begin_draw(rectangle := false) -> void:
	if map == null:
		return
	_leave_draw()
	mode = Mode.RECT if rectangle else Mode.DRAW
	if not selected.is_empty():
		draw_height = map.data.sectors[selected[0]].floor_height
	_changed()


## Stops drawing. A polygon with two or more points is kept unfinished on
## the map (see _leave_draw).
func cancel_draw() -> void:
	_leave_draw()
	mode = Mode.SELECT
	_changed()


## Ends the drawing in progress. A polygon with at least two points is saved
## as unfinished, to be continued later; one continued and taken back to
## fewer points is discarded.
func _leave_draw() -> void:
	if mode == Mode.DRAW and editor != null and map != null and map.data != null:
		if points.size() >= 2:
			editor.keep_draft(points, draw_height, draft_index)
		elif draft_index >= 0:
			editor.discard_draft(draft_index)
	_reset_draw_state()


## Continues unfinished polygon `index` from its first (end 0) or last (end 1)
## point.
func resume_draft(index: int, end: int) -> void:
	if map == null or index < 0 or index >= map.data.drafts.size():
		return
	cancel_drag()
	_leave_draw()
	var d := map.data.drafts[index]
	points = d.points.duplicate()
	if end == 0:
		points.reverse()
	draw_height = d.height
	draft_index = index
	draft_hover = -1
	mode = Mode.DRAW
	selected.clear()
	selected_wall = null
	handle = null
	_update_cursor()
	_changed()


func is_drawing() -> bool:
	return mode == Mode.DRAW or mode == Mode.RECT


## Starts placing the editor's clipboard: it follows the mouse until clicked.
func begin_paste() -> void:
	if map == null:
		return
	cancel_drag()
	_leave_draw()
	paste_basis = Transform2D.IDENTITY
	mode = Mode.PASTE
	if not selected.is_empty():
		draw_height = map.data.sectors[selected[0]].floor_height
	_update_cursor()
	_changed()


## Where the clipboard would be pasted now: its rotation / mirror, then its
## bounding box corner moved to the cursor.
func paste_transform() -> Transform2D:
	# Rotating or mirroring moves the box; keep its corner at the cursor.
	var lo := Vector2(INF, INF)
	for s in editor.clipboard:
		for p in s.polygons:
			for v in p:
				lo = lo.min(paste_basis * v)
	if lo.x == INF:
		lo = Vector2.ZERO
	return Transform2D(0.0, cursor - lo) * paste_basis


func _reset_draw_state() -> void:
	points.clear()
	draft_index = -1
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
		var motion: InputEventMouseMotion = event
		mouse_pos = motion.position
		if _removed_corner_at != NOWHERE and mouse_pos.distance_to(_removed_corner_at) > REMOVED_CORNER_PX:
			_removed_corner_at = NOWHERE
		if box_pending and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if not box_active and mouse_pos.distance_to(box_start) >= BOX_START_PX:
				box_active = true
			if box_active:
				_update_box()
				editor.update_overlays()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		if drag != null:
			_update_drag()
			editor.update_overlays()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if mode == Mode.PASTE:
			_update_cursor()
			editor.update_overlays()
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_update_hover()
		editor.update_overlays()
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		mouse_pos = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mode == Mode.PASTE:
					_update_cursor()
					if cursor_valid and editor.paste_at(paste_transform()):
						mode = Mode.SELECT
						_changed()
					_consume_release = true
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				_update_hover()
				if mode == Mode.SELECT and mb.double_click and handle != null and handle.kind == Handle.Kind.EDGE:
					_split_at_handle()
					_consume_release = true
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if (mode == Mode.SELECT or (mode == Mode.DRAW and points.is_empty())) \
						and draft_hover >= 0 and draft_hover_end >= 0 and not mb.shift_pressed:
					resume_draft(draft_hover, draft_hover_end)
					_consume_release = true
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if mode == Mode.DRAW:
					_draw_click()
					_consume_release = true
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if mode == Mode.RECT:
					_rect_click()
					_consume_release = true
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if handle != null and not mb.shift_pressed:
					_start_drag()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				var before: Array[int] = []
				before.assign(selected)
				var result := _select_click(mb.shift_pressed)
				if result == EditorPlugin.AFTER_GUI_INPUT_STOP:
					# Clicked a surface: dragging on from here draws a selection box.
					box_pending = true
					box_active = false
					box_start = mouse_pos
					_box_additive = mb.shift_pressed
					_box_before = before
					_box_click.assign(selected)
				return result
			if drag != null:
				_end_drag()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if box_pending:
				var was_box := box_active
				box_pending = false
				box_active = false
				if was_box:
					_update_box()
					_consume_release = false
					_changed()
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

	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed:
			return _key(k)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _key(k: InputEventKey) -> int:
	var plain := not (k.ctrl_pressed or k.alt_pressed or k.meta_pressed)
	var command := (k.ctrl_pressed or k.meta_pressed) and not k.alt_pressed and not k.shift_pressed
	var shift_command := (k.ctrl_pressed or k.meta_pressed) and not k.alt_pressed and k.shift_pressed
	# Texture tools over the surface under the mouse.
	if mode == Mode.SELECT and shift_command and not k.echo and (k.keycode == KEY_C or k.keycode == KEY_V):
		_update_hover()
		if hover == null:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var wall := hovered_wall()
		if k.keycode == KEY_C:
			editor.copy_uv(hover.sector, hover.part, wall)
		else:
			editor.paste_uv(_hover_targets(), hover.part, wall)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if mode == Mode.SELECT and k.alt_pressed and not (k.ctrl_pressed or k.meta_pressed) and ARROWS.has(k.keycode):
		_update_hover()
		if hover == null:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var step := editor.grid_step * (0.125 if k.shift_pressed else 1.0)
		var dir: Vector2 = ARROWS[k.keycode]
		editor.nudge_uv(_hover_targets(), hover.part, hovered_wall(), dir * step)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if box_active and k.keycode == KEY_ESCAPE:
		box_pending = false
		box_active = false
		selected.assign(_box_before)
		_changed()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if command and not k.echo and k.keycode == KEY_C and mode == Mode.SELECT and not selected.is_empty():
		editor.copy_selected()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if command and not k.echo and k.keycode == KEY_V and (mode == Mode.SELECT or mode == Mode.PASTE):
		editor.begin_paste()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if mode == Mode.PASTE:
		return _paste_key(k, plain)
	# Typing a length for the selected wall (not on the keypad: Godot's view
	# shortcuts are there).
	if mode == Mode.SELECT and selected_wall != null and drag == null and plain and k.unicode > 0 			and TYPED_CHARS.contains(char(k.unicode)) and not (k.keycode >= KEY_KP_MULTIPLY and k.keycode <= KEY_KP_9):
		var ch := char(k.unicode)
		if not (ch == "." and typed.contains(".")):
			typed += ch
		_changed()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if mode == Mode.SELECT and not typed.is_empty() and plain:
		match k.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				var v := typed_meters()
				typed = ""
				if v > 0.0:
					editor.set_wall_length(v)
				_changed()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			KEY_BACKSPACE:
				typed = typed.left(-1)
				_changed()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			KEY_ESCAPE:
				typed = ""
				_changed()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
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
			if drag != null:
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
				editor.join_selected()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_DELETE:
			if mode != Mode.SELECT or not plain:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			# One press does one thing: a held key's repeats, or the same press
			# arriving twice, would otherwise go on to delete the sector whose
			# corner was just removed.
			if k.echo or k.get_instance_id() == _delete_event:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_delete_event = k.get_instance_id()
			# What's under the mouse now (a click may have changed the selection
			# since it last moved).
			_update_hover()
			if draft_hover >= 0:
				editor.discard_draft(draft_hover)
				draft_hover = -1
				_update_hover()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if handle != null and handle.kind == Handle.Kind.VERTEX:
				editor.remove_corner(handle.a)
				_removed_corner_at = mouse_pos
				_update_hover()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if _removed_corner_at != NOWHERE:
				editor.notify("No corner here any more. To delete the sector, move the mouse away and press Delete.", DMEditor.Severity.INFO)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if mode == Mode.SELECT and selected_wall != null and plain:
				editor.set_wall_hidden(true)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if mode == Mode.SELECT and not selected.is_empty() and plain:
				editor.delete_selected()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_PAGEUP, KEY_PAGEDOWN:
			if plain and _nudge_hovered(1 if k.keycode == KEY_PAGEUP else -1):
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			if plain and not k.echo:
				editor.shift_grid(-1 if k.keycode == KEY_BRACKETLEFT else 1)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Alt+arrow keys: which way the texture moves (x along its width, y along
## its height; up is -y on walls, so the texture rises).
const ARROWS := {KEY_LEFT: Vector2(-1, 0), KEY_RIGHT: Vector2(1, 0), KEY_UP: Vector2(0, -1), KEY_DOWN: Vector2(0, 1)}


## Keys while placing a paste: R / Shift+R rotate 90°, E / Shift+E by the
## Rotate angle, M mirrors, Esc cancels.
func _paste_key(k: InputEventKey, plain: bool) -> int:
	if not plain or k.echo:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	match k.keycode:
		KEY_R:
			paste_basis = Transform2D(PI * 0.5 * (-1.0 if k.shift_pressed else 1.0), Vector2.ZERO) * paste_basis
		KEY_E:
			paste_basis = Transform2D(deg_to_rad(editor.rotate_angle) * (-1.0 if k.shift_pressed else 1.0), Vector2.ZERO) * paste_basis
		KEY_M:
			paste_basis = Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO) * paste_basis
		KEY_ESCAPE:
			mode = Mode.SELECT
		KEY_ENTER, KEY_KP_ENTER:
			if cursor_valid and editor.paste_at(paste_transform()):
				mode = Mode.SELECT
		_:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
	_changed()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


## Double-click on a selected sector's wall: a new corner there (on the grid
## when a grid point lies on the wall, else right under the mouse).
func _split_at_handle() -> void:
	var p := _plane_point(handle.h)
	if p == NOWHERE:
		return
	var a := handle.a
	var b := handle.b
	var at := Geometry2D.get_closest_point_to_segment(p, a, b)
	if not Input.is_key_pressed(KEY_SHIFT):
		var step := editor.grid_step
		var g := p.snapped(Vector2(step, step))
		if Geometry2D.get_closest_point_to_segment(g, a, b).distance_to(g) < DMGeo.LINE_EPS:
			at = g
	if at.distance_to(a) < DMGeo.LINE_EPS or at.distance_to(b) < DMGeo.LINE_EPS:
		return
	editor.insert_corner(at)
	_update_hover()


func _select_click(additive: bool) -> int:
	if hover == null:
		if not additive and not selected.is_empty():
			selected.clear()
			_changed()
		# Let Godot handle clicks on empty space (select other nodes, etc.).
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var s := hover.sector
	selected_wall = null
	typed = ""
	if additive:
		if selected.has(s):
			selected.erase(s)
		else:
			selected.append(s)
	else:
		selected.assign([s])
		if hover.part == DMBuilder.Part.WALL:
			var edge := map.build_info.edge_of(hover.face)
			selected_wall = Wall.new(s, edge[0], edge[1])
	_consume_release = true
	_changed()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


## Raises (dir 1) or lowers (dir -1) the hovered floor or ceiling by one grid
## step. When the hovered sector is selected, all selected sectors move.
func _nudge_hovered(dir: int) -> bool:
	if hover == null or hover.part == DMBuilder.Part.WALL:
		return false
	var s := hover.sector
	var targets: Array[int] = []
	if selected.has(s):
		targets.assign(selected)
	else:
		targets.append(s)
	editor.nudge_heights(targets, hover.part, dir * editor.grid_step)
	_update_hover()
	return true


## The wall under the mouse (its sector's polygon edge), or null.
func hovered_wall() -> Wall:
	if hover == null or hover.part != DMBuilder.Part.WALL:
		return null
	var edge := map.build_info.edge_of(hover.face)
	return Wall.new(hover.sector, edge[0], edge[1])


## The sectors an action on the hovered surface applies to: all selected
## ones when the hovered one is selected (floors and ceilings), else it.
func _hover_targets() -> Array[int]:
	var out: Array[int] = []
	if hover == null:
		return out
	if hover.part != DMBuilder.Part.WALL and selected.has(hover.sector):
		out.assign(selected)
	else:
		out.append(hover.sector)
	return out


## Box select: the sectors whose middle (on the floor) is inside the box on
## screen, added to the earlier selection with Shift. A box around nothing
## leaves what the click selected.
func _update_box() -> void:
	var box := Rect2(box_start, Vector2.ZERO).expand(mouse_pos)
	var found: Array[int] = []
	for si in map.data.sectors.size():
		var s := map.data.sectors[si]
		if s.polygons.is_empty():
			continue
		var sp := _screen(_v3(sector_middle(s), s.floor_height))
		if sp != NOWHERE and box.has_point(sp):
			found.append(si)
	if found.is_empty():
		selected.assign(_box_click)
		return
	var out: Array[int] = []
	if _box_additive:
		out.assign(_box_before)
	for si in found:
		if not out.has(si):
			out.append(si)
	selected = out
	selected_wall = null


## A point in the middle of a sector's floor: the center of its bounds when
## that's on the floor, else a point inside its largest piece.
static func sector_middle(s: DMSector) -> Vector2:
	var box := Rect2(s.polygons[0][0], Vector2.ZERO)
	var largest := s.polygons[0]
	for poly in s.polygons:
		for q in poly:
			box = box.expand(q)
		if DMGeo.signed_area(poly) > DMGeo.signed_area(largest):
			largest = poly
	if s.contains_point(box.get_center()):
		return box.get_center()
	return DMGeo.interior_point(largest)


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
	var result := editor.commit_loop(points, draft_index)
	if result.ok:
		_reset_draw_state()
		mode = Mode.SELECT
		selected.assign([result.index])
	elif mode == Mode.RECT:
		points.clear()
	_changed()


## The typed number in meters, or -1 when nothing usable is typed.
func typed_meters() -> float:
	if typed.is_empty() or typed == ".":
		return -1.0
	return DMUnits.from_display(typed.to_float(), editor.units)


## Freeform drawing: where a typed length would put the next point, or
## NOWHERE.
func typed_point() -> Vector2:
	var length := typed_meters()
	if mode != Mode.DRAW or points.is_empty() or length <= 0.0:
		return NOWHERE
	var last := points[points.size() - 1]
	var dir := cursor - last
	var angle := 0.0 if dir.length() < 1e-6 else dir.angle()
	if not Input.is_key_pressed(KEY_SHIFT):
		angle = snappedf(angle, deg_to_rad(15.0))
	var p := last + Vector2.from_angle(angle) * length
	return Vector2(snappedf(p.x, DMGeo.SNAP), snappedf(p.y, DMGeo.SNAP))


func _place_typed_point() -> void:
	var p := typed_point()
	typed = ""
	if p != NOWHERE:
		points.append(p)
	elif points.is_empty():
		editor.notify("Click the first point, then type the length of each side.")
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
		editor.notify("Give the rectangle a width and a depth first (move the mouse or type them).")
		return
	points = PackedVector2Array([a, Vector2(c.x, a.y), c, Vector2(a.x, c.y)])
	_finish()


func _near_first() -> bool:
	if points.is_empty():
		return false
	if cursor.distance_to(points[0]) < DMGeo.SNAP:
		return true
	var sp := _screen(Vector3(points[0].x, draw_height, points[0].y))
	return sp != NOWHERE and sp.distance_to(mouse_pos) <= CLOSE_PX


func _update_hover() -> void:
	if camera == null or map == null:
		hover = null
		return
	hover = map.pick(camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos))
	_find_draft()
	handle = _find_handle() if mode == Mode.SELECT and draft_hover < 0 else null
	if is_drawing():
		var started := rect_started if mode == Mode.RECT else not points.is_empty()
		if not started and hover != null and hover.part == DMBuilder.Part.FLOOR:
			draw_height = map.data.sectors[hover.sector].floor_height
		_update_cursor()


func _update_cursor() -> void:
	cursor_valid = false
	if camera == null or map == null:
		return
	var p := _plane_point(draw_height)
	if p == NOWHERE:
		return
	cursor = _snap_point(p, draw_height, points.duplicate())
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
		var sp := _screen(Vector3(v.x, h, v.y))
		if sp == NOWHERE:
			continue
		var d := sp.distance_to(mouse_pos)
		if d < best:
			best = d
			out = v
			snapped_to_vertex = true
	if not snapped_to_vertex and not Input.is_key_pressed(KEY_SHIFT):
		var step := editor.grid_step
		out = p.snapped(Vector2(step, step))
	return out


## Where the ray through screen point `at` (default: the mouse) hits the
## horizontal plane at map height `h` (map coordinates), or NOWHERE.
func _plane_point(h: float, at := NOWHERE) -> Vector2:
	var screen_pos := mouse_pos if at == NOWHERE else at
	var xf := map.map_transform()
	var hit: Variant = (xf * Plane(Vector3.UP, h)).intersects_ray(
		camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return NOWHERE
	var world: Vector3 = hit
	var local := xf.affine_inverse() * world
	return Vector2(local.x, local.z)


# --- Dragging corners and walls ------------------------------------------------

## Sets draft_hover / draft_hover_end to the unfinished polygon under the
## mouse: an end of one (to continue it), or else a side (Select only, to
## discard it). Not while placing points, nor the one being continued.
func _find_draft() -> void:
	draft_hover = -1
	draft_hover_end = -1
	if map == null or map.data == null or camera == null:
		return
	if not (mode == Mode.SELECT or (mode == Mode.DRAW and points.is_empty())):
		return
	var drafts := map.data.drafts
	var best := HANDLE_PX
	for di in drafts.size():
		var d := drafts[di]
		if di == draft_index or d.points.is_empty():
			continue
		var last := d.points.size() - 1
		for end: int in [last, 0]:
			var dist := _screen_distance(_v3(d.points[end], d.height))
			if dist < best:
				best = dist
				draft_hover = di
				draft_hover_end = 0 if end == 0 else 1
	if draft_hover >= 0 or mode != Mode.SELECT:
		return
	best = EDGE_PX
	for di in drafts.size():
		var d := drafts[di]
		for i in range(1, d.points.size()):
			var dist := _segment_distance(_v3(d.points[i - 1], d.height), _v3(d.points[i], d.height))
			if dist < best:
				best = dist
				draft_hover = di


## The corner or wall of a selected sector under the mouse, if any.
func _find_handle() -> Handle:
	var info := map.build_info
	if selected.is_empty() or info.is_empty():
		return null
	var best := HANDLE_PX
	var found: Handle = null
	for si in selected:
		var outline := info.outline(si)
		var h := map.data.sectors[si].floor_height
		for q in outline:
			var d := _screen_distance(_v3(q, h))
			if d < best:
				best = d
				found = Handle.make(Handle.Kind.VERTEX, q, q, h)
	for c in info.outer_corners:
		if not selected.has(c.sector):
			continue
		var d := _screen_distance(_v3(c.outer, c.h))
		if d < best:
			best = d
			found = Handle.make(Handle.Kind.OUTER_VERTEX, c.outer, c.outer, c.h)
			found.sector = c.sector
			found.inner = c.inner
	if found != null:
		return found
	best = EDGE_PX
	for si in selected:
		var outline := info.outline(si)
		var h := map.data.sectors[si].floor_height
		for i in range(0, outline.size(), 2):
			var d := _segment_distance(_v3(outline[i], h), _v3(outline[i + 1], h))
			if d < best:
				best = d
				found = Handle.make(Handle.Kind.EDGE, outline[i], outline[i + 1], h)
	for e in info.outer_edges:
		if not selected.has(e.sector):
			continue
		var d := _segment_distance(_v3(e.a2, e.h), _v3(e.b2, e.h))
		if d < best:
			best = d
			found = Handle.make(Handle.Kind.OUTER_EDGE, e.a2, e.b2, e.h)
			found.sector = e.sector
			found.inner_a = e.a
			found.inner_b = e.b
			found.out = e.out
			found.thickness = e.thickness
	return found


## Screen distance from the mouse to a map point (INF when off screen).
func _screen_distance(local: Vector3) -> float:
	var sp := _screen(local)
	return INF if sp == NOWHERE else sp.distance_to(mouse_pos)


## Screen distance from the mouse to a map segment (INF when off screen).
func _segment_distance(a: Vector3, b: Vector3) -> float:
	var sa := _screen(a)
	var sb := _screen(b)
	if sa == NOWHERE or sb == NOWHERE:
		return INF
	return Geometry2D.get_closest_point_to_segment(mouse_pos, sa, sb).distance_to(mouse_pos)


func _start_drag() -> void:
	var start := _plane_point(handle.h)
	drag = Drag.new()
	drag.handle = handle
	drag.before = map.data.duplicate_data()
	drag.start = start if start != NOWHERE else handle.a
	drag.to_a = handle.a
	drag.to_b = handle.b
	drag.thickness_now = handle.thickness
	_consume_release = false


func _update_drag() -> void:
	var hd := drag.handle
	var p := _plane_point(hd.h)
	if p == NOWHERE:
		return
	var a := hd.a
	var b := hd.b
	if hd.kind == Handle.Kind.OUTER_VERTEX or hd.kind == Handle.Kind.OUTER_EDGE:
		_update_outer_drag(p)
		return
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	if hd.kind == Handle.Kind.VERTEX:
		var target := _snap_point(p, hd.h, PackedVector2Array(), {DMMapData.key_of(a): true})
		from.append(a)
		to.append(target)
		drag.to_a = target
		drag.to_b = target
	else:
		var d := p - drag.start
		if not Input.is_key_pressed(KEY_SHIFT):
			var step := editor.grid_step
			d = d.snapped(Vector2(step, step))
		from.append_array([a, b])
		to.append_array([a + d, b + d])
		drag.to_a = a + d
		drag.to_b = b + d
	drag.moved = not drag.to_a.is_equal_approx(a) or not drag.to_b.is_equal_approx(b)
	# Every mouse move restarts from the snapshot. No changed signals (the
	# dock and toolbar refresh once the drag ends) and no collision rebuild
	# (it's brought up to date in _end_drag).
	map.data.copy_from(drag.before, false)
	if drag.moved:
		map.data.move_vertices(from, to, false)
	drag.valid = map.data.validate() == ""
	map.rebuild(false)


## Dragging a thick wall's outer corner (placed freely) or outer face
## (changes that wall's thickness).
func _update_outer_drag(p: Vector2) -> void:
	var hd := drag.handle
	map.data.copy_from(drag.before, false)
	var s := map.data.sectors[hd.sector]
	if hd.kind == Handle.Kind.OUTER_VERTEX:
		var target := _snap_point(p, hd.h)
		drag.to_a = target
		drag.to_b = target
		drag.moved = not target.is_equal_approx(hd.a)
		if drag.moved:
			s.outer_corners[DMMapData.key_of(hd.inner)] = target - hd.inner
	else:
		var t := maxf((p - hd.inner_a).dot(hd.out), 0.0)
		if not Input.is_key_pressed(KEY_SHIFT):
			t = maxf(snappedf(t, editor.grid_step), 0.0)
		drag.thickness_now = t
		drag.to_a = hd.inner_a + hd.out * t
		drag.to_b = hd.inner_b + hd.out * t
		drag.moved = not is_equal_approx(t, hd.thickness)
		if drag.moved:
			var edge := s.override_edge(hd.inner_a, hd.inner_b)
			s.set_wall_override(edge[0], edge[1], {"thickness": t})
			s.clear_outer_corners([hd.inner_a, hd.inner_b])
	drag.valid = true
	map.rebuild(false)


## Undo names for drags, by Handle.Kind.
const DRAG_ACTIONS: Array[String] = ["Move Corner", "Move Wall", "Move Wall Corner", "Set Wall Thickness"]


func _end_drag() -> void:
	var d := drag
	drag = null
	var why := map.data.validate()
	if not why.is_empty():
		map.data.copy_from(d.before)
		map.rebuild()
		editor.notify("Can't move it there: " + why + ".")
	elif d.moved:
		editor.commit_snapshot(DRAG_ACTIONS[d.handle.kind], d.before)
	# A drag that ended where it started (or a commit that didn't rebuild)
	# still owes the collision shape its update.
	map.ensure_built()
	_update_hover()
	_changed()


func cancel_drag() -> void:
	if drag == null or map == null:
		drag = null
		return
	map.data.copy_from(drag.before)
	map.rebuild()
	drag = null
	_changed()


## Tints the selected sectors in the viewport (see DMMap.set_highlight).
func update_highlight() -> void:
	if map == null or map.data == null:
		return
	map.ensure_built()
	validate_selection()
	map.set_highlight(PackedInt32Array(selected), Color(COLOR_SELECTED, SELECTION_TINT))


func _changed() -> void:
	if editor != null:
		editor.on_tool_changed()


# --- Overlay -----------------------------------------------------------------

func draw_overlay(overlay: Control) -> void:
	if camera == null or map == null or map.data == null:
		return
	map.ensure_built()
	validate_selection()
	update_highlight()
	var info := map.build_info
	var sectors := map.data.sectors

	# Selected sectors: outline at floor and ceiling height.
	for si in selected:
		var outline := info.outline(si)
		var s := sectors[si]
		for i in range(0, outline.size(), 2):
			_line3(overlay, _v3(outline[i], s.floor_height), _v3(outline[i + 1], s.floor_height), COLOR_SELECTED, 3.0)
			_line3(overlay, _v3(outline[i], s.ceiling_height), _v3(outline[i + 1], s.ceiling_height), Color(COLOR_SELECTED, 0.45), 1.5)
	if drag == null or drag.handle.kind == Handle.Kind.VERTEX:
		_draw_wall_lengths(overlay)

	_draw_drafts(overlay)
	_draw_hidden_walls(overlay)
	if selected_wall != null:
		_draw_selected_wall(overlay)
	if mode == Mode.SELECT:
		_draw_handles(overlay)
	if mode == Mode.SELECT and drag == null and handle == null and draft_hover < 0 and hover != null:
		_draw_face_outline(overlay, hover.face, COLOR_HOVER, 2.0)
		var s := sectors[hover.sector]
		var part := hover.part
		var text := "Wall"
		if part == DMBuilder.Part.WALL:
			var edge := map.build_info.edge_of(hover.face)
			text = "Wall  " + DMUnits.format(edge[0].distance_to(edge[1]), editor.units)
		if part == DMBuilder.Part.FLOOR:
			text = "Floor  " + DMUnits.format(s.floor_height, editor.units)
		elif part == DMBuilder.Part.CEILING:
			text = "Ceiling  " + DMUnits.format(s.ceiling_height, editor.units)
		_label(overlay, mouse_pos + Vector2(16, -8), text, Color.WHITE)

	if box_active:
		var r := Rect2(box_start, Vector2.ZERO).expand(mouse_pos)
		overlay.draw_rect(r, Color(COLOR_SELECTED, 0.12))
		overlay.draw_rect(r, COLOR_SELECTED, false, 1.5)
	if mode == Mode.DRAW:
		_draw_drawing(overlay)
	elif mode == Mode.RECT:
		_draw_rect(overlay)
	elif mode == Mode.PASTE:
		_draw_paste(overlay)


## Unfinished polygons in red, their ends marked; the one under the mouse
## brighter, with what clicking does.
func _draw_drafts(overlay: Control) -> void:
	var drafts := map.data.drafts
	for di in drafts.size():
		if di == draft_index and mode == Mode.DRAW:
			continue
		var d := drafts[di]
		var lit := di == draft_hover
		var color := COLOR_DRAFT.lightened(0.45) if lit else COLOR_DRAFT
		for i in range(1, d.points.size()):
			_line3(overlay, _v3(d.points[i - 1], d.height), _v3(d.points[i], d.height), color, 3.0 if lit else 2.5)
		for i in d.points.size():
			var is_end := i == 0 or i == d.points.size() - 1
			var on_end := lit and draft_hover_end >= 0 and i == (0 if draft_hover_end == 0 else d.points.size() - 1)
			_marker(overlay, _v3(d.points[i], d.height), Color.WHITE if on_end else color, 5.0 if is_end else 3.0)
	if draft_hover >= 0 and drag == null:
		var tip := "Unfinished polygon:  click to continue from here" if draft_hover_end >= 0 \
			else "Unfinished polygon:  click an end to continue it"
		if mode == Mode.SELECT:
			tip += "  •  Delete discards it"
		_label(overlay, mouse_pos + Vector2(16, -8), tip, COLOR_DRAFT.lightened(0.45))


func _draw_paste(overlay: Control) -> void:
	if cursor_valid:
		var xf := paste_transform()
		var h := draw_height
		for s in editor.clipboard:
			for p in s.polygons:
				for i in p.size():
					_line3(overlay, _v3(xf * p[i], h), _v3(xf * p[(i + 1) % p.size()], h), COLOR_DRAW, 2.5)
		_marker(overlay, _v3(cursor, h), COLOR_DRAW, 5.0)
	var hint := "Paste:  click to place (it cuts what's under it, like drawing)  •  R / Shift+R rotate 90°  •  E / Shift+E rotate %s°  •  M mirrors  •  Shift: no grid snap  •  Esc cancels" % str(snappedf(editor.rotate_angle, 0.01))
	_label(overlay, Vector2(12, overlay.size.y - 14), hint, Color(1, 1, 1, 0.85))


## Faces built from the selected wall's edge.
func selected_wall_faces() -> Array[int]:
	var out: Array[int] = []
	if selected_wall == null:
		return out
	var fe := map.build_info.face_edge
	var fs := map.build_info.face_sector
	for f in fs.size():
		if fs[f] == selected_wall.sector and fe[f * 2].is_equal_approx(selected_wall.a) \
				and fe[f * 2 + 1].is_equal_approx(selected_wall.b):
			out.append(f)
	return out


func _draw_selected_wall(overlay: Control) -> void:
	for f in selected_wall_faces():
		_draw_face_outline(overlay, f, Color.WHITE, 3.0)
	# Its ends, A and B (Keep fixed in the dock picks which stays put when
	# setting its length), the fixed one highlighted.
	var w := selected_wall
	var h := map.data.sectors[w.sector].floor_height
	var anchor := editor.length_anchor
	var ends: Array[Vector2] = [w.a, w.b]
	for i in 2:
		var fixed := anchor == (DMEditor.LengthAnchor.KEEP_A if i == 0 else DMEditor.LengthAnchor.KEEP_B)
		var sp := _screen(_v3(ends[i], h))
		if sp != NOWHERE:
			overlay.draw_circle(sp, 6.5, Color(0, 0, 0, 0.6))
			overlay.draw_circle(sp, 5.0, COLOR_SELECTED if fixed else Color.WHITE)
			_label(overlay, sp + Vector2(8, 16), "AB"[i] + (" (fixed)" if fixed else ""), COLOR_SELECTED if fixed else Color.WHITE)
	if anchor == DMEditor.LengthAnchor.CENTER:
		_marker(overlay, _v3((w.a + w.b) * 0.5, h), COLOR_SELECTED, 3.5)
	if not typed.is_empty() and mode == Mode.SELECT:
		_label(overlay, mouse_pos + Vector2(16, 18), "Wall length: %s▏%s   Enter sets it  •  Esc cancels" % [
			typed, DMUnits.suffix(editor.units)], COLOR_DRAW)
	var s := map.data.sectors[selected_wall.sector]
	var o := s.wall_override(selected_wall.a, selected_wall.b)
	if DMSector.setting_bool(o, "hidden"):
		_dashed_wall(overlay, selected_wall.a, selected_wall.b, DMSector.setting_float(o, "bottom", s.floor_height),
			DMSector.setting_float(o, "top", s.ceiling_height), Color.WHITE)


## Hidden walls of the selected sectors, as dashed outlines.
func _draw_hidden_walls(overlay: Control) -> void:
	for hw in map.build_info.hidden_walls:
		if selected.has(hw.sector):
			_dashed_wall(overlay, hw.p0, hw.p1, hw.bottom, hw.top, Color(COLOR_SELECTED, 0.8))


func _dashed_wall(overlay: Control, p0: Vector2, p1: Vector2, bottom: float, top: float, color: Color) -> void:
	var c := PackedVector3Array([_v3(p0, bottom), _v3(p1, bottom), _v3(p1, top), _v3(p0, top)])
	for i in 4:
		var sa := _screen(c[i])
		var sb := _screen(c[(i + 1) % 4])
		if sa != NOWHERE and sb != NOWHERE:
			overlay.draw_dashed_line(sa, sb, color, 2.0, 6.0)


func _draw_handles(overlay: Control) -> void:
	var info := map.build_info
	for si in selected:
		var h := map.data.sectors[si].floor_height
		for q in info.outline(si):
			_square(overlay, _v3(q, h), COLOR_SELECTED)
	for c in info.outer_corners:
		if selected.has(c.sector):
			_square(overlay, _v3(c.outer, c.h), COLOR_DRAW)
	var active := drag.handle if drag != null else handle
	if active == null:
		return
	var color := COLOR_BAD if drag != null and not drag.valid else Color.WHITE
	var h := active.h
	var a := drag.to_a if drag != null else active.a
	var b := drag.to_b if drag != null else active.b
	if active.is_edge():
		_line3(overlay, _v3(a, h), _v3(b, h), color, 4.0)
		_length_label(overlay, a, b, h)
	_marker(overlay, _v3(a, h), color, 5.0)
	if active.is_edge():
		_marker(overlay, _v3(b, h), color, 5.0)
	var tips: Array[String] = ["Drag to move this corner  •  Delete removes it", "Drag to move this wall  •  double-click adds a corner",
		"Drag to reshape the thick wall's outer corner", "Drag to change this wall's thickness"]
	var tip := tips[active.kind]
	var u := editor.units
	if drag != null and active.kind == Handle.Kind.OUTER_EDGE:
		tip = "Thickness: " + DMUnits.format(drag.thickness_now, u)
	elif drag != null and active.kind == Handle.Kind.OUTER_VERTEX:
		tip = "Corner: %s, %s" % [DMUnits.format(a.x, u), DMUnits.format(a.y, u)]
	elif drag != null:
		tip = "Can't go here (sides would cross or overlap)" if not drag.valid else (
			"Corner: %s, %s" % [DMUnits.format(a.x, u), DMUnits.format(a.y, u)]
			if active.kind == Handle.Kind.VERTEX else "Moved %s" % DMUnits.format(a.distance_to(active.a), u))
	_label(overlay, mouse_pos + Vector2(16, -8), tip, color)


func _square(overlay: Control, local: Vector3, color: Color) -> void:
	var sp := _screen(local)
	if sp != NOWHERE:
		overlay.draw_rect(Rect2(sp - Vector2(3.5, 3.5), Vector2(7, 7)), Color(0, 0, 0, 0.7))
		overlay.draw_rect(Rect2(sp - Vector2(2.5, 2.5), Vector2(5, 5)), color)


func _draw_drawing(overlay: Control) -> void:
	var h := draw_height
	for i in range(1, points.size()):
		_line3(overlay, _v3(points[i - 1], h), _v3(points[i], h), COLOR_DRAW, 2.5)
		_length_label(overlay, points[i - 1], points[i], h)
	var tp := typed_point()
	if cursor_valid:
		var closing := tp == NOWHERE and points.size() >= 3 and _near_first()
		if not points.is_empty():
			var end := tp if tp != NOWHERE else (points[0] if closing else cursor)
			_line3(overlay, _v3(points[points.size() - 1], h), _v3(end, h), Color(COLOR_DRAW, 0.6), 2.0)
			_length_label(overlay, points[points.size() - 1], end, h)
			if tp != NOWHERE:
				_marker(overlay, _v3(tp, h), COLOR_DRAW, 4.0)
		_marker(overlay, _v3(cursor, h), COLOR_CLOSE if closing else COLOR_DRAW, 5.0)
	for i in points.size():
		_marker(overlay, _v3(points[i], h), COLOR_CLOSE if i == 0 and points.size() >= 3 else COLOR_DRAW, 3.5)
	if not typed.is_empty():
		_label(overlay, mouse_pos + Vector2(16, 18), "Length: %s▏%s   Enter places the point" % [
			typed, DMUnits.suffix(editor.units)], COLOR_DRAW)
	var hint := "Draw polygon:  click to add points  •  type a length + Enter for an exact side  •  click the first point or Enter to finish  •  Backspace undoes  •  Shift: free angle / no snap  •  Esc stops (2+ points are kept, in red, to finish later)"
	_label(overlay, Vector2(12, overlay.size.y - 14), hint, Color(1, 1, 1, 0.85))


func _draw_rect(overlay: Control) -> void:
	var h := draw_height
	if cursor_valid:
		_marker(overlay, _v3(cursor, h), COLOR_DRAW, 5.0)
	var hint := "Draw rectangle:  click a corner"
	if rect_started:
		var a := rect_anchor
		var c := rect_corner()
		var corners := PackedVector2Array([a, Vector2(c.x, a.y), c, Vector2(a.x, c.y)])
		for i in 4:
			_line3(overlay, _v3(corners[i], h), _v3(corners[(i + 1) % 4], h), COLOR_DRAW, 2.5)
		_marker(overlay, _v3(a, h), COLOR_DRAW, 4.0)
		_length_label(overlay, corners[0], corners[1], h)
		_length_label(overlay, corners[1], corners[2], h)
		var fields: Array[String] = ["Width", "Depth"]
		var parts := PackedStringArray()
		for f in 2:
			var value := DMUnits.format(absf(c.x - a.x) if f == 0 else absf(c.y - a.y), editor.units)
			if f == rect_field and not typed.is_empty():
				value = "%s▏%s" % [typed, DMUnits.suffix(editor.units)]
			var locked := rect_size[f] > 0.0 or (f == rect_field and not typed.is_empty())
			var text := "%s: %s" % [fields[f], value]
			if locked:
				text += " (set)"
			parts.append(("[ %s ]" % text) if f == rect_field else text)
		_label(overlay, mouse_pos + Vector2(16, 18), "   ".join(parts), COLOR_DRAW)
		hint = "Draw rectangle:  click the opposite corner, or type the width, Tab, the depth, then Enter  •  Backspace clears a typed size  •  Esc cancels"
	_label(overlay, Vector2(12, overlay.size.y - 14), hint, Color(1, 1, 1, 0.85))


func _draw_face_outline(overlay: Control, f: int, color: Color, width: float) -> void:
	var faces := map.build_info.face_points
	if f < 0 or f >= faces.size():
		return
	var pts := faces[f]
	for i in pts.size():
		_line3(overlay, pts[i], pts[(i + 1) % pts.size()], color, width)


## Every wall of the selected sectors labelled with its length, at the
## floor. Walls shared by two selected sectors get one label; walls too short
## on screen to fit one get none.
func _draw_wall_lengths(overlay: Control) -> void:
	var done := {}
	var font := overlay.get_theme_font("font", "Label")
	var size := overlay.get_theme_font_size("font_size", "Label")
	for si in selected:
		var outline := map.build_info.outline(si)
		var h := map.data.sectors[si].floor_height
		for i in range(0, outline.size(), 2):
			var a := outline[i]
			var b := outline[i + 1]
			var ka := DMMapData.key_of(a)
			var kb := DMMapData.key_of(b)
			var key := [ka, kb] if ka < kb else [kb, ka]
			if done.has(key):
				continue
			done[key] = true
			var sa := _screen(_v3(a, h))
			var sb := _screen(_v3(b, h))
			if sa == NOWHERE or sb == NOWHERE:
				continue
			var text := DMUnits.format(a.distance_to(b), editor.units)
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
			if sa.distance_to(sb) < text_size.x + 16.0:
				continue
			var mid := (sa + sb) * 0.5
			_label(overlay, mid + Vector2(-text_size.x * 0.5, -4.0), text, COLOR_SELECTED.lightened(0.5))


func _length_label(overlay: Control, a: Vector2, b: Vector2, h: float) -> void:
	var length := a.distance_to(b)
	if length < 1e-4:
		return
	var sp := _screen(_v3((a + b) * 0.5, h))
	if sp != NOWHERE:
		_label(overlay, sp + Vector2(6, -6), DMUnits.format(length, editor.units), Color.WHITE)


static func _v3(p: Vector2, h: float) -> Vector3:
	return Vector3(p.x, h, p.y)


## Map-local point to screen, or NOWHERE when behind the camera.
func _screen(local: Vector3) -> Vector2:
	var world := map.map_transform() * local
	if camera.is_position_behind(world):
		return NOWHERE
	return camera.unproject_position(world)


func _line3(overlay: Control, a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var sa := _screen(a)
	var sb := _screen(b)
	if sa == NOWHERE or sb == NOWHERE:
		return
	overlay.draw_line(sa, sb, color, width, true)


func _marker(overlay: Control, local: Vector3, color: Color, radius: float) -> void:
	var sp := _screen(local)
	if sp != NOWHERE:
		overlay.draw_circle(sp, radius + 1.5, Color(0, 0, 0, 0.6))
		overlay.draw_circle(sp, radius, color)


func _label(overlay: Control, pos: Vector2, text: String, color: Color) -> void:
	var font := overlay.get_theme_font("font", "Label")
	var size := overlay.get_theme_font_size("font_size", "Label")
	overlay.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.85))
	overlay.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
