shader_type canvas_item;
// Oxygen-loss post effect for the MEMORY EXAMINATION (NO4 → O2 countdown → recovery).
// amount 0..1: desaturate, vignette, chromatic wobble. red 0..1: red vignette creeping in
// from the edges. black 0..1: fade to black. keep_rect (SCREEN_UV x,y,w,h): the response
// slot stays legible (effects mostly skip it).
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float black : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float red : hint_range(0.0, 1.0) = 0.0;
uniform vec4 keep_rect = vec4(0.0);
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment() {
	vec2 uv = SCREEN_UV;
	float f = 0.012;   // soft edge of the kept slot
	float inside = smoothstep(keep_rect.x - f, keep_rect.x, uv.x)
		* (1.0 - smoothstep(keep_rect.x + keep_rect.z, keep_rect.x + keep_rect.z + f, uv.x))
		* smoothstep(keep_rect.y - f, keep_rect.y, uv.y)
		* (1.0 - smoothstep(keep_rect.y + keep_rect.w, keep_rect.y + keep_rect.w + f, uv.y));
	float k = 1.0 - inside * 0.85;
	float a = amount * k;
	float wob = sin(TIME * 23.0 + uv.y * 40.0) * 0.0025 * a;
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(wob, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(wob, 0.0)).b;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l) * vec3(1.05, 0.86, 0.8), a * 0.85);
	vec2 d = (uv - 0.5) * vec2(1.6, 1.0);
	float r = length(d);
	float inner = mix(0.95, 0.25, a) - pulse * 0.06 * a;
	float v = 1.0 - smoothstep(inner, inner + 0.55, r);
	c *= mix(1.0, v, clamp(a * 1.1, 0.0, 1.0));
	c *= 1.0 - 0.25 * a;
	// red edges: ring whose inner radius shrinks as `red` grows; heartbeat pulse widens it
	float rd = length((uv - 0.5) * vec2(1.25, 1.0));
	float r_in = mix(0.58, 0.26, red) - pulse * 0.03 * red;
	float rmask = smoothstep(r_in, r_in + 0.34, rd) * clamp(red * 1.6, 0.0, 1.0) * k;
	vec3 blood = vec3(0.55, 0.02, 0.02) + c * vec3(0.45, 0.12, 0.12);
	c = mix(c, blood, rmask * 0.8);
	c = mix(c, vec3(0.0), black);
	COLOR = vec4(c, 1.0);
}
