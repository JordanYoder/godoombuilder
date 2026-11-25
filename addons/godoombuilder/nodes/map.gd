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


## The last build result (see DMBuilder.build).
var build_info := {}

var _mesh_node: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _dirty := true


func _ready() -> void:
	if data == null:
		data = DMMapData.new()
	if Engine.is_editor_hint():
		_heal_shared_data()
	ensure_built()


## Rebuilds now if the data changed since the last build.
func ensure_built() -> void:
	if _dirty:
		rebuild()


func rebuild() -> void:
	_dirty = false
	_ensure_mesh_node()
	build_info = DMBuilder.build(data)
	var mesh := DMBuilder.to_mesh(build_info)
	_mesh_node.mesh = mesh
	_shape.shape = mesh.create_trimesh_shape() if mesh.get_surface_count() > 0 else null


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
## Returns {} or {face, sector, part, point (map-local), distance}.
func pick(origin: Vector3, direction: Vector3) -> Dictionary:
	ensure_built()
	if build_info.is_empty():
		return {}
	var inv := map_transform().affine_inverse()
	var o := inv * origin
	var dir := (inv.basis * direction).normalized()
	var tris: PackedVector3Array = build_info.tris
	var tri_face: PackedInt32Array = build_info.tri_face
	var normals: PackedVector3Array = build_info.face_normal
	var best := INF
	var hit := {}
	for t in tri_face.size():
		var f := tri_face[t]
		if normals[f].dot(dir) >= 0.0:
			continue
		var p = Geometry3D.ray_intersects_triangle(o, dir, tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2])
		if p == null:
			continue
		var dist := o.distance_to(p)
		if dist < best:
			best = dist
			hit = {"face": f, "sector": build_info.face_sector[f], "part": build_info.face_part[f],
				"point": p, "distance": dist}
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
	for other in root.find_children("*", "DMMap", true, false):
		if other != self and other.data == data:
			data = data.duplicate_data()
			return
