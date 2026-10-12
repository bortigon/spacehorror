// Screen refresh: a soft glow band that sweeps down the screen, then rests dark.
// Put this on a ColorRect that fills the screen. Every uniform shows up in the
// Inspector under Material > Shader Parameters.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.12, 0.11, 0.17, 1.0);

// Seconds for the band to travel top to bottom, then seconds of darkness.
uniform float sweep_time : hint_range(0.2, 10.0) = 2.0;
uniform float pause_time : hint_range(0.0, 10.0) = 2.0;

// How tall the glowing tail is (1.0 = full screen height) and how soft its leading edge is.
uniform float band_height : hint_range(0.05, 1.5) = 0.6;
uniform float edge_softness : hint_range(0.001, 0.3) = 0.05;

// CRT texture. Scanlines only show where the glow is, since black times anything is black.
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_count = 320.0;
uniform float flicker_strength : hint_range(0.0, 0.3) = 0.04;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.015;

// auto_loop on: repeats forever using sweep_time + pause_time.
// auto_loop off: the band sits wherever manual_progress says (0 = top, 1 = gone),
// so a script can play one refresh on demand, e.g. on a page change.
uniform bool auto_loop = true;
uniform float manual_progress = -1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float t;
	if (auto_loop) {
		t = mod(TIME, sweep_time + pause_time) / sweep_time;
	} else {
		t = manual_progress;
	}

	// The head of the band travels far enough that its tail fully leaves the screen.
	float head = t * (1.0 + band_height);
	float d = head - UV.y;                                  // > 0 once the head has passed this row
	float lead = smoothstep(-edge_softness, 0.0, d);        // soft front edge
	float tail = 1.0 - smoothstep(0.0, band_height, d);     // fades out above the head
	float band = lead * tail;

	vec3 col = mix(base_color.rgb, glow_color.rgb, band);

	float scan = 0.5 + 0.5 * sin(UV.y * scanline_count * 6.28318);
	col *= 1.0 - scanline_strength * scan;

	float frame = floor(TIME * 24.0);
	col *= 1.0 + flicker_strength * (hash(vec2(frame, 1.7)) - 0.5) * 2.0;
	col += (hash(floor(FRAGCOORD.xy) + frame) - 0.5) * noise_strength;

	COLOR = vec4(max(col, vec3(0.0)), base_color.a);
}