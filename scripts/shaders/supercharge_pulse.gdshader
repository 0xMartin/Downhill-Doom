shader_type canvas_item;

// Supercharge screen pulse effect - simple brightness/vignette pulse

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.0;  // 1.0 = 1Hz
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	// Sine wave pulse (0 to 1 range)
	float pulse = (sin(TIME * pulse_speed * TAU) + 1.0) * 0.5;
	float effect_strength = pulse * intensity;
	
	// Sample screen
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	
	// Simple brightness boost (gamma down = brighter midtones)
	float gamma = 1.0 - effect_strength * 0.15;
	vec3 result = pow(screen_color.rgb, vec3(gamma));
	
	// Pulsing vignette (bright center)
	vec2 uv_centered = SCREEN_UV - 0.5;
	float dist = length(uv_centered);
	float vignette_boost = 1.0 + (1.0 - smoothstep(0.0, 0.7, dist)) * effect_strength * 0.2;
	result *= vignette_boost;
	
	COLOR = vec4(result, 1.0);
}
