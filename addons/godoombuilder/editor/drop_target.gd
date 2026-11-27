@tool
class_name DMDropTarget
extends Control
## Lets a material or texture be dragged from the FileSystem dock (or the
## Inspector) onto a sector map's floor, ceiling or walls in a 3D view.
##
## It covers one 3D view but only catches the mouse while something is being
## dragged; a drop that isn't for a sector map goes on to Godot's own view
## (e.g. dropping a scene still adds it).


## What applies the drop.
var editor: DMEditor
## Which 3D view (0-3) this is over: its camera is used to find the surface.
var view := 0


func _init() -> void:
	name = "GoDoomBuilderDrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		mouse_filter = Control.MOUSE_FILTER_PASS
	elif what == NOTIFICATION_DRAG_END:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if editor == null or not is_droppable(data):
		return false
	var target := _target_at(at)
	if target == null:
		return false
	editor.show_drop_hint(target.map, target.hit)
	return true


func _drop_data(at: Vector2, data: Variant) -> void:
	var target := _target_at(at)
	var res := dropped_resource(data)
	if target == null or res == null:
		return
	editor.drop_on_surface(target.map, target.hit, res)


## True when `data` (from a drag) is a material or texture, without loading it.
static func is_droppable(data: Variant) -> bool:
	return _droppable_path(data) != "" or _dragged_resource(data) != null


## The material or texture `data` carries (loaded from its file), or null.
static func dropped_resource(data: Variant) -> Resource:
	var res := _dragged_resource(data)
	if res != null:
		return res
	var path := _droppable_path(data)
	if path.is_empty():
		return null
	res = load(path)
	return res if res is Material or res is Texture2D else null


static func _dragged_resource(data: Variant) -> Resource:
	if data is Dictionary:
		var d: Dictionary = data
		if d.get("type") == "resource":
			var v: Variant = d.get("resource")
			if v is Material or v is Texture2D:
				var res: Resource = v
				return res
	return null


## The first dragged file that's a material or texture, or "".
static func _droppable_path(data: Variant) -> String:
	if not data is Dictionary:
		return ""
	var d: Dictionary = data
	if d.get("type") != "files":
		return ""
	var files: PackedStringArray = d.get("files", PackedStringArray())
	for path in files:
		if _is_material_or_texture(path):
			return path
	return ""


## Checked by the editor's file type (no loading while dragging), or by
## loading it outside the editor (e.g. in tests).
static func _is_material_or_texture(path: String) -> bool:
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		var type := fs.get_file_type(path) if fs != null else ""
		return not type.is_empty() and (ClassDB.is_parent_class(type, "Material") or ClassDB.is_parent_class(type, "Texture2D"))
	if not ResourceLoader.exists(path):
		return false
	var res := load(path)
	return res is Material or res is Texture2D


## A sector map surface a drop would land on.
class Target:
	var map: DMMap
	var hit: DMMap.Hit


## The sector map surface under `at` in this view, or null.
func _target_at(at: Vector2) -> Target:
	var vp := EditorInterface.get_editor_viewport_3d(view)
	var camera := vp.get_camera_3d() if vp != null else null
	var root := EditorInterface.get_edited_scene_root()
	if camera == null or root == null:
		return null
	# The 3D view may render at a different resolution than it's shown.
	var scale := Vector2(vp.size) / size if size.x > 0.0 and size.y > 0.0 else Vector2.ONE
	var pos := at * scale
	var origin := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var maps: Array[Node] = root.find_children("*", "DMMap", true, false)
	if root is DMMap:
		maps.append(root)
	var best: Target = null
	var best_dist := INF
	for node in maps:
		var m := node as DMMap
		if m == null or not m.is_visible_in_tree():
			continue
		var hit := m.pick(origin, dir)
		if hit == null:
			continue
		var dist := origin.distance_to(m.global_transform * hit.point)
		if dist < best_dist:
			best_dist = dist
			best = Target.new()
			best.map = m
			best.hit = hit
	return best
