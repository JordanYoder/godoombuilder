@tool
class_name DMGrid
extends RefCounted
## The snap grid shown in the editor viewport while a map is being edited:
## a large flat plane at the drawing height with lines every grid step and a
## brighter line every 8 steps, fading out with distance.
##
## It lives directly in the rendering server, so it never becomes part of the
## edited scene.


const SIZE := 2000.0
const MAJOR_EVERY := 8.0

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform float step = 0.5;
uniform float major_every = 8.0;
uniform vec4 line_color : source_color = vec4(0.75, 0.75, 0.8, 0.35);
uniform vec4 major_color : source_color = vec4(1.0, 0.6, 0.3, 0.55);
uniform float fade_distance = 60.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 on a grid line, 0 between lines, anti-aliased to about one pixel.
float lines(vec2 coord) {
	vec2 width = fwidth(coord);
	vec2 dist = abs(fract(coord - 0.5) - 0.5) / max(width, vec2(1e-5));
	return 1.0 - min(min(dist.x, dist.y), 1.0);
}

void fragment() {
	vec2 cell = world_pos.xz / step;
	float minor = lines(cell);
	float major = lines(cell / major_every);
	float fade = 1.0 - smoothstep(fade_distance * 0.5, fade_distance, length(world_pos - CAMERA_POSITION_WORLD));
	ALBEDO = mix(line_color.rgb, major_color.rgb, major);
	ALPHA = max(line_color.a * minor, major_color.a * major) * fade;
}
"""

var _mesh: PlaneMesh
var _material: ShaderMaterial
var _instance := RID()
var _world: World3D


func _init() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_mesh = PlaneMesh.new()
	_mesh.size = Vector2(SIZE, SIZE)
	_mesh.material = _material


## Shows the grid in `world` at height `y` with lines every `step` meters, or
## hides it.
func update(world: World3D, show: bool, y: float, step: float) -> void:
	if not show or world == null:
		_free_instance()
		return
	if world != _world:
		_free_instance()
	if not _instance.is_valid():
		_world = world
		_instance = RenderingServer.instance_create2(_mesh.get_rid(), world.scenario)
		RenderingServer.instance_geometry_set_cast_shadows_setting(_instance, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	_material.set_shader_parameter("step", maxf(step, 0.001))
	_material.set_shader_parameter("major_every", MAJOR_EVERY)
	_material.set_shader_parameter("fade_distance", clampf(step * 120.0, 20.0, 400.0))
	# Lift it a hair above the floor so it isn't hidden inside it.
	RenderingServer.instance_set_transform(_instance, Transform3D(Basis(), Vector3(0, y + 0.002, 0)))


func cleanup() -> void:
	_free_instance()


func _free_instance() -> void:
	if _instance.is_valid():
		RenderingServer.free_rid(_instance)
	_instance = RID()
	_world = null
