@tool
extends EditorPlugin
## GoDoomBuilder: Doom-style sector mapping for Godot. The editing itself is
## in DMEditor; this connects it to Godot's editor (undo history, messages,
## the dock, the toolbar and the grid).


const SETTINGS := "godoombuilder"


## DMEditor with the editor-specific parts filled in.
class PluginEditor:
	extends DMEditor

	var host: EditorPlugin
	var dock: DMDock
	var toolbar: DMToolbar
	var grid: DMGrid

	func _record_undo(action: String, before: DMMapData, after: DMMapData, merge: bool) -> void:
		var ur := host.get_undo_redo()
		ur.create_action(action, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE, map)
		ur.add_do_method(map.data, "copy_from", after)
		ur.add_undo_method(map.data, "copy_from", before)
		ur.commit_action(false)

	func notify(message: String, severity := Severity.WARNING) -> void:
		var toaster := EditorInterface.get_editor_toaster()
		if toaster == null:
			print("GoDoomBuilder: ", message)
			return
		toaster.push_toast(message, EditorToaster.SEVERITY_INFO if severity == Severity.INFO else EditorToaster.SEVERITY_WARNING)

	func update_overlays() -> void:
		host.update_overlays()

	func _refresh_ui() -> void:
		if dock != null:
			dock.refresh()
		if toolbar != null:
			toolbar.visible = map != null
			toolbar.refresh()
		_update_grid()

	func _update_grid() -> void:
		if grid == null:
			return
		if map == null or not map.is_inside_tree():
			grid.update(null, false, 0.0, grid_step)
			return
		var vp := EditorInterface.get_editor_viewport_3d(0)
		var world: World3D = vp.find_world_3d() if vp != null else map.get_world_3d()
		var y := (map.global_transform * Vector3(0, tool.grid_height(), 0)).y
		grid.update(world, true, y, grid_step)

	func new_map() -> void:
		var root := EditorInterface.get_edited_scene_root()
		if root == null:
			notify("Open or create a 3D scene first.")
			return
		var m := DMMap.new()
		m.name = "SectorMap"
		m.data = DMMapData.new()
		var ur := host.get_undo_redo()
		ur.create_action("Add Sector Map", UndoRedo.MERGE_DISABLE, root)
		ur.add_do_method(root, "add_child", m, true)
		ur.add_do_method(m, "set_owner", root)
		ur.add_do_reference(m)
		ur.add_undo_method(root, "remove_child", m)
		ur.commit_action()
		var sel := EditorInterface.get_selection()
		sel.clear()
		sel.add_node(m)

	func _get_setting(key: String, fallback: Variant) -> Variant:
		return EditorInterface.get_editor_settings().get_project_metadata(SETTINGS, key, fallback)

	func _set_setting(key: String, value: Variant) -> void:
		EditorInterface.get_editor_settings().set_project_metadata(SETTINGS, key, value)

	var _file_dialog: EditorFileDialog
	var _on_file := Callable()

	func _pick_file(save: bool, on_pick: Callable) -> void:
		if _file_dialog == null:
			_file_dialog = EditorFileDialog.new()
			_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
			_file_dialog.add_filter("*.tres", "Sector prefab")
			_file_dialog.add_filter("*.res", "Sector prefab (binary)")
			_file_dialog.file_selected.connect(func(path: String) -> void:
				if _on_file.is_valid():
					_on_file.call(path))
			EditorInterface.get_base_control().add_child(_file_dialog)
		_on_file = on_pick
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE if save else EditorFileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.title = "Save Selection as Prefab" if save else "Paste Prefab"
		_file_dialog.popup_centered_ratio(0.6)

	func free_dialogs() -> void:
		if _file_dialog != null:
			_file_dialog.queue_free()
			_file_dialog = null
		_on_file = Callable()


var editor: PluginEditor

var _dock: EditorDock
var _toolbar: DMToolbar
var _grid: DMGrid


func _enter_tree() -> void:
	editor = PluginEditor.new()
	editor.host = self
	_grid = DMGrid.new()
	editor.grid = _grid
	editor.load_settings()

	var dock_panel := DMDock.new()
	dock_panel.editor = editor
	editor.dock = dock_panel
	_dock = EditorDock.new()
	_dock.name = "DMDock"
	_dock.title = "Sectors"
	_dock.layout_key = "godoombuilder"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_dock.dock_icon = preload("res://addons/godoombuilder/icons/map.svg")
	_dock.add_child(dock_panel)
	add_dock(_dock)

	_toolbar = DMToolbar.new()
	_toolbar.editor = editor
	_toolbar.visible = false
	editor.toolbar = _toolbar
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)


func _exit_tree() -> void:
	editor.save_settings()
	editor.dispose()
	editor.free_dialogs()
	editor.dock = null
	editor.toolbar = null
	editor.grid = null
	if _grid != null:
		_grid.cleanup()
		_grid = null
	if _toolbar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
		_toolbar = null
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null


func _handles(object: Object) -> bool:
	return object is DMMap


func _edit(object: Object) -> void:
	editor.set_map(object as DMMap)


func _make_visible(visible: bool) -> void:
	if not visible:
		editor.set_map(null)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if editor.map == null:
		return AFTER_GUI_INPUT_PASS
	return editor.tool.handle_input(camera, event)


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if editor.map != null:
		editor.tool.draw_overlay(overlay)
