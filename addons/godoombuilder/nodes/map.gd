@tool
@icon("res://addons/godoombuilder/icons/map.svg")
class_name DMMap
extends Node3D
## A Doom-style map built from sectors: each sector is a floor area with its own
## floor and ceiling heights, and walls are generated between them.
##
## Select this node and use the Sectors dock to draw and edit it. The mesh and
## collision are rebuilt from the sector data, in the editor and in the game.


@export var data: DMMapData:
	set(value):
		if data == value:
			return
		if data != null and data.changed.is_connected(_on_data_changed):
			data.changed.disconnect(_on_data_changed)
		data = value
		if data != null:
			data.changed.connect(_on_data_changed)
		_on_data_changed()

@export_group("Collision")
@export var collision_enabled := true:
	set(value):
		collision_enabled = value
		_apply_collision_settings()
@export_flags_3d_physics var collision_layer := 1:
	set(value):
		collision_layer = value
		_apply_collision_settings()
@export_flags_3d_physics var collision_mask := 1:
	set(value):
		collision_mask = value
		_apply_collision_settings()


## What pick() hit.
class Hit:
	var face: int
	var sector: int
	## DMBuilder.Part
	var part: int
	## Map-local.
	var point: Vector3
	var distance: float


## The last build result (see DMBuilder.build).
var build_info := DMBuildInfo.new()

var _mesh_node: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _dirty := true
var _collision_dirty := false
## Editor selection tint (see set_highlight).
var _highlight_node: MeshInstance3D
var _highlight_sectors := PackedInt32Array()
var _highlight_color := Color.TRANSPARENT
var _highlight_info: DMBuildInfo


func _ready() -> void:
	if data == null:
		data = DMMapData.new()
	if Engine.is_editor_hint():
		_heal_shared_data()
	for problem in data.check():
		push_warning("GoDoomBuilder: %s: %s" % [get_path() if is_inside_tree() else name, problem])
	ensure_built()


## Rebuilds now if the data changed since the last build (and brings the
## collision up to date if a rebuild skipped it).
func ensure_built() -> void:
	if _dirty:
		rebuild()
	elif _collision_dirty:
		_update_collision()


## Rebuilds the mesh from the data. `with_collision` false leaves the old
## collision shape in place (e.g. while dragging, where it would be rebuilt on
## every mouse move); ensure_built() or the next full rebuild() updates it.
func rebuild(with_collision := true) -> void:
	_dirty = false
	_ensure_mesh_node()
	build_info = DMBuilder.build(data)
	_mesh_node.mesh = DMBuilder.to_mesh(build_info)
	if with_collision:
		_update_collision()
	else:
		_collision_dirty = true


## True when the collision shape lags behind the mesh (see rebuild()).
func is_collision_stale() -> bool:
	return _collision_dirty


func _update_collision() -> void:
	_collision_dirty = false
	_ensure_mesh_node()
	var tris := build_info.tris
	if tris.is_empty():
		_shape.shape = null
		return
	# The mesh's own triangles, in the same winding, so this matches what
	# Mesh.create_trimesh_shape() would give without going through the mesh.
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tris)
	_shape.shape = shape


## Tints the surfaces of the given sectors with `color` (its alpha is how
## strong the tint is), e.g. to show the editor's selection. Empty clears it.
## Cheap to call every frame: it only rebuilds when something changed.
func set_highlight(sectors: PackedInt32Array, color: Color) -> void:
	if sectors == _highlight_sectors and color == _highlight_color and _highlight_info == build_info:
		return
	_highlight_sectors = sectors
	_highlight_color = color
	_highlight_info = build_info
	if sectors.is_empty() or build_info == null or build_info.tris.is_empty():
		if is_instance_valid(_highlight_node):
			_highlight_node.mesh = null
		return
	if not is_instance_valid(_highlight_node):
		_highlight_node = MeshInstance3D.new()
		_highlight_node.name = "SelectionTint"
		_highlight_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_highlight_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_highlight_node, false, Node.INTERNAL_MODE_BACK)
	var picked := {}
	for si in sectors:
		picked[si] = true
	var info := build_info
	var verts := PackedVector3Array()
	# Lifted a few millimetres off each surface so the tint isn't hidden by
	# the surface it lies on.
	for t in info.tri_face.size():
		var f := info.tri_face[t]
		if not picked.has(info.face_sector[f]):
			continue
		var lift := info.face_normal[f] * 0.004
		for k in 3:
			verts.append(info.tris[t * 3 + k] + lift)
	if verts.is_empty():
		_highlight_node.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	mat.render_priority = 1
	mesh.surface_set_material(0, mat)
	_highlight_node.mesh = mesh


## The generated mesh node (internal: not saved with the scene).
func mesh_node() -> MeshInstance3D:
	_ensure_mesh_node()
	return _mesh_node


## The generated collision body (internal: not saved with the scene).
func collision_body() -> StaticBody3D:
	_ensure_mesh_node()
	return _body


## Casts a world-space ray against the map. Faces seen from behind are skipped,
## so looking down through a ceiling hits the floor below.
## Returns what it hits first, or null.
func pick(origin: Vector3, direction: Vector3) -> Hit:
	ensure_built()
	if build_info.is_empty():
		return null
	var inv := map_transform().affine_inverse()
	var o := inv * origin
	var dir := (inv.basis * direction).normalized()
	var tris := build_info.tris
	var normals := build_info.face_normal
	var boxes := build_info.face_box
	var tri_start := build_info.face_tri_start
	var best := INF
	var hit: Hit = null
	for f in normals.size():
		if normals[f].dot(dir) >= 0.0:
			continue
		# Skip faces whose bounding box the ray misses (or only meets beyond
		# the best hit so far) before testing their triangles.
		var box := boxes[f]
		if not box.has_point(o):
			var entry: Variant = box.intersects_ray(o, dir)
			if entry == null:
				continue
			var entry_point: Vector3 = entry
			if o.distance_to(entry_point) > best:
				continue
		for t in range(tri_start[f], tri_start[f + 1]):
			var p: Variant = Geometry3D.ray_intersects_triangle(o, dir, tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2])
			if p == null:
				continue
			var at: Vector3 = p
			var dist := o.distance_to(at)
			if dist < best:
				best = dist
				hit = Hit.new()
				hit.face = f
				hit.sector = build_info.face_sector[f]
				hit.part = build_info.face_part[f]
				hit.point = at
				hit.distance = dist
	return hit


## The map's world transform (its local transform while outside the tree).
func map_transform() -> Transform3D:
	return global_transform if is_inside_tree() else transform


func _on_data_changed() -> void:
	_dirty = true
	if is_inside_tree():
		_flush.call_deferred()


func _flush() -> void:
	if _dirty and is_inside_tree():
		rebuild()


func _ensure_mesh_node() -> void:
	if is_instance_valid(_mesh_node):
		return
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "MapMesh"
	add_child(_mesh_node, false, Node.INTERNAL_MODE_BACK)
	_body = StaticBody3D.new()
	_body.name = "MapCollision"
	_shape = CollisionShape3D.new()
	_body.add_child(_shape)
	add_child(_body, false, Node.INTERNAL_MODE_BACK)
	_apply_collision_settings()


func _apply_collision_settings() -> void:
	if not is_instance_valid(_body):
		return
	_body.collision_layer = collision_layer if collision_enabled else 0
	_body.collision_mask = collision_mask if collision_enabled else 0
	_shape.disabled = not collision_enabled


## A duplicated map node (Ctrl+D) would share its data with the original;
## give the copy its own so editing one doesn't change the other.
func _heal_shared_data() -> void:
	var root := get_tree().edited_scene_root if get_tree() != null else null
	if root == null or data == null:
		return
	for node in root.find_children("*", "DMMap", true, false):
		var other := node as DMMap
		if other != null and other != self and other.data == data:
			data = data.duplicate_data()
			return
