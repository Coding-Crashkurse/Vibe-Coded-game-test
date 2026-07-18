// res://scripts/shaders/water_compat.gdshader
// Compatibility-sicherer Wasser-Shader (gl_compatibility): nur VERTEX/NORMAL/VIEW/TIME/ALPHA.
// KEIN hint_depth_texture, KEIN SCREEN_UV/SCREEN_TEXTURE -> laeuft im Compatibility-Renderer.
// Optik: Vertex-Wellen + Fresnel-Tiefenfarbe + Transparenz. Bewusster Verzicht auf Tiefenschaum/Uferlinie.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec4 shallow : source_color = vec4(0.32, 0.62, 0.78, 0.80);
uniform vec4 deep    : source_color = vec4(0.06, 0.20, 0.45, 0.90);
uniform float amp = 0.05;
uniform float speed = 1.3;

void vertex() {
	VERTEX.y += (sin(VERTEX.x * 3.0 + TIME * speed) + cos(VERTEX.z * 2.4 + TIME * speed * 0.8)) * amp;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep.rgb, shallow.rgb, fres);
	ALPHA  = mix(deep.a, shallow.a, fres);
	ROUGHNESS = 0.15;
}
