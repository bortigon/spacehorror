@tool
class_name StoryScene
extends RefCounted
## SCENE WRITER DATA: load / normalize / validate / save story/scenes/<id>.json.
## Shared by the game runner (templates/authored_scene.gd) and the editor plugin.
## Format reference: docs/SCENE_WRITER.md.

const FORMAT := 1
const SCENES_DIR := "res://story/scenes/"
const BUILD_DIR := "res://scenes/authored/"
const RUNNER_SCRIPT := "res://templates/authored_scene.gd"
const RUNNER_SCENE := "res://templates/authored_scene.tscn"
const TEMPLATE_SCENE := "res://templates/pda_screen.tscn"
const SOUNDS_DIR := "res://assets/sounds/"
## Passages of scenes/intro.tscn an authored scene may jump to with "intro:<id>".
const INTRO_PASSAGES: Array[String] = ["home_bunk", "home_lock", "home_airlock"]
const END_TYPES: Array[String] = ["continue", "choices", "death", "qte", "map_tour", "transition", "hold"]
## Scene "ui": "stage" = full-screen story stage (default); "game" = inside the main game UI
## (header, tab rail, title, minimap; the map can be opened).
const UI_MODES: Array[String] = ["stage", "game"]
## Map walkthrough targets (besides room:<id> and door:<a>|<b>).
const TOUR_TARGETS: Array[String] = ["map", "rooms"]
const RED_MODES: Array[String] = ["off", "static", "ramp"]
const DEFAULT_SPEED := 40
const DEFAULT_QTE_LABEL := "NO WAIT, I UNDERSTAND"

const _Markup := preload("res://ui/story_markup.gd")
const _Vessel := preload("res://data/vessel.gd")

static var last_error := ""


static func json_path(id: String) -> String:
	return SCENES_DIR + id + ".json"


static func tscn_path(id: String) -> String:
	return BUILD_DIR + id + ".tscn"


## Ids of every story/scenes/*.json (sorted).
static func list_scenes() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(SCENES_DIR):
		return out
	for f in DirAccess.get_files_at(SCENES_DIR):
		if f.get_extension().to_lower() == "json":
			out.append(f.get_basename())
	out.sort()
	return out


## Loads + normalizes a scene file. {} on failure (reason in last_error).
static func load_file(path: String) -> Dictionary:
	last_error = ""
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	elif ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is JSON:
			return normalize((res as JSON).data if (res as JSON).data is Dictionary else {})
	if text == "":
		last_error = "Cannot read %s" % path
		return {}
	return parse_text(text, path)


static func parse_text(text: String, label := "scene") -> Dictionary:
	var j := JSON.new()
	var err := j.parse(text)
	if err != OK:
		last_error = "%s: JSON error on line %d: %s" % [label, j.get_error_line(), j.get_error_message()]
		return {}
	if not (j.data is Dictionary):
		last_error = "%s: the file must contain one { ... } object" % label
		return {}
	return normalize(j.data)


static func to_json(d: Dictionary) -> String:
	return JSON.stringify(normalize(d), "  ", false) + "\n"


static func save_file(d: Dictionary, path := "") -> Error:
	var n := normalize(d)
	if path == "":
		path = json_path(str(n["id"]))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		last_error = "Cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
		return FileAccess.get_open_error()
	f.store_string(to_json(n))
	f.close()
	return OK


static func sanitize_id(s: String) -> String:
	var out := ""
	for c in s.strip_edges().to_lower().replace(" ", "_").replace("-", "_"):
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			out += c
	return out


static func new_scene(id := "new_scene") -> Dictionary:
	return normalize({"id": id, "title": "NEW SCENE", "screens": [new_screen("s1")]})


static func new_screen(id: String) -> Dictionary:
	return normalize_screen({"id": id, "text": "", "end": {"type": "continue", "goto": "next"}})


# ---------------------------------------------------------------- normalize

## Fills defaults, fixes types and puts keys in a stable, readable order. Unknown keys are kept.
static func normalize(src: Dictionary) -> Dictionary:
	var d := {}
	d["format"] = FORMAT
	d["id"] = sanitize_id(str(src.get("id", "")))
	d["title"] = str(src.get("title", ""))
	d["speed"] = clampi(int(_num(src.get("speed", DEFAULT_SPEED), DEFAULT_SPEED)), 1, 200)
	d["background"] = str(src.get("background", ""))
	d["background_alpha"] = _r(clampf(_num(src.get("background_alpha", 0.12), 0.12), 0.0, 1.0))
	d["ambience"] = str(src.get("ambience", ""))
	d["show_hud"] = bool(src.get("show_hud", true))
	var ui := str(src.get("ui", "stage")).to_lower()
	d["ui"] = ui if ui in UI_MODES else "stage"
	d["fade_in"] = _r(clampf(_num(src.get("fade_in", 0.0), 0.0), 0.0, 10.0))
	d["after"] = str(src.get("after", ""))
	var screens: Array = []
	var raw: Variant = src.get("screens", [])
	if raw is Array:
		for s: Variant in raw:
			if s is Dictionary:
				screens.append(normalize_screen(s))
	d["screens"] = screens
	for k: Variant in src:
		if not d.has(k):
			d[k] = src[k]
	return d


static func normalize_screen(s: Dictionary) -> Dictionary:
	var o := {}
	o["id"] = sanitize_id(str(s.get("id", "")))
	o["heading"] = str(s.get("heading", ""))
	o["text"] = str(s.get("text", ""))
	o["speed"] = clampi(int(_num(s.get("speed", 0), 0)), 0, 200)
	o["shake"] = clampi(int(_num(s.get("shake", 0), 0)), 0, 20)
	var red: Dictionary = s.get("red", {}) if s.get("red", {}) is Dictionary else {}
	var mode := str(red.get("mode", "off")).to_lower()
	o["red"] = {"mode": mode if mode in RED_MODES else "off",
		"from": _r(clampf(_num(red.get("from", 0.0), 0.0), 0.0, 1.0)),
		"to": _r(clampf(_num(red.get("to", 0.0), 0.0), 0.0, 1.0))}
	var vo: Dictionary = s.get("vo", {}) if s.get("vo", {}) is Dictionary else {}
	var cues: Array = []
	var rc: Variant = vo.get("cues", [])
	if rc is Array:
		for c: Variant in rc:
			if c is Array and (c as Array).size() >= 2:
				cues.append([_r(_num(c[0], 0.0)), _r(_num(c[1], 0.0))])
	o["vo"] = {"clip": str(vo.get("clip", "")), "from": _r(maxf(0.0, _num(vo.get("from", 0.0), 0.0))),
		"to": _r(_num(vo.get("to", -1.0), -1.0)), "cues": cues}
	var sfx: Array = []
	var rs: Variant = s.get("sfx", [])
	if rs is Array:
		for e: Variant in rs:
			if e is Dictionary:
				var ed := {"clip": str((e as Dictionary).get("clip", ""))}
				if (e as Dictionary).has("at"):
					ed["at"] = _r(maxf(0.0, _num(e["at"], 0.0)))
				else:
					ed["line"] = maxi(1, int(_num((e as Dictionary).get("line", 1), 1)))
				sfx.append(ed)
	o["sfx"] = sfx
	o["question"] = str(s.get("question", ""))
	o["end"] = normalize_end(s.get("end", {}) if s.get("end", {}) is Dictionary else {})
	if s.has("acts"):
		var acts := normalize_acts(s.get("acts", {}))
		if not acts.is_empty():
			o["acts"] = acts
	for k: Variant in s:
		if not o.has(k):
			o[k] = s[k]
	return o


static func normalize_end(e: Dictionary) -> Dictionary:
	var t := str(e.get("type", "continue")).to_lower()
	if t not in END_TYPES:
		t = "continue"
	match t:
		"choices":
			var list: Array = []
			var rc: Variant = e.get("choices", [])
			if rc is Array:
				for c: Variant in rc:
					if c is Dictionary:
						var ops: Array = []
						var ro: Variant = (c as Dictionary).get("ops", [])
						if ro is Array:
							ops = (ro as Array).duplicate(true)
						elif ro is String and str(ro).strip_edges() != "":
							ops = [str(ro)]
						list.append({"label": str(c.get("label", "")), "goto": str(c.get("goto", "next")),
							"ops": ops, "if": str(c.get("if", ""))})
			return {"type": t, "choices": list}
		"death":
			return {"type": t, "heading": str(e.get("heading", "")), "message": str(e.get("message", "")),
				"retry": str(e.get("retry", ""))}
		"qte":
			return {"type": t, "label": str(e.get("label", DEFAULT_QTE_LABEL)),
				"seconds": _r(clampf(_num(e.get("seconds", 10.0), 10.0), 1.0, 120.0)),
				"goto": str(e.get("goto", "next")), "fail_message": str(e.get("fail_message", "")),
				"retry": str(e.get("retry", ""))}
		"map_tour":
			var tips: Array = []
			var rt: Variant = e.get("tips", [])
			if rt is Array:
				for tip: Variant in rt:
					if tip is Dictionary:
						tips.append({"text": str((tip as Dictionary).get("text", "")),
							"target": str((tip as Dictionary).get("target", "map")).strip_edges()})
					elif tip is String:
						tips.append({"text": str(tip), "target": "map"})
			var arrive: Array = []
			var ra: Variant = e.get("on_arrive", [])
			if ra is Array:
				for op: Variant in ra:
					if str(op).strip_edges() != "":
						arrive.append(str(op).strip_edges())
			elif ra is String and str(ra).strip_edges() != "":
				arrive = [str(ra).strip_edges()]
			return {"type": t, "tips": tips, "move_to": str(e.get("move_to", "")).strip_edges(),
				"move_prompt": str(e.get("move_prompt", "")), "on_arrive": arrive, "goto": str(e.get("goto", "next"))}
		"hold":
			return {"type": t, "goto": str(e.get("goto", ""))}
		"transition":
			return {"type": t, "card": str(e.get("card", "")), "goto": str(e.get("goto", "next"))}
	var cont := {"type": "continue", "goto": str(e.get("goto", "next"))}
	var need := str(e.get("require", "")).strip_edges()
	if need != "":
		cont["require"] = need
	return cont


## Act functions on a screen. New shape is a dictionary keyed by id.
## An old popup list (array of {id, title, actions}) is converted so old files still load.
static func normalize_acts(raw: Variant) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for k: Variant in (raw as Dictionary).keys():
			var id := sanitize_id(str(k))
			if id == "" or not ((raw as Dictionary)[k] is Dictionary):
				continue
			out[id] = _normalize_act_body((raw as Dictionary)[k])
		return out
	if raw is Array:
		for a: Variant in raw:
			if not (a is Dictionary):
				continue
			var id := sanitize_id(str((a as Dictionary).get("id", "")))
			if id == "":
				continue
			var body: Dictionary = (a as Dictionary).duplicate(true)
			if str(body.get("text", "")) == "" and str(body.get("title", "")) != "":
				body["text"] = str(body.get("title", ""))
			if not body.has("choices") and body.has("actions"):
				body["choices"] = body.get("actions", [])
			out[id] = _normalize_act_body(body)
	return out


static func _normalize_act_body(a: Dictionary) -> Dictionary:
	var choices: Array = []
	var rc: Variant = a.get("choices", a.get("actions", []))
	if rc is Array:
		for c: Variant in rc:
			if c is Dictionary:
				choices.append(_normalize_act_choice(c))
	return {"text": str(a.get("text", "")), "choices": choices}


static func _normalize_act_choice(c: Dictionary) -> Dictionary:
	return {
		"label": str(c.get("label", "")),
		"hours": maxi(0, int(_num(c.get("hours", 0), 0))),
		"item": sanitize_id(str(c.get("item", ""))),
		"detail": str(c.get("detail", "")),
		"required": bool(c.get("required", false)),
	}


static func _num(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	if v is String and (v as String).is_valid_float():
		return (v as String).to_float()
	return fallback


static func _r(v: float) -> float:
	return snappedf(v, 0.01)


# ---------------------------------------------------------------- validate

## Problems as [{level: "error" | "warning", screen: index or -1, msg}]. Errors block Build.
static func validate(src: Dictionary, known_scenes: PackedStringArray = PackedStringArray()) -> Array:
	var d := normalize(src)
	var out: Array = []
	if known_scenes.is_empty():
		known_scenes = list_scenes()
	var id := str(d["id"])
	var raw_id := str(src.get("id", "")).strip_edges()
	if id == "":
		out.append(_p("error", -1, "The scene needs an id (it becomes the file name)."))
	elif raw_id != id:
		out.append(_p("warning", -1, "Scene id will be saved as \"%s\" (only a-z, 0-9 and _)." % id))
	if str(d["title"]).strip_edges() == "":
		out.append(_p("warning", -1, "The scene has no title."))
	var bg := str(d["background"])
	if bg != "" and not ResourceLoader.exists(bg):
		out.append(_p("error", -1, "Background not found: %s" % bg))
	var amb := str(d["ambience"])
	if amb != "" and not ResourceLoader.exists(amb):
		out.append(_p("error", -1, "Ambience not found: %s" % amb))
	var screens: Array = d["screens"]
	if screens.is_empty():
		out.append(_p("error", -1, "The scene has no screens."))
		return out
	var ids := {}
	for i in screens.size():
		var sid := str(screens[i]["id"])
		if sid == "":
			out.append(_p("error", i, "Screen %d has no id." % (i + 1)))
		elif ids.has(sid):
			out.append(_p("error", i, "Two screens are called \"%s\"." % sid))
		ids[sid] = true
	if str(d["after"]) != "":
		_check_target(out, -1, "When the scene ends", str(d["after"]), d, ids, known_scenes, false)
	for i in screens.size():
		var s: Dictionary = screens[i]
		var name := "Screen %d (%s)" % [i + 1, s["id"]]
		var last := i == screens.size() - 1
		var end_type := str((s["end"] as Dictionary)["type"])
		if end_type == "transition":
			if str((s["end"] as Dictionary).get("card", "")).strip_edges() == "":
				out.append(_p("warning", i, "%s: the transition card has no text." % name))
		elif str(s["text"]).strip_edges() == "" and str(s["heading"]).strip_edges() == "" and end_type != "map_tour":
			out.append(_p("warning", i, "%s is empty." % name))
		var m = _Markup.new().parse(str(s["text"]))
		for w: String in m.warnings:
			out.append(_p("warning", i, "%s: %s." % [name, w]))
		var vo: Dictionary = s["vo"]
		var clip := str(vo["clip"])
		if clip != "":
			if not ResourceLoader.exists(clip):
				out.append(_p("error", i, "%s: voice clip not found: %s" % [name, clip]))
			var cues: Array = vo["cues"]
			if cues.size() > m.line_count:
				out.append(_p("warning", i, "%s: %d cues but only %d text lines (extra cues are ignored)." % [name, cues.size(), m.line_count]))
			var prev := -1.0
			for k in cues.size():
				var c: Array = cues[k]
				if float(c[1]) <= float(c[0]):
					out.append(_p("warning", i, "%s: cue %d ends before it starts." % [name, k + 1]))
				if float(c[0]) < prev:
					out.append(_p("warning", i, "%s: cue %d starts before the previous one." % [name, k + 1]))
				prev = float(c[0])
		elif not (vo["cues"] as Array).is_empty():
			out.append(_p("warning", i, "%s has cue times but no voice clip." % name))
		for e: Dictionary in s["sfx"]:
			var sc := str(e["clip"])
			if sc == "":
				out.append(_p("error", i, "%s: a sound effect has no clip." % name))
			elif not ResourceLoader.exists(sc):
				out.append(_p("error", i, "%s: sound not found: %s" % [name, sc]))
			if e.has("line") and int(e["line"]) > maxi(m.line_count, 1):
				out.append(_p("warning", i, "%s: sound at line %d but the text has %d lines." % [name, int(e["line"]), m.line_count]))
		var red: Dictionary = s["red"]
		if str(red["mode"]) == "ramp" and is_equal_approx(float(red["from"]), float(red["to"])):
			out.append(_p("warning", i, "%s: red ramp has the same start and end." % name))
		var end: Dictionary = s["end"]
		match str(end["type"]):
			"continue":
				_check_target(out, i, name + " CONTINUE", str(end["goto"]), d, ids, known_scenes, last)
			"choices":
				var list: Array = end["choices"]
				if list.is_empty():
					out.append(_p("error", i, "%s ends in choices but has none." % name))
				for k in list.size():
					var c: Dictionary = list[k]
					if str(c["label"]).strip_edges() == "":
						out.append(_p("error", i, "%s: choice %d has no text." % [name, k + 1]))
					_check_target(out, i, "%s choice %d" % [name, k + 1], str(c["goto"]), d, ids, known_scenes, last)
			"death":
				if str(end["retry"]) != "":
					_check_target(out, i, name + " RETRY", str(end["retry"]), d, ids, known_scenes, false)
				elif i == 0:
					out.append(_p("warning", i, "%s: death on the first screen retries the same screen." % name))
			"qte":
				_check_target(out, i, name + " countdown", str(end["goto"]), d, ids, known_scenes, last)
				if str(end["retry"]) != "":
					_check_target(out, i, name + " RETRY", str(end["retry"]), d, ids, known_scenes, false)
			"map_tour":
				_check_tour(out, i, name, end, d)
				_check_target(out, i, name + " after the walkthrough", str(end["goto"]), d, ids, known_scenes, last)
			"transition":
				_check_target(out, i, name + " transition", str(end["goto"]), d, ids, known_scenes, last)
			"hold":
				if str(end["goto"]) != "":
					_check_target(out, i, name + " CONTINUE", str(end["goto"]), d, ids, known_scenes, false)
				if not last:
					out.append(_p("warning", i, "%s holds (ends the scene) but is not the last screen." % name))
	return out


## Map walkthrough: tips with text, targets that exist on the ship map, move_to a room.
static func _check_tour(out: Array, i: int, name: String, end: Dictionary, d: Dictionary) -> void:
	var tips: Array = end["tips"]
	if tips.is_empty():
		out.append(_p("error", i, "%s: the map walkthrough has no tips." % name))
	var m := _Vessel.default_map()
	var rooms: Dictionary = m.get("rooms", {})
	for k in tips.size():
		var tip: Dictionary = tips[k]
		if str(tip["text"]).strip_edges() == "":
			out.append(_p("error", i, "%s: tip %d has no text." % [name, k + 1]))
		var why := tour_target_problem(str(tip["target"]), m)
		if why != "":
			out.append(_p("error", i, "%s: tip %d %s" % [name, k + 1, why]))
	var mv := str(end["move_to"])
	if mv != "" and not rooms.has(mv):
		out.append(_p("error", i, "%s: \"move to\" room \"%s\" is not on the map (%s)." % [name, mv, ", ".join(PackedStringArray(rooms.keys()))]))
	if not (end.get("on_arrive", []) as Array).is_empty() and mv == "":
		out.append(_p("warning", i, "%s: \"on_arrive\" ops only run when the walkthrough has a \"move to\" room." % name))
	if str(d["ui"]) != "game":
		out.append(_p("warning", i, "%s: a map walkthrough reads best with the main game UI (scene \"ui\": \"game\")." % name))


## "" if a walkthrough target is valid on the map, else what is wrong.
static func tour_target_problem(tgt: String, m: Dictionary = {}) -> String:
	if m.is_empty():
		m = _Vessel.default_map()
	var rooms: Dictionary = m.get("rooms", {})
	if tgt in TOUR_TARGETS:
		return ""
	if tgt.begins_with("room:"):
		return "" if rooms.has(tgt.substr(5)) else "points at an unknown room \"%s\"." % tgt.substr(5)
	if tgt.begins_with("door:"):
		var parts := tgt.substr(5).split("|", false)
		if parts.size() == 2:
			for dd: Dictionary in m.get("doors", []):
				var a := str(dd.get("a", ""))
				var b := str(dd.get("b", ""))
				if (a == parts[0] and b == parts[1]) or (a == parts[1] and b == parts[0]):
					return ""
		return "points at an unknown door \"%s\" (use door:<room>|<room>)." % tgt.substr(5)
	return "has an unknown target \"%s\" (map, rooms, room:<id>, door:<a>|<b>)." % tgt


## Every walkthrough target on the default map (editor dropdown).
static func tour_targets() -> PackedStringArray:
	var out := PackedStringArray(TOUR_TARGETS)
	var m := _Vessel.default_map()
	for id in (m.get("rooms", {}) as Dictionary):
		out.append("room:" + str(id))
	for dd: Dictionary in m.get("doors", []):
		out.append("door:%s|%s" % [dd.get("a", ""), dd.get("b", "")])
	return out


static func _check_target(out: Array, i: int, what: String, t: String, d: Dictionary, ids: Dictionary,
		known: PackedStringArray, is_last: bool) -> void:
	t = t.strip_edges()
	if t == "order:next":
		return   # next screen in story/SCENE_ORDER.md; nothing after it shows the unwritten screen
	if t == "" or t == "next":
		if is_last and str(d["after"]) == "":
			out.append(_p("error", i, "%s goes to the next screen, but this is the last screen. Pick a target or set \"When the scene ends\"." % what))
		return
	if ids.has(t):
		return
	if t.begins_with("scene:"):
		var sid := t.substr(6).get_slice("/", 0)
		if sid != str(d["id"]) and not known.has(sid):
			out.append(_p("error", i, "%s: no scene story/scenes/%s.json." % [what, sid]))
		return
	if t.begins_with("intro:"):
		if not INTRO_PASSAGES.has(t.substr(6)):
			out.append(_p("warning", i, "%s: \"%s\" is not a known intro passage (%s)." % [what, t.substr(6), ", ".join(INTRO_PASSAGES)]))
		return
	if t.begins_with("tscn:"):
		if not ResourceLoader.exists(t.substr(5)):
			out.append(_p("error", i, "%s: scene file not found: %s" % [what, t.substr(5)]))
		return
	out.append(_p("error", i, "%s: there is no screen called \"%s\"." % [what, t]))


static func _p(level: String, screen: int, msg: String) -> Dictionary:
	return {"level": level, "screen": screen, "msg": msg}


## Human label for a goto target (dropdowns, preview).
static func target_label(t: String) -> String:
	if t == "order:next":
		return "NEXT"
	if t == "" or t == "next":
		return "Next screen"
	if t.begins_with("scene:"):
		return "Scene: " + t.substr(6)
	if t.begins_with("intro:"):
		return "Intro: " + t.substr(6)
	if t.begins_with("tscn:"):
		return "Scene file: " + t.substr(5).get_file()
	return "Screen: " + t


## Human label for a walkthrough target.
static func tour_target_label(tgt: String) -> String:
	if tgt == "map":
		return "Whole map + you-are-here dot"
	if tgt == "rooms":
		return "All rooms"
	var m := _Vessel.default_map()
	if tgt.begins_with("room:"):
		var r: Dictionary = (m.get("rooms", {}) as Dictionary).get(tgt.substr(5), {})
		return "Room: " + str(r.get("label", tgt.substr(5)))
	if tgt.begins_with("door:"):
		var parts := tgt.substr(5).split("|", false)
		var names := PackedStringArray()
		for pid in parts:
			names.append(str(((m.get("rooms", {}) as Dictionary).get(pid, {}) as Dictionary).get("label", pid)))
		return "Door: " + " / ".join(names)
	return tgt
