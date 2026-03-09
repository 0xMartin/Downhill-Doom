shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Golden NPC shader - tints the entire model with a shiny gold color
// Applied via material_override on MeshInstance3D nodes

uniform vec3 gold_color : source_color = vec3(1.0, 0.84, 0.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.8;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.15;

void fragment() {
	ALBEDO = gold_color;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = gold_color * emission_strength;
}
