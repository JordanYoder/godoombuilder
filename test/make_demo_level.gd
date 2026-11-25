# Builds test/demo_level.tscn: a small sector map to walk around in.
# Run from the project folder (re-run any time to regenerate it):
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://test/make_demo_level.gd
extends SceneTree


static func rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## A two-tone checker material (one square per 0.5 m-ish), saved as a .tres.
static func checker(name: String, a: Color, b: Color) -> StandardMaterial3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var c := a if ((x / 32) + (y / 32)) % 2 == 0 else b
			# A faint edge line makes the grid readable.
			if x % 32 == 0 or y % 32 == 0:
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 0.9
	var path := "res://test/materials/%s.tres" % name
	ResourceSaver.save(mat, path)
	return load(path) as StandardMaterial3D


func _initialize() -> void:
	var floor_mat := checker("demo_floor", Color(0.55, 0.55, 0.58), Color(0.42, 0.42, 0.45))
	var wall_mat := checker("demo_wall", Color(0.72, 0.62, 0.48), Color(0.62, 0.52, 0.40))
	var ceil_mat := checker("demo_ceiling", Color(0.32, 0.32, 0.36), Color(0.26, 0.26, 0.30))
	var step_mat := checker("demo_step", Color(0.80, 0.55, 0.25), Color(0.68, 0.45, 0.18))
	var slime_mat := checker("demo_slime", Color(0.25, 0.75, 0.25), Color(0.18, 0.60, 0.18))

	var d := DMSector.new()
	d.floor_height = 0.0
	d.ceiling_height = 5.0
	d.floor_material = floor_mat
	d.ceiling_material = ceil_mat
	d.wall_material = wall_mat

	var data := DMMapData.new()
	var s := data.sectors

	# Main hall, 12 x 10 m, 5 m high.
	data.add_loop(rect(0, 0, 12, 10), d)
	# Staircase up to a platform along the east wall: 0.25 m steps.
	var heights := [0.25, 0.5, 0.75]
	for i in heights.size():
		var r := data.add_loop(rect(7.5 + i * 0.5, 2, 8.0 + i * 0.5, 8), d)
		data.sectors[r.index].floor_height = heights[i]
		data.sectors[r.index].floor_material = step_mat
	var plat := data.add_loop(rect(9, 2, 12, 8), d)
	data.sectors[plat.index].floor_height = 1.0
	# A pit, 0.75 m deep (jump out).
	var pit := data.add_loop(rect(1.5, 6, 4.5, 9), d)
	data.sectors[pit.index].floor_height = -0.75
	# A pillar: draw a sector, then delete it so its area is solid.
	var pillar := data.add_loop(rect(3, 2, 4, 3), d)
	data.delete_sectors([pillar.index])
	# Low corridor north, 2.5 m ceiling.
	var hall := data.add_loop(rect(4, 10, 6, 16), d)
	data.sectors[hall.index].ceiling_height = 2.5
	# Second room, one 0.5 m step up, with a sunken slime pool under a tall skylight.
	var room := data.add_loop(rect(0, 16, 10, 24), d)
	data.sectors[room.index].floor_height = 0.5
	data.sectors[room.index].ceiling_height = 4.0
	var pool := data.add_loop(rect(3, 18, 7, 22), d)
	data.sectors[pool.index].floor_height = 0.25
	data.sectors[pool.index].ceiling_height = 7.0
	data.sectors[pool.index].floor_material = slime_mat

	var level := Node3D.new()
	level.name = "DemoLevel"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(level, we)

	var map := DMMap.new()
	map.name = "SectorMap"
	map.data = data
	_add(level, map)

	for spot in [Vector3(6, 4, 5), Vector3(10.5, 4, 5), Vector3(5, 2.2, 13), Vector3(5, 3.5, 20)]:
		var light := OmniLight3D.new()
		light.name = "Light%d" % level.get_child_count()
		light.position = spot
		light.omni_range = 11.0
		light.light_energy = 1.6
		light.shadow_enabled = true
		_add(level, light)
	var glow := OmniLight3D.new()
	glow.name = "SlimeGlow"
	glow.position = Vector3(5, 1.0, 20)
	glow.light_color = Color(0.4, 1.0, 0.4)
	glow.light_energy = 1.2
	glow.omni_range = 5.0
	_add(level, glow)

	var player := (load("res://test/player/fps_player.tscn") as PackedScene).instantiate()
	player.name = "FPSPlayer"
	player.position = Vector3(6, 0.05, 2)
	player.rotation.y = PI # Face north, toward the corridor.
	_add(level, player)

	var packed := PackedScene.new()
	var err := packed.pack(level)
	if err == OK:
		err = ResourceSaver.save(packed, "res://test/demo_level.tscn")
	print("demo level: %d sectors, save %s" % [data.sectors.size(), "OK" if err == OK else "FAILED (%d)" % err])
	level.free()
	quit(0 if err == OK else 1)


static func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = parent
