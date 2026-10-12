// HOLO WINDOW FX: drawn on a ColorRect that sits on top of a holo window (ui/holo_window.gd).
// It only adds light and noise (alpha blended), so it needs no screen texture and works in the
// Compatibility renderer next to the global CRT shader.
//   flash         bright green-white fill: the dot / line of the tube-TV turn-on (0..1)
//   noise_amount  static grain over the window (0..1)
//   scan_strength dark scanlines; scan_offset makes them drift
//   flicker       0..1, adds a faint brightness pulse (the hologram shimmer)
//   glitch        0..1, thin red / cyan bands at random rows for a few frames
shader_type canvas_item;

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.0;
uniform float scan_strength : hint_range(0.0, 0.6) = 0.065;
uniform float scan_count = 110.0;
uniform float scan_offset = 0.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float glitch_seed = 0.0;
uniform vec4 tint : source_color = vec4(0.62, 1.0, 0.72, 1.0);
uniform vec4 glitch_a : source_color = vec4(1.0, 0.25, 0.35, 1.0);
uniform vec4 glitch_b : source_color = vec4(0.25, 0.95, 1.0, 1.0);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Standard "over" for non-premultiplied colour.
vec4 over(vec4 top, vec4 bottom) {
	float a = top.a + bottom.a * (1.0 - top.a);
	if (a <= 0.0001) {
		return vec4(0.0);
	}
	vec3 c = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / a;
	return vec4(c, a);
}

void fragment() {
	vec4 col = vec4(0.0);

	// scanlines drifting down
	float s = 0.5 + 0.5 * sin((UV.y * scan_count + scan_offset) * 6.2831853);
	col = over(vec4(0.0, 0.06, 0.02, scan_strength * s), col);

	// one soft bright band rolling through the window
	float band_y = fract(TIME * 0.11 + glitch_seed * 0.37);
	float band = smoothstep(0.09, 0.0, abs(UV.y - band_y));
	col = over(vec4(tint.rgb, band * 0.035 * (0.4 + flicker)), col);

	// brightness pulse
	col = over(vec4(tint.rgb, flicker * 0.03), col);

	// glitch bands (red / cyan offset look)
	if (glitch > 0.001) {
		float row = floor(UV.y * 44.0);
		float h = hash21(vec2(row, glitch_seed));
		if (h > 0.84) {
			vec4 g = h > 0.92 ? glitch_a : glitch_b;
			col = over(vec4(g.rgb, glitch * 0.14), col);
		}
	}

	// static
	if (noise_amount > 0.001) {
		float frame = floor(TIME * 40.0 + glitch_seed * 7.0);
		float n = hash21(floor(FRAGCOORD.xy * 0.5) + vec2(frame * 1.37, frame * 0.71));
		float a = noise_amount * step(0.45, n) * (0.35 + 0.65 * n);
		col = over(vec4(mix(tint.rgb, vec3(1.0), 0.5) * (0.6 + 0.4 * n), a), col);
	}

	// tube-TV flash on top of everything
	col = over(vec4(mix(tint.rgb, vec3(1.0), 0.65), flash), col);

	COLOR = col;
}
