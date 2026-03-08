shader_type spatial;
render_mode unshaded, cull_front;

// Red outline shader using uniform scale with inverted faces
// Renders backfaces of a scaled-up mesh (avoids sharp angle artifacts)

uniform vec4 outline_color : source_color = vec4(1.0, 0.15, 0.1, 1.0);
uniform float outline_scale : hint_range(1.0, 1.5) = 1.12;  // 12% larger = ~12px outline

void vertex() {
	// Scale vertex position uniformly from center
	VERTEX *= outline_scale;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
