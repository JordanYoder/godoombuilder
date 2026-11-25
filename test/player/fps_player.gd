extends CharacterBody3D
## Simple first-person player for walking around sector maps.
##
## WASD move · mouse look · Space jump · Shift run · V fly (noclip)
## Click captures the mouse, Esc releases it.
## Walks up steps up to `step_height` like a Doom player (no jumping needed).
## Like Doom, the body moves onto a step instantly but the view eases after it,
## so stairs feel like a smooth climb instead of a series of jolts.


@export var walk_speed := 5.0
@export var run_speed := 8.5
@export var fly_speed := 10.0
@export var jump_velocity := 4.6
@export var mouse_sensitivity := 0.0025
## Tallest ledge you can walk up without jumping (Doom: 24 units = 0.75 m).
@export var step_height := 0.6
@export var acceleration := 12.0
## How quickly the view catches up after a step up or down (higher = snappier,
## 0 = no smoothing).
@export var step_smoothing := 14.0

## Vertical movement per frame, while standing, that counts as a step down.
const STEP_DOWN_DETECT := 0.08

@onready var head: Node3D = $Head
@onready var hud: Label = $HUD/Help

var flying := false
## How far the view currently lags behind the body (meters; eases to 0).
var view_offset := 0.0
var _head_base_y := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	_head_base_y = head.position.y
	floor_snap_length = step_height
	floor_max_angle = deg_to_rad(46.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		rotate_y(-m.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x - m.relative.y * mouse_sensitivity, -1.55, 1.55)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_V:
				flying = not flying
				$Collision.disabled = flying
				velocity = Vector3.ZERO
				view_offset = 0.0
				_apply_view_offset()
				_update_hud()
			KEY_H:
				hud.visible = not hud.visible


func _physics_process(delta: float) -> void:
	var input := Vector2(
		_key(KEY_D) - _key(KEY_A),
		_key(KEY_S) - _key(KEY_W))
	if flying:
		_fly(input, delta)
		return

	var running := Input.is_physical_key_pressed(KEY_SHIFT)
	var speed := run_speed if running else walk_speed
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y))
	wish.y = 0.0
	wish = wish.normalized() * speed
	var blend := clampf(acceleration * delta, 0.0, 1.0)
	if not is_on_floor():
		blend *= 0.3
	velocity.x = lerpf(velocity.x, wish.x, blend)
	velocity.z = lerpf(velocity.z, wish.z, blend)

	if is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * delta

	var was_on_floor := is_on_floor()
	var y_before := global_position.y
	var stepped := was_on_floor and _try_step_up(delta)
	if stepped:
		# Already moved forward onto the step; keep vertical motion only this frame.
		var keep := velocity
		velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)
		move_and_slide()
		velocity = Vector3(keep.x, velocity.y, keep.z)
	else:
		move_and_slide()

	# Steps (up, or snapping down while walking) move the body at once; hold the
	# view where it was and let it catch up. Jumps and falls are not smoothed.
	var dy := global_position.y - y_before
	if stepped or (was_on_floor and is_on_floor() and dy < -STEP_DOWN_DETECT):
		view_offset = clampf(view_offset - dy, -step_height * 1.5, step_height * 1.5)
	_ease_view(delta)


func _ease_view(delta: float) -> void:
	if step_smoothing <= 0.0:
		view_offset = 0.0
	else:
		view_offset *= exp(-step_smoothing * delta)
		if absf(view_offset) < 0.001:
			view_offset = 0.0
	_apply_view_offset()


func _apply_view_offset() -> void:
	head.position.y = _head_base_y + view_offset


## Steps onto a ledge in front of the player if it's low enough.
func _try_step_up(delta: float) -> bool:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.0001:
		return false
	var start := global_transform
	if not test_move(start, motion):
		return false # Nothing in the way.
	var up := Vector3.UP * step_height
	if test_move(start, up):
		return false # No headroom.
	var raised := start.translated(up)
	if test_move(raised, motion):
		return false # Too tall: still blocked at step height.
	var moved := raised.translated(motion)
	var hit := KinematicCollision3D.new()
	if not test_move(moved, -up, hit):
		return false # Nothing to stand on.
	if hit.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false
	global_position = moved.origin + hit.get_travel()
	return true


func _fly(input: Vector2, delta: float) -> void:
	var dir := head.global_transform.basis * Vector3(input.x, 0.0, input.y)
	dir += Vector3.UP * (_key(KEY_SPACE) - _key(KEY_CTRL))
	var speed := fly_speed * (2.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	global_position += dir.normalized() * speed * delta if dir.length() > 0.01 else Vector3.ZERO


static func _key(code: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(code) else 0.0


func _update_hud() -> void:
	if hud == null:
		return
	hud.text = "WASD move   Mouse look   Space jump   Shift run   V fly %s   Esc free mouse   H hide help" % (
		"(ON: Space up, Ctrl down)" if flying else "(off)")
