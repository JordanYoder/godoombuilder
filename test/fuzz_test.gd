# Randomized tests for the sector map core: draws and drags random shapes and
# checks the rules every map must keep. Run from the project folder:
#   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://test/fuzz_test.gd
# A failure prints its seed; pass it back to rerun just that case:
#   ... --script res://test/fuzz_test.gd -- --seed=1234
# More rounds for a longer search: -- --rounds=500 [--start=5000] (add --verbose to print the
# shapes involved in a failed draw).
extends SceneTree

const ROUNDS := 40
const DRAWS_PER_ROUND := 12
const DRAGS_PER_ROUND := 8
const SAMPLES := 300

var fails := 0
var rng := RandomNumberGenerator.new()


func fail(seed_used: int, what: String) -> void:
	fails += 1
	print("FAIL seed=%d: %s" % [seed_used, what])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := -1
	var rounds := ROUNDS
	var first := 1000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			only = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--start="):
			first = int(arg.trim_prefix("--start="))
		elif arg.begins_with("--rounds="):
			rounds = int(arg.trim_prefix("--rounds="))
	var seeds: Array[int] = []
	if only >= 0:
		seeds.append(only)
	else:
		for r in rounds:
			seeds.append(first + r)
	var drawn_total := 0
	var refused_total := 0
	var dragged_total := 0
	for sd in seeds:
		var counts := _round(sd)
		drawn_total += counts[0]
		refused_total += counts[1]
		dragged_total += counts[2]
	print("%d rounds: %d shapes drawn, %d refused, %d valid drags" % [seeds.size(), drawn_total, refused_total, dragged_total])
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)


## One map: random draws, then random corner drags. Returns [drawn, refused, dragged].
func _round(sd: int) -> Array[int]:
	rng.seed = sd
	var data := DMMapData.new()
	var defaults := DMSector.new()
	var drawn: Array[PackedVector2Array] = []
	var refused := 0
	for d in DRAWS_PER_ROUND:
		var loop := _random_loop()
		var before := data.duplicate_data()
		var r := data.add_loop(loop, defaults)
		if not r.ok:
			refused += 1
			# The plugin restores the snapshot on failure; it must be exact.
			data.copy_from(before)
			if not _same(data, before):
				fail(sd, "restoring after a refused draw changed the map")
			if r.message.contains("covered"):
				drawn.append(DMGeo.normalized(loop))
			continue
		drawn.append(DMGeo.normalized(loop))
		var why := data.validate()
		if not why.is_empty():
			fail(sd, "after drawing shape %d: %s" % [d, why])
			if OS.get_cmdline_user_args().has("--verbose"):
				print("  drew ", loop)
				for s in before.sectors:
					print("  before: ", s.polygons)
				for s in data.sectors:
					for p in s.polygons:
						if not DMGeo.is_simple(p):
							print("  not simple: ", p)
			return [drawn.size(), refused, 0]
		_check_coverage(sd, data, drawn, "after drawing shape %d" % d)
		_check_round_trip(sd, data, "after drawing shape %d" % d)
		_check_build(sd, data, "after drawing shape %d" % d)
	if not data.check().is_empty():
		fail(sd, "check() complains about a map made by drawing: %s" % ", ".join(data.check()))

	# Drags: move a random corner; keep valid results, undo invalid ones.
	var dragged := 0
	for d in DRAGS_PER_ROUND:
		var verts := data.all_vertices()
		if verts.is_empty():
			break
		var from := verts[rng.randi_range(0, verts.size() - 1)]
		var to := from + Vector2(rng.randi_range(-4, 4), rng.randi_range(-4, 4)) * 0.5
		var before := data.duplicate_data()
		data.move_vertices(PackedVector2Array([from]), PackedVector2Array([to]))
		if data.validate().is_empty():
			dragged += 1
			_check_round_trip(sd, data, "after drag %d" % d)
			_check_build(sd, data, "after drag %d" % d)
		else:
			data.copy_from(before)
			if not _same(data, before):
				fail(sd, "undoing an invalid drag changed the map")
	return [drawn.size(), refused, dragged]


## A random rectangle, or a star-shaped polygon (may cross itself after
## snapping to the grid, which add_loop must refuse cleanly).
func _random_loop() -> PackedVector2Array:
	var c := Vector2(rng.randi_range(-12, 12), rng.randi_range(-12, 12)) * 0.5
	if rng.randf() < 0.5:
		var size := Vector2(rng.randi_range(1, 12), rng.randi_range(1, 12)) * 0.5
		return PackedVector2Array([c, c + Vector2(size.x, 0), c + size, c + Vector2(0, size.y)])
	var n := rng.randi_range(3, 9)
	var angles: Array[float] = []
	for i in n:
		angles.append(rng.randf() * TAU)
	angles.sort()
	var out := PackedVector2Array()
	for a in angles:
		var r := rng.randf_range(0.5, 5.0)
		out.append((c + Vector2(cos(a), sin(a)) * r).snapped(Vector2(0.25, 0.25)))
	return out


## Every sampled point inside a drawn shape is in exactly one sector, and every
## point outside all drawn shapes is in none (no gaps, no overlaps). Points near
## any edge are skipped, since either answer is right there.
func _check_coverage(sd: int, data: DMMapData, drawn: Array[PackedVector2Array], when: String) -> void:
	var edges := PackedVector2Array()
	for p in drawn:
		for i in p.size():
			edges.append_array([p[i], p[(i + 1) % p.size()]])
	for s in data.sectors:
		for p in s.polygons:
			for i in p.size():
				edges.append_array([p[i], p[(i + 1) % p.size()]])
	var locator := data.locator()
	for k in SAMPLES:
		var pt := Vector2(rng.randf_range(-12, 18), rng.randf_range(-12, 18))
		if locator.sector_at(pt) != data.sector_at(pt):
			fail(sd, "%s: the sector locator disagrees with sector_at at %s" % [when, pt])
			return
		var near_edge := false
		for i in range(0, edges.size(), 2):
			if Geometry2D.get_closest_point_to_segment(pt, edges[i], edges[i + 1]).distance_to(pt) < 0.01:
				near_edge = true
				break
		if near_edge:
			continue
		var inside_drawn := false
		for p in drawn:
			if DMGeo.point_in_polygon(pt, p):
				inside_drawn = true
				break
		var count := 0
		for s in data.sectors:
			if s.contains_point(pt):
				count += 1
		if count != (1 if inside_drawn else 0):
			fail(sd, "%s: point %s is in %d sectors (drawn there: %s)" % [when, pt, count, inside_drawn])
			if OS.get_cmdline_user_args().has("--verbose"):
				for p in drawn:
					if DMGeo.point_in_polygon(pt, p):
						print("  drawn around it: ", p)
				for s in data.sectors:
					for p in s.polygons:
						if p.size() > 0 and Rect2(p[0], Vector2.ZERO).expand(pt).size.length() < 30:
							pass
				print("  last drawn: ", drawn[drawn.size() - 1])
				for s in data.sectors:
					if s.contains_point(pt):
						print("  sector containing it: ", s.polygons)
			return


## An undo snapshot restores exactly what was there.
func _check_round_trip(sd: int, data: DMMapData, when: String) -> void:
	var snap := data.duplicate_data()
	var other := DMMapData.new()
	other.copy_from(snap)
	if not _same(other, data):
		fail(sd, "%s: a snapshot doesn't restore the same map" % when)


## Building never fails and keeps its per-face tables in step.
func _check_build(sd: int, data: DMMapData, when: String) -> void:
	var info := DMBuilder.build(data)
	var faces := (info.face_points as Array).size()
	if (info.face_tri_start as PackedInt32Array).size() != faces + 1 or (info.face_box as Array).size() != faces \
			or (info.face_normal as PackedVector3Array).size() != faces or (info.tris as PackedVector3Array).size() != (info.tri_face as PackedInt32Array).size() * 3:
		fail(sd, "%s: build tables out of step" % when)
	if (info.outlines as Array).size() != data.sectors.size():
		fail(sd, "%s: one outline per sector expected" % when)
	# Floors cover the sectors' area exactly (every piece triangulated).
	var floor_area := 0.0
	var tris: PackedVector3Array = info.tris
	for t in (info.tri_face as PackedInt32Array).size():
		if info.face_part[info.tri_face[t]] == DMBuilder.Part.FLOOR:
			floor_area += (tris[t * 3 + 1] - tris[t * 3]).cross(tris[t * 3 + 2] - tris[t * 3]).length() * 0.5
	var area := 0.0
	for s in data.sectors:
		area += s.area()
	if absf(floor_area - area) > 0.001 * maxf(area, 1.0):
		fail(sd, "%s: floors cover %.4f m² but sectors are %.4f m²" % [when, floor_area, area])


## Every saved property of every sector matches.
static func _same(a: DMMapData, b: DMMapData) -> bool:
	if a.sectors.size() != b.sectors.size():
		return false
	for i in a.sectors.size():
		for prop in a.sectors[i].get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE and a.sectors[i].get(prop.name) != b.sectors[i].get(prop.name):
				return false
	return true
