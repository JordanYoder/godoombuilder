# Plays the demo level headlessly with simulated key presses. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://test/player_test.gd
extends SceneTree

var fails := 0
var worst_down := 0.0
var player: CharacterBody3D


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func hold(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## Teleports the player, facing `yaw` (0 = -Z, PI/2 = -X, -PI/2 = +X, PI = +Z), and lets it land.
func place(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation = Vector3(0, yaw, 0)
	player.velocity = Vector3.ZERO
	await frames(30)


func walk(code: Key, n: int) -> void:
	hold(code, true)
	await frames(n)
	hold(code, false)
	await frames(10)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load("res://test/demo_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("FPSPlayer")
	await frames(60)
	check(player.is_on_floor() and absf(player.global_position.y) < 0.05,
		"player lands on the hall floor (y=%.3f)" % player.global_position.y)

	# Walk north (+Z) toward the corridor.
	var z0 := player.global_position.z
	await walk(KEY_W, 60)
	check(player.global_position.z > z0 + 3.0, "W walks forward (moved %.2f m)" % (player.global_position.z - z0))

	# Walk east up the 0.25 m stairs onto the 1 m platform, no jumping.
	await place(Vector3(6.5, 0.05, 5), -PI / 2.0)
	await walk(KEY_W, 90)
	var p := player.global_position
	check(p.x > 9.2 and absf(p.y - 1.0) < 0.06, "walks up the stairs onto the platform (x=%.2f y=%.2f)" % [p.x, p.y])

	# Walk back west off the platform and down the stairs.
	await walk(KEY_S, 90)
	p = player.global_position
	check(p.x < 7.4 and absf(p.y) < 0.06, "walks back down to the hall floor (x=%.2f y=%.2f)" % [p.x, p.y])

	# The view eases over steps instead of jumping (Doom-style).
	var cam: Camera3D = player.get_node("Head/Camera3D")
	var jumps := []
	for smoothing in [0.0, 14.0]:
		player.step_smoothing = smoothing
		await place(Vector3(6.5, 0.05, 5), -PI / 2.0)
		var worst := 0.0
		var last := cam.global_position.y
		hold(KEY_W, true)
		for i in 90:
			await physics_frame
			worst = maxf(worst, absf(cam.global_position.y - last))
			last = cam.global_position.y
		hold(KEY_W, false)
		await frames(30)
		jumps.append(worst)
	print("  biggest camera jump per frame on the stairs: %.3f m unsmoothed, %.3f m smoothed" % jumps)
	check(jumps[0] > 0.2, "without smoothing the view jumps a whole step")
	check(jumps[1] < 0.09, "with smoothing the view moves at most %.3f m per frame" % jumps[1])
	check(is_zero_approx(player.view_offset), "the view settles back to eye height on the platform")
	worst_down = 0.0
	var last_down := cam.global_position.y
	hold(KEY_S, true)
	for i in 90:
		await physics_frame
		worst_down = maxf(worst_down, absf(cam.global_position.y - last_down))
		last_down = cam.global_position.y
	hold(KEY_S, false)
	await frames(30)
	check(worst_down < 0.09, "walking down the stairs is smooth too (%.3f m per frame)" % worst_down)

	# Walls block: walking into the west wall stops at it.
	await place(Vector3(1.0, 0.05, 1.0), PI / 2.0)
	await walk(KEY_W, 60)
	check(player.global_position.x > 0.3, "the outer wall blocks the player (x=%.2f)" % player.global_position.x)

	# Drop into the pit and jump out.
	await place(Vector3(3.0, 0.05, 7.5), 0.0)
	check(absf(player.global_position.y + 0.75) < 0.06, "falls to the pit floor (y=%.2f)" % player.global_position.y)
	await walk(KEY_W, 60)
	check(player.global_position.y < -0.7, "can't simply walk out of the 0.75 m pit")
	hold(KEY_W, true)
	hold(KEY_SPACE, true)
	await frames(8)
	hold(KEY_SPACE, false)
	await frames(50)
	hold(KEY_W, false)
	await frames(20)
	check(absf(player.global_position.y) < 0.06 and player.global_position.z < 6.0,
		"jumping gets out of the pit (y=%.2f z=%.2f)" % [player.global_position.y, player.global_position.z])

	# Through the low corridor and up the 0.5 m step into the second room.
	await place(Vector3(5, 0.05, 11), PI)
	await walk(KEY_W, 75)
	p = player.global_position
	check(p.z > 16.5 and absf(p.y - 0.5) < 0.06, "corridor leads up a step into the second room (z=%.2f y=%.2f)" % [p.z, p.y])

	# Fly mode moves freely and V turns it back off.
	hold(KEY_V, true)
	await frames(2)
	hold(KEY_V, false)
	var fly_ok: bool = player.flying
	hold(KEY_SPACE, true)
	await frames(30)
	hold(KEY_SPACE, false)
	check(fly_ok and player.global_position.y > 1.5, "V turns on fly mode and Space rises")
	hold(KEY_V, true)
	await frames(2)
	hold(KEY_V, false)
	await frames(90)
	check(not player.flying and player.is_on_floor(), "V again turns fly off and the player lands")

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
