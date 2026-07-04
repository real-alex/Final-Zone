shader_type canvas_item;

// Red edge vignette shown when the player takes damage.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float edge = smoothstep(0.25, 0.72, length(centered));
	COLOR = vec4(0.8, 0.08, 0.06, edge * intensity);
}
