@tool
extends RefCounted
## SCENE WRITER VO TIMING: finds the spoken parts of a WAV (silence detection on the raw PCM,
## like ffmpeg silencedetect noise=-35dB d=0.25) and fits them to the screen's text lines.
## Reads the original .wav file from the project (works whatever the import compression is).
## MP3 / OGG cannot be analysed here: use "Spread evenly" and adjust the times by hand.

const THRESHOLD_DB := -35.0
const MIN_SILENCE := 0.25
const MIN_SILENCE_FINE := 0.12   # with line texts: finer cut, the fit below picks the real breaks
const GAP_WEIGHT := 0.6          # prefer line breaks at longer pauses
const HOP := 0.01            # analysis window (seconds)

static var last_error := ""


## [[start, end], ...] one per line (n lines) inside [from, to] (to <= 0 = end of clip), or [] + last_error.
## `lines` (optional) = the text of each line: longer lines get longer speech parts when the
## clip has more pauses than lines (breaths, extra words).
static func auto_time(path: String, n: int, from := 0.0, to := -1.0, lines: PackedStringArray = PackedStringArray()) -> Array:
	last_error = ""
	if n <= 0:
		last_error = "The screen has no text lines."
		return []
	if path.get_extension().to_lower() != "wav":
		last_error = "Auto-time only reads .wav files. Use Spread evenly for %s." % path.get_extension().to_upper()
		return []
	var env := peak_envelope(path)
	if env.is_empty():
		return []
	var length := env.size() * HOP
	if to <= 0.0 or to > length:
		to = length
	var segs := speech_segments(env, from, to, MIN_SILENCE_FINE if lines.size() == n else MIN_SILENCE)
	if segs.is_empty():
		last_error = "No speech found above %d dB." % int(THRESHOLD_DB)
		return []
	return fit(segs, n, lines)


## Per-window peak level in dBFS (decimated: every 4th frame, first channel).
static func peak_envelope(path: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not FileAccess.file_exists(path):
		last_error = "File not found: %s" % path
		return out
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WAVE":
		last_error = "Not a RIFF/WAVE file: %s" % path
		return out
	var fmt := -1
	var channels := 1
	var rate := 44100
	var bits := 16
	var data_at := -1
	var data_len := 0
	var p := 12
	while p + 8 <= b.size():
		var cid := b.slice(p, p + 4).get_string_from_ascii()
		var clen := b.decode_u32(p + 4)
		if cid == "fmt ":
			fmt = b.decode_u16(p + 8)
			channels = maxi(1, b.decode_u16(p + 10))
			rate = maxi(1, b.decode_u32(p + 12))
			bits = b.decode_u16(p + 22)
			if fmt == 0xFFFE and clen >= 26:
				fmt = b.decode_u16(p + 32)   # WAVE_FORMAT_EXTENSIBLE sub-format
		elif cid == "data":
			data_at = p + 8
			data_len = mini(clen, b.size() - data_at)
			break
		p += 8 + clen + (clen & 1)
	if data_at < 0 or not ((fmt == 1 and bits in [8, 16, 24, 32]) or (fmt == 3 and bits == 32)):
		last_error = "Unsupported WAV format (format %d, %d bit)." % [fmt, bits]
		return out
	var bpf := channels * bits / 8
	var frames := data_len / bpf
	var hop_frames := maxi(1, int(rate * HOP))
	var step := 4
	var f := 0
	while f < frames:
		var peak := 0.0
		var end := mini(frames, f + hop_frames)
		var k := f
		while k < end:
			var o := data_at + k * bpf
			var v := 0.0
			match bits:
				16:
					v = absf(b.decode_s16(o) / 32768.0)
				8:
					v = absf((b[o] - 128) / 128.0)
				24:
					var s := b[o] | (b[o + 1] << 8) | (b[o + 2] << 16)
					if s & 0x800000:
						s -= 0x1000000
					v = absf(s / 8388608.0)
				32:
					v = absf(b.decode_float(o)) if fmt == 3 else absf(b.decode_s32(o) / 2147483648.0)
			peak = maxf(peak, v)
			k += step
		out.append(linear_to_db(peak) if peak > 0.0 else -120.0)
		f = end
	return out


## Speech parts [[s, e], ...]: everything that is not a silence of at least MIN_SILENCE.
static func speech_segments(env: PackedFloat32Array, from: float, to: float, min_silence := MIN_SILENCE) -> Array:
	var segs: Array = []
	var i0 := clampi(int(from / HOP), 0, env.size())
	var i1 := clampi(int(ceil(to / HOP)), 0, env.size())
	var min_sil := maxi(1, int(round(min_silence / HOP)))
	var start := -1
	var quiet := 0
	for i in range(i0, i1):
		if env[i] >= THRESHOLD_DB:
			if start < 0:
				start = i
			quiet = 0
		elif start >= 0:
			quiet += 1
			if quiet >= min_sil:
				segs.append([start * HOP, (i - quiet + 1) * HOP])
				start = -1
				quiet = 0
	if start >= 0:
		segs.append([start * HOP, (i1 - quiet) * HOP])
	return segs.filter(func(s: Array) -> bool: return float(s[1]) - float(s[0]) >= 0.05)


## Fits speech parts to n lines. More parts than lines: groups neighbouring parts so each line's
## share of the speaking time matches its share of the text (dynamic programming); without line
## texts, merges the closest neighbours. Fewer parts than lines: splits the longest part.
static func fit(segs: Array, n: int, lines: PackedStringArray = PackedStringArray()) -> Array:
	var s: Array = segs.duplicate(true)
	if s.size() > n and lines.size() == n:
		s = _fit_weighted(s, lines)
	while s.size() > n:
		var best := 0
		var gap := INF
		for i in s.size() - 1:
			var g := float(s[i + 1][0]) - float(s[i][1])
			if g < gap:
				gap = g
				best = i
		s[best] = [s[best][0], s[best + 1][1]]
		s.remove_at(best + 1)
	while s.size() < n:
		var li := 0
		for i in s.size():
			if float(s[i][1]) - float(s[i][0]) > float(s[li][1]) - float(s[li][0]):
				li = i
		var a := float(s[li][0])
		var e := float(s[li][1])
		var mid := (a + e) * 0.5
		s[li] = [a, mid]
		s.insert(li + 1, [mid, e])
	var out: Array = []
	for c: Array in s:
		out.append([snappedf(float(c[0]), 0.01), snappedf(float(c[1]), 0.01)])
	return out


static func _fit_weighted(s: Array, lines: PackedStringArray) -> Array:
	var m := s.size()
	var n := lines.size()
	var chars := 0.0
	for l in lines:
		chars += maxf(3.0, float(l.length()))
	var span := float(s[m - 1][1]) - float(s[0][0])
	# cost[i][j]: best cost putting parts 0..i-1 on lines 0..j-1; back[i][j]: where line j-1 starts
	var cost: Array = []
	var back: Array = []
	for i in m + 1:
		var row: Array = []
		var brow: Array = []
		for j in n + 1:
			row.append(INF)
			brow.append(-1)
		cost.append(row)
		back.append(brow)
	cost[0][0] = 0.0
	for j in range(1, n + 1):
		var want := span * maxf(3.0, float(lines[j - 1].length())) / chars
		for i in range(j, m - (n - j) + 1):
			for k in range(j - 1, i):
				if cost[k][j - 1] == INF:
					continue
				var d := float(s[i - 1][1]) - float(s[k][0])
				var c: float = cost[k][j - 1] + pow((d - want) / maxf(want, 0.5), 2.0)
				if k > 0:
					c -= GAP_WEIGHT * minf(float(s[k][0]) - float(s[k - 1][1]), 1.0)
				if c < cost[i][j]:
					cost[i][j] = c
					back[i][j] = k
	var out: Array = []
	var i := m
	for j in range(n, 0, -1):
		var k: int = back[i][j]
		if k < 0:
			return s   # should not happen; fall back to closest-gap merging
		out.push_front([s[k][0], s[i - 1][1]])
		i = k
	return out


## Evenly spread cues over [from, to], weighted by line length, with a short gap between lines.
static func spread(lines: PackedStringArray, from: float, to: float) -> Array:
	var n := lines.size()
	if n == 0 or to <= from:
		return []
	var total := 0.0
	for l in lines:
		total += maxf(4.0, float(l.length()))
	var gap := minf(0.3, (to - from) * 0.1 / maxf(1.0, n))
	var usable := (to - from) - gap * (n - 1)
	var t := from
	var out: Array = []
	for l in lines:
		var d := usable * maxf(4.0, float(l.length())) / total
		out.append([snappedf(t, 0.01), snappedf(t + d, 0.01)])
		t += d + gap
	return out
