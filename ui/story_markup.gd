@tool
class_name StoryMarkup
extends RefCounted
## SCENE WRITER MARKUP: parses screen text written in the Scene Writer (or by hand in a
## story/scenes/*.json file), times the typewriter, and renders the animated bbcode.
## Shared by the game (ui/story_stage.gd) and the editor preview (addons/scene_writer).
##
##   [error]WORD[/error]        WORD scrambles while it types, then settles amber (any word).
##   [error level=6]WORD[/error]  same, glitch intensity 0-10. 0 is the look above. 10 stays hard to read.
##   [error=ERROR]Alex[/error]  "Alex" types normally, holds, then scrambles into "ERROR".
##   [error=DEMON delay=1.5 level=10]voice[/error]
##                              "voice" stays readable for 1.5 s, then becomes a hard-to-read DEMON.
##   [expo]prose[/expo]         IBM Plex Serif, for room description (not the terminal face).
##   [act=locker]locker[/act]   clickable. Shown as LOCKER, bold, underline on the letters only.
##   [shake]text[/shake]        shaky text (default strength 6). [shake=12]...[/shake] = 1..20.
##   [pause=1.0]                typing stops for 1.0 s here ([pause] alone = 0.5 s).
##   [b]bold[/b]  [i]italic[/i]
##   New line = line break. Empty line = paragraph gap.
##   A line starting with "+" continues the previous line's paragraph (same line on screen,
##   but still its own VO cue).
##   {v:name} and {flag:x?A|B} are filled in by the game before parsing.
##   Any other "[" is shown as a normal character.
##
## Timing: speed mode = LEAD_IN + 1/cps per character + pauses (+ small gaps at line breaks).
## Cue mode (VO): non-empty line k types across 85 % of cue k [start, end] (clip seconds);
## lines without a cue continue after the last cue at the screen speed. Pauses are ignored.

const ERROR_COLOR := "#e07040"
const EXPO_FONT := "res://assets/fonts/IBMPlexSerif-Regular.ttf"
const SCRAMBLE := "#%&@!?/\\|<>*$01"
const TYPE_FRACTION := 0.85   # a VO line finishes typing at 85 % of its spoken span
const GLITCH_SECONDS := 0.35  # an [error] word keeps scrambling this long after it is typed
const MORPH_HOLD := 0.6       # [error=X]: original shown this long before it scrambles
const MORPH_SECONDS := 0.5    # ...and scrambles into X over this long
const LEAD_IN := 0.3
const LINE_GAP := 0.12
const PARA_GAP := 0.25
const SHAKE_DEFAULT := 6
const TEXT_COLOR := Color(0.56, 0.8, 0.6)

## One entry per shown character: {c, line, shake, err, b, i, pause, t}
## line = cue line index (-1 for line breaks / joiners), err = index into errs or -1.
var chars: Array = []
## [error] spans: {to, first, last, text}
var errs: Array = []
var line_count := 0
var end_pause := 0.0
var duration := 0.0
var line_starts: Array = []   # first-character time of each cue line
var line_ends: Array = []     # last-character time of each cue line
var warnings: Array = []      # unclosed tags etc. (shown by the Scene Writer checks)

var _shake: Array = []
var _err := -1
var _b := 0
var _i := 0
var _expo := 0
var _act := ""
var _pause := 0.0
var _cue := -1
var _line_started := false


## Parses markup text. Returns self for chaining: var m = StoryMarkup.new().parse(text)
func parse(src: String) -> RefCounted:
	chars.clear()
	errs.clear()
	warnings.clear()
	_shake.clear()
	_err = -1
	_b = 0
	_i = 0
	_expo = 0
	_act = ""
	_pause = 0.0
	_cue = -1
	var lines := src.replace("\r\n", "\n").replace("\r", "\n").replace("\t", "    ").split("\n")
	for li in lines.size():
		var line: String = lines[li]
		var cont := line.strip_edges().begins_with("+")
		if cont:
			line = line.substr(line.find("+") + 1).strip_edges(true, false)
		if li > 0:
			_emit_sep(" " if cont and not chars.is_empty() else "\n")
		_line_started = false
		_parse_line(line)
	end_pause = _pause
	line_count = _cue + 1
	if _err >= 0:
		warnings.append("[error] is not closed with [/error]")
	if not _shake.is_empty():
		warnings.append("[shake] is not closed with [/shake]")
	if _b > 0 or _i > 0:
		warnings.append("[b] / [i] is not closed")
	if _expo > 0:
		warnings.append("[expo] is not closed with [/expo]")
	if _act != "":
		warnings.append("[act] is not closed with [/act]")
	time_by_speed(40.0)
	return self


func _parse_line(line: String) -> void:
	var k := 0
	var n := line.length()
	while k < n:
		var ch := line[k]
		if ch == "[":
			var close := line.find("]", k + 1)
			if close > k and _apply_tag(line.substr(k + 1, close - k - 1)):
				k = close + 1
				continue
		_emit(ch)
		k += 1


func _apply_tag(raw: String) -> bool:
	var tag := raw.strip_edges()
	var low_tag := tag.to_lower()
	if low_tag == "/act":
		_act = ""
		return true
	if low_tag == "act" or low_tag.begins_with("act=") or low_tag.begins_with("act "):
		var act_val := ""
		var act_eq := tag.find("=")
		if act_eq >= 0:
			act_val = tag.substr(act_eq + 1).strip_edges()
		_act = act_val.to_lower() if act_val != "" else "act"
		return true
	var head := tag
	var rest := ""
	var sp := tag.find(" ")
	if sp >= 0:
		head = tag.substr(0, sp)
		rest = tag.substr(sp + 1).strip_edges()
	var low := head.to_lower()
	var val := ""
	var eq := head.find("=")
	if eq >= 0:
		val = head.substr(eq + 1).strip_edges()
		low = head.substr(0, eq).to_lower().strip_edges()
	match low:
		"error":
			if _err >= 0:
				warnings.append("[error] inside another [error]")
			var spec := _error_spec(val, rest)
			errs.append({"to": spec["to"], "level": spec["level"], "delay": spec["delay"],
				"first": -1, "last": -1, "text": ""})
			_err = errs.size() - 1
		"/error":
			_err = -1
		"shake":
			var lv := SHAKE_DEFAULT if val == "" else clampi(int(val.to_float()), 1, 20)
			_shake.append(lv)
		"/shake":
			if not _shake.is_empty():
				_shake.pop_back()
		"pause":
			_pause += 0.5 if val == "" else maxf(0.0, val.to_float())
		"b":
			_b += 1
		"/b":
			_b = maxi(0, _b - 1)
		"i":
			_i += 1
		"/i":
			_i = maxi(0, _i - 1)
		"expo":
			_expo += 1
		"/expo":
			_expo = maxi(0, _expo - 1)
		_:
			return false
	return true


## [error=WORD level=N delay=S]. WORD is the glitch text. level 0 and a missing delay match the old tag.
func _error_spec(val: String, rest: String) -> Dictionary:
	var to := val
	var level := 0
	var delay := -1.0
	for part in rest.split(" ", false):
		var bit := part.strip_edges()
		if bit.begins_with("level="):
			level = clampi(int(bit.substr(6).to_float()), 0, 10)
		elif bit.begins_with("delay="):
			delay = maxf(0.0, bit.substr(6).to_float())
		elif to == "" and not bit.contains("="):
			to = bit
	return {"to": to, "level": level, "delay": delay}


func _emit(c: String) -> void:
	if not _line_started and c.strip_edges() != "":
		_line_started = true
		_cue += 1
	# Spaces stay outside the act style so the underline starts on the first letter.
	var use_act := "" if (_act != "" and (c == " " or c == "\t")) else _act
	var e := {"c": c, "line": _cue if _line_started else -1,
		"shake": 0 if _shake.is_empty() else int(_shake.back()),
		"err": _err, "b": _b > 0, "i": _i > 0, "expo": _expo > 0, "act": use_act, "pause": _pause, "t": 0.0}
	_pause = 0.0
	if _err >= 0:
		var span: Dictionary = errs[_err]
		if int(span["first"]) < 0:
			span["first"] = chars.size()
		span["last"] = chars.size()
		span["text"] = str(span["text"]) + c
	chars.append(e)


func _emit_sep(c: String) -> void:
	chars.append({"c": c, "line": -1, "shake": 0, "err": -1, "b": false, "i": false, "expo": false, "act": "",
		"pause": _pause, "t": 0.0})
	_pause = 0.0


# ---------------------------------------------------------------- timing

## Typewriter at `cps` characters per second, honouring [pause] and line breaks.
func time_by_speed(cps: float) -> void:
	var step := 1.0 / maxf(cps, 1.0)
	var t := LEAD_IN
	var prev_nl := false
	for ch: Dictionary in chars:
		t += float(ch["pause"])
		if ch["c"] == "\n":
			t += PARA_GAP if prev_nl else LINE_GAP
			ch["t"] = t
			prev_nl = true
			continue
		prev_nl = false
		t += step
		ch["t"] = t
	duration = t + end_pause
	_line_times()


## VO timing: cues = [[start, end], ...] in clip seconds, one per non-empty line.
func time_by_cues(cues: Array, cps: float) -> void:
	var per_line: Array = []
	for _k in line_count:
		per_line.append([])
	for idx in chars.size():
		var ln := int(chars[idx]["line"])
		if ln >= 0:
			(per_line[ln] as Array).append(idx)
	var last_end := 0.0
	for k in line_count:
		var ids: Array = per_line[k]
		var n := ids.size()
		var s := 0.0
		var e := 0.0
		if k < cues.size() and cues[k] is Array and (cues[k] as Array).size() >= 2:
			s = float(cues[k][0])
			e = float(cues[k][1])
			if e <= s:
				e = s + float(n) / maxf(cps, 1.0)
		else:
			s = last_end + 0.3
			e = s + float(n) / maxf(cps, 1.0) / TYPE_FRACTION
		var span := maxf(0.15, (e - s) * TYPE_FRACTION)
		for j in n:
			chars[ids[j]]["t"] = s + span * float(j + 1) / float(maxi(n, 1))
		last_end = maxf(last_end, e)
	var prev := 0.0
	for ch: Dictionary in chars:
		if int(ch["line"]) < 0:
			ch["t"] = prev
		else:
			prev = float(ch["t"])
	duration = maxf(last_end, prev)
	_line_times()


func _line_times() -> void:
	line_starts.clear()
	line_ends.clear()
	for _k in line_count:
		line_starts.append(-1.0)
		line_ends.append(0.0)
	for ch: Dictionary in chars:
		var ln := int(ch["line"])
		if ln < 0:
			continue
		if float(line_starts[ln]) < 0.0:
			line_starts[ln] = float(ch["t"])
		line_ends[ln] = float(ch["t"])


## Time the given 1-based line starts typing (SFX "line" events).
func line_start(line_1based: int) -> float:
	var k := line_1based - 1
	if k < 0 or k >= line_starts.size():
		return 0.0
	return maxf(0.0, float(line_starts[k]) - 0.01)


# ---------------------------------------------------------------- rendering

## bbcode of the text typed up to clock `t`. `wall` drives the settled ERROR flicker.
func render(t: float, wall: float) -> String:
	var out := ""
	var run := ""
	var run_key := ""
	var run_ch: Dictionary = {}
	var idx := 0
	var n := chars.size()
	while idx < n:
		var ch: Dictionary = chars[idx]
		if float(ch["t"]) > t:
			break
		var e := int(ch["err"])
		if e >= 0:
			out += _wrap(run, run_ch)
			run = ""
			run_key = ""
			var k := idx
			while k < n and int(chars[k]["err"]) == e and float(chars[k]["t"]) <= t:
				k += 1
			out += _wrap(_err_bb(e, k - idx, t, wall), ch, true)
			idx = k
			continue
		var key := "%d|%s|%s|%s|%s" % [int(ch["shake"]), ch["b"], ch["i"], ch.get("expo", false), ch.get("act", "")]
		if key != run_key:
			out += _wrap(run, run_ch)
			run = ""
			run_key = key
			run_ch = ch
		run += "[lb]" if ch["c"] == "[" else str(ch["c"])
		idx += 1
	out += _wrap(run, run_ch)
	return out


## Everything typed (true once t >= duration).
func is_complete(t: float) -> bool:
	return t >= duration


func _wrap(text: String, ch: Dictionary, raw := false) -> String:
	if text == "" or ch.is_empty():
		return text
	var act := str(ch.get("act", "")).strip_edges()
	var lead := ""
	var trail := ""
	var s := text
	if act != "":
		var i := 0
		var j := s.length()
		while i < j and (s[i] == " " or s[i] == "\t"):
			i += 1
		while j > i and (s[j - 1] == " " or s[j - 1] == "\t"):
			j -= 1
		lead = s.substr(0, i)
		trail = s.substr(j)
		s = s.substr(i, j - i)
		if s == "":
			return lead + trail
		if not raw:
			s = s.to_upper()
			# Bold and [u] cover the letters only. underline=never is a [url] option,
			# not part of url=, so the click meta stays exactly act:<id>. The url's
			# own line stays off, and a space beside the word is not underlined.
			s = "[url href=act:%s underline=never][color=#cfe8d4][b][u]%s[/u][/b][/color][/url]" % [act, s]
		else:
			s = "[url href=act:%s underline=never]%s[/url]" % [act, s]
	elif not raw and bool(ch["b"]):
		s = "[b]%s[/b]" % s
	if bool(ch["i"]):
		s = "[i]%s[/i]" % s
	if bool(ch.get("expo", false)):
		s = "[font=%s]%s[/font]" % [EXPO_FONT, s]
	var lv := int(ch["shake"])
	if lv > 0:
		s = "[shake rate=18.0 level=%d connected=1]%s[/shake]" % [lv, s]
	return lead + s + trail


func _err_bb(k: int, shown: int, t: float, wall: float) -> String:
	var e: Dictionary = errs[k]
	var text := str(e["text"])
	var to := str(e["to"])
	var level := clampi(int(e.get("level", 0)), 0, 10)
	var delay := float(e.get("delay", -1.0))
	var total := text.length()
	var t_last := float(chars[int(e["last"])]["t"]) if int(e["last"]) >= 0 else 0.0
	if to == "":
		var settle := GLITCH_SECONDS if delay < 0.0 else delay
		var word := ""
		if shown < total or t - t_last < settle:
			word = scramble(shown + (level / 3))
		elif level <= 0:
			word = flicker(text, wall, k)
		else:
			word = distort(text, wall, k, level)
		return _err_paint(word, level)
	var hold := MORPH_HOLD if delay < 0.0 else delay
	var el := t - t_last - hold
	if shown < total or el < 0.0:
		return esc(text.substr(0, shown))
	if el < MORPH_SECONDS:
		var p := el / MORPH_SECONDS
		var n := int(round(lerpf(float(total), float(to.length()), p)))
		var w := ""
		var wild := float(level) / 10.0
		for i in n:
			if level > 0 and randf() < wild * 0.85:
				w += SCRAMBLE[randi() % SCRAMBLE.length()]
			elif p > 0.75 and i < to.length() and randf() < p:
				w += to[i]
			elif i < total and randf() > p * 1.3:
				w += text[i]
			else:
				w += SCRAMBLE[randi() % SCRAMBLE.length()]
		var col := TEXT_COLOR.lerp(Color(ERROR_COLOR), clampf(p * 1.5, 0.0, 1.0))
		return "[color=#%s]%s[/color]" % [col.to_html(false), esc(w)]
	var settled := flicker(to, wall, k) if level <= 0 else distort(to, wall, k, level)
	return _err_paint(settled, level)


func _err_paint(word: String, level: int) -> String:
	var body := "[color=%s][b]%s[/b][/color]" % [ERROR_COLOR, esc(word)]
	if level >= 4:
		body = "[shake rate=%d level=%d connected=0]%s[/shake]" % [18 + level * 2, level, body]
	return body


static func scramble(n: int) -> String:
	var w := ""
	for _c in n:
		w += SCRAMBLE[randi() % SCRAMBLE.length()]
	return w


## Settled word with the subtle flicker: one character, ~70 ms, every ~5 s, staggered per word.
## Intensity 1-10. 10 keeps almost every letter scrambled, so a demon line is hard to read.
static func distort(word: String, wall: float, k: int, level: int) -> String:
	var wild := clampf(float(level) / 10.0, 0.0, 1.0)
	var out := ""
	for i in word.length():
		var phase := fmod(wall * lerpf(3.0, 30.0, wild) + float(i) * 0.71 + float(k) * 0.41, 1.0)
		if phase < lerpf(0.12, 0.94, wild):
			out += SCRAMBLE[randi() % SCRAMBLE.length()]
		else:
			out += word[i]
	if level >= 8 and fmod(wall * 11.0 + float(k), 1.0) < wild:
		out += SCRAMBLE[randi() % SCRAMBLE.length()]
	return out


static func flicker(word: String, wall: float, k: int) -> String:
	if word.length() > 0 and fmod(wall + float(k) * 1.7, 5.3) < 0.07:
		var at := k % word.length()
		return word.substr(0, at) + SCRAMBLE[randi() % SCRAMBLE.length()] + word.substr(at + 1)
	return word


static func esc(t: String) -> String:
	return t.replace("[", "[lb]")


# ---------------------------------------------------------------- plain text

## Plain text of each cue line as it reads once settled (error replacements applied).
func plain_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for _k in line_count:
		out.append("")
	var done := {}
	for ch: Dictionary in chars:
		var ln := int(ch["line"])
		if ln < 0:
			continue
		var e := int(ch["err"])
		if e >= 0:
			if done.has(e):
				continue
			done[e] = true
			var span: Dictionary = errs[e]
			out[ln] += str(span["to"]) if str(span["to"]) != "" else str(span["text"])
			continue
		out[ln] += str(ch["c"])
	for k in out.size():
		out[k] = out[k].strip_edges()
	return out


## Last non-empty line as shown on screen (the default pinned question after a response).
## "+" continuation lines count as part of the same line.
func last_line() -> String:
	var shown := PackedStringArray([""])
	var done := {}
	for ch: Dictionary in chars:
		if ch["c"] == "\n":
			shown.append("")
			continue
		var e := int(ch["err"])
		if e >= 0:
			if done.has(e):
				continue
			done[e] = true
			var span: Dictionary = errs[e]
			shown[shown.size() - 1] += str(span["to"]) if str(span["to"]) != "" else str(span["text"])
			continue
		shown[shown.size() - 1] += str(ch["c"])
	for k in range(shown.size() - 1, -1, -1):
		if shown[k].strip_edges() != "":
			return shown[k].strip_edges()
	return ""
